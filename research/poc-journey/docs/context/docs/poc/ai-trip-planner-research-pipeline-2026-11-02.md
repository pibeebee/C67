# Pembaruan kode PoC: browser dan perbaikan jadwal otomatis

Tanggal: 2 November 2026. Lingkup: PoC CLI di `poc/ai-trip-planner`, tanpa perubahan aplikasi iOS C67.

Instruksi pengguna: tingkatkan kelemahan penyusunan jadwal sebelum data memadai dan implementasikan pencarian informasi melalui headless browser. **Tidak menjalankan tes lagi; cukup perubahan kode dan memastikan kompilasi.**

## Perubahan yang diimplementasikan

- `plan:research` mengumpulkan walking, probe transit dan forecast sebelum menyusun itinerary. Probe transit awal bukan jam pilihan pengguna; rute diambil lagi pada waktu keberangkatan hasil simulasi.
- Playwright/Chromium membaca sumber publik resmi. Model dapat meminta pencarian dan pembacaan halaman dalam putaran terstruktur yang dibatasi. Search snippet tidak menjadi bukti fakta.
- Ekstraksi menyimpan URL, teks terbatas, hash, timestamp, kutipan dan applicability tanggal. Klaim tanpa kutipan/angka yang cocok ditolak. Semantik ekstraksi tetap perlu review; jam umum/bersyarat tidak diam-diam menggantikan constraint yang diberikan.
- Simulasi memisahkan kunjungan, perpindahan dan waiting, menambahkan buffer sistem, serta mempropagasikan perubahan ke seluruh perjalanan. Tujuan tidak dihapus untuk menyembunyikan ketidaklayakan.
- Feedback evidence dan simulasi dikirim otomatis ke model untuk repair, default maksimal tiga proposal. Data yang tetap hilang menghasilkan status unknown/needs_information; tidak menjadi durasi nol atau layanan transportasi terkonfirmasi.
- Laporan tabel memakai perhitungan kode, sementara teks mentah AI disimpan terpisah. Ada budget request/model/token dan snapshot/reuse dengan batas umur.
- Jalur lama `plan:untimed` dipertahankan untuk pembanding. Hasil live versi sebelumnya tidak ditulis ulang menjadi hasil versi baru.

## Artefak kode

| File | Peran |
|---|---|
| `src/plan-researched.ts` | Orkestrasi, checkpoint, repair loop, laporan |
| `src/research-browser.ts` | Browser terisolasi, official search/read, batas akses dan resource |
| `src/research-agent.ts` | Permintaan browser oleh AI dan ekstraksi berkutip |
| `src/planning-data.ts` | Evidence rute, probe awal dan forecast |
| `src/planning-simulation.ts` | ETA berurutan, buffer, waiting, propagasi, konflik |
| `src/model-session.ts` | Batas agregat panggilan/token, metadata tanpa reasoning internal |
| `src/untimed.ts` | Proposal lama dikembangkan agar menerima session/evidence/feedback baru |

Path file pada tabel relatif terhadap `poc/ai-trip-planner`.

## Verifikasi pekerjaan ini

Kompilasi: `npm run check` → `tsc --noEmit` lulus.

Library Playwright 1.64.1 dipasang dengan `--ignore-scripts` untuk dependency/tipe. Tidak menjalankan tes, fixture/demo, browser, instalasi binary browser, atau provider Google/OpenRouter. Tidak ada itinerary baru yang dihasilkan pada pekerjaan ini. Keberhasilan runtime pencarian, ekstraksi, perbaikan model dan kualitas itinerary **belum diverifikasi**.

[Panduan konfigurasi dan menjalankan nanti](../../../../apps/ai-trip-planner/RESEARCH_PIPELINE.md) menjelaskan kebutuhan Chromium, batas kerja, sumber evidence, artefak, dan status hasil. Panduan tersebut tidak mengubah batas verifikasi pekerjaan ini.
