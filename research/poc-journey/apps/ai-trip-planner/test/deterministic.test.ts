import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, writeFile, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import {
  parseRoutingInput,
  timestamp,
  openingInfo,
  unknownHours,
  type RoutingInput,
  type RoutingProvider,
  type LocationInput,
  type ResolvedLocation,
  type RouteOption,
  type Forecast,
} from "../src/deterministic-model.ts";
import {
  planWithoutAI,
  visitSlot,
  evaluateOrder,
  wetMinutes,
} from "../src/deterministic-planner.ts";
import { GoogleRoutingProvider } from "../src/deterministic-provider.ts";

const response = (value: unknown) => new Response(JSON.stringify(value));
const rawInput = (count = 2) => ({
  title: "SYNTHETIC TEST ONLY",
  date: "2026-12-01",
  timeZone: "Asia/Tokyo",
  startTime: "07:00",
  regionCode: "JP",
  origin: { id: "A", query: "A", exposure: "outdoor" },
  places: Array.from({ length: count }, (_, i) => ({
    id: `P${i + 1}`,
    query: `P${i + 1}`,
    exposure: "outdoor",
  })),
});
const resolved = (p: LocationInput): ResolvedLocation => ({
  ...p,
  status: "resolved",
  match: {
    placeId: p.id,
    name: p.name,
    address: "test",
    latitude: 35,
    longitude: 139,
  },
  alternatives: [],
  hours: unknownHours(),
  evidenceId: `place:${p.id}`,
  error: null,
});
class FakeProvider implements RoutingProvider {
  departures: { from: string; to: string; at: number }[] = [];
  matrixCalls = 0;
  unavailable = false;
  rain = false;
  closed = false;
  cost: (from: string, to: string, mode: string) => number = () => 60;
  async resolve(p: LocationInput) {
    const result = resolved(p);
    if (this.closed && p.role === "visit")
      result.hours = {
        status: "closed",
        windows: [],
        note: "Synthetic closure",
      };
    return result;
  }
  option(
    from: string,
    to: string,
    mode: "WALK" | "TRANSIT",
    at: number,
  ): RouteOption {
    return {
      id: `${from}/${to}/${mode}`,
      from,
      to,
      mode,
      status: this.unavailable ? "no_route" : "ok",
      durationSeconds: this.unavailable ? null : this.cost(from, to, mode),
      distanceMeters: null,
      walkingSeconds: mode === "WALK" ? this.cost(from, to, mode) : 60,
      departureAt: at,
      source: "departure_query",
      details: [],
      note: "SYNTHETIC TEST ONLY",
    };
  }
  async matrix(locations: ResolvedLocation[], input: RoutingInput) {
    this.matrixCalls++;
    return locations.flatMap((a) =>
      locations
        .filter((b) => b.id !== a.id)
        .flatMap((b) =>
          input.modes.map((m) => ({
            ...this.option(a.id, b.id, m, input.startsAt),
            source: "matrix_probe" as const,
          })),
        ),
    );
  }
  async routes(
    a: ResolvedLocation,
    b: ResolvedLocation,
    at: number,
    input: RoutingInput,
  ) {
    this.departures.push({ from: a.id, to: b.id, at });
    return input.modes.map((m) => this.option(a.id, b.id, m, at));
  }
  async forecasts(
    locations: ResolvedLocation[],
    input: RoutingInput,
  ): Promise<Forecast[]> {
    return locations.map((p) => ({
      locationId: p.id,
      status: this.rain ? "available" : "outside_forecast_horizon",
      note: "SYNTHETIC TEST ONLY",
      hours: this.rain
        ? Array.from({ length: 24 }, (_, h) => ({
            at: timestamp(
              input.date,
              `${String(h).padStart(2, "0")}:00`,
              input.timeZone,
            ),
            rainProbability: 100,
          }))
        : [],
    }));
  }
}

test("optional dwell defaults to 30, user override is retained, transfers have zero extra visit time", () => {
  const raw = rawInput(3);
  const input = parseRoutingInput({
    ...raw,
    places: [
      raw.places[0],
      { ...raw.places[1], dwellMinutes: 60 },
      { ...raw.places[2], role: "transfer" },
    ],
  });
  assert.deepEqual(
    input.places.map((p) => [p.dwellMinutes, p.dwellSource]),
    [
      [30, "default"],
      [60, "user"],
      [0, "transfer"],
    ],
  );
  assert.equal(
    new Date(input.startsAt * 1000).toISOString(),
    "2026-11-30T22:00:00.000Z",
  );
  assert.equal(input.finishBy, "23:59");
  assert.equal(input.finishSource, "end_of_day");
  assert.throws(
    () =>
      parseRoutingInput({
        ...raw,
        places: [{ ...raw.places[0], role: "transfer", dwellMinutes: 30 }],
      }),
    /transfer/,
  );
  assert.throws(
    () => parseRoutingInput({ ...raw, places: [raw.places[0], raw.places[0]] }),
    /unique/,
  );
});

