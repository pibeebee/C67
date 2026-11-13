import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import {
  parseUntimed,
  validateDayProposal,
  forecastAvailability,
  verifyVisits,
  type PlaceContext,
  type DayProposal,
  type DayRow,
} from "../src/untimed.ts";

const raw = JSON.parse(
  await readFile(
    new URL(
      "../examples/funabashi-enoshima-2026-12-05-untimed.json",
      import.meta.url,
    ),
    "utf8",
  ),
);
const context = JSON.parse(
  await readFile(
    new URL(
      "../examples/funabashi-enoshima-place-context.json",
      import.meta.url,
    ),
    "utf8",
  ),
) as PlaceContext;
const input = parseUntimed(raw, context);
// Synthetic timeline tests coverage and spatial/clock integrity, never travel feasibility.
function timeline(): DayProposal {
  let minute = 60;
  let location = input.origin;
  const rows: DayRow[] = [];
  const clock = (m: number) =>
    `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;
  const move = (to: string, mode: "WALK" | "TRANSIT" = "WALK") => {
    rows.push({
      kind: "move",
      activityId: null,
      from: location,
      to,
      start: clock(minute),
      end: clock(++minute),
      mode,
      note: "Synthetic transfer.",
    });
    location = to;
  };
  for (const activity of input.activities) {
    if (activity.id === "E03") move("kamakura_station", "TRANSIT");
    if (activity.id === "E07") {
      move("kamakura_station");
      move("inamura_station", "TRANSIT");
    }
    if (activity.id === "E09") {
      move("inamura_station");
      move("shichiri_station", "TRANSIT");
    }
    if (activity.id === "E22") move("katase_station");
    if (location !== activity.locationId) {
      rows.push({
        kind: "move",
        activityId: null,
        from: location,
        to: activity.locationId,
        start: clock(minute),
        end: clock(++minute),
        mode: input.requiredTransit.some(
          (p) => p.from === location && p.to === activity.locationId,
        )
          ? "TRANSIT"
          : "WALK",
        note: "Synthetic transfer, not a provider estimate.",
      });
      location = activity.locationId;
    }
    rows.push({
      kind: "visit",
      activityId: activity.id,
      from: location,
      to: location,
      start: clock(minute),
      end: clock((minute += 5)),
      mode: "NONE",
      note: "Synthetic visit.",
    });
  }
  rows.push({
    kind: "move",
    activityId: null,
    from: location,
    to: input.returnTo,
    start: clock(minute),
    end: clock(++minute),
    mode: "TRANSIT",
    note: "Synthetic return.",
  });
  return {
    status: "proposal_needs_verification",
    summary: "Synthetic only.",
    assumptions: [],
    uncertainties: [],
    rows,
  };
}
test("new input contains no baseline times/durations and starts/ends at Funabashi station", () => {
  assert.equal(input.date, "2026-12-05");
  assert.equal(input.activities.length, 14);
  assert.equal(input.origin, "funabashi_station");
  assert.equal(input.returnTo, input.origin);
  assert.equal(/\d{2}:\d{2}/.test(JSON.stringify(input)), false);
  assert.throws(
    () => parseUntimed({ ...raw, startTime: "07:00" }, context),
    /no clock/,
  );
  const withDuration = structuredClone(raw);
  withDuration.activities[0].durationMinutes = 45;
  assert.throws(() => parseUntimed(withDuration, context), /durations\/times/);
});
test("generated timelines cannot teleport, overlap or omit the station return", () => {
  assert.equal(
    validateDayProposal(timeline(), input, context).rows.length > 0,
    true,
  );
  const teleport = timeline();
  teleport.rows[1]!.from = "bridge";
  assert.throws(
    () => validateDayProposal(teleport, input, context),
    /teleports/,
  );
  const overlap = timeline();
  overlap.rows[1]!.start = "01:00";
  assert.throws(
    () => validateDayProposal(overlap, input, context),
    /gap or overlap/,
  );
  const noReturn = timeline();
  noReturn.rows.pop();
  assert.throws(() => validateDayProposal(noReturn, input, context), /return/);
});
test("optional Oiwayamichi remains visible and the coastal WALK cannot become transit", () => {
  const noOptional = timeline();
  const row = noOptional.rows.find((r) => r.activityId === "E17")!;
  row.kind = "wait";
  row.activityId = null;
  assert.throws(
    () => validateDayProposal(noOptional, input, context),
    /Every requested activity/,
  );
  const changed = timeline();
  changed.rows.find(
    (r) =>
      r.from === input.requiredWalk!.from && r.to === input.requiredWalk!.to,
  )!.mode = "TRANSIT";
  assert.throws(
    () => validateDayProposal(changed, input, context),
    /coastal walk/,
  );
  const skippedTrain = timeline();
  skippedTrain.rows.find(
    (r) => r.from === "kamakura_station" && r.to === "inamura_station",
  )!.mode = "WALK";
  assert.throws(
    () => validateDayProposal(skippedTrain, input, context),
    /Requested transit pair missing/,
  );
});
test("December forecast is unknown and source hours remain distinct from user input", () => {
  const availability = forecastAvailability(
    input.date,
    new Date("2026-11-02T13:00:00Z"),
  );
  assert.equal(availability.status, "outside_forecast_horizon");
  assert.equal(availability.daysAhead, 33);
  assert.equal(availability.rainProbability, null);
  assert.equal(availability.sunset, null);
  const checks = verifyVisits(input, context, timeline());
  assert.ok(checks.find((c) => c.activityId === "E19")!.status === "conflict");
  assert.ok(checks.find((c) => c.activityId === "E19")!.dateInPublishedSeason);
});
