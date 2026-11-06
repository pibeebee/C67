# Verifikasi PoC Travel Diary — 20 Oktober 2026

## Hasil yang sudah diamati

- Xcode 27.1 (27A9275), deployment target iOS 18 tetap dipertahankan.
- Build Debug iOS Simulator berhasil, termasuk build ulang dari lokasi proyek asli setelah instalasi.
- Build Debug target iPhone (`iphoneos`, generic iOS) juga berhasil dengan `CODE_SIGNING_ALLOWED=NO`. Ini bukti kompilasi, bukan instalasi atau uji pada iPhone fisik.
- **13 unit test TravelDiaryTests lulus**, termasuk lokasi di dalam/luar/batas, akurasi rendah, Lokasi Tepat tidak aktif, sampel invalid/lama/masa depan, larangan memakai fix sebelum unggah, keluar radius sebelum unggah, persistence/reload, kegagalan tulis, perlindungan file rusak, dan identitas pin yang berubah.
- **3 UI test TravelDiaryFlowTests lulus** pada iPhone 17e Simulator / iOS 27.0: outside+uncertain terkunci; demo inside sampai Shared Postcard; serta callback Core Location dengan lokasi simulator sampai unggahan lokal. Test Core Location tidak memakai provider demo, tetapi GPS tetap simulasi dan izin When-In-Use disiapkan melalui simctl.
- Screenshot map, arrival, outside/uncertain, dan kartu hasil diperiksa secara visual. Gambar contoh adalah ilustrasi/fixture, bukan foto dari peserta uji.
- Pemeriksaan kecil keterbacaan ilustrasi pin mini dilakukan setelah penyiapan tes; tidak mengubah alur validasi.

Hasil lengkap lokal: `/private/tmp/c6-travel-diary-poc-20261020/TravelDiaryVerified.xcresult`.
Ringkasan test dan screenshot: folder `evidence/` di sebelah dokumen ini.

## Batas bukti

Belum ada uji GPS pada iPhone fisik, pengujian kamera fisik, interaksi memilih foto iCloud melalui picker, uji lapangan di batas radius, uji izin ditolak melalui dialog sistem, atau uji nilai emosional bersama pengguna. Belum ada unggahan server atau pertukaran foto lintas perangkat. Unit test lokasi dan GPS simulator bukan bukti kehadiran fisik atau ketahanan terhadap spoofing. Suite UI lama tidak dijalankan karena entry screen sengaja berubah; jalurnya tetap tersedia lewat `--legacy-poc`.

## Keutuhan kode sebelumnya

Implementasi ContentView yang ditemukan sebelum pekerjaan ini disalin ke LegacyPOCView. Pemeriksaan teks membuktikan isi identik setelah nama tipe LegacyPOCView dikembalikan menjadi ContentView. Instalasi memeriksa hash semua file yang telah ada; hanya ContentView dan teks izin kamera/lokasi pada project.pbxproj yang boleh berubah. Backup dua file tersebut dibuat sebelum penggantian. Perubahan lokal yang sebelumnya sudah ada dipertahankan.