test("regular hours handle overnight and split sessions; far-future current hours do not override them", () => {
  const input = parseRoutingInput(rawInput());
  const hours = openingInfo(
    {
      currentOpeningHours: { periods: [] },
      regularOpeningHours: {
        periods: [
          { open: { day: 1, hour: 22 }, close: { day: 2, hour: 2 } },
          { open: { day: 2, hour: 9 }, close: { day: 2, hour: 12 } },
          { open: { day: 2, hour: 13 }, close: { day: 2, hour: 18 } },
        ],
      },
    },
    input,
    "2026-11-03",
  );
  assert.equal(hours.status, "regular");
  assert.equal(hours.windows.length, 3);
  const slot = visitSlot(
    hours,
    timestamp(input.date, "11:45", input.timeZone),
    60,
    false,
  );
  assert.equal(slot.start, timestamp(input.date, "13:00", input.timeZone));
  assert.equal(slot.conflict, false);
  assert.equal(
    visitSlot(hours, timestamp(input.date, "17:45", input.timeZone), 60, false)
      .conflict,
    true,
  );
  assert.equal(
    visitSlot(hours, timestamp(input.date, "23:00", input.timeZone), 0, true)
      .conflict,
    false,
  );
});

test("current dated opening periods are applied only within the next seven days", () => {
  const input = parseRoutingInput(rawInput());
  const p = {
    currentOpeningHours: {
      periods: [
        {
          open: { date: { year: 2026, month: 12, day: 1 }, hour: 10 },
          close: { date: { year: 2026, month: 12, day: 1 }, hour: 14 },
        },
      ],
    },
  };
  const hours = openingInfo(p, input, "2026-11-29");
  assert.equal(hours.status, "date_specific");
  assert.deepEqual(hours.windows, [
    {
      start: timestamp(input.date, "10:00", input.timeZone),
      end: timestamp(input.date, "14:00", input.timeZone),
    },
  ]);
  assert.equal(openingInfo(p, input, "2026-11-03").status, "unknown");
});

test("optimizer avoids a nearest-neighbor trap, includes return, and propagates actual departures", async () => {
  const input = parseRoutingInput({ ...rawInput(), modes: ["WALK"] });
  const p = new FakeProvider();
  const costs: Record<string, number> = {
    "A/P1": 1,
    "A/P2": 2,
    "P1/P2": 100,
    "P2/P1": 2,
    "P1/A": 1,
    "P2/A": 1,
  };
  p.cost = (a, b) => costs[`${a}/${b}`]! * 60;
  const result = await planWithoutAI(input, p);
  assert.deepEqual(result.fastest!.order, ["P2", "P1"]);
  assert.equal(result.fastest!.travelMinutes, 5);
  assert.equal(result.fastest!.finishesAt, input.startsAt + (60 + 5) * 60);
  assert.equal(result.fastest!.stops.at(-1)!.placeId, "A");
  for (const c of result.candidates)
    for (const [i, s] of c.stops.entries())
      assert.equal(
        s.departureAt,
        i === 0 ? input.startsAt : c.stops[i - 1]!.leaveAt,
      );
  assert.equal(result.aiCalls, 0);
});

test("fifteen destinations are preserved with bounded search, no factorial expansion", async () => {
  const input = parseRoutingInput({
    ...rawInput(15),
    modes: ["WALK"],
    search: { beamWidth: 64, shortlist: 2 },
  });
  const result = await planWithoutAI(input, new FakeProvider());
  assert.ok(result.fastest!.feasible);
  assert.equal(new Set(result.fastest!.order).size, 15);
  assert.equal(result.fastest!.stops.length, 16);
  assert.equal(result.fastest!.dwellMinutes, 450);
  assert.ok(result.search!.expanded < 50000);
  assert.equal(result.weatherAdjusted, null);
});

test("missing routes stay missing; neither zero-minute edges nor fake completion are produced", async () => {
  const input = parseRoutingInput(rawInput());
  const p = new FakeProvider();
  p.unavailable = true;
  const result = await planWithoutAI(input, p);
  assert.equal(result.status, "insufficient_route_data");
  assert.equal(result.fastest, null);
  const candidate = await evaluateOrder(
    input,
    input.places.map(resolved),
    resolved(input.origin),
    resolved(input.returnTo),
    p,
    [],
    "fastest",
  );
  assert.equal(candidate.complete, false);
  assert.equal(candidate.finishesAt, null);
  assert.equal(candidate.stops[0]!.arrivalAt, null);
  assert.equal(candidate.unvisitedIds.length, 2);
});

