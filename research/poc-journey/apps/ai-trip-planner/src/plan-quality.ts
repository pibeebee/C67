import { readFile, mkdir, writeFile, rename } from "node:fs/promises";
import { resolve, dirname } from "node:path";
import { parseArgs } from "node:util";
import { ensure } from "./domain.ts";
import { parsePlaceContext } from "./place-context.ts";
import { parseUntimed } from "./untimed.ts";
import { researchConfig } from "./research-browser.ts";
import { workflowConfig } from "./workflow-config.ts";
import { evidenceWorkflow } from "./evidence-workflow.ts";
import type { Simulation } from "./planning-simulation.ts";
import type { SemanticReview } from "./workflow-review.ts";

const json = async (path: string) =>
  JSON.parse(await readFile(resolve(path), "utf8"));
const cell = (v: unknown) =>
  String(v ?? "—")
    .replace(/[\r\n]/g, " ")
    .replace(/([\\|\[\]<>])/g, "\\$1");
async function main() {
  const { values } = parseArgs({
    options: {
      input: { type: "string" },
      context: { type: "string" },
      research: { type: "string" },
      out: { type: "string" },
    },
    strict: true,
  });
  ensure(
    values.input && values.context && values.out,
    "Use --input FILE --context FILE [--research FILE] --out NEW_DIR. Historical evidence snapshots use plan:research:v2.",
  );
  const context = parsePlaceContext(await json(values.context));
  const input = parseUntimed(await json(values.input), context);
  ensure(
    context.facts.every((f) =>
      f.activityIds.every((id) => input.activities.some((a) => a.id === id)),
    ),
    "Context fact references another trip's activity.",
  );
  const rc = researchConfig(
    values.research ? await json(values.research) : context.research,
    context,
  );
  const options = workflowConfig(process.env);
  ensure(
    options.base.reasoningMode === "on",
    "This workflow requires reasoning on.",
  );
  ensure(
    process.env.GOOGLE_MAPS_API_KEY?.trim(),
    "Google Routes key is missing.",
  );
  const out = resolve(values.out);
  await mkdir(dirname(out), { recursive: true });
  await mkdir(out, { mode: 0o700 });
  const save = async (name: string, value: unknown) => {
    const target = resolve(out, name);
    await mkdir(dirname(target), { recursive: true, mode: 0o700 });
    await writeFile(`${target}.tmp`, JSON.stringify(value, null, 2) + "\n", {
      mode: 0o600,
    });
    await rename(`${target}.tmp`, target);
  };
  await save("run.json", {
    startedAt: new Date().toISOString(),
    workflowVersion: 3,
    input,
    roleModels: Object.fromEntries(
      Object.entries(options.roles).map(([role, c]) => [
        role,
        {
          model: c.model,
          maxCompletionTokens: c.maxTokens,
          timeoutMs: c.timeoutMs,
        },
      ]),
    ),
    constraints:
      "No change to user destinations; reviewer agreement does not replace evidence.",
  });
  const result = await evidenceWorkflow(
    input,
    context,
    rc,
    options,
    save,
    process.env.GOOGLE_MAPS_API_KEY!,
  );
  const simulation = result.simulation as Simulation | null,
    review = result.review as SemanticReview | null;
  const lines = [
    `# Evidence-driven itinerary — ${input.date}`,
    "",
    `Status: **${result.status}**. Stop reason: ${cell(result.stopReason)}.`,
    "",
    `User places and modes are preserved. All clock times are proposed/simulated JST. verifiedTravelFeasibility remains false.`,
    "",
    `Independent review matches current evidence: ${result.reviewMatchesCurrentEvidence}.`,
    "",
    "## Evidence requirements",
    "",
    "| Requirement | Critical | Evidence status | Sources |",
    "|---|---|---|",
    ...result.requirements.map(
      (r) =>
        `| ${cell(r.id)} | ${r.critical} | ${r.status} | ${cell(r.evidenceIds.join(", "))} |`,
    ),
  ];
  if (simulation) {
    lines.push(
      "",
      "## Simulated itinerary",
      "",
      "| Time JST | Minutes | Activity / movement | Basis |",
      "|---|---:|---|---|",
    );
    for (const row of simulation.rows) {
      const p = row.proposed;
      const activity = input.activities.find((a) => a.id === p.activityId);
      const name =
        row.durationSource === "source_opening_wait"
          ? `Waiting for supplied opening at ${context.locations[p.to]!.name}`
          : p.kind === "move"
            ? `${context.locations[p.from]!.name} → ${context.locations[p.to]!.name}`
            : p.kind === "wait"
              ? `Waiting (${p.waitPurpose ?? "unclassified"})`
              : activity?.label;
      lines.push(
        `| ${row.startsAt.slice(0, 16).replace("T", " ")} – ${row.endsAt.slice(0, 16).replace("T", " ")} | ${row.allocatedMinutes} | ${cell(name)} | ${cell(row.note)} |`,
      );
    }
    lines.push(
      "",
      "## Computed issues",
      "",
      ...simulation.issues.map(
        (i) =>
          `- ${i.severity}/${i.code}: ${cell(i.message)} [${cell(i.evidenceIds.join(", "))}]`,
      ),
    );
  }
  if (review)
    lines.push(
      "",
      "## Independent semantic review",
      "",
      cell(review.summary),
      "",
      ...review.findings.map(
        (f) =>
          `- ${f.severity}: ${cell(f.explanation)}; next: ${f.nextAction}; evidence: ${cell(f.evidenceIds.join(", "))}`,
      ),
    );
  lines.push(
    "",
    "## Evidence provenance and limits",
    "",
    `Browser: ${result.pages.filter((p) => p.status === "ok").length}/${result.pages.length} pages read. ${result.evidence.claims.length} quote-grounded claims. These counts do not establish completeness.`,
    "",
    `The reviewer is a separate API conversation and may share the same model. Semantic review can still be wrong; code guards, citations, unknown statuses and final user review remain necessary. General/weekly operating hours retain their conditions; no_route is not proof trains do not operate.`,
    "",
    `No booking, account action, new destination selection or silent restaurant substitution. Forecast outside the horizon remains deferred.`,
    "",
    `Detailed tool history (without internal reasoning), original context, evidence ledger, cycle snapshots and API usage are stored beside this report.`,
    "",
  );
  await writeFile(resolve(out, "report.md"), lines.join("\n"), { mode: 0o600 });
  console.log(
    JSON.stringify(
      {
        out,
        status: result.status,
        stopReason: result.stopReason,
        cycles: result.cycles,
        reviewMatchesCurrentEvidence: result.reviewMatchesCurrentEvidence,
        modelCalls: result.model.calls.length,
      },
      null,
      2,
    ),
  );
  if (
    ["incomplete", "review_incomplete", "no_valid_proposal"].includes(
      result.status,
    )
  )
    process.exitCode = 1;
}
main().catch((error) => {
  let message =
    error instanceof Error ? error.message : "Evidence workflow failed.";
  for (const secret of [
    process.env.GOOGLE_MAPS_API_KEY,
    process.env.OPENROUTER_API_KEY,
  ])
    if (secret) message = message.split(secret).join("[REDACTED]");
  console.error(`[Quality] ${message}`);
  process.exitCode = 1;
});
