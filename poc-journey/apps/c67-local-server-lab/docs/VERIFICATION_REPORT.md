# Hasil implementasi server itinerary lokal

**6 November 2026, WIB.** Implementasi lokal dan replay selesai. Server aktual di Mac, SQLite, engine Swift, runtime E5 dan client simulator telah dijalankan end-to-end. **Hipotesis pengurangan waktu live ≥30% belum diuji:** konfigurasi Apple Maps Server API/WeatherKit REST belum tersedia. User memilih melanjutkan dengan simulator setelah client iPhone mengalami kegagalan LAN.

## Yang diimplementasikan

- Swift/Vapor API dengan satu worker, antrean3 outstanding, result/progres, idempotency, cancellation, timeout240 detik, SQLite/WAL dan recovery restart.
- Apply atomik memeriksa client, input hash, expiry dan base revision; hasil terlambat tidak menimpa accepted baseline.
- Engine hybrid/objective dan fakta sumber dari PoC disalin tanpa mengubah source asli. A menjalankan orkestrasi/package asli, B/C memakai engine bersama di server. Tidak ada LLM judge/backend Node lama.
- C: bulk snapshot maksimal10 tujuan menurut asal/moda/departure yang sama, dedup akuisisi, exact-time final-leg validation, satu runtime E5 CPU dengan passage cache berbasis area/konten/model, dan proof lower bound sebelum ETA.
- Adapter REST: ES256 JWT/token, search, ETA, weather/attribution, timeout, 401 invalidation/expiry, 429/Retry-After, bounded campaign guard; tanpa native/mock fallback. Diuji dengan stub; belum dengan akun aktual.
- Harness iOS A/B/C, persist result sebelum timer berhenti, progres, ekspor per run, relaunch dan cancellation. Live campaign gated terpisah dari replay.

## Bukti verifikasi

| Lapisan | Hasil |
| --- | --- |
| Swift lokal | **60/60**:25 XCTest baru +35 Swift Testing aturan warisan |
| HTTP nyata Mac | **12/12** contract checks |
| CLI →HTTP Mac replay final | **51/51** outcome didukung auditor;28 pembanding objective identik terhadap A |
| Simulator →HTTP Mac replay | **51/51** outcome didukung auditor;28 pembanding objective identik terhadap A |
| Auditor negative controls | Enam pemalsuan hasil ditolak |
| E5 |384 elemen hasil salinan runtime cocok dengan E5 asli dalam1e-7; passage cache area/query policy diuji |
| UI | Progres dan selesai diamati;51 observasi dipulihkan setelah relaunch; mulai/batal diverifikasi melalui Device Hub |
| iPhone fisik | App terpasang/terbuka, koneksi LAN gagal; bukan hasil benchmark fisik yang berhasil |
| REST live | Tidak dipanggil: kredensial belum ada |

Skenario ready berjumlah42 per replay (12 kasus ukuran itinerary +REV5+MIX5, masing-masing3 varian); sembilan outcome non-ready memang diharapkan. TIGHT5 pada C memberi proof27000>21600 detik dan nol request ETA; A/B memberi no_feasible_candidate, tanpa klaim global infeasible. SIX dan UNKNOWN menahan input tanpa mencari rute.

## Apa yang sudah terbukti tentang optimasi

| Kasus | A/B call ETA | C call ETA | Sel ETA masing-masing varian |
| --- | ---: | ---: | ---: |
| N1 |2 |2 |2 |
| N3 |21 |15 |21 |
| N4 |39 |26 |39 |
| N5 |53 |31 |53 |

Pada N5, batch menurunkan panggilan **41,5%** sambil mempertahankan sel, objective, durasi, semua tujuan dan deadline. Ini bukti akuisisi bulk bekerja pada oracle bersama. Ruas final tetap divalidasi pada waktu berangkat yang sebenarnya dalam simulasi.

Timings replay tersedia di CSV/JSON, menggunakan oracle yang tidak menunggu jaringan provider. Pada run simulator pertama yang lengkap, median N3 A/B/C sekitar0,757/0,483/0,387 detik; N5 sekitar0,861/0,609/0,535 detik. Waktu tersebut **tidak sebanding langsung** dengan benchmark MapKit iPhone lama (N5 median65,39 detik). Tidak dipakai untuk meluluskan target30%, membuat SLA atau p95.

