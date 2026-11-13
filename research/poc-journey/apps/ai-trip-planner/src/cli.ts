import { readFile, mkdir, writeFile } from "node:fs/promises";
import { parseArgs } from "node:util";
import { resolve } from "node:path";
import { aiConfig, chooseWithAI, fixtureDecision } from "./ai.ts";
import { FixtureData, LiveData, type Fixture } from "./data.ts";
import {
  ensure,
  parseInput,
  prepareTrip,
  type Evidence,
  type Mode,
} from "./domain.ts";
import { Http } from "./http.ts";
import { markdown, makeReport } from "./report.ts";
import { schedule } from "./scheduler.ts";

const HELP = `C67 itinerary PoC (Node 24+, no UI)

  npm run demo
  npm run config -- --mode live
  npm run plan -- --mode live --input examples/johan.json --out results/live-01
  npm run plan -- --mode fixture-ai --input examples/johan.json
  npm run plan -- --mode fixture --input examples/johan.json --visited D --from D --ready-at 17:20

Options:
  --mode live|fixture-ai|fixture   Default: live. No automatic simulated fallback.
  --input PATH                  Trip JSON (default: examples/johan.json).
  --date YYYY-MM-DD              Override input date (otherwise input supports tomorrow).
  --visited B,D --from D --ready-at HH:mm
                                Replan only unvisited stops, leaving D at the given WIB time.
  --out DIRECTORY               Write report.json and report.md; existing files are not overwritten.
  --check-config                Show key presence only; never make provider calls.
  --help                        Show this help.
`;

async function main() {
  const { values } = parseArgs({
    options: {
      mode: { type: "string", default: "live" },
      input: { type: "string", default: "examples/johan.json" },
      date: { type: "string" },
      visited: { type: "string" },
      from: { type: "string" },
      "ready-at": { type: "string" },
      out: { type: "string" },
      "check-config": { type: "boolean" },
      help: { type: "boolean" },
    },
  });
  if (values.help) {
    console.log(HELP);
    return;
  }
  ensure(
    ["live", "fixture-ai", "fixture"].includes(values.mode),
    "--mode must be live, fixture-ai or fixture.",
  );
  const mode = values.mode as Mode;
  const required =
    mode === "fixture"
      ? []
      : mode === "fixture-ai"
        ? ["OPENROUTER_API_KEY", "OPENROUTER_MODEL"]
        : ["GOOGLE_MAPS_API_KEY", "OPENROUTER_API_KEY", "OPENROUTER_MODEL"];
  const missing = required.filter((key) => !process.env[key]?.trim());
  if (values["check-config"]) {
    console.log(
      JSON.stringify(
        {
          mode,
          required: Object.fromEntries(
            required.map((key) => [
              key,
              process.env[key]?.trim() ? "set" : "missing",
            ]),
          ),
          ready: missing.length === 0,
          noNetworkCallsMade: true,
        },
        null,
        2,
      ),
    );
    if (missing.length) process.exitCode = 2;
    return;
  }
  ensure(
    missing.length === 0,
    `Missing configuration: ${missing.join(", ")}. Copy .env.example to .env and configure locally. Use npm run demo for an explicitly synthetic, non-AI demonstration.`,
  );
  const modelConfig = mode === "fixture" ? null : aiConfig(process.env);
  const inputPath = resolve(values.input);
  let raw: unknown;
  try {
    raw = JSON.parse(await readFile(inputPath, "utf8"));
  } catch {
    throw new Error(
      "Cannot read trip input as JSON. Check --input path and JSON syntax.",
    );
  }
  const trip = prepareTrip(parseInput(raw, values.date), {
    visitedIds: values.visited
      ? values.visited.split(",").map((s) => s.trim())
      : [],
    fromId: values.from,
    readyAt: values["ready-at"],
  });
  if (mode === "live")
    ensure(
      trip.startsAt > Date.now() / 1000 + 60,
      "Live routing requires a future departure (at least one minute from now). Use --date or change the trip time.",
    );
  const started = Date.now();
  const http = new Http();
  const fixture = JSON.parse(
    await readFile(new URL("../fixtures/abcd.json", import.meta.url), "utf8"),
  ) as Fixture;
  const provider =
    mode === "live"
      ? new LiveData(process.env.GOOGLE_MAPS_API_KEY!.trim(), http)
      : new FixtureData(fixture);
  console.error(
    `[PoC] ${mode}: evaluating ${trip.places.length} remaining destinations. ${mode === "fixture" ? "AI will NOT be called." : "One OpenRouter call will be made after scheduling."}`,
  );
  const result = await schedule(trip, provider);
  const ai =
    mode === "fixture"
      ? fixtureDecision(result.candidates, trip)
      : await chooseWithAI(result.candidates, trip, http, modelConfig!);
  const inputEvidence: Evidence[] = trip.places.map((p) => ({
    id: `input:${p.id}`,
    source: "User-provided, unverified place context and constraints",
    synthetic: false,
    fetchedAt: new Date().toISOString(),
    data: p,
  }));
  const candidateEvidence: Evidence[] = result.candidates.map((c) => ({
    id: `candidate:${c.id}`,
    source: "PoC schedule calculation",
    synthetic: mode !== "live",
    fetchedAt: new Date().toISOString(),
    data: {
      order: c.order,
      score: c.score,
      feasible: c.feasible,
      violations: c.violations,
    },
  }));
  const report = makeReport(
    mode,
    trip,
    ai,
    result.candidates,
    result.baselineOriginal,
    result.baselineTravelOnly,
    result.initialCandidateCount,
    [...inputEvidence, ...provider.evidence, ...candidateEvidence],
    http.calls,
    Date.now() - started,
  );
  const rendered = markdown(report);
  if (values.out) {
    const directory = resolve(values.out);
    await mkdir(directory, { recursive: true, mode: 0o700 });
    await writeFile(
      resolve(directory, "report.json"),
      JSON.stringify(report, null, 2) + "\n",
      { flag: "wx", mode: 0o600 },
    );
    await writeFile(resolve(directory, "report.md"), rendered, {
      flag: "wx",
      mode: 0o600,
    });
    console.error(`[PoC] Reports saved to ${directory}`);
  }
  console.log(rendered);
}

main().catch((error) => {
  const message = error instanceof Error ? error.message : "Unknown error.";
  // Even unexpected errors must not leak configured keys into logs.
  let safe = message;
  for (const key of [
    process.env.GOOGLE_MAPS_API_KEY,
    process.env.OPENROUTER_API_KEY,
  ])
    if (key) safe = safe.split(key).join("[REDACTED]");
  console.error(`[PoC] ${safe}`);
  process.exitCode = 1;
});
