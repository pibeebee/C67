import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID, generateKeyPairSync, verify } from 'node:crypto';
import { once } from 'node:events';
import { Failure, validateInput, type Input } from '../src/domain.ts';
import { schedule } from '../src/scheduler.ts';
import { plan } from '../src/engine.ts';
import { SyntheticProviders, LiveProviders, appleToken } from '../src/providers.ts';
import { publicAddress, readPublicPage } from '../src/research.ts';
import { MemoryStore } from '../src/store.ts';
import { createAPI, workOnce } from '../src/server.ts';

const ids = [
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  '33333333-3333-4333-8333-333333333333',
];
function input(): Input {
  return {
    title: 'Synthetic coffee afternoon',
    origin: { latitude: -6.26, longitude: 106.8 },
    places: ids.map((id, i) => ({
      id,
      name: `Synthetic stop ${i + 1}`,
      location: { latitude: -6.26 + i * 0.001, longitude: 106.81 + i * 0.001 },
      visit_seconds: 1800,
    })),
    preferences: 'Coffee and reading; relaxed pace',
    starts_at: '2026-11-01T08:00:00.000Z',
    finish_by: '2026-11-01T14:00:00.000Z',
    time_zone: 'Asia/Jakarta',
    mode: 'walking',
  };
}

test('directed matrix chooses the 48-minute fixture and keeps every selected place', async () => {
  const value = input();
  value.places.forEach((place) => {
    place.visit_seconds = 0;
  });
  const labels = new Map([
    ['origin', 'A'],
    [ids[0], 'B'],
    [ids[1], 'C'],
    [ids[2], 'D'],
  ]);
  const matrix: Record<string, number> = {
    AB: 20,
    AC: 15,
    AD: 8,
    BC: 30,
    BD: 45,
    CB: 30,
    CD: 10,
    DB: 45,
    DC: 10,
  };
  const result = await schedule(value, async (from, to) => ({
    duration_seconds: matrix[labels.get(from)! + labels.get(to)!] * 60,
    distance_meters: null,
    evidence_id: 'fixture',
  }));
  assert.deepEqual(
    result[0].stops.map((stop) => stop.id),
    [ids[2], ids[1], ids[0]],
  );
  assert.equal((Date.parse(result[0].finishes_at) - Date.parse(value.starts_at)) / 60000, 48);
});

test('preferred window affects ranking while infeasible plans retain all destinations', async () => {
  const value = input();
  value.places[2].preferred_before = '2026-11-01T08:10:00Z';
  value.finish_by = '2026-11-01T08:15:00Z';
  const result = await schedule(value, async () => ({
    duration_seconds: 300,
    distance_meters: null,
    evidence_id: 'fixture',
  }));
  assert.equal(result[0].stops[0].id, ids[2]);
  assert.equal(result[0].feasible, false);
  assert.equal(result[0].stops.length, 3);
  assert.ok(result[0].warnings.length);
});

test('unknown routes fail explicitly; live never substitutes synthetic travel', async () => {
  await assert.rejects(
    () =>
      schedule(input(), async () => {
        throw new Failure('ROUTE_UNAVAILABLE', 503);
      }),
    /ROUTE_UNAVAILABLE/,
  );
  await assert.rejects(
    () => plan(input(), new LiveProviders({})),
    /PROVIDER_CONFIGURATION_REQUIRED/,
  );
});

test('provider route times are recalculated at candidate departure instants', async () => {
  const calls: string[] = [];
  await schedule(input(), async (_from, _to, departure) => {
    calls.push(departure);
    return { duration_seconds: 60, distance_meters: 100, evidence_id: 'fixture' };
  });
  assert.ok(new Set(calls).size > 1);
});

test('six-stop search bounds route calls and honors cancellation without inventing fallback', async () => {
  const value = input();
  value.places = [...value.places, ...value.places.map((p) => ({ ...p, id: randomUUID() }))];
  let calls = 0;
  const candidates = await schedule(value, async () => {
    calls++;
    return { duration_seconds: 60, distance_meters: null, evidence_id: 'fixture' };
  });
  assert.ok(calls <= 72);
  assert.equal(candidates[0].stops.length, 6);
  const controller = new AbortController();
  controller.abort();
  await assert.rejects(
    () => plan(value, new SyntheticProviders(), 'plan', controller.signal),
    /aborted/i,
  );
});

