// Two real model calls over the same saved candidates. No new Maps/weather requests.
// Only final answers and token counters are retained, never internal reasoning text.
import { readFile, mkdir, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { parseArgs } from "node:util";
import { createHash } from "node:crypto";
import { aiConfig, chooseWithAI } from "./ai.ts";
import {
  ensure,
  parseInput,
  prepareTrip,
  wib,
  type Decision,
} from "./domain.ts";
import { Http } from "./http.ts";
import { assertPreserved, rank } from "./scheduler.ts";
import { type Report } from "./report.ts";

function record(value: unknown): Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}
function number(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}
const hash = (value: unknown) =>
  createHash("sha256").update(JSON.stringify(value)).digest("hex");
type Observation = {
  actualModel: string | null;
  finishReason: string | null;
  promptTokens: number | null;
  completionTokens: number | null;
  reasoningTokens: number | null;
  visibleTokens: number | null;
  cachedPromptTokens: number | null;
  reportedCost: number | null;
  contentCharacters: number;
};
class ObservedHttp extends Http {
  promptHash: string | null = null;
  schemaHash: string | null = null;
  observation: Observation | null = null;
  finalAnswer: Record<string, unknown> | null = null;
  override async json(
    label: string,
    url: string,
    init: RequestInit = {},
    timeoutMs = 30000,
  ): Promise<unknown> {
    const request = record(JSON.parse(String(init.body)));
    this.promptHash = hash(request.messages);
    this.schemaHash = hash(request.response_format);
    const raw = record(await super.json(label, url, init, timeoutMs));
    const choice = record(
      Array.isArray(raw.choices) ? raw.choices[0] : undefined,
    );
    const message = record(choice.message);
    if (
      typeof message.content === "string" &&
      message.content.length <= 50000
    ) {
      try {
        const final = record(JSON.parse(message.content));
        // Only the requested final-answer fields; never persist reasoning/analysis fields.
        this.finalAnswer = Object.fromEntries(
          ["candidateId", "summary", "rationale", "tradeoffs", "uncertainties"]
            .filter((key) => key in final)
            .map((key) => [key, final[key]]),
        );
      } catch {
        /* Invalid final JSON is left unavailable. */
      }
    }
    const usage = record(raw.usage);
    const completion = number(usage.completion_tokens);
    const reasoning = number(
      record(usage.completion_tokens_details).reasoning_tokens,
    );
    this.observation = {
      actualModel: typeof raw.model === "string" ? raw.model : null,
      finishReason:
        typeof choice.finish_reason === "string" ? choice.finish_reason : null,
      promptTokens: number(usage.prompt_tokens),
      completionTokens: completion,
      reasoningTokens: reasoning,
      visibleTokens:
        completion !== null && reasoning !== null
          ? Math.max(0, completion - reasoning)
          : null,
      cachedPromptTokens: number(
        record(usage.prompt_tokens_details).cached_tokens,
      ),
      reportedCost: number(usage.cost),
      contentCharacters:
        typeof message.content === "string" ? message.content.length : 0,
    };
    return raw;
  }
}
type Variant = {
  mode: "off" | "on";
  maxTokens: number;
  timeoutMs: number;
  elapsedMs: number;
  passed: boolean;
  error: string | null;
  promptHash: string | null;
  schemaHash: string | null;
  observation: Observation | null;
  decision: Decision | null;
  finalAnswer: Record<string, unknown> | null;
  selectedFacts: {
    candidateId: string;
    order: string[];
    score: number;
    feasible: boolean;
    travelMinutes: number;
    waitMinutes: number;
    finishWIB: string;
    visits: {
      placeId: string;
      visitWIB: string;
      leaveWIB: string;
      durationMinutes: number;
    }[];
  } | null;
};
const cell = (value: unknown) =>
  String(value ?? "—")
    .replace(/\|/g, "\\|")
    .replace(/[\r\n]/g, " ");
