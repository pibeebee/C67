# Verifikasi POC 0.5 — rundown, peta kegiatan & Calendar

15 Oktober 2026 · versi 0.5 build 7 · iOS 18+ · Xcode 27 · Simulator iPhone 18 Pro iOS 27.

## Scope

- Buat/edit/hapus kegiatan dengan waktu, zona waktu, catatan dan lokasi opsional.
- Pilih lokasi melalui pencarian MapKit, ketuk peta atau tombol Pilih titik tengah; pengaturan meeting point memakai pemilih yang sama.
- Pin kegiatan berbeda dari orang, dapat dipilih langsung/Daftar, dan membuka detail. Detail kegiatan dapat membuka peta terfokus.
- Aktivasi kegiatan membutuhkan konfirmasi; memperbarui titik/waktu berkumpul tanpa mengubah pemeriksaan.
- Rundown dan meeting point versi terbaru diterbitkan ke share privat TL per peserta, terpisah dari payload GPS. Peserta read-only dengan cache/status/retry foreground.
- Ekspor satu arah melalui editor EventKitUI native; receipt hanya pada `.saved`, pembatalan tidak dianggap saved, ekspor ulang memperingatkan duplikat.

[Penggunaan, arsitektur, langkah dua iPhone dan batas](../ITINERARY_GUIDE.md).

## Hasil

| Pemeriksaan | Hasil dan batas |
|---|---|
| Unit/integration terbaru | **77/77 lulus**: Domain 23, Demo 7, GroupMap 15, JourneyPlan 19, QR 13 |
| UI unik terbaru | **25/25 lulus**: 19 alur sebelumnya dan 6 rundown/Calendar |
| Agregasi terbaru per kasus | **102 passed, 0 failed, 0 skipped**, gabungan regresi dan tes ulang; [JSON/provenance](test-summary-v5.json) |
| Regresi lengkap | Bundle terfinalisasi `c67-v5-regression.xcresult`: **100 passed, 1 failed** (encoding QR) |
| Run final setelah perbaikan | Bundle terfinalisasi `c67-v5-final.xcresult`: **86/86 passed, TEST SUCCEEDED** — seluruh 77 unit/integrasi dan 9 UI terdampak |
| Build Simulator & Debug iPhone signed | Passed, versi **0.5 build 7** |
| Signature iPhone | Passed `codesign --verify --deep --strict --verbose=2` |
| Inspeksi visual | Screenshot [rundown](../../../../docs/missing-evidence.md#missing-970098afd604), [pemilih titik](../../../../docs/missing-evidence.md#missing-56f7a37320fc), [pin kegiatan](../../../../docs/missing-evidence.md#missing-19e51e40685a), [editor Calendar native](../../../../docs/missing-evidence.md#missing-2e4d46a377aa) |
| CloudKit multi-akun / Calendar saved akun nyata | **Belum diuji** |

Tidak ada klaim satu run 102/102; hasil terbaru 102 kasus diambil dari regresi dan run final. Perbaikan QR tidak mengubah protokol v3 atau signature welcome. Log/bundle sementara berada di `/private/tmp` dan dapat dibersihkan OS; ringkasan JSON serta screenshot disimpan pada repo. Log signed final: `/private/tmp/c67-v5-device-final.log`.

## Bukti yang diperiksa

Tes model/integrasi memakai store in-memory dan transport CloudKit pengganti untuk menguji:

- Decode snapshot lama, fallback plan stabil, penyimpanan ulang dan rollback save failure.
- Validasi waktu, zona waktu, koordinat, ID duplikat, jumlah/ukuran payload, run dan versi.
- Aktivasi/edit/hapus titik aktif, meeting point manual dan status pemeriksaan yang tetap terpisah.
- Fan-out per peserta, retry/offline, perubahan selama publish, peserta baru menerima versi yang sama, dan kanal parsial/dicabut tidak memblokir semua peserta.
- Fetch tanpa GPS, cache offline, penghapusan titik melalui snapshot baru, versi lama/conflict ditolak, fetch terlambat setelah leave diabaikan, rollback simpan lokal.
- Mapping EventKit title/waktu/zona/catatan/koordinat dan receipt/fingerprint lokal yang tidak masuk payload rundown.

Tes UI menjalankan layar SwiftUI asli dan editor Apple: tambah/edit/hapus, picker batal/simpan, default meeting point kosong lalu simpan/hapus, pin/daftar/detail, aktivasi batal/setuju, peserta baca-saja, dan pembatalan editor Calendar.

## Riwayat kegagalan dan perbaikan

- Build awal menemukan default argument yang memanggil initializer MainActor dari konteks nonisolated. Transport dibuat pada initializer actor, lalu build lulus.
- Run fokus awal `/private/tmp/c67-v5-focused.xcresult` mencatat 4 kegagalan: fixture versi lama yang invalid; helper tes tidak menunggu pin selesai muncul; query judul detail ambigu karena detail belakang dan sheet depan sama-sama ada di hierarchy; serta tes mengetik lanjutan ke teks yang sedang terseleksi. Fixture/query/wait dan target edit diperbaiki, lalu kasus-kasus tersebut lulus pada regresi.
- Regresi `/private/tmp/c67-v5-regression.xcresult` menemukan QR encoding tidak deterministik: JSONEncoder dapat menyusun key berbeda pada pemanggilan berikutnya. Encoder kini menggunakan `.sortedKeys`; tes round-trip memeriksa 20 encoding berulang dan decoding gambar QR asli. Tes gambar QR dan encoding berulang lulus pada run final; tidak ada failure ditandai lulus tanpa tes ulang.

## Belum dibuktikan

- Publish/fetch child record pada share CloudKit lama maupun baru, propagation ke dua atau lebih akun nyata, ACL read-only/tanpa undangan, cleanup bersamaan dengan operasi cloud, skala 20 perangkat dan latensi/baterai lapangan.
- Live MKLocalSearch pada jaringan/region nyata; tes picker menggunakan pemilihan titik native, tanpa mengklaim kualitas hasil pencarian.
- Penyimpanan event ke Calendar akun nyata, penolakan izin/kegagalan editor pada iPhone, identitas kalender tujuan atau keberadaan event setelah keluar editor. Unit mapping bukan bukti saved, UI cancel bukan bukti saved.
- VoiceOver lengkap, iPad, seluruh ukuran Dynamic Type, App Review, TestFlight/Production.

Sinkronisasi berjalan saat foreground; tidak ada push atau jaminan realtime. Status cloud bukan acknowledgement peserta membaca. App tidak meminta full Calendar access, tidak mengimpor Calendar, dan tidak memperbarui/menghapus ekspor lama otomatis. Pemeriksaan tetap eksplisit oleh TL. Batas GPS dari [0.4](VERIFICATION_V4.md) dan [0.4.1](VERIFICATION_V41.md) tetap berlaku.
