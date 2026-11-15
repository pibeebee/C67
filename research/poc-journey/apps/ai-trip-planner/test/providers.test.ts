import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { chooseWithAI, fixtureDecision } from "../src/ai.ts";
import {
  FixtureData,
  LiveData,
  duration,
  parseWeather,
  type Fixture,
} from "../src/data.ts";
import { parseInput, prepareTrip } from "../src/domain.ts";
import { Http } from "../src/http.ts";
import { schedule } from "../src/scheduler.ts";

const raw = JSON.parse(
  await readFile(new URL("../examples/johan.json", import.meta.url), "utf8"),
);
const fixture = JSON.parse(
  await readFile(new URL("../fixtures/abcd.json", import.meta.url), "utf8"),
) as Fixture;
const trip = () => prepareTrip(parseInput(structuredClone(raw), "2026-11-03"));
const response = (data: unknown) =>
  new Response(JSON.stringify(data), {
    headers: { "Content-Type": "application/json" },
  });

test("Google duration parser rejects missing, negative and malformed durations", () => {
  assert.equal(duration("2.5s"), 3);
  for (const value of [undefined, "-1s", "NaNs", "50m"])
    assert.throws(() => duration(value), /invalid duration/);
});

test("matrix failures and omitted elements never become zero-minute journeys", () => {
  const t = trip();
  const data = new LiveData("test-key", new Http());
  const origins = [t.origin, ...t.places];
  assert.throws(
    () =>
      data.parseMatrix(
        [
          {
            originIndex: 0,
            destinationIndex: 0,
            status: { code: 7 },
            condition: "ROUTE_NOT_FOUND",
          },
        ],
        t,
        origins,
      ),
    /No usable Google route/,
  );
  assert.throws(() => data.parseMatrix([], t, origins), /omitted/);
});

test("Google matrix preserves directed cells and supports omitted zero-value protobuf indices", async () => {
  const t = trip();
  const origins = [t.origin, ...t.places];
  const cells = origins.flatMap((from, oi) =>
    t.places
      .filter((to) => to.id !== from.id)
      .map((to) => ({
        ...(oi ? { originIndex: oi } : {}),
        ...(t.places.indexOf(to)
          ? { destinationIndex: t.places.indexOf(to) }
          : {}),
        status: {},
        condition: "ROUTE_EXISTS",
        duration: `${100 + oi * 10 + t.places.indexOf(to)}s`,
        distanceMeters: 1000,
      })),
  );
  let body: Record<string, unknown> | undefined;
  const data = new LiveData(
    "test-key",
    new Http(async (_url, init) => {
      body = JSON.parse(String(init?.body));
      return response(cells);
    }),
  );
  const matrix = await data.matrix(t);
  assert.equal(matrix.size, 9);
  assert.notEqual(
    matrix.get("B/C")!.durationSeconds,
    matrix.get("C/B")!.durationSeconds,
  );
  assert.equal(body!.routingPreference, "TRAFFIC_AWARE");
});

test("walking routes omit driving-only traffic settings and use proposed departure time", async () => {
  const t = trip();
  t.input.mode = "WALK";
  let body: Record<string, unknown> | undefined;
  const http = new Http(async (_url, init) => {
    body = JSON.parse(String(init?.body));
    return response({ routes: [{ duration: "600s", distanceMeters: 800 }] });
  });
  const data = new LiveData("test-key", http);
  await data.route(t.origin, t.places[0]!, t.startsAt, t);
  assert.equal(body!.travelMode, "WALK");
  assert.equal(body!.routingPreference, undefined);
  assert.equal(body!.departureTime, new Date(t.startsAt * 1000).toISOString());
  await data.route(t.origin, t.places[0]!, t.startsAt, t);
  assert.equal(http.calls["Google Routes leg"], 1);
});

test("weather parser preserves nulls and rejects overlapping hourly samples", () => {
  const missing = parseWeather(
    {
      hourly: { time: [1793689200], precipitation_probability: [null] },
      daily: { sunset: [null], sunrise: [null] },
    },
    "C",
    "weather:C",
  );
  assert.equal(missing.hours[0]!.rainProbability, null);
  assert.equal(missing.sunset, null);
  assert.throws(
    () =>
      parseWeather(
        { hourly: { time: [1793689200, 1793689200] } },
        "C",
        "weather:C",
      ),
    /nonoverlapping/,
  );
});

test("failed weather request is disclosed as unavailable, without fabricated values", async () => {
  const data = new LiveData(
    "test-key",
    new Http(async () => new Response("{}", { status: 503 })),
  );
  const weather = await data.weather(trip());
  assert.ok(
    [...weather.values()].every(
      (w) => w.hours.length === 0 && w.sunset === null && w.warning,
    ),
  );
});

