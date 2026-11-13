# Build-only checkpoint — 11 November 2026

PoC C67 Pocket Engine Lab diimplementasikan sebagai folder dan bundle terpisah. Pemeriksaan dibatasi pada generasi proyek, build/kompilasi, pembacaan deklarasi SDK, dan inspeksi statis sumber/artefak. **Tidak ada pengujian fitur atau eksekusi aplikasi/server.**

## Hasil

| Pemeriksaan | Hasil |
| --- | --- |
| `xcodegen generate` | Berhasil; proyek Xcode tersedia di `App/C67PocketEngineLab.xcodeproj` |
| `swift build --disable-sandbox` | Berhasil, exit 0; `PocketEngine` macOS dikompilasi |
| Xcode Debug, generic iOS Simulator, signing nonaktif | `BUILD SUCCEEDED`, exit 0 |
| Xcode Release, generic iOS device/arm64, signing nonaktif | `BUILD SUCCEEDED`, exit 0 |
| `python3 -m py_compile Server/server.py` | Berhasil, exit 0; hanya kompilasi bytecode Python, tidak memanggil `main()` |

Toolchain aktual: Xcode 27.2 (27B52), Swift 6.4.2. Target deployment aplikasi iOS 26.0; library macOS 26.0/iOS 26.0. Paket tanpa dependency eksternal. Build iOS menggunakan akses cache Xcode/SwiftPM yang diperlukan; percobaan awal di sandbox tidak dapat mengakses cache manifest dan CoreSimulator service. Akses build diberikan untuk melanjutkan kompilasi, tanpa boot simulator atau perintah run/test.

Masalah yang diperbaiki sebelum build akhir:

- Isolasi actor conformance delegate Core Location pada Swift 6. Manager dibuat pada main actor dan delegate menggunakan conformance preconcurrency yang sesuai.
- Konfigurasi launch screen dan dukungan orientasi dalam Info.plist yang dihasilkan XcodeGen.

Log SwiftPM masih memuat peringatan bahwa cache tingkat pengguna tidak dapat ditulis dalam sandbox; kompilasi berhasil menggunakan scratch/module cache lokal. Pemrosesan metadata App Intents pernah mencatat bahwa tidak ada dependency App Intents; PoC ini tidak mendefinisikan App Intents. Log build iOS terakhir tidak menunjukkan error atau warning compiler.

## Artefak

- Log Swift: `../.local/swift-build.log`.
- Log Simulator: `../.local/ios-build.log`.
- Log perangkat: `../.local/ios-device-build.log`.
- Bundle Simulator: `../.local/DerivedData/Build/Products/Debug-iphonesimulator/C67PocketEngineLab.app`.
- Bundle perangkat unsigned: `../.local/DeviceDerivedData/Build/Products/Release-iphoneos/C67PocketEngineLab.app`.

Artefak `.local` diabaikan Git. Proyek dapat dibuat ulang dari `App/project.yml`; Info.plist dan entitlements ikut tersedia.

## Batas validasi

Tidak menjalankan `swift test`, `xcodebuild test`, unit/UI test, simulator app launch, instalasi perangkat, HTTP health check, server Python, impor bukti, atau permintaan MapKit/WeatherKit/TomTom/Foundation Models. Tidak memeriksa API key, tidak menyalin kredensial lab lama, tidak mengonsumsi kredit provider, dan tidak membuat/mengubah database katalog server.

Build perangkat tidak menandatangani aplikasi dan tidak membuktikan entitlement WeatherKit pada akun/perangkat. Koneksi server, permission lokasi, persistensi SwiftData, indeks Spotlight, inference Foundation Models, kontrak respons TomTom, dan hasil optimizer belum diverifikasi saat runtime. Tidak ada benchmark akurasi, latency, penggunaan baterai atau memori.

Katalog seed berisi 30 identitas sumber terbuka dengan fakta operasional kosong. Kunjungan dapat menerima konfirmasi pribadi untuk tanggal perjalanan; kelengkapan fakta bersama menunggu impor hasil pengayaan yang sudah ditinjau dari jalur akuisisi terpisah.
