# Eksperimen itinerary Jepang tanpa jam — 2 November 2026

Permintaan: ulangi daftar trip Kamakura–Enoshima tanpa memasukkan jam atau durasi, untuk 5 Desember 2026, satu hari, berangkat dan kembali ke Stasiun Funabashi.

## Kebutuhan produk yang diperbarui

Tempat dan waktu tiap tempat yang diharapkan adalah komponen wajib. Waktu berangkat, tanggal, batas pulang, preferensi dan hal lain opsional. Percobaan ini merupakan pengecualian eksplisit untuk menguji proposal sistem ketika jam pengguna tidak diberikan. CLI lama masih memiliki persyaratan teknis yang lebih sempit; eksperimen ini tidak menyatakan seluruh kontrak produk sudah diimplementasikan.

## Implementasi percobaan

- `poc/ai-trip-planner/src/plan-untimed.ts`: pengumpulan evidence, proposal AI, validasi dan laporan.
- `poc/ai-trip-planner/src/untimed.ts`: validasi input tanpa jam, timeline tanpa tumpang tindih/teleportasi, kelengkapan aktivitas, coastal walk dan perpindahan kereta, pengecekan rute serta jam bersumber.
- `poc/ai-trip-planner/examples/funabashi-enoshima-2026-12-05-untimed.json`: daftar 14 aktivitas, coastal walk dan enam pasangan kereta; tanpa jam/durasi lama.
- `poc/ai-trip-planner/examples/funabashi-enoshima-place-context.json`: identitas/ketidakpastian lokasi, pasangan walking untuk dikumpulkan dan ringkasan sumber resmi. File konteks disiapkan melalui riset sumber; runner tidak melakukan browser research otomatis.

## Hasil

AI menghasilkan usulan 07:00–22:00 JST dengan seluruh aktivitas dan transportasi yang diminta. Draf awal tidak menegaskan dua perpindahan kereta, sehingga constraint input/validator diperjelas dan AI diminta melakukan satu repair. Hasil final lolos cakupan/struktur, namun belum layak dinyatakan terverifikasi: 11 walking punya estimasi Google, 6 transit no_route, dan 4 leg restoran unresolved. Sepuluh leg tersebut tidak dianggap nol menit.

Ditemukan buffer walking sangat tipis, narasi menunggu illumination yang tidak cocok dengan jam sumber, serta kualitas bahasa belum konsisten. Forecast tanggal trip di luar horizon pada tanggal pengumpulan. Jadwal dan prosa mentah dipertahankan; hasil teknis dan mutu rekomendasi dibedakan.

[Review lengkap hasil lokal](../../../../apps/ai-trip-planner/results/japan-2026-12-05-untimed-run2/review.md) dan [jadwal lengkap](../../../../apps/ai-trip-planner/results/japan-2026-12-05-untimed-run2/report.md). `results/` diabaikan Git; tautan tersebut membutuhkan artefak lokal.

Validasi: 41 tes backend PoC, typecheck, dan format lulus. Dua request AI nyata, reasoning on, total 37.555 token di dua panggilan; plafon konteks 1.000.000 per request. Tidak ada pengujian pengguna atau validasi perjalanan lapangan pada eksperimen ini.

## Menjalankan

```sh
npm run plan:untimed -- \
  --input examples/funabashi-enoshima-2026-12-05-untimed.json \
  --context examples/funabashi-enoshima-place-context.json \
  --out results/japan-untimed-new
```

Gunakan direktori hasil baru. `--reuse`, `--repair` dan `--proposal` dijelaskan di [README PoC](../../../../apps/ai-trip-planner/README.md). Memperbaiki draf AI tidak memasukkan kembali jam baseline pengguna.
