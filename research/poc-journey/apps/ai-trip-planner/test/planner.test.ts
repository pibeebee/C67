import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { aiConfig, fixtureDecision, validateDecision } from "../src/ai.ts";
import { FixtureData, type Fixture } from "../src/data.ts";
import {
  at,
  parseInput,
  prepareTrip,
  resolveDate,
  type Candidate,
  type Weather,
} from "../src/domain.ts";
import {
  assertPreserved,
  evaluate,
  schedule,
  summarizeWeather,
} from "../src/scheduler.ts";

const raw = JSON.parse(
  await readFile(new URL("../examples/johan.json", import.meta.url), "utf8"),
) as Record<string, unknown>;
const fixture = JSON.parse(
  await readFile(new URL("../fixtures/abcd.json", import.meta.url), "utf8"),
) as Fixture;
const input = () => parseInput(structuredClone(raw), "2026-11-03");
const setup = () => ({
  trip: prepareTrip(input()),
  data: new FixtureData(structuredClone(fixture)),
});

test("contextual planning chooses a sunset/dry window over the shortest travel path", async () => {
  const { trip, data } = setup();
  const result = await schedule(trip, data);
  assert.deepEqual(result.baselineTravelOnly.order, ["D", "C", "B"]);
  assert.equal(result.baselineTravelOnly.travelMinutes, 48);
  const selected = result.candidates[0]!;
  assert.deepEqual(selected.order, ["B", "D", "C"]);
  assert.equal(selected.preferredWindowMissMinutes, 0);
  assert.ok(
    selected.rainExposureMinutes <
      result.baselineTravelOnly.rainExposureMinutes,
  );
  assert.ok(selected.travelMinutes > result.baselineTravelOnly.travelMinutes);
  assertPreserved(trip, selected);
});

test("replan keeps visited history and every unvisited destination, and reports infeasibility", async () => {
  const base = input();
  const before = structuredClone(base);
  const trip = prepareTrip(base, {
    visitedIds: ["D"],
    fromId: "D",
    readyAt: "17:20",
  });
  const result = await schedule(trip, new FixtureData(fixture));
  assert.deepEqual(
    trip.visited.map((p) => p.id),
    ["D"],
  );
  assert.ok(result.candidates.every((c) => !c.feasible));
  for (const candidate of result.candidates) {
    assert.deepEqual([...candidate.order].sort(), ["B", "C"]);
    assert.ok(
      candidate.violations.some((v) => v.includes("Finish time exceeded")),
    );
    assertPreserved(trip, candidate);
  }
  assert.deepEqual(base, before);
});

test("already visited B and D are never scheduled again when extending D", async () => {
  const trip = prepareTrip(input(), {
    visitedIds: ["B", "D"],
    fromId: "D",
    readyAt: "17:20",
  });
  const result = await schedule(trip, new FixtureData(fixture));
  assert.deepEqual(result.candidates[0]!.order, ["C"]);
  assert.equal(
    result.candidates[0]!.stops[0]!.arrivalAt,
    at("2026-11-03", "17:30"),
  );
});

test("directed routes are not assumed symmetric", async () => {
  const { trip } = setup();
  const changed = structuredClone(fixture);
  changed.minutes.B!.D = 95;
  changed.minutes.D!.B = 7;
  const matrix = await new FixtureData(changed).matrix(trip);
  assert.equal(matrix.get("B/D")!.durationSeconds, 5700);
  assert.equal(matrix.get("D/B")!.durationSeconds, 420);
});

test("per-leg estimates use departure after the previous visit and opening-hours wait", async () => {
  const { trip, data } = setup();
  const place = trip.places[0]!;
  place.openingHours = { opensAt: "15:00", closesAt: "20:00" };
  const calls: { from: string; departure: number }[] = [];
  const candidate = await evaluate(
    trip,
    trip.places,
    false,
    async (from, to, departure) => {
      calls.push({ from: from.id, departure });
      return data.route(from, to, departure);
    },
    await data.weather(trip),
  );
  assert.equal(candidate.stops[0]!.visitAt, at(trip.input.date, "15:00"));
  assert.equal(calls[1]!.departure, at(trip.input.date, "16:00"));
  assert.equal(calls[2]!.departure, candidate.stops[1]!.leaveAt);
  assert.equal(candidate.stops[0]!.waitMinutes, 40);
  assertPreserved(trip, candidate);
});

test("closing time is a hard constraint, even when the deadline can be met", async () => {
  const { trip, data } = setup();
  trip.places[0]!.openingHours = { opensAt: "10:00", closesAt: "14:30" };
  const candidate = await evaluate(
    trip,
    trip.places,
    false,
    (from, to, departure) => data.route(from, to, departure),
    await data.weather(trip),
  );
  assert.equal(candidate.feasible, false);
  assert.ok(candidate.violations.some((v) => v.includes("closing time")));
});

