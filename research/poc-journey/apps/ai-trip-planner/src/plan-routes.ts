import { readFile, mkdir, writeFile, rename, readdir } from "node:fs/promises";
import { resolve, dirname } from "node:path";
import { createHash } from "node:crypto";
import { parseArgs } from "node:util";
import { fileURLToPath } from "node:url";
import { ensure } from "./domain.ts";
import { localClock, parseRoutingInput } from "./deterministic-model.ts";
import { GoogleRoutingProvider } from "./deterministic-provider.ts";
import {
  planWithoutAI,
  type RoutingCandidate,
} from "./deterministic-planner.ts";

const cell = (value: unknown) =>
  String(value ?? "—")
    .replace(/[\r\n]/g, " ")
    .replace(/[|<>]/g, " ");
export function renderRoutingReport(
  result: Awaited<ReturnType<typeof planWithoutAI>>,
  mode = "live",
): string {
  const { input } = result;
  const when = (value: number | null) => {
    if (value === null) return "—";
    const day = new Intl.DateTimeFormat("en-CA", {
      timeZone: input.timeZone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).format(value * 1000);
    return `${day === input.date ? "" : `${day} `}${localClock(value, input.timeZone)}`;
  };
  const lines = [
    "# Hasil itinerary tanpa AI",
    "",
    `Status: **${result.status}**. Mode: **${mode}**. Panggilan AI: **0**.`,
    "",
    `${input.date}, ${input.timeZone}; berangkat ${input.startTime} dari ${cell(input.origin.name)}, kembali ke ${cell(input.returnTo.name)}. Batas selesai ${input.finishBy} (${input.finishSource}).`,
    "",
    `Semua ${input.places.length} tujuan dipertahankan. Durasi default ${input.defaultDwellMinutes} menit; transfer tidak menambah waktu kunjungan.`,
    "",
    "## Identitas tempat dan asumsi",
    "",
    "| ID | Permintaan | Hasil provider | Status | Singgah | Catatan |",
    "| --- | --- | --- | --- | --- | --- |",
  ];
  for (const p of result.locations)
    lines.push(
      `| ${cell(p.id)} | ${cell(p.name)} | ${cell(p.match?.name)} | ${p.status} | ${p.dwellMinutes} (${p.dwellSource}) | ${cell(p.referenceNote ?? p.error ?? p.hours.note)} |`,
    );
  const candidate = (title: string, c: RoutingCandidate | null) => {
    lines.push("", `## ${title}`, "");
    if (!c) {
      lines.push("Tidak ada kandidat lengkap yang dapat ditampilkan.");
      return;
    }
    lines.push(
      `**${c.feasible ? "Lolos batas waktu/jam yang diketahui; data bersyarat tetap perlu diperhatikan" : "Tidak memenuhi batas trip; bukan itinerary yang layak diikuti"}.**`,
      "",
      `Perpindahan ${c.travelMinutes.toFixed(1)} menit; singgah ${c.dwellMinutes} menit; menunggu buka ${c.waitMinutes.toFixed(1)} menit. Selesai ${when(c.finishesAt)}.`,
      "",
      "| Urutan | Tempat | Berangkat dari sebelumnya | Tiba | Mulai singgah | Lanjut | Moda dipilih | Durasi perjalanan | Singgah |",
      "| --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    );
    for (const [i, s] of c.stops.entries())
      lines.push(
        `| ${i + 1} | ${cell(s.name)} | ${when(s.departureAt)} | ${when(s.arrivalAt)} | ${when(s.visitAt)} | ${when(s.leaveAt)} | ${s.chosen?.mode ?? "—"} | ${s.chosen?.durationSeconds === null || !s.chosen ? "—" : (s.chosen.durationSeconds / 60).toFixed(1)} | ${s.dwellMinutes} |`,
      );
    lines.push(
      "",
      "Pilihan moda per ruas (hanya moda dalam lingkup WALK/TRANSIT; bukan semua operator di dunia):",
      "",
      "| Dari → ke | Moda | Status | Menit | Catatan |",
      "| --- | --- | --- | --- | --- |",
    );
    for (const s of c.stops)
      for (const option of s.options)
        lines.push(
          `| ${cell(s.from)} → ${cell(s.placeId)} | ${option.mode} | ${option.status} | ${option.durationSeconds === null ? "—" : (option.durationSeconds / 60).toFixed(1)} | ${cell(option.note)} |`,
        );
    lines.push(
      "",
      "Konflik:",
      "",
      ...(c.conflicts.length
        ? c.conflicts.map((v) => `- ${cell(v)}`)
        : ["- Tidak ditemukan konflik terhadap batas yang diketahui."]),
      "",
      "Data bersyarat:",
      "",
      ...[...new Set(c.conditional)].map((v) => `- ${cell(v)}`),
    );
  };
  candidate("Kandidat tercepat yang dievaluasi", result.fastest);
  lines.push(
    "",
    "## Cuaca",
    "",
    result.weatherReason,
    "",
    `Parameter eksperimen: rainWeight=${input.weatherPolicy.rainWeight}; tambahan waktu maksimum ${input.weatherPolicy.maxExtraMinutes} menit dibanding kandidat tercepat. Angka ini bukan hasil kalibrasi pengguna.`,
    "",
  );
  for (const f of result.forecasts)
    lines.push(
      `- ${cell(f.locationId)}: ${f.status}${f.note ? ` — ${cell(f.note)}` : ""}`,
    );
  if (result.weatherAdjusted)
    candidate("Kandidat dengan pertimbangan cuaca", result.weatherAdjusted);
  lines.push(
    "",
    "## Batas kesimpulan",
    "",
    "- Urutan dipilih dari pencarian terbatas; tidak ada jaminan optimum global.",
    "- Matrix adalah probe pada jam berangkat awal. Kandidat akhir diperiksa ulang menggunakan waktu keberangkatan setiap ruas.",
    "- Skor hujan adalah perkiraan paparan/kenyamanan dengan cakupan data yang disebutkan, bukan penambahan durasi perjalanan akibat hujan.",
    "- Kondisi lintas wilayah sepanjang ruas dan perlindungan di lokasi menunggu belum dimodelkan secara rinci.",
    "- Jam reguler tidak menjamin jam khusus tanggal trip. Lokasi pendekatan tidak menjadi toko/titik yang telah dikonfirmasi.",
    "- Google Routes tidak mendukung mitra transit Jepang: https://developers.google.com/maps/faq#transit_directions_countries",
    "",
    `Pencarian: ${result.search?.method ?? "belum dimulai"}; ${result.search?.expanded ?? 0} ekspansi, ${result.search?.orders.length ?? 0} urutan dan ${result.candidates.length} kandidat akhir.`,
    "",
  );
  return lines.join("\n");
}

async function main() {
  const { values } = parseArgs({
    options: {
      input: { type: "string" },
      out: { type: "string" },
      "check-config": { type: "boolean" },
      help: { type: "boolean" },
    },
    strict: true,
  });
  if (values.help) {
    console.log(
      "plan --input FILE --out NEW_DIR\nDeterministic WALK/TRANSIT routing, Google Places + Routes + Open-Meteo. No AI key/model/browser required.\n--check-config checks key presence without making requests.",
    );
    return;
  }
  if (values["check-config"]) {
    const ready = Boolean(process.env.GOOGLE_MAPS_API_KEY?.trim());
    console.log(
      JSON.stringify(
        {
          ready,
          GOOGLE_MAPS_API_KEY: ready ? "set" : "missing",
          requiresAI: false,
          noNetworkCallsMade: true,
        },
        null,
        2,
      ),
    );
    if (!ready) process.exitCode = 2;
    return;
  }
  ensure(values.input && values.out, "Use --input FILE --out NEW_DIR.");
  ensure(
    process.env.GOOGLE_MAPS_API_KEY?.trim(),
    "GOOGLE_MAPS_API_KEY is missing. AI configuration is not required.",
  );
  const input = parseRoutingInput(
    JSON.parse(await readFile(resolve(values.input), "utf8")),
  );
  const out = resolve(values.out);
  await mkdir(dirname(out), { recursive: true });
  await mkdir(out, { mode: 0o700 });
  const save = async (name: string, data: unknown, raw = false) => {
    const path = resolve(out, name);
    await writeFile(
      `${path}.tmp`,
      raw ? String(data) : JSON.stringify(data, null, 2) + "\n",
      { mode: 0o600 },
    );
    await rename(`${path}.tmp`, path);
  };
  const sourceHashes: Record<string, string> = {};
  for (const file of await readdir(new URL("./", import.meta.url)))
    if (file.endsWith(".ts"))
      sourceHashes[file] = createHash("sha256")
        .update(await readFile(new URL(file, import.meta.url)))
        .digest("hex");
  await save("manifest.json", {
    startedAt: new Date().toISOString(),
    workflowVersion: 4,
    engine: "deterministic",
    aiCalls: 0,
    networkMode: "live",
    sourceHashes,
  });
  await save("user-input.json", input);
  const provider = new GoogleRoutingProvider(
    process.env.GOOGLE_MAPS_API_KEY!.trim(),
  );
  const progress = async (phase: string) => {
    console.error(`[PoC v4] ${phase}`);
    await save("progress.json", {
      phase,
      providerCalls: provider.http.calls,
      aiCalls: 0,
    });
  };
  try {
    const result = await planWithoutAI(input, provider, progress);
    await save("report.json", {
      ...result,
      generatedAt: new Date().toISOString(),
      providerCalls: provider.http.calls,
    });
    await save("report.md", renderRoutingReport(result), true);
    await save("provider-evidence.json", provider.evidence);
    await progress("complete");
    console.log(
      JSON.stringify(
        {
          status: result.status,
          aiCalls: 0,
          resolvedPlaces: result.locations.filter((p) => p.match).length,
          candidateCount: result.candidates.length,
          fastestOrder: result.fastest?.order ?? null,
          travelMinutes: result.fastest?.travelMinutes ?? null,
          feasible: result.fastest?.feasible ?? false,
          report: resolve(out, "report.md"),
        },
        null,
        2,
      ),
    );
    if (
      [
        "needs_location_selection",
        "insufficient_route_data",
        "no_feasible_candidate",
      ].includes(result.status)
    )
      process.exitCode = 2;
  } catch (error) {
    await save("provider-evidence.json", provider.evidence);
    await save("failure.json", {
      error: error instanceof Error ? error.message : "Planner failed.",
      aiCalls: 0,
    });
    throw error;
  }
}
// Importing the renderer for tests does not launch the CLI.
if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
)
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : "Planner failed.");
    process.exitCode = 1;
  });
