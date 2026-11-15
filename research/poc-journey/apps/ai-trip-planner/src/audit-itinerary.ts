import { readFile, mkdir, writeFile } from "node:fs/promises";
import { resolve, dirname } from "node:path";
import { parseArgs } from "node:util";
import { createHash } from "node:crypto";
import { aiConfig } from "./ai.ts";
import { ensure } from "./domain.ts";
import { Http } from "./http.ts";
import {
  collectAudit,
  eventSlots,
  parseAuditInput,
  type Snapshot,
} from "./audit.ts";
import { auditWithAI } from "./audit-model.ts";

type AI = Awaited<ReturnType<typeof auditWithAI>>;
const cell = (v: unknown) =>
  String(v ?? "—")
    .replace(/\|/g, "\\|")
    .replace(/[\r\n]/g, " ");
const number = (v: number | null) =>
  v === null ? "belum diketahui" : v.toFixed(1);
function render(
  snapshot: Snapshot,
  ai: AI | null,
  aiError: string | null,
  reused: boolean,
) {
  const { input } = snapshot;
  const routeCount = snapshot.legs.filter((l) => l.status === "ok").length;
  const lines = [
    `# ${input.title}`,
    "",
    `Tanggal: **${input.date}** · **Asia/Tokyo, JST (+09:00)** · ${input.events.length} baris asli dipertahankan.`,
    "",
    "**Status: perlu perubahan atau konfirmasi; belum terverifikasi sebagai perjalanan utuh.**",
    "",
    `Data ${reused ? "digunakan ulang dari snapshot" : "diambil dari provider"} pada ${snapshot.collectedAt}. ${routeCount}/${snapshot.legs.length} leg memiliki hasil rute; sisanya tetap unknown. Tidak ada durasi yang dikarang untuk menggantikan data kosong.`,
    "",
    "## Jadwal awal pengguna dan prakiraan regional",
    "",
    "| ID | JST | Kegiatan | Prakiraan peluang hujan pada slot |",
    "|---|---|---|---|",
    ...eventSlots(input, snapshot.forecasts).map(
      (e) =>
        `| ${e.id} | ${e.time} | ${cell(e.label)}${e.optional ? " (opsional)" : ""} | ${e.regionalForecast?.rainProbability === null || e.regionalForecast?.rainProbability === undefined ? "belum dinilai" : `${e.regionalForecast.rainProbability.toFixed(1)}%`} |`,
    ),
    "",
    "Prakiraan memakai titik regional, bukan GPS apartment atau jaminan cuaca tepat di suatu bangunan. Slot kegiatan dapat mencakup perpindahan; probabilitas di atas bukan prediksi menit hujan.",
    "",
    "## Pemeriksaan rute independen pada jam rencana",
    "",
    "| Leg | Moda | Dari → ke | Slot menit | Estimasi provider menit | Sisa slot menit | Status |",
    "|---|---|---|---:|---|---|---|",
    ...snapshot.legs.map(
      (l) =>
        `| ${l.id} | ${l.mode} | ${cell(input.locations[l.from]!.name)} → ${cell(input.locations[l.to]!.name)} | ${l.plannedMinutes} | ${number(l.estimatedMinutes)} | ${number(l.remainingMinutes)} | ${l.status} |`,
    ),
    "",
    "Leg diperiksa dengan waktu keberangkatan baseline masing-masing. Keterlambatan belum dipropagasikan, waktu kereta yang tidak tersedia tidak diverifikasi, dan jadwal baru belum dioptimalkan. Sisa slot pada activity_and_travel harus menampung kegiatan, antrean dan jeda.",
    "",
    "## Temuan dari data dan perhitungan",
    "",
    ...snapshot.findings.map(
      (f) =>
        `- **${f.severity} · ${f.eventIds.join(", ")}:** ${f.message} Bukti: ${f.evidenceIds.map((id) => `\`${id}\``).join(", ")}.`,
    ),
    "",
    "## Sumber tempat dan acara",
    "",
    ...input.facts.map(
      (f) =>
        `- [${f.name}](${f.url}): ${f.startDate ? `${f.startDate}–${f.endDate}. ` : ""}${f.opensAt ? `${f.opensAt}–${f.closesAt} JST. ` : ""}${f.note}`,
    ),
    "",
    "## Evaluasi AI",
    "",
  ];
  if (aiError) lines.push(`AI belum berhasil: ${cell(aiError)}`, "");
  if (ai) {
    lines.push(
      `Model: \`${cell(ai.metadata.actualModel)}\`; reasoning: **${ai.metadata.reasoning}**; batas completion: ${ai.metadata.maxCompletionTokens}; plafon konteks: ${ai.metadata.contextBudget.limitTokens}.`,
      "",
      `Token yang dilaporkan: ${JSON.stringify(ai.metadata.usage)}. Waktu AI: ${(ai.metadata.latencyMs / 1000).toFixed(2)} detik.`,
      "",
      "Preflight konteks memakai estimasi konservatif byte UTF-8 ditambah cadangan overhead, bukan tokenizer model yang persis. Jumlah token aktual diverifikasi dari usage ketika tersedia; batas konteks aktual provider juga berlaku.",
      "",
    );
    if (ai.error) lines.push(`Respons ditolak: ${ai.error}`, "");
    if (ai.decision) {
      lines.push(
        ai.decision.summary,
        "",
        ...ai.decision.findings.map(
          (f) =>
            `- **${f.severity} · ${f.eventIds.join(", ")}:** ${f.explanation}\n  Saran untuk ditinjau: ${f.proposedAdjustment}\n  Bukti: ${f.evidenceIds.map((id) => `\`${id}\``).join(", ")}.`,
        ),
        "",
        "Ketidakpastian:",
        ...ai.decision.uncertainties.map((s) => `- ${s}`),
        "",
      );
    }
  }
  lines.push(
    "Semua baris baseline tetap disimpan. Saran AI belum diterapkan; referensi yang valid tidak menjamin seluruh prosa bebas kesalahan. Teks reasoning internal tidak disimpan.",
    "",
  );
  return lines.join("\n");
}
async function main() {
  const { values } = parseArgs({
    options: {
      input: {
        type: "string",
        default: "examples/funabashi-enoshima-2026-11-05.json",
      },
      out: { type: "string", default: "results/japan-itinerary-audit" },
      reuse: { type: "string" },
      "collect-only": { type: "boolean" },
    },
  });
  const out = resolve(values.out);
  await mkdir(dirname(out), { recursive: true });
  await mkdir(out, { mode: 0o700 });
  let snapshot: Snapshot;
  if (values.reuse) {
    snapshot = JSON.parse(
      await readFile(resolve(values.reuse), "utf8"),
    ) as Snapshot;
    parseAuditInput(snapshot.input);
    ensure(
      snapshot.legs.length === snapshot.input.legs.length,
      "Incomplete route snapshot.",
    );
  } else {
    ensure(
      process.env.GOOGLE_MAPS_API_KEY?.trim(),
      "GOOGLE_MAPS_API_KEY is missing.",
    );
    const input = parseAuditInput(
      JSON.parse(await readFile(resolve(values.input), "utf8")),
    );
    console.error(
      `[Audit] ${input.events.length} events, ${input.legs.length} candidate legs, ${input.date} JST. Collecting real route/weather data.`,
    );
    snapshot = await collectAudit(input, new Http());
  }
  await writeFile(
    resolve(out, "collected.json"),
    JSON.stringify(snapshot, null, 2) + "\n",
    { flag: "wx", mode: 0o600 },
  );
  console.error(
    `[Audit] Snapshot saved. Route results: ${snapshot.legs.filter((l) => l.status === "ok").length}/${snapshot.legs.length}.`,
  );
  let ai: AI | null = null;
  let aiError: string | null = null;
  if (!values["collect-only"]) {
    try {
      const config = aiConfig(process.env);
      ensure(
        config.reasoningMode === "on",
        "This requested experiment requires OPENROUTER_REASONING=on.",
      );
      console.error(
        `[Audit] Calling ${config.model}, reasoning on; context cap ${config.contextLimit}, completion reserve ${config.maxTokens}.`,
      );
      ai = await auditWithAI(snapshot, new Http(), config);
    } catch (error) {
      aiError = error instanceof Error ? error.message : "AI request failed.";
    }
  }
  const result = {
    generatedAt: new Date().toISOString(),
    inputHash: createHash("sha256")
      .update(JSON.stringify(snapshot.input))
      .digest("hex"),
    eventsPreserved: snapshot.input.events.length,
    mode: "ordered_itinerary_audit",
    date: snapshot.input.date,
    timeZone: snapshot.input.timeZone,
    reusedProviderData: Boolean(values.reuse),
    googleCallsThisRun: values.reuse
      ? 0
      : (snapshot.httpCalls["Google audit route"] ?? 0),
    weatherCallsThisRun: values.reuse
      ? 0
      : (snapshot.httpCalls["Open-Meteo audit"] ?? 0),
    ai,
    aiError,
    status: "needs_changes_or_confirmation",
    snapshotFile: "collected.json",
  };
  await writeFile(
    resolve(out, "report.json"),
    JSON.stringify(result, null, 2) + "\n",
    { flag: "wx", mode: 0o600 },
  );
  await writeFile(
    resolve(out, "report.md"),
    render(snapshot, ai, aiError, Boolean(values.reuse)),
    { flag: "wx", mode: 0o600 },
  );
  console.log(
    JSON.stringify(
      {
        out,
        eventCount: result.eventsPreserved,
        routes: snapshot.legs.map((l) => ({
          id: l.id,
          status: l.status,
          estimatedMinutes: l.estimatedMinutes,
          remainingMinutes: l.remainingMinutes,
        })),
        aiPassed: Boolean(ai?.decision),
        aiError: aiError ?? ai?.error ?? null,
        aiMetadata: ai?.metadata ?? null,
      },
      null,
      2,
    ),
  );
  if (!values["collect-only"] && (!ai?.decision || aiError))
    process.exitCode = 1;
}
main().catch((error) => {
  let safe = error instanceof Error ? error.message : "Audit failed.";
  for (const key of [
    process.env.GOOGLE_MAPS_API_KEY,
    process.env.OPENROUTER_API_KEY,
  ])
    if (key) safe = safe.split(key).join("[REDACTED]");
  console.error(`[Audit] ${safe}`);
  process.exitCode = 1;
});
