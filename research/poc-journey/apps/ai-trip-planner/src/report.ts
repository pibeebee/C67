import {
  iso,
  wib,
  type AIResult,
  type Candidate,
  type Evidence,
  type Mode,
  type Trip,
} from "./domain.ts";
import { WEIGHTS } from "./scheduler.ts";

export function makeReport(
  mode: Mode,
  trip: Trip,
  ai: AIResult,
  candidates: Candidate[],
  baselineOriginal: Candidate,
  baselineTravelOnly: Candidate,
  initialCandidateCount: number,
  evidence: Evidence[],
  calls: Record<string, number>,
  elapsedMs: number,
) {
  const selected = candidates.find((c) => c.id === ai.decision.candidateId)!;
  return {
    schemaVersion: "0.1.0",
    generatedAt: new Date().toISOString(),
    mode,
    validationStatus: ai.called
      ? mode === "live"
        ? "Live provider experiment; human quality review still required."
        : "Real AI over synthetic route/weather data; not real-world validation."
      : "Fixture only; AI was NOT executed. Not evidence of AI quality.",
    input: trip.input,
    progress: {
      visitedIds: trip.visited.map((p) => p.id),
      originNow: trip.origin,
      departureAt: iso(trip.startsAt),
      finishBy: iso(trip.finishBy),
    },
    ai: {
      ...ai,
      explanationValidation:
        "Destination IDs and evidence references checked. Prose claims are not automatically fact-checked.",
    },
    recommendation: selected,
    baselineOriginal,
    baselineTravelOnly,
    alternatives: candidates.filter((c) => c.id !== selected.id),
    comparisonWithOriginal: {
      travelMinutesDelta:
        selected.travelMinutes - baselineOriginal.travelMinutes,
      rainExposureMinutesDelta:
        selected.rainExposureMinutes - baselineOriginal.rainExposureMinutes,
      preferredWindowMissMinutesDelta:
        selected.preferredWindowMissMinutes -
        baselineOriginal.preferredWindowMissMinutes,
      finishesMinutesDelta:
        (selected.finishesAt - baselineOriginal.finishesAt) / 60,
    },
    checks: {
      destinationsPreserved: true,
      visitDurationsPreserved: true,
      timelineArithmeticChecked: true,
      selectedPlanFeasible: selected.feasible,
      noSilentAIOrRouteFallback: true,
      aiActuallyCalled: ai.called,
      allProviderDataLive: mode === "live",
      completeRainForecastCoverage: selected.unknownWeatherMinutes === 0,
    },
    search: {
      initialCandidateCount,
      refinedCandidateCount: candidates.length,
      globallyOptimal: false,
      strategy:
        "All permutations at initial departure, each with direct/preferred-wait variants; refine top 3 plus original-order and travel-only baselines at per-leg departures.",
      weights: WEIGHTS,
    },
    diagnostics: { elapsedMs, httpCalls: calls },
    warnings: [
      ...(mode !== "live"
        ? ["Routing, forecast and sunset are synthetic fixtures."]
        : []),
      ...(!ai.called
        ? [
            "OpenRouter was not called. This run is only a local pipeline demonstration.",
          ]
        : []),
      "Place context, exposure and opening hours are user-supplied assumptions; no web research was performed.",
      "Finish time means the end of the final visit. No journey home is included.",
      "Before-sunset preference does not establish golden hour, cloud visibility or venue suitability.",
      "Rain exposure is a scoring proxy, not a forecast of how many minutes it will rain. Waiting and journey weather are not scored.",
      "Weights, shortlist quality and AI reasoning need evaluation. No global optimality or user benefit is established.",
      ...(evidence.some(
        (e) =>
          e.data &&
          typeof e.data === "object" &&
          "fallbackInfo" in e.data &&
          (e.data as { fallbackInfo: unknown }).fallbackInfo,
      )
        ? [
            "Google reported fallback routing for at least one estimate; inspect the evidence.",
          ]
        : []),
      ...selected.violations,
      ...selected.stops.flatMap((s) =>
        s.warnings.map((w) => `${s.placeId}: ${w}`),
      ),
    ],
    evidence,
  };
}
export type Report = ReturnType<typeof makeReport>;
const cell = (v: unknown) =>
  String(v)
    .replace(/\|/g, "\\|")
    .replace(/[\r\n]/g, " ");
