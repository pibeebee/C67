import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import {
  parseAuditInput,
  jstAt,
  jstStamp,
  checkLeg,
  deriveFindings,
  type Snapshot,
} from "../src/audit.ts";
import { validateAuditDecision } from "../src/audit-model.ts";
import { contextBudget, checkUsage } from "../src/context.ts";
import { Http } from "../src/http.ts";

const raw = JSON.parse(
  await readFile(
    new URL("../examples/funabashi-enoshima-2026-11-05.json", import.meta.url),
    "utf8",
  ),
);
const input = () => parseAuditInput(structuredClone(raw));
test("Japan case preserves all 24 events and uses JST rather than WIB", () => {
  const value = input();
  assert.equal(value.events.length, 24);
  assert.equal(value.events[0]!.time, "07:00");
  assert.equal(value.events.at(-1)!.time, "22:00");
  const at = jstAt(value.date, "07:00");
  assert.equal(new Date(at * 1000).toISOString(), "2026-11-04T22:00:00.000Z");
  assert.equal(jstStamp(at), "2026-11-05T07:00:00.000+09:00");
});
test("unresolved apartment does not generate a fabricated route or provider call", async () => {
  const value = input();
  const http = new Http(async () => {
    throw new Error("Must not call");
  });
  const result = await checkLeg(value, value.legs[0]!, http);
  assert.equal(result.status, "unresolved_location");
  assert.equal(result.estimatedMinutes, null);
  assert.deepEqual(http.calls, {});
});
test("empty Japanese transit response remains unknown, not zero or a driving substitute", async () => {
  const value = input();
  let sent: Record<string, unknown> = {};
  const http = new Http(async (_url, init) => {
    sent = JSON.parse(String(init?.body));
    return new Response(JSON.stringify({ geocodingResults: {} }));
  });
  const result = await checkLeg(value, value.legs[1]!, http);
  assert.equal(sent.travelMode, "TRANSIT");
  assert.equal(sent.routingPreference, undefined);
  assert.equal(sent.departureTime, "2026-11-05T07:15:00.000+09:00");
  assert.equal(result.status, "no_route");
  assert.equal(result.estimatedMinutes, null);
});
test("walking time shares the sightseeing slot without silently preserving a full-hour visit", async () => {
  const value = input();
  const http = new Http(
    async () =>
      new Response(
        JSON.stringify({
          routes: [{ duration: "900s", distanceMeters: 1200 }],
        }),
      ),
  );
  const result = await checkLeg(value, value.legs[2]!, http);
  assert.equal(result.plannedMinutes, 60);
  assert.equal(result.estimatedMinutes, 15);
  assert.equal(result.remainingMinutes, 45);
});
test("seasonal illumination checks are date-specific and do not rule out all ordinary lighting", () => {
  const findings = deriveFindings(input(), [], []).filter(
    (f) => f.id.includes("hoseki") || f.id.includes("candle"),
  );
  assert.equal(findings.length, 2);
  assert.ok(
    findings.every((f) =>
      f.message.includes("ordinary lighting availability remains unknown"),
    ),
  );
});
test("invalid time ordering and transit intermediate waypoints fail before provider requests", () => {
  const a = structuredClone(raw);
  a.events[1].time = "06:00";
  assert.throws(() => parseAuditInput(a), /increase/);
  const b = structuredClone(raw);
  b.legs[1].via = ["komachi"];
  assert.throws(() => parseAuditInput(b), /intermediate/);
});
test("one-million cap reserves completion and checks reported input plus completion without double-counting reasoning", () => {
  const budget = contextBudget(
    { messages: [{ content: "鎌倉 江の島" }] },
    16384,
    1000000,
  );
  assert.equal(budget.limitTokens, 1000000);
  assert.ok(budget.estimatedInputTokens > 8192);
  assert.ok(budget.estimatedTotalTokens < 1000000);
  assert.throws(
    () => contextBudget({ content: "x".repeat(1000000) }, 16384, 1000000),
    /before any AI call/,
  );
  assert.deepEqual(
    checkUsage(
      {
        prompt_tokens: 10000,
        completion_tokens: 5000,
        completion_tokens_details: { reasoning_tokens: 3000 },
      },
      15000,
    ),
    {
      inputTokens: 10000,
      completionTokens: 5000,
      totalTokens: 15000,
      withinLimit: true,
    },
  );
  assert.throws(
    () => checkUsage({ prompt_tokens: 10000, completion_tokens: 5000 }, 14999),
    /exceeds/,
  );
});
test("AI audit cannot claim confirmation or invent an event/source reference", () => {
  const data = input();
  const snapshot: Snapshot = {
    collectedAt: "2026-11-02T12:00:00Z",
    input: data,
    legs: [],
    forecasts: [],
    findings: deriveFindings(data, [], []),
    httpCalls: {},
  };
  const answer = {
    status: "needs_changes_or_confirmation",
    summary: "Check event dates.",
    findings: [
      {
        eventIds: ["E19"],
        severity: "conflict",
        explanation: "Seasonal event date differs.",
        proposedAdjustment: "Confirm which illumination is intended.",
        evidenceIds: ["official:hoseki-2026"],
      },
    ],
    uncertainties: ["Apartment address unknown."],
  };
  assert.equal(validateAuditDecision(answer, snapshot).findings.length, 1);
  assert.throws(
    () => validateAuditDecision({ ...answer, status: "confirmed" }, snapshot),
    /cannot claim/,
  );
  const bad = structuredClone(answer);
  bad.findings[0]!.evidenceIds = ["made-up"];
  assert.throws(
    () => validateAuditDecision(bad, snapshot),
    /unknown audit evidence/,
  );
});