test("provider error output does not echo a secret from the response body", async () => {
  const http = new Http(
    async () => new Response('{"error":"example-secret"}', { status: 403 }),
  );
  await assert.rejects(
    http.json("Google Routes", "https://example.test"),
    (error) =>
      error instanceof Error &&
      error.message.includes("HTTP 403") &&
      !error.message.includes("example-secret"),
  );
});

test("OpenRouter adapter sends strict structured output and validates the returned selection", async () => {
  const t = trip();
  const { candidates } = await schedule(t, new FixtureData(fixture));
  const decision = fixtureDecision(candidates, t).decision;
  let body: Record<string, unknown> | undefined;
  const http = new Http(async (_url, init) => {
    body = JSON.parse(String(init?.body));
    return response({
      id: "stub-completion",
      model: "test-model",
      choices: [
        {
          finish_reason: "stop",
          message: { content: JSON.stringify(decision) },
        },
      ],
      usage: { prompt_tokens: 100, completion_tokens: 50 },
    });
  });
  const result = await chooseWithAI(candidates, t, http, {
    key: "test-key",
    model: "test-model",
    maxTokens: 2500,
  });
  assert.equal(result.decision.candidateId, decision.candidateId);
  assert.equal(http.calls.OpenRouter, 1);
  assert.equal(body!.model, "test-model");
  assert.deepEqual(body!.provider, { require_parameters: true });
  const prompt = JSON.parse(
    (body!.messages as { content: string }[])[1]!.content,
  );
  assert.equal(prompt.startsAt, "2026-11-03T14:00:00.000+07:00");
  assert.equal(prompt.finishBy, "2026-11-03T19:00:00.000+07:00");
  assert.ok(prompt.candidates[0].stops[0].arrivalAt.endsWith("+07:00"));
  assert.equal(prompt.candidates[0].scoreRank, 1);
  assert.equal((body!.response_format as { type: string }).type, "json_schema");
});

test("truncated AI response fails instead of falling back to deterministic selection", async () => {
  const t = trip();
  const { candidates } = await schedule(t, new FixtureData(fixture));
  const http = new Http(async () =>
    response({
      choices: [{ finish_reason: "length", message: { content: "{}" } }],
    }),
  );
  await assert.rejects(
    chooseWithAI(candidates, t, http, {
      key: "test-key",
      model: "test-model",
      maxTokens: 256,
    }),
    /did not finish normally/,
  );
});

test("explicit reasoning-off setting reaches OpenRouter without dropping structured output", async () => {
  const t = trip();
  const { candidates } = await schedule(t, new FixtureData(fixture));
  const decision = fixtureDecision(candidates, t).decision;
  let sent: Record<string, unknown> = {};
  const http = new Http(async (_url, init) => {
    sent = JSON.parse(String(init?.body));
    return response({
      model: "test-model",
      choices: [
        {
          finish_reason: "stop",
          message: { content: JSON.stringify(decision) },
        },
      ],
    });
  });
  const result = await chooseWithAI(candidates, t, http, {
    key: "test-key",
    model: "test-model",
    maxTokens: 2500,
    reasoningMode: "off",
  });
  assert.deepEqual(sent.reasoning, { enabled: false });
  assert.equal((sent.response_format as { type: string }).type, "json_schema");
  assert.equal(result.reasoningMode, "off");
  assert.equal(result.maxTokens, 2500);
});

test("reasoning-on uses the larger completion budget and request timeout", async () => {
  const t = trip();
  const { candidates } = await schedule(t, new FixtureData(fixture));
  const decision = fixtureDecision(candidates, t).decision;
  let sent: Record<string, unknown> = {};
  let observedTimeout: number | undefined;
  class Observer extends Http {
    override async json(
      _label: string,
      _url: string,
      init?: RequestInit,
      timeout?: number,
    ) {
      sent = JSON.parse(String(init?.body));
      observedTimeout = timeout;
      return {
        model: "test-model",
        choices: [
          {
            finish_reason: "stop",
            message: { content: JSON.stringify(decision) },
          },
        ],
      };
    }
  }
  const result = await chooseWithAI(candidates, t, new Observer(), {
    key: "test-key",
    model: "test-model",
    maxTokens: 16384,
    reasoningMode: "on",
    timeoutMs: 180000,
  });
  assert.deepEqual(sent.reasoning, { enabled: true });
  assert.equal(sent.max_tokens, 16384);
  assert.equal(observedTimeout, 180000);
  assert.equal(result.reasoningMode, "on");
});