test('model output cannot invent an unevaluated order or select an unavailable candidate', async () => {
  const providers = new SyntheticProviders();
  providers.choose = async () => ({ candidate_id: 'invented', explanation: 'Forged schedule' });
  await assert.rejects(() => plan(input(), providers), /INVALID_MODEL_OUTPUT/);
});

test('live adapters exchange Apple tokens, ground AI choices and retain weather attribution using stub HTTP', async (t) => {
  const keys = generateKeyPairSync('ec', { namedCurve: 'P-256' });
  const pem = keys.privateKey.export({ type: 'pkcs8', format: 'pem' }).toString();
  const env = {
    APPLE_TEAM_ID: 'SYNTHETIC',
    APPLE_MAPS_KEY_ID: 'MAPS',
    APPLE_MAPS_PRIVATE_KEY: pem,
    APPLE_WEATHER_KEY_ID: 'WEATHER',
    APPLE_WEATHER_PRIVATE_KEY: pem,
    APPLE_WEATHER_SERVICE_ID: 'io.synthetic.weather',
    PLANNING_MODEL_API_KEY: 'synthetic-not-a-key',
    PLANNING_MODEL: 'synthetic-model',
  };
  const requests: string[] = [];
  let modelCalls = 0;
  let inputHadWeather = false;
  t.mock.method(globalThis, 'fetch', async (url: string, init: RequestInit) => {
    requests.push(url);
    const address = new URL(url);
    let data: unknown;
    if (address.pathname === '/v1/token')
      data = { accessToken: 'synthetic-access', expiresInSeconds: 3600 };
    else if (address.pathname === '/v1/etas') {
      assert.equal(address.searchParams.get('transportType'), 'Walking');
      assert.match(address.searchParams.get('departureDate')!, /Z$/);
      data = { etas: [{ expectedTravelTimeSeconds: 60, distanceMeters: 100 }] };
    } else if (address.pathname === '/api/v1/attribution/en')
      data = { 'logoLight@2x': '/assets/synthetic-logo.png' };
    else if (address.hostname === 'weatherkit.apple.com')
      data = {
        forecastHourly: {
          metadata: {
            readTime: new Date().toISOString(),
            expireTime: new Date(Date.now() + 3600000).toISOString(),
            attributionURL: 'https://weatherkit.apple.com/legal-attribution.html',
          },
          hours: [
            {
              forecastStart: input().starts_at,
              precipitationChance: 0.8,
              cloudCover: 0.9,
              temperature: 27,
            },
          ],
        },
        forecastDaily: { days: [] },
      };
    else if (address.hostname === 'openrouter.ai') {
      modelCalls++;
      const body = JSON.parse(init.body as string);
      const context = JSON.parse(body.messages[1].content);
      inputHadWeather ||= context.evidence?.some((e: any) => e.kind === 'weather');
      const content =
        modelCalls === 1
          ? { orders: [[...ids].reverse()] }
          : {
              candidate_id: context.candidates[0].id,
              explanation: 'Synthetic stub reasoning grounded in supplied context.',
            };
      data = { choices: [{ message: { content: JSON.stringify(content) } }] };
    } else throw new Error('Unexpected upstream request');
    return new Response(JSON.stringify(data), { headers: { 'Content-Type': 'application/json' } });
  });
  const result = await plan(input(), new LiveProviders(env));
  assert.equal(result.synthetic, false);
  assert.equal(modelCalls, 2);
  assert.equal(inputHadWeather, true);
  assert.equal(
    result.proposal?.evidence.find((e) => e.kind === 'weather')?.attribution_logo_url,
    'https://weatherkit.apple.com/assets/synthetic-logo.png',
  );
  assert.ok(requests.some((url) => url.includes('/v1/etas?')));
  t.mock.restoreAll();
});

test('scheduler holds the current place first during active recalculation', async () => {
  const value = input();
  value.first_place_id = ids[1];
  const result = await schedule(value, async () => ({
    duration_seconds: 60,
    distance_meters: null,
    evidence_id: 'fixture',
  }));
  assert.ok(result.every((candidate) => candidate.stops[0].id === ids[1]));
});

