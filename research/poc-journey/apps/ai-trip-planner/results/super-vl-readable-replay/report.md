# Johan — illustrative Jakarta itinerary

**Mode:** live · **Date:** 2026-11-03 · **Time zone:** WIB

**Evidence status:** Real AI replay over saved Google/Open-Meteo candidates from the prior live run; route/weather were not fetched again.

**AI called:** yes (nvidia/nemotron-3.5-super-vl:free)

**Visited:** none · **Departure now:** 14:00 · **Finish by:** 19:00

**Recommended:** D → B → C · **Feasible:** yes, against supplied constraints

Urutan yang dipilih: D (membaca) → B (ngopi) → C (luar ruang, menunggu hingga jendela sunset).

| Stop | Arrival | Visit | Leave | Travel (min) | Wait (min) | Rain probability during visit |
|---|---|---|---|---:|---:|---|
| D — reading stop (example coordinate) | 14:05 | 14:05 | 14:50 | 5.7 | 0.0 | 80.0% (forecast) |
| B — coffee stop (example coordinate) | 14:59 | 14:59 | 15:59 | 8.7 | 0.0 | 92.9% (forecast) |
| C — outdoor stop (example coordinate) | 16:13 | 16:46 | 17:31 | 13.8 | 33.5 | 100.0% (forecast) |

## Comparison

| Plan | Order | Feasible | Travel (min) | Wait (min) | Rain exposure proxy (min) | Missed preferred overlap (min) | Finish | Score |
|---|---|---|---:|---:|---:|---:|---|---:|
| AI / selected | D → B → C | true | 28.2 | 33.5 | 45.0 | 0.0 | 17:31 | 126.6 |
| Original order | B → C → D | true | 44.3 | 0.0 | 42.6 | 30.0 | 17:14 | 219.5 |
| Travel-only baseline | D → B → C | true | 28.2 | 0.0 | 45.0 | 18.5 | 16:58 | 173.7 |

## Rationale

- **D:** Mulai di D pukul 14:05:42 WIB dan berlaku hingga 14:50:42 WIB (60 menit, dalam jam buka 09:00–20:00). Cuaca: probabilitas hujan 80%, suhu 32,5 °C, awan 53%; tidak ada exposure hujan karena indoor. Lihat candidate:D/B/C:wait. Sources: `input:D`, `route:A/D@1793689200`, `weather:D`.
- **B:** Kunjungi B pukul 14:59:25 WIB hingga 15:59:25 WIB (60 menit, dalam jam buka 10:00–20:00). Tempat cocok untuk ngopi sambil baca di dalam ruangan. Cuaca: probabilitas hujan 92,87%, suhu 31,41 °C, awan 27,25%; exposure hujan 0 menit karena indoor. Lihat candidate:D/B/C:wait. Sources: `input:B`, `route:D/B@1793692242`, `weather:B`.
- **C:** Tunggu hingga jendela sunset dimulai pukul 16:46:43 WIB, lalu kunjungi C pukul 16:46:43–17:31:43 WIB (45 menit, sesuai jendela 60 menit sebelum sunset, dalam jam buka 08:00–20:00). Cuaca saat kunjungan: probabilitas hujan 100%, suhu 30,37 °C, awan 55,67%; exposure hujan 45 menit adalah indikator perangkingan, bukan ramalan durasi hujan. Pastikan Anda menyetujui risiko cuaca tinggi di luar ruang. Lihat candidate:D/B/C:wait. Sources: `input:C`, `route:B/C@1793696365`, `weather:C`.

## Tradeoffs and uncertainties

- Pilihan ini selesaikan semua tiga tempat tanpa melewati batas waktu selesai 19:00 WIB; selesai pukul 17:31:43 WIB.
- Memiliki skor terendah (126,59, peringkat 1) di antaranya, meskipun waktu tunggu lebih lama dari B/D/C:wait (33,5 vs 23,13 menit) karena rute D→B→C lebih efisien secara perjalanan.
- Semua estimasi cuaca menunjukkan probabilitas hujan tinggi, terutama di C (100%). Jeda di C dilakukan untuk mencocokkan jendela preferensi sunset, bukan jaminan cuaca cerah atau visibilitas.
- Jeda saat perjalanan bukan waktu di lokasi; jika Anda ingin menghindari tunggu di luar ruang, pertimbangkan opsi non-tunggu atau ubah urutan, tetapi itu akan meningkatkan skor dan/atau melewatkan jendela sunset.
- Jam buka dan koordinat adalah asumsi yang Anda berikan, bukan fakta terverifikasi lokasi.
- Cuaca adalah estimasi per jam berbasis probabilitas, bukan jaminan; 'missing forecast' berarti tidak diketahui, bukan cerah.
- rainExposureMinutes adalah proxy perangkingan, bukan prediksi menit hujan aktual.

## Warnings and constraints

- Replay uses the prior live run data; this is not a fresh route or forecast lookup.
- Place context, exposure and opening hours are user-supplied assumptions; no web research was performed.
- Finish time means the end of the final visit. No journey home is included.
- Before-sunset preference does not establish golden hour, cloud visibility or venue suitability.
- Rain exposure is a scoring proxy, not a forecast of how many minutes it will rain. Waiting and journey weather are not scored.
- Weights, shortlist quality and AI reasoning need evaluation. No global optimality or user benefit is established.

## Experiment diagnostics

- 12 initial candidates; 5 refined candidates. Global optimality: not established.
- HTTP calls: {"OpenRouter":1}. Elapsed: 9189 ms.
- AI usage (as returned by provider): {"prompt_tokens":6775,"completion_tokens":910,"total_tokens":7685,"cost":0,"is_byok":false,"prompt_tokens_details":{"cached_tokens":0,"cache_write_tokens":0,"audio_tokens":0,"video_tokens":0},"cost_details":{"upstream_inference_cost":0,"upstream_inference_prompt_cost":0,"upstream_inference_completions_cost":0},"completion_tokens_details":{"reasoning_tokens":0,"image_tokens":0,"audio_tokens":0}}.
- Inspect report.json for all alternatives, constraints, normalized input and evidence. Evidence IDs validate references, not the truth of every sentence.