const n = (v: number) => v.toFixed(1);
export function markdown(report: Report): string {
  const c = report.recommendation;
  const lines = [
    `# ${cell(report.input.title)}`,
    "",
    `**Mode:** ${report.mode} · **Date:** ${report.input.date} · **Time zone:** WIB`,
    "",
    `**Evidence status:** ${report.validationStatus}`,
    "",
    `**AI called:** ${report.ai.called ? `yes (${cell(report.ai.model)})` : "NO — deterministic simulation"}`,
    "",
    `**Visited:** ${report.progress.visitedIds.join(", ") || "none"} · **Departure now:** ${wib(Date.parse(report.progress.departureAt) / 1000)} · **Finish by:** ${wib(Date.parse(report.progress.finishBy) / 1000)}`,
    "",
    `**Recommended:** ${c.order.join(" → ")} · **Feasible:** ${c.feasible ? "yes, against supplied constraints" : "NO — review conflicts below"}`,
    "",
    report.ai.decision.summary,
    "",
    "| Stop | Arrival | Visit | Leave | Travel (min) | Wait (min) | Rain probability during visit |",
    "|---|---|---|---|---:|---:|---|",
    ...c.stops.map(
      (s) =>
        `| ${cell(s.name)} | ${wib(s.arrivalAt)} | ${wib(s.visitAt)} | ${wib(s.leaveAt)} | ${n(s.leg.durationSeconds / 60)} | ${n(s.waitMinutes)} | ${s.weather.rainProbability === null ? "unknown" : `${n(s.weather.rainProbability)}% (forecast)`} |`,
    ),
    "",
    "## Comparison",
    "",
    "| Plan | Order | Feasible | Travel (min) | Wait (min) | Rain exposure proxy (min) | Missed preferred overlap (min) | Finish | Score |",
    "|---|---|---|---:|---:|---:|---:|---|---:|",
    ...[
      ["AI / selected", c],
      ["Original order", report.baselineOriginal],
      ["Travel-only baseline", report.baselineTravelOnly],
    ].map(([label, value]) => {
      const p = value as Candidate;
      return `| ${label} | ${p.order.join(" → ")} | ${p.feasible} | ${n(p.travelMinutes)} | ${n(p.waitMinutes)} | ${n(p.rainExposureMinutes)} | ${n(p.preferredWindowMissMinutes)} | ${wib(p.finishesAt)} | ${n(p.score)} |`;
    }),
    "",
    "## Rationale",
    "",
    ...report.ai.decision.rationale.map(
      (r) =>
        `- **${cell(r.placeId)}:** ${r.reason} Sources: ${r.evidenceIds.map((id) => `\`${id}\``).join(", ")}.`,
    ),
    "",
    "## Tradeoffs and uncertainties",
    "",
    ...[
      ...report.ai.decision.tradeoffs,
      ...report.ai.decision.uncertainties,
    ].map((v) => `- ${v}`),
    "",
    "## Warnings and constraints",
    "",
    ...report.warnings.map((v) => `- ${v}`),
    "",
    "## Experiment diagnostics",
    "",
    `- ${report.search.initialCandidateCount} initial candidates; ${report.search.refinedCandidateCount} refined candidates. Global optimality: not established.`,
    `- HTTP calls: ${JSON.stringify(report.diagnostics.httpCalls)}. Elapsed: ${report.diagnostics.elapsedMs} ms.`,
    `- AI usage (as returned by provider): ${JSON.stringify(report.ai.usage)}.`,
    "- Inspect report.json for all alternatives, constraints, normalized input and evidence. Evidence IDs validate references, not the truth of every sentence.",
    "",
  ];
  return lines.join("\n");
}
