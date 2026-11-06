import { readFile, mkdir, writeFile } from "node:fs/promises";
import { resolve, dirname } from "node:path";
import { parseArgs } from "node:util";
import { aiConfig } from "./ai.ts";
import { ensure } from "./domain.ts";
import { Http } from "./http.ts";
import { jstAt } from "./audit.ts";
import {
  parseUntimed,
  collectWalkingHints,
  forecastAvailability,
  proposeDay,
  verifyTransfers,
  verifyVisits,
  validateDayProposal,
  type PlaceContext,
  type UntimedInput,
} from "./untimed.ts";

const json = async (path: string) =>
  JSON.parse(await readFile(resolve(path), "utf8"));
const cell = (value: unknown) =>
  String(value ?? "—")
    .replace(/\|/g, "\\|")
    .replace(/[\r\n]/g, " ");
async function main() {
  const { values } = parseArgs({
    options: {
      input: { type: "string" },
      context: { type: "string" },
      out: { type: "string" },
      reuse: { type: "string" },
      proposal: { type: "string" },
      repair: { type: "string" },
    },
    strict: true,
  });
  ensure(
    values.out && ((values.input && values.context) || values.reuse),
    "Use --input FILE --context FILE --out NEW_DIR, or --reuse collected.json --out NEW_DIR.",
  );
  const config = aiConfig(process.env);
  ensure(
    config.reasoningMode === "on",
    "This experiment requires reasoning on.",
  );
  ensure(
    process.env.GOOGLE_MAPS_API_KEY?.trim(),
    "Google Routes key is missing.",
  );
  let collected: {
    collectedAt: string;
    input: UntimedInput;
    context: PlaceContext;
    walkingHints: Awaited<ReturnType<typeof collectWalkingHints>>;
    weather: ReturnType<typeof forecastAvailability>;
    httpCalls: Record<string, number>;
  };
  let callsThisRun: Record<string, number> = {};
  if (values.reuse) {
    collected = await json(values.reuse);
    if (values.input) {
      const revised = parseUntimed(await json(values.input), collected.context);
      ensure(
        revised.date === collected.input.date &&
          revised.origin === collected.input.origin &&
          revised.returnTo === collected.input.returnTo,
        "Reused evidence must retain its date and start/return stations.",
      );
      collected.input = revised;
    }
    parseUntimed(collected.input, collected.context);
  } else {
    const context = (await json(values.context!)) as PlaceContext;
    const input = parseUntimed(await json(values.input!), context);
    collected = {
      collectedAt: new Date().toISOString(),
      input,
      context,
      walkingHints: [],
      weather: forecastAvailability(input.date),
      httpCalls: {},
    };
  }
  const out = resolve(values.out);
  await mkdir(dirname(out), { recursive: true });
  await mkdir(out, { mode: 0o700 });
  const save = async (name: string, value: unknown) =>
    writeFile(resolve(out, name), JSON.stringify(value, null, 2) + "\n", {
      flag: "wx",
      mode: 0o600,
    });
  await save("user-input.json", collected.input);
  if (!values.reuse) {
    console.error(
      "[Untimed] Collecting directed walking hints; no clock time is supplied to these WALK requests.",
    );
    const http = new Http();
    collected.walkingHints = await collectWalkingHints(collected.context, http);
    collected.httpCalls = { ...http.calls };
    callsThisRun = { ...http.calls };
  }
  await save("collected.json", collected);
  console.error(
    `[Untimed] Saved untimed input and evidence. Calling ${config.model}; reasoning on, context cap ${config.contextLimit}.`,
  );
  const aiHttp = new Http();
  const ai = values.proposal
    ? ((await json(values.proposal)) as Awaited<ReturnType<typeof proposeDay>>)
    : await proposeDay(
        collected.input,
        collected.context,
        { walkingHints: collected.walkingHints, weather: collected.weather },
        aiHttp,
        config,
        values.repair ? await json(values.repair) : undefined,
      );
  await save("proposal.json", ai);
  ensure(
    ai.proposal,
    ai.error ??
      "AI proposal was not valid. See proposal.json; no simulated fallback.",
  );
  const proposal = validateDayProposal(
    ai.proposal,
    collected.input,
    collected.context,
  );
  console.error(
    "[Untimed] Timeline structure passed; checking each proposed transfer at its own departure.",
  );
  const routeHttp = new Http();
  const transfers = await verifyTransfers(
    collected.input,
    collected.context,
    proposal,
    routeHttp,
  );
  const visitChecks = verifyVisits(
    collected.input,
    collected.context,
    proposal,
  );
  callsThisRun = { ...callsThisRun, ...aiHttp.calls, ...routeHttp.calls };
  const conflicts = transfers.filter(
    (t) => t.status === "ok" && t.remainingMinutes! < 0,
  );
  const unknown = transfers.filter((t) => t.status !== "ok");
  const report = {
    generatedAt: new Date().toISOString(),
    mode: "untimed_one_day_ai_proposal",
    repairProposalSource: values.repair ?? null,
    reusedProviderEvidenceSource: values.reuse ?? null,
    reusedAIProposalSource: values.proposal ?? null,
    status: "proposal_needs_verification",
    allOutputTimesSource:
      "AI proposal; user supplied no clock times or durations",
    input: collected.input,
    ai,
    weather: collected.weather,
    transfers,
    visitChecks,
    callsThisRun,
    coverage: {
      activitiesRequested: collected.input.activities.length,
      activitiesScheduled: proposal.rows.filter((r) => r.kind === "visit")
        .length,
      start: proposal.rows[0]!.from,
      finish: proposal.rows.at(-1)!.to,
      date: collected.input.date,
      requiredTransitPairsPreserved: collected.input.requiredTransit.length,
      coastalWalkPreserved: true,
    },
    checks: {
      continuousTimeline: true,
      noOverlappingRows: true,
      sameDayStationReturn: true,
      transferConflicts: conflicts.length,
      unverifiedTransfers: unknown.length,
      visitHoursConflicts: visitChecks.filter(
        (c) => c.status === "conflict" || !c.dateInPublishedSeason,
      ).length,
      fullyVerifiedFeasible: false,
    },
    limitations: [
      "Times and unknown transit allocations are AI proposals, not a confirmed timetable.",
      "Each route check is independent; delays are not propagated and no automatic repair/global optimization is claimed.",
      "No route means this provider query returned no route, never that actual trains are unavailable.",
      "Forecast and exact sunset unavailable; no weather-aware optimality claim.",
      ...collected.context.limitations,
    ],
  };
  await save("report.json", report);
  const lines = [
    `# Usulan trip dari daftar tanpa jam — ${collected.input.date}`,
    "",
    `**${collected.input.origin} → ${collected.input.returnTo}; satu hari, JST.** Semua jam dan durasi di bawah adalah usulan AI. Pengguna tidak memasukkan jam apa pun.`,
    "",
    proposal.summary,
    "",
    `Status: perlu verifikasi. Aktivitas ${report.coverage.activitiesScheduled}/${report.coverage.activitiesRequested}; ${conflicts.length} alokasi perpindahan terlalu pendek; ${unknown.length} perpindahan belum terverifikasi; ${report.checks.visitHoursConflicts} konflik jam/periode kunjungan.`,
    "",
    "| Jam usulan JST | Menit | Jenis | Lokasi / aktivitas | Verifikasi perpindahan |",
    "|---|---:|---|---|---|",
  ];
  let transferIndex = 0;
  for (const row of proposal.rows) {
    const activity = collected.input.activities.find(
      (a) => a.id === row.activityId,
    );
    const name =
      row.kind === "move"
        ? `${collected.context.locations[row.from]!.name} → ${collected.context.locations[row.to]!.name}`
        : (activity?.label ??
          `Menunggu / buffer di ${collected.context.locations[row.to]!.name}`);
    let check = "—";
    if (row.kind === "move") {
      const t = transfers[transferIndex++]!;
      check =
        t.status === "ok"
          ? `Google ${t.estimatedMinutes!.toFixed(1)} menit; sisa slot perpindahan ${t.remainingMinutes!.toFixed(1)} menit${t.remainingMinutes! < 0 ? " — KONFLIK" : ""}${t.partialAddressMatch ? "; partial address match" : ""}`
          : `${t.status}; alokasi AI belum terverifikasi`;
    }
    lines.push(
      `| ${row.start}–${row.end} | ${(jstAt(collected.input.date, row.end) - jstAt(collected.input.date, row.start)) / 60} | ${row.kind === "move" ? row.mode : row.kind} | ${cell(name)} | ${cell(check)} |`,
    );
  }
  lines.push("", "## Catatan AI per slot", "");
  for (const row of proposal.rows)
    lines.push(`- ${row.start}–${row.end}: ${row.note}`);
  lines.push(
    "",
    "## Asumsi sistem dan AI",
    "",
    ...proposal.assumptions.map((x) => `- ${x}`),
    "",
    "## Cuaca",
    "",
    `${collected.weather.status}: tanggal berjarak ${collected.weather.daysAhead} hari saat pengumpulan. Tidak ada probabilitas hujan atau jam sunset yang diberikan. [Dokumentasi Open-Meteo](https://open-meteo.com/en/docs).`,
    "",
    "## Ketidakpastian",
    "",
    ...proposal.uncertainties.map((x) => `- ${x}`),
    ...report.limitations.map((x) => `- ${x}`),
    "",
    "## Sumber tempat/acara",
    "",
    ...collected.context.facts.map((f) => `- [${f.name}](${f.url}): ${f.note}`),
    "",
    "## Metadata pengujian",
    "",
    `Model: ${ai.metadata.actualModel}; reasoning: ${ai.metadata.reasoning}; latency: ${ai.metadata.latencyMs} ms.`,
    "",
    `Token: ${JSON.stringify(ai.metadata.usage)}.`,
    "",
    `HTTP pada run ini: ${JSON.stringify(callsThisRun)}.`,
    "",
    `Struktur timeline lolos; kelayakan seluruh perjalanan belum terkonfirmasi. Jadwal tidak diperbaiki otomatis setelah pengecekan rute.`,
    "",
  );
  await writeFile(resolve(out, "report.md"), lines.join("\n"), {
    flag: "wx",
    mode: 0o600,
  });
  console.log(
    JSON.stringify(
      {
        out,
        date: collected.input.date,
        coverage: report.coverage,
        checks: report.checks,
        aiMetadata: ai.metadata,
        callsThisRun,
      },
      null,
      2,
    ),
  );
}
main().catch((error) => {
  let message =
    error instanceof Error ? error.message : "Untimed planning failed.";
  for (const key of [
    process.env.OPENROUTER_API_KEY,
    process.env.GOOGLE_MAPS_API_KEY,
  ])
    if (key) message = message.split(key).join("[REDACTED]");
  console.error(`[Untimed] ${message}`);
  process.exitCode = 1;
});
