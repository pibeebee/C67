# C67 local itinerary server lab

**Current public checkout — 9 November 2026.** Start with [Context Lab v0.5](ContextHarness/README.md) and the [current handoff](../../docs/context-lab-handoff-2026-11-09.md). Run the repository model bootstrap before building. The dated reports and historical commands below keep their original experiment scope; original-location source-hash checks can differ after publication formatting. [Source export verification](../../evidence/context-lab-relocation-2026-11-09.md).

**Evaluasi user simulasi, 8 November:** tiga kebutuhan baru diuji tanpa tuning engine. Ditemukan kebutuhan yang tidak tertangkap UI, kekurangan kandidat arsitektur, penolakan alias/penerimaan tenant pada identitas, dan artefak grid yang menghilangkan kegiatan opsional. [Hasil dan batas penilaian](docs/SYNTHETIC_USER_RESULTS_2026-11-08.md). Ini bukan validasi kepuasan manusia.

**Personal recommendation PoC, 8 November:** onboarding interests/pace, dynamic candidate discovery, on-device E5, mandatory free OpenRouter judging, within-interest learning, and required/optional itinerary selection are implemented in the isolated Simulator app. [Current flow and setup](ContextHarness/README.md), [protocol](docs/PERSONAL_RECOMMENDATION_PROTOCOL_2026-11-08.md), [implementation and evidence](docs/PERSONAL_RECOMMENDATION_RESULTS_2026-11-08.md). Historical results below concern their own older paths.

**Validasi kode benchmark, 7 November.** Bug cache/anggaran ETA, decoding batch parsial, indikator pemotongan pencarian dan auditor sudah direproduksi serta diperbaiki. Perbandingan offline memperbaiki dua konfigurasi yang sebelumnya gagal. [Laporan validasi](docs/BENCHMARK_CODE_VALIDATION_2026-11-07.md).

**Uji lima tujuan selesai,7 November:** belum ditemukan hasil yang memenuhi batas menunggu30menit. Kontrol60menit menemukan jadwal dengan39,93menit menunggu; seluruh tunggu pada jadwal itu cocok dengan pembulatan grid15menit. [Hasil, kegagalan dan batas](docs/CONTEXT_FIVE_RESULTS_2026-11-07.md).

**Pilot konteks tiga tempat selesai,7 November:** pipeline lengkap fresh-process9,76detik; median pemrosesan rute6,00/12,00/22,71detik menghasilkan jadwal sama dan satu hasil diterima pengguna. Ini belum klaim akurasi populasi. [Laporan, fixture independen dan batas](docs/CONTEXT_PILOT_RESULTS_2026-11-07.md).

**Fokus setelah konsolidasi 7 November:** menguji waktu komputasi dan kesesuaian itinerary dengan keinginan pengguna. Ringkasan pemahaman dan pilot berikutnya (original local evidence, omitted from this publication) membedakan bukti lama, batas engine konteks baru, serta eksperimen yang masih berupa rekomendasi.

Eksperimen server itinerary **lokal di Mac**: Swift/Vapor, SQLite, satu worker, satu runtime E5 CPU. Tidak memakai homelab atau layanan cloud baru. Jalur A–E mempertahankan objective hybrid `elapsed_v2` dari PoC integrasi; planner konteks baru menguji prioritas pengguna secara terpisah.

**Hasil terverifikasi:** 62 tes lokal, 12 pemeriksaan HTTP, 51 observasi replay CLI dan 51 observasi replay simulator lolos. Objective pada 28 pembanding terhadap A identik di masing-masing run. Probe minimum REST aktual berhasil pada 6 November 2026 pukul 19.28 WIB: search, ETA, WeatherKit dan attribution. Benchmark simulator live terkontrol sudah selesai:51 observasi, C lebih cepat26,9%/33,4%/43,4% untuk3/4/5 tujuan. Search REST E2E masih belum menyelesaikan seluruh identitas lokasi. Lihat [laporan live simulator](docs/LIVE_SIMULATOR_BENCHMARK_2026-11-06.md).

- **A:** orkestrasi aplikasi asli, source dan package acuan dipertahankan.
- **B:** engine yang diadaptasi melalui HTTP Mac, satu pasangan ETA per panggilan.
- **C:** engine sama, passage embedding dipersiapkan, snapshot ETA dibatch menurut asal/moda/departure persis sama. Validasi ruas akhir tetap time-dependent.

Pada N5 replay, A/B = 53 call/53 cell, C = 31 call/53 cell. Pengurangan call bukan pengurangan seluruh evaluasi perjalanan. Tidak ada LLM judge.