function render(
  model: string,
  sourceAt: string,
  variants: Variant[],
  promptMatches: boolean,
  schemaMatches: boolean,
): string {
  const [off, on] = variants;
  const row = (label: string, values: unknown[]) =>
    `| ${label} | ${values.map(cell).join(" | ")} |`;
  const lines = [
    "# Perbandingan reasoning — Nemotron",
    "",
    `Model: \`${model}\`. Kandidat dari run ${sourceAt}; rute/cuaca tidak diambil ulang.`,
    "",
    `Prompt identik: **${promptMatches}**. JSON Schema identik: **${schemaMatches}**.`,
    "",
    "Perbandingan dua konfigurasi dengan satu sampel masing-masing. Reasoning dan budget output berubah bersama; hasil ini belum mengisolasi efek reasoning atau membuktikan keunggulan umum. Latensi/caching provider dapat berbeda.",
    "",
    "| Ukuran | Reasoning off | Reasoning on |",
    "|---|---|---|",
    row(
      "Batas completion token",
      variants.map((v) => v.maxTokens),
    ),
    row(
      "Input token",
      variants.map((v) => v.observation?.promptTokens),
    ),
    row(
      "Completion token terpakai",
      variants.map((v) => v.observation?.completionTokens),
    ),
    row(
      "Reasoning token",
      variants.map((v) => v.observation?.reasoningTokens),
    ),
    row(
      "Token terlihat (completion − reasoning)",
      variants.map((v) => v.observation?.visibleTokens),
    ),
    row(
      "Cached input token",
      variants.map((v) => v.observation?.cachedPromptTokens),
    ),
    row(
      "Waktu AI (detik)",
      variants.map((v) => (v.elapsedMs / 1000).toFixed(2)),
    ),
    row(
      "Finish reason",
      variants.map((v) => v.observation?.finishReason),
    ),
    row(
      "Lolos validasi struktur/referensi",
      variants.map((v) => v.passed),
    ),
    row(
      "Kandidat pilihan",
      variants.map((v) => v.selectedFacts?.candidateId),
    ),
    row(
      "Skor (lebih rendah lebih baik)",
      variants.map((v) => v.selectedFacts?.score),
    ),
    row(
      "Selesai WIB",
      variants.map((v) => v.selectedFacts?.finishWIB),
    ),
    row(
      "Biaya yang dilaporkan API",
      variants.map((v) => v.observation?.reportedCost),
    ),
    "",
    "**Batas validasi:** lulus struktur/referensi tidak membuktikan semua prosa benar. Teks reasoning internal tidak disimpan atau ditampilkan. Token completion mencakup reasoning dan jawaban akhir.",
    "",
  ];
  for (const variant of [off!, on!]) {
    lines.push(`## Reasoning ${variant.mode}`, "");
    if (variant.error) lines.push(`Hasil: ${variant.error}`, "");
    if (!variant.decision) {
      lines.push(
        "### Jawaban akhir yang ditolak",
        "",
        "```json",
        JSON.stringify(variant.finalAnswer, null, 2),
        "```",
        "",
      );
      continue;
    }
    lines.push(
      variant.decision.summary,
      "",
      "### Fakta jadwal dari kode",
      "",
      "| Tujuan | Mulai WIB | Selesai WIB | Durasi menit |",
      "|---|---|---|---:|",
      ...(variant.selectedFacts?.visits.map(
        (v) =>
          `| ${v.placeId} | ${v.visitWIB} | ${v.leaveWIB} | ${v.durationMinutes} |`,
      ) ?? []),
      "",
      "### Alasan akhir AI",
      "",
      ...variant.decision.rationale.map(
        (r) => `- **${r.placeId}:** ${r.reason}`,
      ),
      "",
      "### Tradeoff",
      "",
      ...variant.decision.tradeoffs.map((t) => `- ${t}`),
      "",
      "### Ketidakpastian",
      "",
      ...variant.decision.uncertainties.map((t) => `- ${t}`),
      "",
    );
  }
  return lines.join("\n");
}
async function main() {
  const { values } = parseArgs({
    options: {
      source: { type: "string", default: "results/super-vl-live/report.json" },
      out: { type: "string", default: "results/reasoning-comparison" },
      "off-tokens": { type: "string", default: "2500" },
      "on-tokens": { type: "string", default: "16384" },
    },
  });
  const sourcePath = resolve(values.source);
  const source = JSON.parse(await readFile(sourcePath, "utf8")) as Report;
  const visited = source.progress.visitedIds;
  const trip = prepareTrip(parseInput(source.input), {
    visitedIds: visited,
    fromId: visited.length ? source.progress.originNow.id : undefined,
    readyAt: visited.length
      ? wib(Date.parse(source.progress.departureAt) / 1000)
      : undefined,
  });
  const candidates = [source.recommendation, ...source.alternatives].sort(rank);
  for (const candidate of candidates) assertPreserved(trip, candidate);
  const configurations = (["off", "on"] as const).map((mode) =>
    aiConfig({
      ...process.env,
      OPENROUTER_REASONING: mode,
      OPENROUTER_MAX_TOKENS:
        mode === "off" ? values["off-tokens"] : values["on-tokens"],
      OPENROUTER_TIMEOUT_MS: mode === "on" ? "180000" : "30000",
    }),
  );
  const out = resolve(values.out);
  await mkdir(dirname(out), { recursive: true });
  await mkdir(out, { mode: 0o700 }); // Refuse reuse before spending any provider calls.
  const variants: Variant[] = [];
  for (const config of configurations) {
    const mode = config.reasoningMode as "off" | "on";
    console.error(
      `[Compare] ${mode}: ${config.maxTokens} completion tokens, timeout ${config.timeoutMs} ms.`,
    );
    const http = new ObservedHttp();
    const started = Date.now();
    let decision: Decision | null = null;
    let error: string | null = null;
    try {
      decision = (await chooseWithAI(candidates, trip, http, config)).decision;
    } catch (caught) {
      error =
        caught instanceof Error ? caught.message : "Comparison request failed.";
    }
    const selected = decision
      ? candidates.find((c) => c.id === decision.candidateId)
      : undefined;
    const variant: Variant = {
      mode,
      maxTokens: config.maxTokens,
      timeoutMs: config.timeoutMs,
      elapsedMs: Date.now() - started,
      passed: decision !== null,
      error,
      promptHash: http.promptHash,
      schemaHash: http.schemaHash,
      observation: http.observation,
      decision,
      finalAnswer: http.finalAnswer,
      selectedFacts: selected
        ? {
            candidateId: selected.id,
            order: selected.order,
            score: selected.score,
            feasible: selected.feasible,
            travelMinutes: selected.travelMinutes,
            waitMinutes: selected.waitMinutes,
            finishWIB: wib(selected.finishesAt),
            visits: selected.stops.map((s) => ({
              placeId: s.placeId,
              visitWIB: wib(s.visitAt),
              leaveWIB: wib(s.leaveAt),
              durationMinutes: (s.leaveAt - s.visitAt) / 60,
            })),
          }
        : null,
    };
    variants.push(variant);
    await writeFile(
      resolve(out, `${mode}.json`),
      JSON.stringify(variant, null, 2) + "\n",
      { flag: "wx", mode: 0o600 },
    );
    console.error(
      `[Compare] ${mode}: ${variant.passed ? "valid final answer" : variant.error}`,
    );
  }
  const promptMatches = Boolean(
    variants[0]?.promptHash &&
    variants[0].promptHash === variants[1]?.promptHash,
  );
  const schemaMatches = Boolean(
    variants[0]?.schemaHash &&
    variants[0].schemaHash === variants[1]?.schemaHash,
  );
  ensure(
    promptMatches && schemaMatches,
    "Comparison prompts or schemas unexpectedly differ. Inspect per-variant files.",
  );
  const comparison = {
    generatedAt: new Date().toISOString(),
    model: configurations[0]!.model,
    sourcePath,
    sourceGeneratedAt: source.generatedAt,
    promptMatches,
    schemaMatches,
    newGoogleOrWeatherCalls: 0,
    internalReasoningTextStored: false,
    variants,
  };
  await writeFile(
    resolve(out, "comparison.json"),
    JSON.stringify(comparison, null, 2) + "\n",
    { flag: "wx", mode: 0o600 },
  );
  await writeFile(
    resolve(out, "comparison.md"),
    render(
      comparison.model,
      source.generatedAt,
      variants,
      promptMatches,
      schemaMatches,
    ),
    { flag: "wx", mode: 0o600 },
  );
  console.log(
    JSON.stringify(
      {
        out,
        promptMatches,
        schemaMatches,
        results: variants.map((v) => ({
          mode: v.mode,
          passed: v.passed,
          elapsedMs: v.elapsedMs,
          observation: v.observation,
          candidate: v.selectedFacts?.candidateId,
          error: v.error,
        })),
      },
      null,
      2,
    ),
  );
  if (variants.some((v) => !v.passed)) process.exitCode = 1;
}
main().catch((caught) => {
  let message = caught instanceof Error ? caught.message : "Comparison failed.";
  for (const key of [
    process.env.OPENROUTER_API_KEY,
    process.env.GOOGLE_MAPS_API_KEY,
  ])
    if (key) message = message.split(key).join("[REDACTED]");
  console.error(`[Compare] ${message}`);
  process.exitCode = 1;
});
