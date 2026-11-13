# Johan — illustrative Jakarta itinerary

**Mode:** live · **Date:** 2026-11-03 · **Time zone:** WIB

**Evidence status:** Live provider experiment; human quality review still required.

**AI called:** yes (nvidia/nemotron-3.5-super-vl:free)

**Visited:** none · **Departure now:** 14:00 · **Finish by:** 19:00

**Recommended:** D → B → C · **Feasible:** yes, against supplied constraints

Pilihan terbaik yang tersedia adalah D → B → C tanpa menunggu: D (membaca, dalam ruang), B (ngopi, dalam ruang), lalu C (luar ruang) tepat menjelang preferred window. Pilihan ini selesaikan semua tujuan di akhir 19:38 WIB, lebih awal dari batas 21:00 WIB dan dari candidate lain yang selesai 19:38–20:03 WIB. Kelemahannya: hujan di semua tempat cukup tinggi (80–100%) dan C luaran mendapatkan hujan selama 45 menit yang dihitung sebagai proxy, serta overlap preferred window kurang 18,5 menit. Namun, karena semua candidate luaran C sama-sama rainProbability 100 dan rainExposure 45 menit, opsi ini dipilih karena waktu total paling pendek dan selesai paling awal, sehingga memberikan fleksibilitas lebih besar jika cuaca buruk. Harap diperhatikan bahwa cuaca bukan jaminan dan kebukaannya tempat tidak diverifikasi.

| Stop | Arrival | Visit | Leave | Travel (min) | Wait (min) | Rain probability during visit |
|---|---|---|---|---:|---:|---|
| D — reading stop (example coordinate) | 14:05 | 14:05 | 14:50 | 5.7 | 0.0 | 80.0% (forecast) |
| B — coffee stop (example coordinate) | 14:59 | 14:59 | 15:59 | 8.7 | 0.0 | 92.9% (forecast) |
| C — outdoor stop (example coordinate) | 16:13 | 16:13 | 16:58 | 13.8 | 0.0 | 100.0% (forecast) |

## Comparison

| Plan | Order | Feasible | Travel (min) | Wait (min) | Rain exposure proxy (min) | Missed preferred overlap (min) | Finish | Score |
|---|---|---|---:|---:|---:|---:|---|---:|
| AI / selected | D → B → C | true | 28.2 | 0.0 | 45.0 | 18.5 | 16:58 | 173.7 |
| Original order | B → C → D | true | 44.3 | 0.0 | 42.6 | 30.0 | 17:14 | 219.5 |
| Travel-only baseline | D → B → C | true | 28.2 | 0.0 | 45.0 | 18.5 | 16:58 | 173.7 |

## Rationale

- **D:** Kunjungan D (reading stop, indoor) di 07:45–08:24 WIB, rainProbability 80, dalam ruang, cocok untuk membaca sambil menunggu cuaca; evidenceIds: input:D, route:A/D@1793689200, weather:D. Sources: `input:D`, `route:A/D@1793689200`, `weather:D`.
- **B:** Kunjungan B (coffee stop, indoor) di 08:32–09:32 WIB, rainProbability 92.9, dalam ruang dan cocok untuk ngopi sebelum pindah ke C; evidenceIds: input:B, route:D/B@1793692242, weather:B. Sources: `input:B`, `route:D/B@1793692242`, `weather:B`.
- **C:** Kunjungan C (outdoor stop) di 09:33–10:38 WIB, rainProbability 100, rainExposureMinutes 45, preferred window kurang 18,5 menit; semua tempat tetap dikunjungi meskipun risiko hujan luar ruang tinggi; evidenceIds: input:C, route:B/C@1793696365, weather:C. Sources: `input:C`, `route:B/C@1793696365`, `weather:C`.

## Tradeoffs and uncertainties

- Semua kandidat expose C pada hujan 100% dan 45 menit rainExposureMinutes, sehingga tidak ada opsi yang menghindari risiko hujan di luar ruang sepenuhnya. D/B/C:direct dipilih meski overlap window C kurang 18,5 menit karena waktu perjalanan terpendek (28,2 menit), tidak perlu menunggu, dan selesai paling awal (19:38 WIB). Alternatif 'wait' selesai 19:38–20:03 WIB dengan waktu tunggu 23–98 menit dan tidak mengubah paparan hujan C.
- Cuaca adalah probabilitas per jam, bukan jaminan; 100% artinya estimasi tinggi, bukan hujan pasti. Opening hours adalah asumsi pengguna, bukan fakta terverifikasi. Titik koordinat dan nama tempat bersifat contoh, bukan listing terverifikasi.

## Warnings and constraints

- Place context, exposure and opening hours are user-supplied assumptions; no web research was performed.
- Finish time means the end of the final visit. No journey home is included.
- Before-sunset preference does not establish golden hour, cloud visibility or venue suitability.
- Rain exposure is a scoring proxy, not a forecast of how many minutes it will rain. Waiting and journey weather are not scored.
- Weights, shortlist quality and AI reasoning need evaluation. No global optimality or user benefit is established.
- C: Preferred-window overlap is short by 19 minutes; destination retained.

## Experiment diagnostics

- 12 initial candidates; 5 refined candidates. Global optimality: not established.
- HTTP calls: {"Google Routes matrix":1,"Open-Meteo":3,"Google Routes leg":10,"OpenRouter":1}. Elapsed: 10396 ms.
- AI usage (as returned by provider): {"prompt_tokens":5195,"completion_tokens":870,"total_tokens":6065,"cost":0,"is_byok":false,"prompt_tokens_details":{"cached_tokens":0,"cache_write_tokens":0,"audio_tokens":0,"video_tokens":0},"cost_details":{"upstream_inference_cost":0,"upstream_inference_prompt_cost":0,"upstream_inference_completions_cost":0},"completion_tokens_details":{"reasoning_tokens":0,"image_tokens":0,"audio_tokens":0}}.
- Inspect report.json for all alternatives, constraints, normalized input and evidence. Evidence IDs validate references, not the truth of every sentence.