A fresh juga memuat E5 sesuai aplikasi acuan; server mengamortisasi inisialisasi satu runtime. Precompute server terukur sekitar0,796 detik pada startup final, sebelum timer job. Keuntungan ini merupakan bagian perubahan sistem, bukan seluruhnya efek batching. B→C lebih langsung mengisolasi kebijakan persiapan/akuisisi.

## Resource dan batas pengukuran

Server satu proses/worker/provider concurrency1, tanpa Docker/GPU/homelab/cloud. Sampling120 detik pada proses server, interval1 detik, mencatat RSS maksimum sekitar**137,8 MiB** dan maksimum `%CPU` yang dilaporkan ps98,9. Window mencakup sebagian replay dan idle; bukan kebutuhan RAM produksi, CPU profile per tahap atau energi iPhone.

Timer client mencakup submit/queue/poll/fetch/persist hasil; bukan hanya202. Engine metrics warisan memisahkan preference/search/weather/routing. Stopwatch terpisah untuk solver/audit/SQLite/serialization belum ditambahkan; waktu routing tetap gabungan dan overhead sisanya tidak boleh ditebak sebagai CPU. Ini keterbatasan instrumentasi, bukan ketidaklengkapan result.

Server menyimpan history eksperimen untuk audit; beberapa jalur antrean masih membaca history job lengkap. Belum diuji sebagai service lama dengan history besar, multi-user atau workload paralel produksi. Jalur live dan pemetaan respons aktual tetap memerlukan probe dan campaign setelah keys tersedia.

## Kampanye live yang disiapkan

Jadwal penuh75 observasi: fresh36, priming12, warm12, edge15. Dry estimate termasuk overhead20 call/job memberi3372 call/2121cells, sehingga default guard3000call memilih subset fresh+edge **51 observasi**, estimated2284call/1431cells. Warm tidak dipilih setelah melihat hasil; dikeluarkan sebagai kelompok sebelum launch. Estimate ini bukan quota aktual dan pola query live mungkin berbeda.

Manifest saat ini berstatus blocked untuk missing credentials dan allowance provider yang belum dikonfirmasi. Tidak ada key dibuat, akun diubah atau request live yang disamarkan sebagai replay. User menyetujui melanjutkan implementasi/replay tanpa keys. `prepare-live.py`, probe CLI, pacing/guard server, campaign harness dan auditor live telah disiapkan, namun belum tervalidasi end-to-end terhadap provider aktual.

Target tetap minimal tiga pasangan fresh lengkap pada setiap N3/N4/N5 dan median paired C/A≤0,70 dengan semua ready valid. Saat ini: **bukti belum cukup untuk hipotesis kecepatan live**. Kesetaraan pada oracle dan pengurangan jumlah call didukung.

## Pemulihan dan integritas

- Seluruh **66** hash source/input asli sama dengan baseline.
- Salinan OriginalIntegrationModel byte-identik dengan file aplikasi acuan.
- App asli iPhone dan simulator dipasang kembali dan berhasil dibuka tanpa argumen evaluasi.
- Sembilan file normal store sebelum/sesudah **identik**; tidak ada uninstall atau penghapusan container.
- Bukti launch ditolak karena lock, koneksi LAN gagal, percobaan replay awal dan run UI dibatalkan dipertahankan terpisah.
- Perubahan setelah replay CLI/awal simulator hanya presentasi tombol/label cancellation, tambahan test E5 dan penanganan auditor; engine/API source tetap identik. Manifest simulator final membekukan seluruh kode handoff terbaru.
- Server eksperimen dihentikan dan token run dicabut pada penutupan. SQLite, passage index dan bukti tetap ada untuk reproduksi.
- Tidak ada perubahan aplikasi produksi C67, homelab, Supabase, commit/push atau deploy.

## Artefak utama

