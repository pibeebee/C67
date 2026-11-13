# Verifikasi POC 0.4 — peta interaktif & lokasi TL

15 Oktober 2026 · Asia/Jakarta · versi 0.4 build 5 · iOS 18+ · Xcode 27 / Simulator iPhone 18 Pro iOS 27.

## Scope & acceptance

Permintaan pengguna: semua peserta dengan lokasi tersedia ditampilkan sekaligus pada peta interaktif, dan peserta dapat melihat posisi TL. Root cause peta lama: satu `sample` terpilih dan `interactionModes: []` pada preview List. Kini peta layar penuh merender cache per anggota, gesture `.all`, pilihan pin, kamera yang bisa difokuskan dan daftar lokasi/tanpa lokasi.

Kanal balik menambah share privat TL per akun peserta saat QR, dengan akses read-only. Persiapan share bukan consent untuk GPS TL: Start TL membutuhkan consent/durasi sendiri. Stop mematikan sensor/upload lokal, pause cloud menghapus payload tetapi mempertahankan undangan. Referensi cleanup disimpan sebelum penulisan cloud; dua arah memakai cache dan service sensor terpisah. Field persistence baru optional; snapshot lama tetap terbaca. QR kini versi 2 agar client lama tidak keliru menerima handshake baru.

## Hasil