test("weather can choose a slower less-exposed mode, constrained by explicit extra-time budget", async () => {
  const raw = {
    ...rawInput(1),
    weatherPolicy: { rainWeight: 2, maxExtraMinutes: 15 },
  };
  const p = new FakeProvider();
  p.rain = true;
  p.cost = (_a, _b, m) => (m === "WALK" ? 600 : 900);
  const result = await planWithoutAI(parseRoutingInput(raw), p);
  assert.equal(result.fastest!.travelMinutes, 20);
  assert.equal(result.weatherAdjusted!.travelMinutes, 30);
  assert.ok(
    result.weatherAdjusted!.expectedWetMinutes <
      result.fastest!.expectedWetMinutes,
  );
  assert.equal(result.weatherAdjusted!.stops[0]!.options.length, 2);
  const strict = await planWithoutAI(
    parseRoutingInput({
      ...raw,
      weatherPolicy: { rainWeight: 2, maxExtraMinutes: 5 },
    }),
    p,
  );
  assert.ok(
    strict.weatherAdjusted!.travelMinutes <= strict.fastest!.travelMinutes + 5,
  );
});

test("unknown rain probability is not treated as clear, and unknown exposure remains explicit", () => {
  const f: Forecast = {
    locationId: "P",
    status: "available",
    note: null,
    hours: [
      { at: 0, rainProbability: 100 },
      { at: 3600, rainProbability: null },
    ],
  };
  assert.deepEqual(wetMinutes(f, 0, 7200, 1), {
    expectedWetMinutes: 60,
    unknownMinutes: 60,
  });
  assert.deepEqual(wetMinutes(f, 0, 1800, null), {
    expectedWetMinutes: 0,
    unknownMinutes: 30,
  });
  assert.deepEqual(wetMinutes(f, 0, 1800, 0), {
    expectedWetMinutes: 0,
    unknownMinutes: 0,
  });
});

test("closure conflicts preserve destinations and user dwell instead of making the plan fit", async () => {
  const p = new FakeProvider();
  p.closed = true;
  const input = parseRoutingInput({
    ...rawInput(),
    finishBy: "07:30",
    places: [
      { id: "P1", query: "P1", dwellMinutes: 90 },
      { id: "P2", query: "P2" },
    ],
  });
  const result = await planWithoutAI(input, p);
  assert.equal(result.status, "no_feasible_candidate");
  assert.equal(result.fastest!.order.length, 2);
  assert.equal(result.fastest!.dwellMinutes, 120);
  assert.ok(
    result.fastest!.conflicts.some((c) => c.startsWith("OPENING_WINDOW")),
  );
  assert.ok(
    result.fastest!.conflicts.some((c) => c.startsWith("FINISH_LIMIT")),
  );
});

test("ambiguous place selection stops before querying routes rather than silently selecting the first result", async () => {
  const input = parseRoutingInput(rawInput());
  const p = new FakeProvider();
  p.resolve = async (place) => ({
    ...resolved(place),
    status: "ambiguous",
    match: null,
    error: "Choose a place.",
  });
  const result = await planWithoutAI(input, p);
  assert.equal(result.status, "needs_location_selection");
  assert.equal(p.matrixCalls, 0);
  assert.equal(result.locations.length, 3);
});

test("Google Places retains ambiguity, and reference-point hours cannot become the unknown shop's hours", async () => {
  const input = parseRoutingInput(rawInput(1));
  const fetcher: typeof fetch = async () =>
    response({
      places: [
        {
          id: "one",
          displayName: { text: "One" },
          location: { latitude: 35, longitude: 139 },
          regularOpeningHours: {
            periods: [{ open: { day: 0 }, close: undefined }],
          },
        },
        {
          id: "two",
          displayName: { text: "Two" },
          location: { latitude: 35, longitude: 139 },
        },
      ],
    });
  const p = new GoogleRoutingProvider("test-key", { fetcher });
  assert.equal((await p.resolve(input.places[0]!, input)).status, "ambiguous");
  const reference = await p.resolve(
    {
      ...input.places[0]!,
      acceptedNames: ["One"],
      referenceNote: "Area reference only",
    },
    input,
  );
  assert.equal(reference.status, "reference");
  assert.equal(reference.hours.status, "unknown");
  assert.equal(reference.match!.placeId, "one");
});