test("weather is weighted over visit hours rather than only departure weather", () => {
  const start = at("2026-11-03", "15:30");
  const weather: Weather = {
    placeId: "C",
    evidenceId: "weather:C",
    sunrise: null,
    sunset: null,
    hours: [
      {
        at: at("2026-11-03", "15:00"),
        rainProbability: 100,
        temperatureC: 30,
        cloudCover: 80,
      },
      {
        at: at("2026-11-03", "16:00"),
        rainProbability: 0,
        temperatureC: 28,
        cloudCover: 20,
      },
    ],
  };
  const result = summarizeWeather(weather, start, start + 3600, "outdoor");
  assert.equal(result.rainProbability, 50);
  assert.equal(result.rainExposureMinutes, 30);
  assert.equal(result.temperatureC, 29);
});

test("missing forecast is unknown, not zero-percent rain, and missing sunset is disclosed", async () => {
  const { trip, data } = setup();
  const candidate = await evaluate(
    trip,
    trip.places,
    false,
    (from, to, departure) => data.route(from, to, departure),
    new Map(),
  );
  const outdoor = candidate.stops.find((s) => s.placeId === "C")!;
  assert.equal(outdoor.weather.rainProbability, null);
  assert.equal(outdoor.preferredWindowMissMinutes, null);
  assert.equal(outdoor.weather.unknownMinutes, 45);
  assert.ok(outdoor.warnings.some((w) => w.includes("Sunset")));
});

test("malformed dates, duplicate IDs, overnight trips and unsupported modes are rejected", () => {
  assert.throws(
    () => parseInput({ ...raw, date: "2026-02-30" }),
    /calendar date/,
  );
  assert.throws(
    () => parseInput({ ...raw, startTime: "22:00", finishTime: "01:00" }),
    /same day/,
  );
  assert.throws(() => parseInput({ ...raw, mode: "TRANSIT" }), /DRIVE or WALK/);
  const duplicate = structuredClone(raw);
  const places = duplicate.places as { id: string }[];
  places[1]!.id = places[0]!.id;
  assert.throws(() => parseInput(duplicate), /unique/);
  assert.throws(
    () => parseInput({ ...raw, places: Array(6).fill(places[0]) }),
    /1..5/,
  );
});

test("tomorrow is resolved using Jakarta calendar date even near midnight UTC", () => {
  assert.equal(
    resolveDate("tomorrow", Date.parse("2026-11-02T18:00:00Z")),
    "2026-11-04",
  );
});

test("replan requires a valid, visited current location and a forward time", () => {
  assert.throws(
    () => prepareTrip(input(), { visitedIds: ["X"] }),
    /selected destinations/,
  );
  assert.throws(
    () =>
      prepareTrip(input(), {
        visitedIds: ["D"],
        fromId: "C",
        readyAt: "16:00",
      }),
    /visited destination/,
  );
  assert.throws(
    () =>
      prepareTrip(input(), {
        visitedIds: ["D"],
        fromId: "D",
        readyAt: "13:00",
      }),
    /trip start/,
  );
});

test("AI cannot introduce a candidate, fabricate citations or omit stop explanations", async () => {
  const { trip, data } = setup();
  const { candidates } = await schedule(trip, data);
  const valid = fixtureDecision(candidates, trip).decision;
  assert.throws(
    () =>
      validateDecision({ ...valid, candidateId: "invented" }, candidates, trip),
    /unknown or disallowed/,
  );
  const badSource = structuredClone(valid);
  badSource.rationale[0]!.evidenceIds = ["fabricated-weather"];
  assert.throws(
    () => validateDecision(badSource, candidates, trip),
    /unknown or unrelated evidence/,
  );
  assert.throws(
    () => validateDecision({ ...valid, rationale: [] }, candidates, trip),
    /every remaining/,
  );
});

test("AI cannot choose an infeasible plan when a refined feasible plan exists", async () => {
  const { trip, data } = setup();
  const { candidates } = await schedule(trip, data);
  const valid = fixtureDecision(candidates, trip).decision;
  const bad: Candidate = {
    ...candidates[0]!,
    id: "bad",
    feasible: false,
    violations: ["deadline"],
  };
  assert.throws(
    () =>
      validateDecision(
        { ...valid, candidateId: "bad" },
        [...candidates, bad],
        trip,
      ),
    /disallowed/,
  );
});

test("fixture mode does not claim that AI was called", async () => {
  const { trip, data } = setup();
  const { candidates } = await schedule(trip, data);
  const result = fixtureDecision(candidates, trip);
  assert.equal(result.called, false);
  assert.equal(result.model, null);
  assert.ok(result.decision.summary.includes("SIMULATION ONLY"));
});

test("OpenRouter model selection is explicit", () => {
  assert.throws(
    () => aiConfig({ OPENROUTER_API_KEY: "test-key" }),
    /OPENROUTER_MODEL/,
  );
  assert.throws(
    () =>
      aiConfig({
        OPENROUTER_API_KEY: "test-key",
        OPENROUTER_MODEL: "test-model",
        OPENROUTER_MAX_TOKENS: "Infinity",
      }),
    /256 and 32768/,
  );
});
