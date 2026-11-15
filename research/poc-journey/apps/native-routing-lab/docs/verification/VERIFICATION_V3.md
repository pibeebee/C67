# Verifikasi POC v3 — QR pairing dan roster dinamis

15 Oktober 2026 · Asia/Jakarta · Xcode 27 · Simulator iPhone 18 Pro / iOS 27 · minimum iOS 18 · versi 0.3 build 3.

## Hasil

| Pemeriksaan | Bukti/status |
|---|---|
| Build dan launch Simulator | Berhasil melalui XcodeBuildMCP, tanpa compiler warning pada build final |
| Unit/integration | **40 tes unik lulus**: 20 DomainTests + 7 DemoTests + 13 QRPairingTests |
| UI | **9 tes unik lulus**: 6 alur lama + 3 alur QR |
| Total hasil terakhir per kasus | **49 lulus, 0 gagal, 0 skipped**; [ringkasan dan provenance](test-summary-v3.json) |
| Build iPhone Debug signed | Berhasil menggunakan automatic signing proyek yang sama |
| Signature | `codesign --verify --deep --strict --verbose=2` berhasil; valid on disk dan memenuhi Designated Requirement |
| Konfigurasi binary | Container CloudKit lama, Development, versi 0.3 build 3, camera/local network descriptions dan `_c67-pair._tcp`; [ringkasan](signed-config-v3.json) |
| Inspeksi visual | [Konfirmasi peserta](../../../../docs/missing-evidence.md#missing-d6441c33271b) dan [entry Peserta](../../../../docs/missing-evidence.md#missing-a74d2580e653) diperiksa dari screenshot XCTest |
| Pairing fisik dan CloudKit antar-akun v3 | **Belum diuji oleh agen**. Ikuti [panduan QR](../QR_PAIRING_GUIDE.md) pada dua atau lebih iPhone. |

Angka 49 adalah hasil terakhir per tes unik, bukan klaim satu eksekusi penuh terakhir tanpa kegagalan. Full run `/private/tmp/c67-qr-v3-final.xcresult` menghasilkan 48 lulus dan satu kegagalan interaksi XCTest pada toggle consent. Target tap diperbaiki dari tengah frame label multiline ke kontrol switch di ujung kanan; kode aplikasi tidak berubah. Focused rerun `/private/tmp/c67-qr-v3-consent-final.xcresult` lulus dan membuktikan tombol Join disabled sebelum consent serta enabled sesudahnya. Ringkasan JSON mempertahankan provenance kedua run. Tidak ada test failure yang dilewati atau ditandai sebagai lulus tanpa rerun.

Run lengkap sebelumnya, sebelum koreksi akhir pada scope diagnostik dan presentasi per peserta, lulus 48/48. Run unit awal sempat gagal karena Vision tidak dapat membuat inference context di Simulator; pengujian pembacaan gambar QR memakai decoder Core Image dan berhasil. Tes UI awal menemukan ringkasan undangan tidak terlihat akibat form manual/keyboard; input kini dibatasi dan ditutup setelah decode, lalu tes lulus.

## Cakupan tes

- Gambar QR yang dihasilkan Core Image dapat di-decode kembali dengan payload identik. Ini bukan uji kamera fisik/VisionKit.
- QR asing/rusak/terlalu panjang, versi tidak didukung, waktu expired dan lifetime terlalu panjang ditolak.
- Welcome harus cocok dengan public key pada QR, run, invite, akun dan challenge. Receipt tidak dapat dipakai untuk participant/challenge lain.
- Dua orang bernama sama mempunyai identitas dan referensi terpisah, tetap belum diperiksa setelah register.
- Rejoin akun aktif tidak menggandakan anggota dan tidak menghapus pemeriksaan. Run salah, ID collision, sesi ditutup dan kapasitas lebih dari 20 ditolak.
- Snapshot v1/v2 tanpa field QR tetap terbaca. Roster QR dan dua referensi berbeda dapat disimpan dan dimuat ulang.
- Kegagalan simpan tidak mengekspos sebagian roster/reference/events. Run dengan owner aktif tidak dapat diganti perjalanan QR.
- UI: pembuatan perjalanan meminta konfirmasi; batal mempertahankan form; perjalanan baru roster kosong. QR tidak valid tidak menyediakan Join. Undangan valid menampilkan perjalanan/TL dan mewajibkan consent.
- Seluruh tes inti lama dan UI pemeriksaan/simulasi/tindak lanjut/closure/reset/ukuran teks aksesibilitas tetap dijalankan.

## Pemeriksaan implementasi

CloudKit share tetap privat; lookup akun TL dilakukan programatis, TL read-only dan peserta lain tidak diundang ke share tersebut. Bootstrap lokal memakai encryption required, public-key signature dan challenge. Pemilik/container/run/participant undangan diperiksa. Batas ini diinspeksi pada kode dan API dikompilasi; penerapan ACL server tetap harus diuji dengan akun nyata.

Stop mematikan sensor lokal lebih dahulu dan menunggu bootstrap writes sebelum menghapus zone. Cache/polling terpisah per participant; diagnostik hanya mengukur peserta lokasi yang dipilih dan reset ketika pilihan berubah. Ini inspeksi implementasi, bukan uji race jaringan nyata atau audit keamanan menyeluruh.

LocationService, SessionStore dan file entitlement sumber tidak berubah dari v2. Format snapshot diperluas dengan field optional; model SwiftData tidak diubah. Tidak ada server baru, deployment, upload TestFlight, atau perubahan environment Production.

## Reproduksi otomatis

```sh
xcodebuild -project poc-c67.xcodeproj -scheme poc-c67 \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath /tmp/c67-qr-derived \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

Nama Simulator sesuaikan dengan yang tersedia. Tes menggunakan store in-memory; tidak mengganti run tersimpan pengguna. Build signed final tersimpan sementara di `/private/tmp/c67-qr-v3-device`; log `/private/tmp/c67-qr-v3-signed-final.log`. Result bundles disebut di atas. Folder tmp dapat dibersihkan OS; JSON dan screenshot disimpan di proyek.

## Uji perangkat yang masih diperlukan

| Percobaan | Ekspektasi yang perlu dibuktikan | Status |
|---|---|---|
| 1 TL + 1 peserta, akun berbeda | Scan → consent → private share accepted → sampel pertama tanpa copy/paste | Belum dieksekusi |
| Peserta kedua dengan nama sama | Dua anggota/reference/lokasi berbeda; V tetap 0 | Belum dieksekusi |
| Kamera/Jaringan Lokal/lokasi ditolak | Pesan terlihat, tidak mengirim GPS tanpa izin, pemulihan melalui Settings/cleanup | Belum dieksekusi |
| Jauh dari TL setelah pairing | Posisi tetap diterima melalui internet/CloudKit | Belum dieksekusi |
| Stop di tengah pairing dan saat offline | Sensor/pengiriman lokal berhenti; cleanup cloud dikonfirmasi setelah online | Belum dieksekusi |
| QR expired atau TL background | Tidak menerima anggota baru dari sesi lama; QR baru dapat digunakan | Belum dieksekusi |
| Relaunch kedua perangkat | Roster/reference tetap, GPS tidak auto-resume; consent baru untuk melanjutkan | Belum dieksekusi |
| Akun ketiga/tulis sebagai TL | Tidak ada akses tanpa invite; write TL ditolak server | Belum dieksekusi |
| Layar terkunci, jaringan buruk, baterai, banyak perangkat | Ukur umur sampel dan kegagalan, jangan asumsikan interval tetap | Belum dieksekusi |

Pengguna melaporkan POC dua iPhone sebelumnya berhasil; laporan tersebut tidak menjadi bukti pairing QR baru. Belum ada uji skala 20 perangkat, penilaian manfaat bagi TL, audit VoiceOver lengkap atau keputusan App Review.
