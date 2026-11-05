import { parsePlaceContext as parseContext } from "./place-context.ts";
import { readFile, mkdir, writeFile, rename } from "node:fs/promises";
import { resolve, dirname } from "node:path";
import { createHash } from "node:crypto";
import { parseArgs } from "node:util";
import { aiConfig } from "./ai.ts";
import { ensure, object } from "./domain.ts";
import { Http } from "./http.ts";
import { ModelSession } from "./model-session.ts";
import { researchConfig } from "./research-browser.ts";
import {
  researchPlaces,
  contextWithResearch,
  type ResearchSnapshot,
} from "./research-agent.ts";
import {
  RouteEvidenceStore,
  collectInitialRoutes,
  collectForecasts,
  type RouteEvidence,
  type ForecastEvidence,
} from "./planning-data.ts";
import { simulateDay, type Simulation } from "./planning-simulation.ts";
import {
  parseUntimed,
  proposeDay,
  type PlaceContext,
  type UntimedInput,
} from "./untimed.ts";

type Snapshot = {
  schemaVersion: 2;
  collectedAt: string;
  input: UntimedInput;
  originalContext: PlaceContext;
  context: PlaceContext;
  research: ResearchSnapshot;
  initialRoutes: Awaited<ReturnType<typeof collectInitialRoutes>>;
  routeEvidence: RouteEvidence[];
  forecasts: ForecastEvidence[];
  contextHash: string;
  inputHash: string;
};
type Attempt = {
  number: number;
  ai: Awaited<ReturnType<typeof proposeDay>>;
  simulation: Simulation | null;
  error: string | null;
};
const json = async (path: string): Promise<unknown> =>
  JSON.parse(await readFile(resolve(path), "utf8"));
const hash = (value: unknown) =>
  createHash("sha256").update(JSON.stringify(value)).digest("hex");
const number = (
  value: string | undefined,
  fallback: number,
  min: number,
  max: number,
) => {
  const n = Number(value ?? fallback);
  ensure(
    Number.isInteger(n) && n >= min && n <= max,
    "Invalid bounded planner environment setting.",
  );
  return n;
};
const cell = (value: unknown) =>
  String(value ?? "—")
    .replace(/\|/g, "\\|")
    .replace(/[\r\n]/g, " ");

