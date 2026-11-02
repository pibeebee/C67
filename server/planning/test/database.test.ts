import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { PGlite } from '@electric-sql/pglite';
import { plan } from '../src/engine.ts';
import { SyntheticProviders } from '../src/providers.ts';
import type { Event, Input, Job, PersonalTrip, Result } from '../src/domain.ts';

// A disposable PostgreSQL instance with simulated auth claims. No shared DB, Auth
// HTTP server, migration history, network, or production credentials are used.
test('personal planning migration: roles, leases, retries, revisions and active history', async (t) => {
  const db = await PGlite.create();
  const owner = randomUUID();
  const foreign = randomUUID();
  const providers = new SyntheticProviders();
  const value: Input = JSON.parse(
    await readFile(
      new URL('../../../contracts/fixtures/planning-input.json', import.meta.url),
      'utf8',
    ),
  );
  value.starts_at = new Date(Date.now() + 600000).toISOString();
  value.finish_by = new Date(Date.now() + 25200000).toISOString();
  value.places.forEach((place) => {
    place.id = randomUUID();
  });
  const call = async <T>(
    role: 'authenticated' | 'service_role' | 'anon',
    actor: string,
    sql: string,
    args: unknown[] = [],
  ): Promise<T> =>
    db.transaction(async (tx) => {
      await tx.exec(`set local role ${role}`);
      await tx.query(
        "select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role',$2,true)",
        [actor, role],
      );
      return (await tx.query<{ value: T }>(sql, args)).rows[0]?.value;
    });
  const user = <T>(sql: string, args: unknown[] = [], actor = owner) =>
    call<T>('authenticated', actor, sql, args);
  const worker = <T>(sql: string, args: unknown[] = []) => call<T>('service_role', '', sql, args);
  const rejects = (action: () => Promise<unknown>, code: string) =>
    assert.rejects(action, (e: any) => e.code === code, `expected SQLSTATE ${code}`);
  const request = (payload: object, actor = owner) =>
    user<Job>(
      'select public.request_planning_job($1::jsonb) as value',
      [JSON.stringify(payload)],
      actor,
    );
  const claim = () => worker<Job>('select public.claim_planning_job() as value');
  const finish = (job: Job, result: Result | null, error: string | null = null) =>
    worker('select public.finish_planning_job($1,$2,$3::jsonb,$4) as value', [
      job.id,
      job.lease_token,
      result ? JSON.stringify(result) : null,
      error,
    ]);
  const apply = (job: Job, requestID = randomUUID()) =>
    user<PersonalTrip>('select public.apply_planning_proposal($1,$2,$3) as value', [
      job.id,
      requestID,
      job.base_revision,
    ]);
  const event = (trip: PersonalTrip, kind: Event['kind'], rest: Partial<Event> = {}) =>
    user<PersonalTrip>('select public.record_planning_event($1,$2::jsonb) as value', [
      trip.id,
      JSON.stringify({ request_id: randomUUID(), expected_revision: trip.revision, kind, ...rest }),
    ]);
  let initial: Job;
  let trip: PersonalTrip;
  try {
    await db.exec(`
      create role anon; create role authenticated; create role service_role;
      create schema auth; create schema c67_private;
      create table auth.users(id uuid primary key);
      create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
      create function auth.role() returns text language sql stable as $$ select current_setting('request.jwt.claim.role',true) $$;
      grant usage on schema auth to authenticated,anon,service_role;
      revoke all on schema c67_private from public;
    `);
    await db.query('insert into auth.users values($1),($2)', [owner, foreign]);
    await db.exec(
      await readFile(
        new URL(
          '../../supabase/migrations/20261029235123_add_personal_ai_planning.sql',
          import.meta.url,
        ),
        'utf8',
      ),
    );
    t.diagnostic(
      `Disposable engine: ${(await db.query<{ version: string }>('select version()')).rows[0].version}`,
    );

    await t.test('ownership, idempotency, time-window validation and worker grants', async () => {
      const payload = { request_id: randomUUID(), purpose: 'plan', input: value };
      initial = await request(payload);
      assert.equal((await request(payload)).id, initial.id);
      await rejects(
        () => request({ ...payload, input: { ...value, title: 'Changed input' } }),
        'PT409',
      );
      await rejects(
        () => user('select public.get_planning_job($1) as value', [initial.id], foreign),
        'PT404',
      );
      await rejects(() => user('select public.claim_planning_job() as value'), '42501');
      await rejects(
        () =>
          call('anon', '', 'select public.request_planning_job($1::jsonb) as value', [
            JSON.stringify(payload),
          ]),
        '42501',
      );
      const invalid = structuredClone(value);
      invalid.places[0].preferred_after = value.finish_by;
      invalid.places[0].preferred_before = value.starts_at;
      await rejects(
        () => request({ request_id: randomUUID(), purpose: 'plan', input: invalid }),
        'PT400',
      );
      assert.equal('owner_id' in initial, false);
      assert.equal('lease_token' in initial, false);
    });

    await t.test(
      'leased completion rejects forged arithmetic and expired worker identity',
      async () => {
        const job = await claim();
        assert.equal(job.id, initial.id);
        await rejects(
          () => finish({ ...job, lease_token: randomUUID() }, null, 'PROVIDER_UNAVAILABLE'),
          'PT409',
        );
        const result = await plan(job.input, providers);
        const malformed = structuredClone(result);
        malformed.proposal!.stops[0].travel_seconds += 1;
        await rejects(() => finish(job, malformed), 'PT400');
        await finish(job, result);
        await rejects(() => finish(job, result), 'PT409');
        initial = await user<Job>('select public.get_planning_job($1) as value', [job.id]);
        assert.equal(initial.status, 'succeeded');
      },
    );

    await t.test(
      'proposal applies once, direct writes fail and account reads stay isolated',
      async () => {
        const id = randomUUID();
        trip = await apply(initial, id);
        assert.deepEqual(await apply(initial, id), trip);
        assert.equal((await apply(initial)).id, trip.id);
        assert.equal(
          (await user<PersonalTrip[]>('select public.list_personal_planning_trips() as value'))
            .length,
          1,
        );
        await rejects(
          () =>
            user(
              'select public.apply_planning_proposal($1,$2,null) as value',
              [initial.id, randomUUID()],
              foreign,
            ),
          'PT404',
        );
        await rejects(
          () =>
            user(
              'select public.record_planning_event($1,$2::jsonb) as value',
              [
                trip.id,
                JSON.stringify({ request_id: randomUUID(), expected_revision: 1, kind: 'start' }),
              ],
              foreign,
            ),
          'PT404',
        );
        assert.deepEqual(
          await user('select public.list_personal_planning_trips() as value', [], foreign),
          [],
        );
        assert.equal(
          await user<number>(
            'select count(*)::int as value from public.personal_planning_trips',
            [],
            foreign,
          ),
          0,
        );
        await rejects(
          () =>
            user('update public.personal_planning_trips set title=$1 returning id as value', [
              'Forged',
            ]),
          '42501',
        );
      },
    );

    await t.test('start is not arrival, extensions invalidate older proposals', async () => {
      trip = await event(trip, 'start');
      assert.equal(trip.current_stop_id, null);
      const stopID = trip.plan.stops[0].id;
      await rejects(
        () => event(trip, 'extend_stay', { stop_id: stopID, extra_seconds: 1800 }),
        'PT400',
      );
      trip = await event(trip, 'arrive', { stop_id: stopID });
      const encoded = structuredClone(trip.input);
      const equivalentOffset = (instant: string) =>
        new Date(Date.parse(instant) + 7 * 3600000).toISOString().replace('Z', '+07:00');
      encoded.starts_at = equivalentOffset(encoded.starts_at);
      encoded.finish_by = equivalentOffset(encoded.finish_by);
      encoded.first_place_id = null;
      encoded.places.forEach((place) => {
        place.id = place.id.toUpperCase();
        place.website ??= null;
      });
      const payload = {
        request_id: randomUUID(),
        purpose: 'replan',
        input: encoded,
        trip_id: trip.id,
        base_revision: trip.revision,
      };
      await rejects(
        () =>
          request({
            ...payload,
            request_id: randomUUID(),
            input: { ...encoded, title: 'Changed destination intent' },
          }),
        'PT409',
      );
      await request(payload);
      const job = await claim();
      assert.equal(job.input.first_place_id, stopID);
      assert.deepEqual(job.input.origin, trip.plan.stops[0].location);
      await finish(job, await plan(job.input, providers));
      trip = await event(trip, 'extend_stay', { stop_id: stopID, extra_seconds: 1800 });
      await rejects(() => apply(job), 'PT409');
      await rejects(() => request({ ...payload, request_id: randomUUID() }), 'PT409');
    });

    await t.test(
      'active replan retains current stop and completed history across application',
      async () => {
        await request({
          request_id: randomUUID(),
          purpose: 'replan',
          input: trip.input,
          trip_id: trip.id,
          base_revision: trip.revision,
        });
        const current = await claim();
        await finish(current, await plan(current.input, providers));
        trip = await apply(current);
        const completedID = trip.plan.stops[0].id;
        trip = await event(trip, 'complete_stop', { stop_id: completedID });
        const location = { latitude: -6.4, longitude: 106.9 };
        await request({
          request_id: randomUUID(),
          purpose: 'replan',
          input: trip.input,
          trip_id: trip.id,
          base_revision: trip.revision,
          current_origin: location,
        });
        const remaining = await claim();
        assert.equal(remaining.input.places.length, 2);
        assert.equal(remaining.input.first_place_id, null);
        assert.deepEqual(remaining.input.origin, location);
        await finish(remaining, await plan(remaining.input, providers));
        trip = await apply(remaining);
        assert.equal(trip.plan.stops.length, 3);
        assert.deepEqual(trip.completed_stop_ids, [completedID]);
        assert.equal(trip.plan.stops[0].id, completedID);
      },
    );

    await t.test(
      'suggestions cannot apply; abandoned jobs expire and invalidate leases',
      async () => {
        await request({ request_id: randomUUID(), purpose: 'suggest', input: value });
        const suggestions = await claim();
        await finish(suggestions, await plan(suggestions.input, providers, 'suggest'));
        await rejects(() => apply(suggestions), 'PT409');
        const abandoned = await request(
          { request_id: randomUUID(), purpose: 'plan', input: value },
          foreign,
        );
        const lease = await claim();
        assert.equal(lease.id, abandoned.id);
        await db.query(
          "update c67_private.planning_jobs set created_at=now()-interval '11 minutes',lease_expires_at=now()-interval '1 second' where id=$1",
          [lease.id],
        );
        assert.equal(await claim(), null);
        await rejects(() => finish(lease, null, 'PROVIDER_UNAVAILABLE'), 'PT409');
        assert.equal(
          (await user<Job>('select public.get_planning_job($1) as value', [lease.id], foreign))
            .error_code,
          'JOB_EXPIRED',
        );
      },
    );
  } finally {
    await db.close();
  }
});