| Check | Status & batas |
|---|---|
| Unit/integration | **51 tes unik lulus**: Domain 20, Demo 7, QR 13, GroupMap 11 |
| UI | **16 tes unik lulus**: 12 alur sebelumnya + 4 peta/consent TL |
| Hasil terbaru per kasus | **67 passed, 0 failed, 0 skipped**, gabungan regresi dan rerun; [ringkasan mesin](test-summary-v4.json) |
| Build Simulator | Passed; API MapKit, CloudKit dan Core Location terkompilasi |
| Build Debug iPhone signed | Passed, 0.4 build 5; CloudKit Development/container lama |
| Signature | Passed `codesign --verify --deep --strict --verbose=2` pada app signed |
| Inspeksi visual | Passed pada screenshot [seluruh pin demo](../../../../docs/missing-evidence.md#missing-b24c034ff149) dan [peta peserta/TL](../../../../docs/missing-evidence.md#missing-fcc609e72c1a) |
| Device/multi-account | **Not run**; perlu dua atau lebih iPhone setelah pairing QR terbaru |
| App Review/VoiceOver/iPad/skala 20 | **Not run**; tidak ada klaim kelulusan |

Full run `/private/tmp/c67-map-v4-final.log` menjalankan 51 unit/integration dan 15 UI kasus. Satu kasus UI simulasi/pemeriksaan gagal pada dua assertion karena ringkasan di luar area render List; helper scroll diperbaiki untuk menuju ringkasan melalui CollectionView. Semua kasus lain menyelesaikan eksekusi. Xcode tertahan pada pengumpulan diagnostik sesudah suite selesai dan proses tersebut dihentikan; result bundle run ini tidak terfinalisasi. Ringkasan JSON memakai baris completion XCTest dari log, bukan menganggap bundle tersebut valid atau test run sukses.

Rerun `/private/tmp/c67-map-v4-followup.xcresult` mengulang seluruh 51 unit/integration serta kasus UI yang gagal dan kasus baru ketuk pin langsung: **53/53 passed**, `TEST SUCCEEDED`, bundle terfinalisasi. Hasil unik terbaru seluruh kasus menjadi 67 passed. Tidak ada failure yang ditandai lulus tanpa rerun. Perubahan final sebelum rerun adalah reset flag cleanup TL dan helper tes; Info.plist sesudahnya hanya memperjelas pesan izin lokasi dua arah dan dibuild ulang. Kegagalan build awal missing import CloudKit diperbaiki sebelum semua run ini.

## Yang dibuktikan tes

- Demo TL merender empat peserta berbeda plus TL tanpa mengubah hitungan/verifikasi. Nama sama tetap ID berbeda.
- Peta peserta memuat hanya TL dan dirinya, bukan cache peserta lain.
- Lokasi real yang belum tersedia tidak ditempatkan pada pin meeting point. Posisi stale tetap posisi terakhir berlabel; lease expired, run salah, koordinat invalid atau timestamp terlalu jauh di masa depan tidak dibuatkan pin.
- TL paused/epoch berubah tidak memakai ulang sampel lama. Fetch record yang sama tidak meremajakan umur, dan sequence lama ditolak.
- TL tidak dapat mulai tanpa consent; init tidak menyalakan sensor. Referensi TL tersimpan terpisah dari binding lokasi peserta dan mencegah reset run sampai cleanup.
- Snapshot tanpa field leader tetap decode. URL kanal TL dan snapshot meeting point dilindungi signature; manipulasi ditolak. QR versi 1 ditolak secara eksplisit.
- UI: pinch/geser, ganti map style dan fit-all dapat dijalankan; pilih daftar dan ketuk pin langsung membuka nama yang benar. Peta peserta tidak menyediakan peserta lain. Start TL disabled tanpa consent/koneksi yang diperlukan.
- Pemeriksaan manual, closure/reset, follow-up, consent QR dan navigasi Lab tetap diuji. Ukuran teks accessibility3 alur manual lama lulus; bukan audit peta pada semua ukuran/assistive technology.

## Pengujian fisik yang masih diperlukan

| Skenario | Ekspektasi |
|---|---|
| TL + 2 peserta, tiga akun berbeda | Dua kanal privat per peserta diterima; TL melihat kedua posisi, peserta hanya melihat TL/diri sendiri |
| Start TL | Izin Core Location tampil dengan deskripsi dua arah, lokasi pertama sampai ke kedua peserta |
| TL lock screen | Ukur umur data peserta selama TL background; jangan mengasumsikan interval tetap |
| TL stop saat upload | Sensor lokal OFF langsung; payload hilang setelah pause dikonfirmasi; peserta melihat status berhenti setelah fetch |
| Offline/retry/expiry | Sampel menua, lease expiry menyembunyikan pin; stop cloud belum diklaim berhasil ketika offline |
| Stop di tengah bootstrap atau start | Tidak ada GPS tanpa consent; ref parsial tetap bisa di-cleanup, tidak bisa reset run ketika ref masih ada |
| Keluar satu peserta | Akses akun itu ke TL dicabut; kanal peserta lain tidak terpengaruh |
| Relaunch | Tidak auto-resume GPS; referensi tetap, consent sesi baru diperlukan |
| Akun tidak diundang/write peserta | Akses server ditolak; lookup/ACL perlu dibuktikan dengan akun fisik |
| Beberapa posisi bertumpuk | Zoom/Daftar tetap dapat memilih ID yang benar; cluster belum diimplementasikan |

Belum ada validasi jaringan nyata untuk concurrency/race cleanup, manfaat operasional, continuous tracking setelah force-quit, baterai atau skala. TLSamples diunggah ke kanal per peserta, sehingga operasi cloud per sampel bertambah sesuai jumlah koneksi. Polling terbatas tab peran foreground. Meeting point di peserta adalah snapshot saat pairing, belum live sync setelah TL mengubah pin.

## Rujukan UI

[Apple HIG Maps](https://developer.apple.com/design/human-interface-guidelines/maps), diperiksa 15 Oktober 2026: peta interaktif, pilihan jelas, kontrol kontras dan logo/legal tetap terlihat. Native MapKit digunakan pada iOS 18+; daftar tersedia untuk pin bertumpuk/tanpa data. Ini UX remediation terarah, bukan audit HIG global atau aturan App Review. [Panduan penggunaan/desain](../MAP_AND_LEADER_LOCATION.md).

## Reproduksi

```sh
xcodebuild -project poc-c67.xcodeproj -scheme poc-c67 \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath /tmp/c67-map-derived -parallel-testing-enabled NO \
  -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO test
```

Build signed final: `/private/tmp/c67-map-v4-signed-final.log`. Result/log sementara dapat dibersihkan OS. JSON dan screenshot disimpan di repo. Semua demo dan tes UI memakai store in-memory, bukan koordinat pengguna nyata.