function score(simulation: Simulation) {
  return (
    simulation.issues.filter((i) => i.severity === "conflict").length * 100000 +
    simulation.issues.filter((i) => i.severity === "unknown").length * 1000 +
    simulation.changes.length
  );
}
function markdown(
  snapshot: Snapshot,
  best: Attempt | null,
  attempts: Attempt[],
  model: ModelSession,
  stopReason: string,
  options: unknown,
) {
  const lines = [
    `# PoC itinerary dengan browser dan simulasi — ${snapshot.input.date}`,
    "",
    `Status: **${best?.simulation?.status ?? "no_valid_proposal"}**. Jam berasal dari proposal AI yang dihitung ulang kode dengan evidence rute dan buffer. Ini bukan konfirmasi jadwal kereta atau jaminan kelayakan perjalanan.`,
    "",
    `Awal/akhir: ${snapshot.context.locations[snapshot.input.origin]!.name}; ${snapshot.input.timeZone}; satu hari.`,
    "",
    `Putaran proposal: ${attempts.length}; putaran terpilih: ${best?.number ?? "—"}; alasan berhenti: ${stopReason}.`,
    "",
    `Kebijakan sistem: ${JSON.stringify(options)}.`,
    "",
    `Riset: ${snapshot.research.pages.filter((p) => p.status === "ok").length} halaman terbaca, ${snapshot.research.searches.length} pencarian, ${snapshot.research.claims.length} ekstraksi berkutip. Pencocokan kutipan bukan pembuktian otomatis seluruh makna atau penerapan pada tanggal trip.`,
    "",
  ];
  if (best?.simulation) {
    lines.push(
      "| Waktu simulasi JST | Menit | Jenis | Aktivitas / perpindahan | Dasar alokasi |",
      "|---|---:|---|---|---|",
    );
    for (const row of best.simulation.rows) {
      const p = row.proposed;
      const insertedWait = row.durationSource === "source_opening_wait";
      const activity = snapshot.input.activities.find(
        (a) => a.id === p.activityId,
      );
      const name = insertedWait
        ? `Menunggu buka di ${snapshot.context.locations[p.to]!.name}`
        : p.kind === "move"
          ? `${snapshot.context.locations[p.from]!.name} → ${snapshot.context.locations[p.to]!.name}`
          : (activity?.label ??
            `Buffer di ${snapshot.context.locations[p.to]!.name}`);
      lines.push(
        `| ${row.startsAt.slice(0, 16).replace("T", " ")} – ${row.endsAt.slice(0, 16).replace("T", " ")} | ${row.allocatedMinutes} | ${insertedWait ? "wait" : p.kind === "move" ? p.mode : p.kind} | ${cell(name)} | ${cell(row.note)}${row.routeStatus ? `; ${row.routeStatus}` : ""} |`,
      );
    }
    lines.push("", "## Konflik dan data belum terkonfirmasi", "");
    for (const issue of best.simulation.issues)
      lines.push(
        `- **${issue.severity}/${issue.code}**${issue.rowIndex !== null ? ` (baris ${issue.rowIndex + 1})` : ""}: ${issue.message} ${issue.evidenceIds.length ? `[${issue.evidenceIds.join(", ")}]` : ""}`,
      );
  }
  lines.push("", "## Sumber browser", "");
  for (const p of snapshot.research.pages)
    lines.push(
      `- [${cell(p.title || p.url)}](${p.url}): ${p.status}; diambil ${p.retrievedAt}; ${p.truncated ? "teks dibatasi" : "teks tersimpan"}; ${p.id}.`,
    );
  lines.push("", "## Batas hasil", "");
  lines.push(
    "- Riset hanya membaca halaman publik pada domain resmi yang diizinkan, tanpa login atau bypass CAPTCHA. PDF/tabel interaktif yang tidak terbaca tetap belum tersedia.",
    "- no_route bukan bukti kereta nyata tidak berjalan. Durasi dari halaman operator bukan otomatis jadwal kereta bertanggal.",
    "- Waktu kunjungan adalah usulan AI; buffer adalah asumsi sistem. Seluruh tujuan dipertahankan, termasuk jika simulasi melewati tanggal trip.",
    "- Teks dan alasan mentah AI tersimpan terpisah di direktori attempt; tabel laporan dibentuk dari perhitungan kode.",
    "- Konteks sumber awal tetap merupakan input bersumber; hanya ekstraksi yang mengutip tanggal trip eksplisit dapat ditambahkan sebagai batas jam/periode baru. Konflik sumber tidak disembunyikan.",
    ...snapshot.context.limitations.map((s) => `- ${s}`),
    ...snapshot.research.uncertainties.map((s) => `- Riset: ${s}`),
  );
  lines.push(
    "",
    "## Penggunaan AI",
    "",
    `\`${JSON.stringify(model.summary())}\``,
    "",
  );
  return lines.join("\n");
}

