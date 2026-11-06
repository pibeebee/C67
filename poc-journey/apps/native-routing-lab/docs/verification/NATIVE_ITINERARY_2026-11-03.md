# Verifikasi perencana itinerary native

Tanggal: 3 November 2026 (WIB).

## Hasil

- Build **generic iOS unsigned berhasil** memakai Xcode 27.2 (27B52). Minimum deployment target proyek tetap iOS 18.0.
- `swift-format lint --strict` untuk keenam file baru: lolos.
- `plutil -lint` untuk project dan entitlements: lolos.
- `git diff --check`: lolos.
- Nilai entitlements iCloud/CloudKit sebelumnya dibandingkan dengan salinan sebelum integrasi: tidak berubah. WeatherKit ditambahkan sebagai capability lokal baru.
- Hash source final dibandingkan source saat build terakhir dimulai: sama.
- Compiler hanya memberi warning metadata App Intents yang dilewati karena target tidak memakai framework tersebut; tidak ada error Swift.

## Perintah build

```sh
xcodebuild -project poc-c67.xcodeproj -scheme poc-c67 \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/poc-c67-native-itinerary-build \
  CODE_SIGNING_ALLOWED=NO build
```

Build tidak menjalankan aplikasi atau Simulator. Tidak ada tes iOS yang dijalankan, sesuai batasan sesi sebelumnya. Log lokal akhir berada di `/private/tmp/c67-native-itinerary-20261103/build-ios-verified.log`; hash dan daftar source ada di [metadata verifikasi](native-itinerary-source-hashes.json).

## Belum tervalidasi runtime

- Pemilihan lokasi dan interaksi UI pada perangkat/Simulator.
- Ketersediaan dan ketepatan ETA MapKit untuk semua ruas Jepang pada 1 Desember 2026.
- Autentikasi WeatherKit, konfigurasi App ID/portal, provisioning, dan tampilan atribusi dari layanan nyata.
- Kelayakan perjalanan serta kualitas urutan pada data layanan nyata.

Transit diimplementasikan sebagai ETA, tanpa mengklaim detail jalur/jadwal kereta. Jam operasional diisi manual atau ditandai belum diketahui. Prakiraan 1 Desember masih di luar horizon WeatherKit pada tanggal pemeriksaan; tidak dibuat data pengganti.

## Cakupan perubahan

Fitur baru berada di `poc-c67/Features/NativePlanner/`. Integrasi menambahkan tab Rencana/Jejak, launch argument `--native-itinerary`, entitlement dan capability WeatherKit, serta panduan. Jalur `--legacy-poc` dan argumen diary lama dipertahankan. Tidak mereset data lokal, tidak mengubah container/akun cloud, dan tidak mengubah repo aplikasi C67 utama.

Salinan file integrasi sebelum perubahan berada di `/private/tmp/c67-native-itinerary-20261103/originals/`. Proyek sudah memiliki perubahan lokal sebelum pekerjaan ini; perubahan tersebut dipertahankan.