test('input rejects duplicate locations identities, invalid zone, unsupported mode and excess places', () => {
  const duplicate = input();
  duplicate.places[1].id = duplicate.places[0].id;
  assert.throws(() => validateInput(duplicate));
  const invalidZone = input();
  invalidZone.time_zone = 'not-a-zone';
  assert.throws(() => validateInput(invalidZone));
  const invalidMode = input();
  (invalidMode as any).mode = 'transit';
  assert.throws(() => validateInput(invalidMode));
  const invalidOrigin = input();
  invalidOrigin.origin.latitude = NaN;
  assert.throws(() => validateInput(invalidOrigin));
  const missingZone = input();
  delete (missingZone as any).time_zone;
  assert.throws(() => validateInput(missingZone));
  const excess = input();
  excess.places = Array.from({ length: 7 }, () => ({ ...excess.places[0], id: randomUUID() }));
  assert.throws(() => validateInput(excess));
});

test('browser rejects credentials, private addresses, non-HTTPS and mapped IPv6', async () => {
  for (const value of [
    '127.0.0.1',
    '10.1.1.1',
    '169.254.169.254',
    '172.18.0.1',
    '192.168.1.1',
    '::1',
    '::ffff:127.0.0.1',
    '2002:7f00::1',
  ])
    assert.equal(publicAddress(value), false, value);
  assert.equal(publicAddress('8.8.8.8'), true);
  await assert.rejects(() => readPublicPage('http://127.0.0.1'));
  await assert.rejects(() => readPublicPage('https://name:password@example.com'));
  await assert.rejects(() => readPublicPage('https://example.com:8080'));
});

test('Apple signing uses ES256 P1363 and distinct Maps/Weather claims', () => {
  const keys = generateKeyPairSync('ec', { namedCurve: 'P-256' });
  const pem = keys.privateKey.export({ type: 'pkcs8', format: 'pem' }).toString();
  const env = {
    APPLE_TEAM_ID: 'TEAM',
    APPLE_MAPS_KEY_ID: 'MAPS',
    APPLE_MAPS_PRIVATE_KEY: pem,
    APPLE_WEATHER_KEY_ID: 'WEATHER',
    APPLE_WEATHER_PRIVATE_KEY: pem,
    APPLE_WEATHER_SERVICE_ID: 'io.c67.weather',
  };
  for (const purpose of ['maps', 'weather'] as const) {
    const token = appleToken(env, purpose, 1000);
    const [h, p, signature] = token.split('.');
    const header = JSON.parse(Buffer.from(h, 'base64url').toString());
    const payload = JSON.parse(Buffer.from(p, 'base64url').toString());
    assert.equal(header.alg, 'ES256');
    assert.equal(payload.iss, 'TEAM');
    assert.equal(payload.exp, 2200);
    assert.equal(
      verify(
        'sha256',
        Buffer.from(`${h}.${p}`),
        { key: keys.publicKey, dsaEncoding: 'ieee-p1363' },
        Buffer.from(signature, 'base64url'),
      ),
      true,
    );
    if (purpose === 'weather') {
      assert.equal(header.id, 'TEAM.io.c67.weather');
      assert.equal(payload.sub, 'io.c67.weather');
    } else assert.equal(payload.scope, 'server_api');
  }
});