async function main() {
  const { values } = parseArgs({
    options: {
      input: { type: "string" },
      context: { type: "string" },
      research: { type: "string" },
      out: { type: "string" },
      reuse: { type: "string" },
    },
    strict: true,
  });
  ensure(
    values.out && (values.reuse || (values.input && values.context)),
    "Use --input FILE --context FILE [--research FILE] --out NEW_DIR, or --reuse V2_COLLECTED_JSON --out NEW_DIR. Old snapshots use plan:untimed:legacy.",
  );
  const config = aiConfig(process.env);
  ensure(config.reasoningMode === "on", "This pipeline requires reasoning on.");
  ensure(process.env.GOOGLE_MAPS_API_KEY?.trim(), "Google Routes key missing.");
  const options = {
    walkingBufferMinutes: number(process.env.POC_WALK_BUFFER_MINUTES, 5, 1, 30),
    transitBufferMinutes: number(
      process.env.POC_TRANSIT_BUFFER_MINUTES,
      10,
      1,
      60,
    ),
    maxAttempts: number(process.env.POC_MAX_PLAN_ATTEMPTS, 3, 1, 4),
    maxRouteRequests: number(process.env.POC_MAX_ROUTE_REQUESTS, 90, 1, 150),
    maxModelCalls: number(process.env.POC_MAX_MODEL_CALLS, 8, 2, 12),
    maxRunTokens: number(
      process.env.POC_MAX_RUN_TOKENS,
      1000000,
      32768,
      1000000,
    ),
    evidenceMaxAgeMinutes: number(
      process.env.POC_EVIDENCE_MAX_AGE_MINUTES,
      60,
      1,
      1440,
    ),
  };
  const model = new ModelSession(
    config,
    options.maxModelCalls,
    options.maxRunTokens,
  );
  const out = resolve(values.out);
  await mkdir(dirname(out), { recursive: true });
  await mkdir(out, { mode: 0o700 });
  const save = async (name: string, value: unknown) => {
    const target = resolve(out, name);
    await mkdir(dirname(target), { recursive: true, mode: 0o700 });
    const temporary = `${target}.tmp`;
    await writeFile(temporary, JSON.stringify(value, null, 2) + "\n", {
      mode: 0o600,
    });
    await rename(temporary, target);
  };
  const state = {
    phase: "starting",
    runStartedAt: new Date().toISOString(),
    options,
    reused: values.reuse ?? null,
  };
  try {
    let snapshot: Snapshot;
    let liveRoutes: RouteEvidenceStore | null = null;
    if (values.reuse) {
      const raw = object(await json(values.reuse), "V2 snapshot");
      ensure(
        raw.schemaVersion === 2,
        "Only V2 collected snapshots are reusable here; use plan:untimed:legacy for old runs.",
      );
      snapshot = raw as unknown as Snapshot;
      parseContext(snapshot.originalContext);
      parseUntimed(snapshot.input, snapshot.originalContext);
      ensure(
        snapshot.inputHash === hash(snapshot.input) &&
          snapshot.contextHash === hash(snapshot.originalContext),
        "Snapshot input/context hash mismatch.",
      );
      const age = (Date.now() - Date.parse(snapshot.collectedAt)) / 60000;
      ensure(
        Number.isFinite(age) &&
          age >= 0 &&
          age <= options.evidenceMaxAgeMinutes,
        "Reused evidence is stale or has an invalid timestamp; collect a fresh snapshot.",
      );
      for (const stamp of [
        ...snapshot.routeEvidence.map((e) => e.fetchedAt),
        ...snapshot.forecasts.map((e) => e.fetchedAt),
        ...snapshot.research.pages.map((p) => p.retrievedAt),
      ]) {
        const sourceAge = (Date.now() - Date.parse(stamp)) / 60000;
        ensure(
          Number.isFinite(sourceAge) &&
            sourceAge >= 0 &&
            sourceAge <= options.evidenceMaxAgeMinutes,
          "A reused provider/browser observation is stale; collect fresh evidence.",
        );
      }
      ensure(
        !values.input && !values.context && !values.research,
        "Reuse is immutable; changed destinations or research configuration require fresh collection.",
      );
    } else {
      const originalContext = parseContext(await json(values.context!));
      const input = parseUntimed(await json(values.input!), originalContext);
      ensure(
        originalContext.facts.every((f) =>
          f.activityIds.every((id) =>
            input.activities.some((a) => a.id === id),
          ),
        ),
        "Source context references an activity outside this trip.",
      );
      const rc = researchConfig(
        values.research
          ? await json(values.research)
          : originalContext.research,
        originalContext,
      );
      await save("user-input.json", input);
      await save("original-context.json", originalContext);
      state.phase = "collecting_initial_routes_and_weather";
      await save("progress.json", state);
      const routes = new RouteEvidenceStore(
        originalContext,
        process.env.GOOGLE_MAPS_API_KEY!,
        options.maxRouteRequests,
      );
      const weatherHttp = new Http();
      liveRoutes = routes;
      const initialRoutes = await collectInitialRoutes(
        input,
        originalContext,
        routes,
      );
      const forecasts = await collectForecasts(
        input,
        originalContext,
        weatherHttp,
      );
      await save("initial-evidence.json", {
        initialRoutes,
        forecasts,
        httpCalls: { ...routes.http.calls, ...weatherHttp.calls },
      });
      state.phase = "headless_browser_research";
      await save("progress.json", state);
      console.error(
        "[Planner] Reading official pages with isolated headless Chromium; AI can request bounded search/read actions.",
      );
      const research = await researchPlaces(
        input,
        originalContext,
        rc,
        model,
        (v) => save("research.json", v),
      );
      snapshot = {
        schemaVersion: 2,
        collectedAt: new Date().toISOString(),
        input,
        originalContext,
        context: contextWithResearch(originalContext, research),
        research,
        initialRoutes,
        routeEvidence: routes.evidence,
        forecasts,
        contextHash: hash(originalContext),
        inputHash: hash(input),
      };
    }
    await save("user-input.json", snapshot.input);
    if (values.reuse) {
      await save("original-context.json", snapshot.originalContext);
      await save("initial-evidence.json", {
        initialRoutes: snapshot.initialRoutes,
        forecasts: snapshot.forecasts,
        reusedFrom: values.reuse,
      });
    }
    await save("collected.json", snapshot);
    const routes =
      liveRoutes ??
      new RouteEvidenceStore(
        snapshot.context,
        process.env.GOOGLE_MAPS_API_KEY!,
        options.maxRouteRequests,
      );
    if (!liveRoutes) routes.seed(snapshot.routeEvidence);
    const attempts: Attempt[] = [];
    let best: Attempt | null = null,
      repair: unknown = undefined,
      stopReason = "attempt_limit";
    const fingerprints = new Set<string>();
    for (let n = 1; n <= options.maxAttempts; n++) {
      state.phase = `proposal_and_simulation_${n}`;
      await save("progress.json", { ...state, model: model.summary() });
      console.error(
        `[Planner] Proposal/simulation ${n}/${options.maxAttempts}.`,
      );
      const evidence = {
        routeEvidence: routes.evidence,
        initialTransitProbe: snapshot.initialRoutes.probeTimeSource,
        regionalForecasts: snapshot.forecasts,
        browserClaims: snapshot.research.claims,
        researchUncertainties: snapshot.research.uncertainties,
        policy: {
          ...options,
          allUnknownRoutesRemainUnverified: true,
          neverReplaceUnknownRestaurant: true,
        },
      };
      await save(`attempt-${n}/decision-input.json`, {
        input: snapshot.input,
        context: snapshot.context,
        evidence,
        repair,
      });
      let ai: Attempt["ai"];
      try {
        ai = await proposeDay(
          snapshot.input,
          snapshot.context,
          evidence,
          new Http(),
          config,
          repair,
          model,
        );
      } catch (error) {
        await save(`attempt-${n}/failure.json`, {
          error: error instanceof Error ? error.message : "Model call failed.",
          model: model.summary(),
        });
        stopReason = "model_request_or_budget_failure";
        break;
      }
      const attempt: Attempt = {
        number: n,
        ai,
        simulation: null,
        error: ai.error,
      };
      attempts.push(attempt);
      await save(`attempt-${n}/ai.json`, ai);
      if (!ai.proposal) {
        repair = {
          previousFinal: ai.rawFinal,
          structuralValidationError: ai.error,
          instruction:
            "Correct this structural failure; do not omit activities, station pairs, or same-day return.",
        };
        await save("attempts.json", attempts);
        continue;
      }
      attempt.simulation = await simulateDay(
        snapshot.input,
        snapshot.context,
        ai.proposal,
        routes,
        snapshot.forecasts,
        {
          walking: options.walkingBufferMinutes,
          transit: options.transitBufferMinutes,
        },
      );
      if (!snapshot.research.pages.some((p) => p.status === "ok")) {
        attempt.simulation.issues.push({
          code: "BROWSER_RESEARCH_UNAVAILABLE",
          severity: "unknown",
          rowIndex: null,
          message:
            "No official page was successfully read; file context must not be presented as refreshed browser evidence.",
          evidenceIds: [],
          repairableByScheduling: false,
        });
        if (attempt.simulation.status === "ready_for_review")
          attempt.simulation.status = "needs_information";
      }
      await save(`attempt-${n}/simulation.json`, attempt.simulation);
      await save("route-evidence.json", routes.evidence);
      await save("attempts.json", attempts);
      if (!best || score(attempt.simulation) < score(best.simulation!))
        best = attempt;
      if (!attempt.simulation.repairRecommended) {
        stopReason =
          attempt.simulation.status === "needs_information"
            ? "missing_data_requires_confirmation"
            : "checks_stable";
        break;
      }
      const fingerprint = hash({
        rows: attempt.simulation.rows.map((r) => ({
          from: r.proposed.from,
          to: r.proposed.to,
          activity: r.proposed.activityId,
          startsAt: r.startsAt,
          endsAt: r.endsAt,
        })),
        issues: attempt.simulation.issues.map((i) => ({
          code: i.code,
          rowIndex: i.rowIndex,
        })),
      });
      if (fingerprints.has(fingerprint)) {
        stopReason = "no_schedule_improvement";
        break;
      }
      fingerprints.add(fingerprint);
      repair = {
        previousProposal: ai.proposal,
        propagatedSimulation: attempt.simulation,
        instruction:
          "Repair actual opening/date conflicts and insufficient travel allocations using this simulation. Its times already propagate earlier waits/travel. Keep every destination and required mode/pair, include system buffers, and return on the trip date. Visit durations in this untimed case remain explicit AI proposals. If a source is missing, preserve unknown rather than inventing proof. A clock change cannot fix a closed event season or an unknown restaurant identity.",
      };
    }
    state.phase = "complete";
    const report = {
      generatedAt: new Date().toISOString(),
      mode: "browser_researched_simulated_itinerary",
      status: best?.simulation?.status ?? "no_valid_proposal",
      stopReason,
      bestAttempt: best?.number ?? null,
      input: snapshot.input,
      options,
      model: model.summary(),
      googleRequestsThisRun: routes.http.calls["Google planning route"] ?? 0,
      contextSourceProvenance: snapshot.originalContext.facts.map((f) => ({
        id: f.id,
        url: f.url,
        browserReadThisSnapshot: snapshot.research.pages.some(
          (p) => p.status === "ok" && p.requestedUrl === f.url,
        ),
        quoteGroundedClaimIds: snapshot.research.claims
          .filter((c) => c.url === f.url)
          .map((c) => c.id),
        note: "Reading a page does not independently validate every initial context statement.",
      })),
      researchSummary: {
        pagesRead: snapshot.research.pages.filter((p) => p.status === "ok")
          .length,
        searches: snapshot.research.searches.length,
        claims: snapshot.research.claims.length,
        rejectedClaims: snapshot.research.rejectedClaims.length,
      },
      simulation: best?.simulation ?? null,
      routeEvidence: routes.evidence,
      forecasts: snapshot.forecasts,
      reusedEvidence: values.reuse ?? null,
      allOutputTimesSource:
        "AI proposal followed by deterministic route/buffer/opening-wait propagation",
      verifiedTravelFeasibility: false,
      artifactFiles: [
        "user-input.json",
        "collected.json",
        "research.json",
        "initial-evidence.json",
        "attempts.json",
        "route-evidence.json",
      ],
    };
    await save("research.json", snapshot.research);
    await save("attempts.json", attempts);
    await save("route-evidence.json", routes.evidence);
    await save("report.json", report);
    await save("progress.json", {
      ...state,
      model: model.summary(),
      stopReason,
    });
    await writeFile(
      resolve(out, "report.md"),
      markdown(snapshot, best, attempts, model, stopReason, options),
      { mode: 0o600 },
    );
    console.log(
      JSON.stringify(
        {
          out,
          status: report.status,
          stopReason,
          attempts: attempts.length,
          bestAttempt: report.bestAttempt,
          model: model.summary(),
          research: report.researchSummary,
        },
        null,
        2,
      ),
    );
    if (!best) process.exitCode = 1;
  } catch (error) {
    await save("failure.json", {
      phase: state.phase,
      error: error instanceof Error ? error.message : "Planner failed.",
      model: model.summary(),
    });
    throw error;
  }
}
main().catch((error) => {
  let message =
    error instanceof Error ? error.message : "Researched planning failed.";
  for (const key of [
    process.env.OPENROUTER_API_KEY,
    process.env.GOOGLE_MAPS_API_KEY,
  ])
    if (key) message = message.split(key).join("[REDACTED]");
  console.error(`[Planner] ${message}`);
  process.exitCode = 1;
});