**Eksperimen terbaru D:** pencarian urutan lokal lalu validasi finalis mencapai median **7,05detik untuk5tujuan** pada simulator live, dibanding C35,85detik. Seluruh34observasi C/D lolos audit. D mengamati lebih sedikit edge dan dapat kehilangan kualitas jika prior salah; hasil ini belum klaim discovery E2E atau jaminan generalisasi. [Laporan D](docs/FAST_D_RESULTS_2026-11-06.md).

**Evaluasi urutan eksperimen, 7 November:** 144 fixture independen/576 observasi kebijakan mengungkap gap D; E3 menguranginya dengan biaya validasi tambahan. Pada simulator live, N5 D7,12detik vs E19,10detik, dengan elapsed itinerary E15menit27detik lebih pendek. Discovery luar katalog menemukan enam nama tetapi belum memenuhi integrasi/fakta planner. E adalah varian lab eksperimen, bukan default produk. [Laporan dan batas lengkap](docs/DECISION_SEQUENCE_RESULTS_2026-11-07.md).

**Google Places context engine:** library terpisah, CLI dan API lokal untuk search/details, jam, indikasi waktu dari ulasan, preferensi pengguna serta pencarian urutan+slot. [Setup API key dan penggunaan](docs/GOOGLE_PLACES_CONTEXT_SETUP.md), [verifikasi dan batas](docs/GOOGLE_PLACES_CONTEXT_VERIFICATION_2026-11-07.md). Belum ada panggilan Google live sebelum key tersedia; D/E dan aplikasi acuan tetap terpisah.

## Menjalankan lokal

Google Places sudah melewati [verifikasi live satu tempat](docs/GOOGLE_PLACES_CONTEXT_LIVE_2026-11-07.md): Place Details + jam + lima ulasan dan 16 skenario lokal. Pada run satu tempat tersebut belum ada integrasi ETA nyata atau validasi relevansi pengguna. Status lanjutannya ada di laporan pilot tiga tempat di atas.

Prasyarat: Mac dengan toolchain Swift 6.2+ dan SDK Apple 26+; versi yang diuji Swift 6.4.2, macOS 27.2, Xcode 27.2. Aset model E5 sudah disertakan dan diperiksa SHA-256 ketika dimuat. Gunakan build Debug untuk pembanding A karena injeksi oracle memakai `@testable` package asli.

Dari folder ini:

```sh
swift build -j 4
swift test -j 4
python3 scripts/start.py
python3 scripts/freeze.py artifacts/my-replay
python3 scripts/replay.py artifacts/my-replay
python3 scripts/audit.py artifacts/my-replay
python3 scripts/test-auditor.py artifacts/my-replay
python3 scripts/stop.py
```

Setiap run memakai direktori bukti baru. Start menghasilkan konfigurasi privat `.local/client-config.json`, bukan mencetak token. Server default `127.0.0.1:8767`; `/health` terbuka, endpoint lab membutuhkan token sementara. `stop.py` hanya menghentikan PID binary lab yang tercatat, lalu mencabut token. SQLite dan hasil tetap tersedia.

Untuk harness, generate `ClientHarness/project.yml` dengan XcodeGen dan build scheme `C67LocalServerHarness`. Jalankan simulator menggunakan `scripts/simulator-run.py --simulator <ID> --run <ID-baru>` setelah app terpasang. Config dibaca dari file privat dan diberikan melalui environment; kredensial Apple tidak masuk client. Lihat [setup](docs/SETUP.md) sebelum memasang di iPhone: bundle ID harness menggunakan ID PoC asli, sehingga backup dan restore wajib.

## Dokumen dan bukti

- [Hasil dan batas verifikasi](docs/VERIFICATION_REPORT.md)
- [Setup, provider dan restore](docs/SETUP.md)
- [Kontrak API yang tersedia](docs/API.md)
- [Asal kode dan adaptasi](docs/REUSE.md)
- [Protokol final](docs/BENCHMARK_PROTOCOL.md)
- Rencana yang disetujui (original local evidence, omitted from this publication)
- Audit CLI (original local evidence, omitted from this publication), audit simulator (original local evidence, omitted from this publication), kesiapan live (original local evidence, omitted from this publication)

Log/artefak merupakan bukti engineering lokal dan tidak otomatis aman untuk publikasi. Folder `.local`, private key dan file konfigurasi token diabaikan Git. Eksperimen ini belum membuktikan portabilitas Linux, ketahanan produksi, throughput banyak pengguna atau akurasi perjalanan lapangan.