- Manifest CLI (original local evidence, omitted from this publication), audit CLI (original local evidence, omitted from this publication), CSV CLI (original local evidence, omitted from this publication)
- Manifest client final (original local evidence, omitted from this publication), audit client final (original local evidence, omitted from this publication), CSV client final (original local evidence, omitted from this publication)
- Replay simulator awal lengkap (original local evidence, omitted from this publication), negative controls (original local evidence, omitted from this publication)
- HTTP contract (original local evidence, omitted from this publication), tes Swift (original local evidence, omitted from this publication)
- Resource samples (original local evidence, omitted from this publication), store preservation (original local evidence, omitted from this publication)
- Preflight (original local evidence, omitted from this publication), live readiness (original local evidence, omitted from this publication)
- Layar selesai (original local evidence, omitted from this publication), progres (original local evidence, omitted from this publication)

Dokumentasi teknis yang diperiksa: [ETA Server API](https://developer.apple.com/documentation/applemapsserverapi/-v1-etas), [Maps token](https://developer.apple.com/documentation/applemapsserverapi/-v1-token), [WeatherKit REST](https://developer.apple.com/documentation/weatherkitrestapi), [attribution REST](https://developer.apple.com/documentation/weatherkitrestapi/attribution), [Vapor](https://docs.vapor.codes/). Kesesuaian implementasi dengan stub tidak menggantikan bukti akun/provider live.

## Pembaruan autentikasi setelah benchmark

Pada 6 November 2026, pemeriksaan dokumentasi setup menemukan bahwa JWT developer Maps perlu claim `scope: server_api`. LabJWT telah diperbaiki untuk menambahkan scope hanya pada token Maps; token WeatherKit tetap memakai Service ID tanpa scope Maps. Tes lokal signature/claims untuk keduanya lulus. Tidak ada probe provider live atau pengulangan benchmark. Manifest replay di atas merekam versi sebelum koreksi ini dan dipertahankan sebagai bukti historis. Lihat catatan koreksi (original local evidence, omitted from this publication) dan log tes (original local evidence, omitted from this publication).

## Pembaruan kredensial — 6 November 2026, 19.28 WIB

Setelah user mengisi `.env.local`, validasi konfigurasi serta satu probe minimum provider aktual berhasil: Maps search memberikan satu hasil, satu ETA available, WeatherKit REST available, dan attribution tersedia. Lima panggilan provider tingkat aplikasi serta satu ETA cell digunakan, termasuk pertukaran token Maps. Tidak ada benchmark itinerary penuh atau kampanye A/B/C live pada tahap verifikasi kredensial ini. Status awal “kredensial belum tersedia” di bagian pelaksanaan sebelumnya adalah kondisi historis, bukan kondisi terkini.

Lihat hasil probe (original local evidence, omitted from this publication) dan ringkasan verifikasi (original local evidence, omitted from this publication). Private key dan token tidak dimasukkan ke bukti.

## Pembaruan benchmark simulator live —6 November2026

Benchmark terkontrol selesai51 observasi:42 ready+9 outcome non-ready yang sesuai, seluruhnya lolos audit independen. Median A/B/C untuk3 tujuan27,41/27,54/20,34 detik;4 tujuan46,68/46,76/31,08;5 tujuan63,44/63,52/35,98. Target≥30% pada setiap keluarga belum tercapai karena N3 hanya26,9%. Ini memakai shared real pins dan provider ETA/cuaca aktual; search REST E2E belum lolos seluruh venue. Host idle sleep, timeout dan aturan pemulihan dicatat terpisah, tidak dihapus dari bukti. Lihat [laporan lengkap](LIVE_SIMULATOR_BENCHMARK_2026-11-06.md).

## Pembaruan D — handoff7November2026

D diimplementasikan dan diuji:69tes lokal lulus,34observasi replay+34live C/D lolos auditor. Median C/D untuk3tujuan20,31/4,75detik;4tujuan31,18/5,89;5tujuan35,85/7,05. Semua14pasangan ready live mempunyai elapsed trip sama, tetapi uji adversarial membuktikan first-feasible dapat kehilangan kualitas saat prior salah. Tidak ada klaim optimum atau discovery E2E. Source asli dipertahankan dan proses eksperimen ditutup. [Hasil dan trade-off lengkap](FAST_D_RESULTS_2026-11-06.md).