test('durable boundaries: owned jobs, retry identity, apply, active extension and stale proposal', async () => {
  let now = Date.parse('2026-11-01T08:00:00Z');
  const store = new MemoryStore(() => now);
  const providers = new SyntheticProviders();
  const owner = randomUUID();
  const foreign = randomUUID();
  const request = { request_id: randomUUID(), purpose: 'plan' as const, input: input() };
  const job = await store.request(owner, request);
  assert.equal((await store.request(owner, request)).id, job.id);
  await assert.rejects(
    () => store.request(owner, { ...request, input: { ...request.input, title: 'Different' } }),
    /REQUEST_CONFLICT/,
  );
  await assert.rejects(() => store.job(foreign, job.id), /NOT_FOUND/);
  await workOnce(store, providers);
  const finished = await store.job(owner, job.id);
  assert.equal(finished.status, 'succeeded');
  const applyID = randomUUID();
  const trip = await store.apply(owner, job.id, applyID, null);
  assert.deepEqual(await store.apply(owner, job.id, applyID, null), trip);
  const started = await store.event(owner, trip.id, {
    request_id: randomUUID(),
    expected_revision: 1,
    kind: 'start',
  });
  await assert.rejects(
    () =>
      store.event(owner, trip.id, {
        request_id: randomUUID(),
        expected_revision: started.revision,
        kind: 'extend_stay',
        stop_id: started.plan.stops[0].id,
        extra_seconds: 1800,
      }),
    /INVALID_EVENT/,
  );
  const active = await store.event(owner, trip.id, {
    request_id: randomUUID(),
    expected_revision: started.revision,
    kind: 'arrive',
    stop_id: started.plan.stops[0].id,
  });
  const oldJob = await store.request(owner, {
    request_id: randomUUID(),
    purpose: 'replan',
    input: active.input,
    trip_id: active.id,
    base_revision: active.revision,
  });
  await workOnce(store, providers);
  const extended = await store.event(owner, active.id, {
    request_id: randomUUID(),
    expected_revision: active.revision,
    kind: 'extend_stay',
    stop_id: active.plan.stops[0].id,
    extra_seconds: 1800,
  });
  await assert.rejects(
    () => store.apply(owner, oldJob.id, randomUUID(), active.revision),
    /REVISION_CONFLICT/,
  );
  const updatedJob = await store.request(owner, {
    request_id: randomUUID(),
    purpose: 'replan',
    input: extended.input,
    trip_id: extended.id,
    base_revision: extended.revision,
  });
  await workOnce(store, providers);
  const updated = await store.apply(owner, updatedJob.id, randomUUID(), extended.revision);
  assert.equal(updated.revision, extended.revision + 1);
  assert.equal(updated.plan.stops[0].id, active.plan.stops[0].id);
  const complete = await store.event(owner, updated.id, {
    request_id: randomUUID(),
    expected_revision: updated.revision,
    kind: 'complete_stop',
    stop_id: updated.plan.stops[0].id,
  });
  now += 60000;
  const remaining = await store.request(owner, {
    request_id: randomUUID(),
    purpose: 'replan',
    input: complete.input,
    trip_id: complete.id,
    base_revision: complete.revision,
  });
  assert.equal(remaining.input.places.length, 2);
  assert.equal(remaining.input.first_place_id, null);
  assert.deepEqual(remaining.input.origin, updated.plan.stops[0].location);
});

test('additional suggestions do not mutate selected destinations and cannot be applied', async () => {
  const store = new MemoryStore();
  const owner = randomUUID();
  const original = input();
  const job = await store.request(owner, {
    request_id: randomUUID(),
    purpose: 'suggest',
    input: original,
  });
  await workOnce(store, new SyntheticProviders());
  const result = await store.job(owner, job.id);
  assert.equal(result.result?.candidates.length, 1);
  assert.equal(result.input.places.length, 3);
  await assert.rejects(
    () => store.apply(owner, job.id, randomUUID(), null),
    /PROPOSAL_NOT_APPLICABLE/,
  );
});

test('HTTP contract accepts queued work, rejects foreign reads and malformed/anonymous requests', async () => {
  const store = new MemoryStore();
  const api = createAPI(store, new SyntheticProviders());
  api.listen(0, '127.0.0.1');
  await once(api, 'listening');
  const address = api.address() as any;
  const base = `http://127.0.0.1:${address.port}`;
  const owner = randomUUID();
  try {
    const request = { request_id: randomUUID(), purpose: 'plan', input: input() };
    const response = await fetch(`${base}/v1/planning/jobs`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${owner}` },
      body: JSON.stringify(request),
    });
    assert.equal(response.status, 202);
    const job = (await response.json()) as any;
    assert.equal(
      (
        await fetch(`${base}/v1/planning/jobs/${job.id}`, {
          headers: { Authorization: `Bearer ${randomUUID()}` },
        })
      ).status,
      404,
    );
    assert.equal((await fetch(`${base}/v1/planning/trips`)).status, 401);
    const malformed = await fetch(`${base}/v1/planning/jobs`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${owner}` },
      body: '{',
    });
    assert.equal(malformed.status, 400);
    const invalid = await fetch(`${base}/v1/planning/jobs`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${owner}` },
      body: 'null',
    });
    assert.equal(invalid.status, 400);
    await workOnce(store, new SyntheticProviders());
    const result = (await (
      await fetch(`${base}/v1/planning/jobs/${job.id}`, {
        headers: { Authorization: `Bearer ${owner}` },
      })
    ).json()) as any;
    assert.equal(result.status, 'succeeded');
    assert.equal(result.result.synthetic, true);
  } finally {
    api.closeAllConnections();
    await new Promise<void>((resolve) => api.close(() => resolve()));
  }
});
