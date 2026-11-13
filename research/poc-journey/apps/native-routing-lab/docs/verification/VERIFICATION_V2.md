# Verifikasi POC v2 — tampilan dan demo

15 Oktober 2026 · Asia/Jakarta · iOS 18 minimum, Xcode 27, Simulator iPhone 18 Pro / iOS 27.

## Scope dan bukti

Pengguna memilih **Utamakan tampilan dan demo**. Iterasi ini mengganti presentasi layar, menyediakan skenario demo dan filter daftar, serta memandu setup peserta. Tracking nyata tetap satu peserta ke satu TL. Kode CloudLocationChannel, LocationService, format RunState/SavedRun dan entitlement CloudKit tidak berubah.

| Pemeriksaan | Hasil |
|---|---|
| Build Simulator + launch | Berhasil melalui XcodeBuildMCP |
| Unit/integration | **27 tes lulus, 0 gagal** |
| UI Simulator | **6 tes lulus, 0 gagal** |
| Total run final | **33 lulus, 0 gagal, 0 skipped**; [ringkasan mesin](test-summary-v2.json) |
| Build Debug iPhone signed | Berhasil, `0.2` build `2` |
| Entitlement binary signed | CloudKit; container `iCloud.giovanchristoffel.poc-c67`; Development |
| Inspeksi visual | Dashboard dan setup peserta diperiksa dari screenshot Simulator |
| Ukuran teks | Tes alur manual pada accessibility3 lulus; bukan audit VoiceOver lengkap |

Screenshot berisi fixture simulasi: [dashboard](../../../../docs/missing-evidence.md#missing-ff73377fd1ab), [setup peserta](../../../../docs/missing-evidence.md#missing-4d649a8eeac1). Tampilan hasil uji dan preview bukan pengukuran GPS fisik.

## Perilaku baru yang diuji

- Skenario regroup menyimpan E=3, V=2, U=1, X=1, O=1. Reviewed mempunyai empat event pemeriksaan eksplisit dan tetap memerlukan penutupan TL.
- Data stale tetap sintetis, berumur tiga menit, dan tidak mengubah P01 menjadi diperiksa.
- Gagal menyimpan skenario tidak mengganti run/riwayat/cache sebelumnya; share nyata yang masih dibind melarang pemuatan skenario.
- Filter peserta dan pencarian nama sama tidak mengubah ringkasan global.
- UI mengharuskan konfirmasi sebelum memuat skenario. Batal mempertahankan hitungan/run sebelumnya.
- Form tindak lanjut menyimpan catatan tanpa otomatis menutup kasus ketika peserta diperiksa.
- Pemeriksaan manual, penutupan dengan catatan, reset sesi berikutnya dan stale label tetap berjalan setelah perubahan tata letak.
- Setup Peserta tidak mengaktifkan Start sebelum consent/pairing terpenuhi; demo tidak memulai GPS.

Seluruh 20 tes inti versi sebelumnya juga dijalankan, termasuk rollback/reload SwiftData, idempotensi, expected/verified/follow-up yang independen, closure guards, sequence/epoch/run, expiry dan consent upload.

## Reproduksi

```sh
xcodebuild -project poc-c67.xcodeproj -scheme poc-c67 \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath /tmp/c67-demo-derived \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

Pilih Simulator yang tersedia pada Mac Anda. Tes UI menggunakan store in-memory. Launch argument `--demo-preview` juga menggunakan store in-memory, agar screenshot tidak mengganti run lokal yang tersimpan. Scheme Run normal tidak memuat argumen demo/tes.

Result bundle final di Mac ini: `/private/tmp/c67-demo-v2-tests-final.xcresult`. Log tes: `/private/tmp/c67-demo-v2-tests-final.log`. Log build signed: `/private/tmp/c67-demo-v2-signed-final.log`. Folder sementara dapat dibersihkan OS; JSON ringkasan dan screenshot disimpan di repository.

Alat `test_sim` pertama timeout setelah 300 detik saat run UI yang belum diperbaiki. Hasil final di atas berasal dari xcodebuild langsung setelah dialog konfirmasi dan navigasi tes diperbaiki. Tidak ada kegagalan/skipped yang diperlakukan sebagai lulus.

## Batas kesimpulan

Pengguna melaporkan POC dua iPhone sebelumnya berhasil; agen tidak mengulang pengukuran GPS antar-akun pada iterasi UI ini. Setelah update, ulangi pairing, Start/Stop, layar terkunci dan offline pada dua iPhone sesuai [panduan demo/uji](../DEMO_GUIDE.md).

Build signed dan tes Simulator tidak membuktikan runtime CloudKit multi-akun, baterai, akurasi kabin bus atau manfaat bagi TL. Pelacakan beberapa peserta sekaligus, multi-TL, serta distribusi TestFlight/App Store tidak ditambahkan pada iterasi ini. Format persistence dipertahankan; update tidak mereset run otomatis. Memuat demo atau membuat run baru tetap tindakan penggantian data lokal yang dikonfirmasi pengguna.