test("Japan transit is explicitly unsupported; matrix elements are chunked, directed, and preserve protobuf zero indices", async () => {
  const input = parseRoutingInput({
    ...rawInput(15),
    modes: ["WALK", "TRANSIT"],
  });
  const calls: Record<string, unknown>[] = [];
  const fetcher: typeof fetch = async (_url, init) => {
    const body = JSON.parse(String(init?.body));
    calls.push(body);
    assert.ok(body.origins.length * body.destinations.length <= 100);
    return response(
      body.origins.flatMap((_a: unknown, oi: number) =>
        body.destinations.map((_b: unknown, di: number) => ({
          ...(oi ? { originIndex: oi } : {}),
          ...(di ? { destinationIndex: di } : {}),
          condition: "ROUTE_EXISTS",
          status: {},
          duration: `${100 + oi * 10 + di}s`,
        })),
      ),
    );
  };
  const p = new GoogleRoutingProvider("test-key", { fetcher });
  const locations = [input.origin, ...input.places].map(resolved);
  const matrix = await p.matrix(locations, input);
  assert.equal(calls.length, 4);
  assert.ok(calls.every((c) => c.travelMode === "WALK"));
  assert.equal(matrix.filter((r) => r.mode === "TRANSIT").length, 16 * 15);
  assert.ok(
    matrix
      .filter((r) => r.mode === "TRANSIT")
      .every(
        (r) => r.status === "unsupported_region" && r.durationSeconds === null,
      ),
  );
  assert.equal(
    matrix.find((r) => r.from === "A" && r.to === "P1" && r.mode === "WALK")!
      .durationSeconds,
    101,
  );
  assert.equal(
    matrix.find((r) => r.from === "P1" && r.to === "A" && r.mode === "WALK")!
      .durationSeconds,
    110,
  );
});

test("Google missing matrix cells and provider errors never become usable zero-duration routes", async () => {
  const input = parseRoutingInput({ ...rawInput(1), modes: ["WALK"] });
  const p = new GoogleRoutingProvider("secret-test-value", {
    fetcher: async () => response([]),
  });
  const matrix = await p.matrix(
    [input.origin, ...input.places].map(resolved),
    input,
  );
  assert.ok(
    matrix.every(
      (r) => r.status === "provider_error" && r.durationSeconds === null,
    ),
  );
  const bad = new GoogleRoutingProvider("secret-test-value", {
    fetcher: async () => new Response("secret-test-value", { status: 403 }),
  });
  const result = await bad.resolve(input.origin, input);
  assert.equal(result.status, "unavailable");
  assert.ok(!JSON.stringify(bad.evidence).includes("secret-test-value"));
});

test("real CLI accepts no OpenRouter configuration, writes a report, and never calls an AI endpoint", async () => {
  const root = await mkdtemp(join(tmpdir(), "routing-cli-"));
  try {
    await writeFile(
      join(root, "input.json"),
      JSON.stringify({ ...rawInput(1), modes: ["WALK"] }),
    );
    const script = `globalThis.fetch=async(url,init)=>{const u=String(url),b=init?.body?JSON.parse(init.body):{};if(u.includes('openrouter'))throw Error('AI MUST NOT BE CALLED');let d;if(u.includes('places.googleapis'))d={places:[{id:b.textQuery,displayName:{text:b.textQuery},location:{latitude:35,longitude:139}}]};else if(u.includes('computeRouteMatrix'))d=b.origins.flatMap((_,i)=>b.destinations.map((_,j)=>({originIndex:i,destinationIndex:j,status:{},condition:'ROUTE_EXISTS',duration:'60s'})));else if(u.includes('computeRoutes'))d={routes:[{duration:'60s',legs:[{steps:[{travelMode:'WALK',staticDuration:'60s'}]}]}]};else if(u.includes('open-meteo'))d={hourly:{time:[],precipitation_probability:[]}};else throw Error('Unexpected endpoint');return new Response(JSON.stringify(d))};`;
    const result = spawnSync(
      process.execPath,
      [
        "--import",
        `data:text/javascript,${encodeURIComponent(script)}`,
        fileURLToPath(new URL("../src/plan-routes.ts", import.meta.url)),
        "--input",
        join(root, "input.json"),
        "--out",
        join(root, "output"),
      ],
      {
        env: {
          ...process.env,
          GOOGLE_MAPS_API_KEY: "test-key",
          OPENROUTER_API_KEY: "",
          OPENROUTER_MODEL: "",
        },
        encoding: "utf8",
      },
    );
    assert.equal(result.status, 0, result.stderr);
    const report = JSON.parse(
      await readFile(join(root, "output/report.json"), "utf8"),
    );
    assert.equal(report.aiCalls, 0);
    assert.equal(report.fastest.order.length, 1);
    assert.ok(
      (await readFile(join(root, "output/report.md"), "utf8")).includes(
        "Panggilan AI: **0**",
      ),
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
