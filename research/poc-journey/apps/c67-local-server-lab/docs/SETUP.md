# Menjalankan, menghubungkan, dan memulihkan lab

## Mac dan replay

Jalankan perintah README dari folder lab. `swift build` dan `swift test` default Debug; A menggunakan `@testable` terhadap package acuan. Dependency remote dikunci di Package.resolved: Vapor 4.122.3, ONNX Runtime 1.24.2, swift-transformers 1.4.0 dan transitif yang diselesaikan SwiftPM. Build/replay bukan layanan produksi atau klaim Linux-ready.

`python3 scripts/start.py` membuat satu server loopback. File `.local/client-config.json` dan `.local/process.json` memiliki mode 0600; token tidak dicetak. Default data SQLite `.local/jobs.sqlite`; passage vectors `.local/embeddings`; log provider terpisah per job. Hindari menjalankan dua server pada database yang sama.

Untuk iPhone, pilih IP LAN Mac secara eksplisit:

```sh
python3 scripts/start.py --host <IP-LAN-Mac>
```

Gunakan Wi-Fi yang saling dapat menghubungkan kedua device, dan izinkan Jaringan Lokal pada iPhone. Tidak ada tunnel publik. Koneksi HTTP hanya untuk harness pengembangan; Info.plist harness mengizinkan HTTP. Pengaturan ini tidak dimasukkan ke aplikasi produksi.

## Harness iOS

Generate `xcodegen generate --spec ClientHarness/project.yml`, lalu build scheme C67LocalServerHarness. Helper simulator membaca token privat dan memberikan environment tanpa menaruhnya pada command line. Setelah terpasang:

```sh
python3 scripts/simulator-run.py --simulator <ID> --run <ID-baru>
```

Mode tanpa `--lab-auto` tersedia lewat `--no-auto`; gunakan tombol Run dan Cancel. Relaunch normal memuat observasi run terakhir yang telah disimpan. Result per kasus serta observations/status berada di Documents/C67LocalServerLab/<run>. Rerun dengan ID yang sudah mempunyai status mendapat suffix attempt; bukti sebelumnya dipertahankan.

**Bundle ID harness sama dengan PoC asli** untuk memakai signing yang sudah tersedia. Sebelum pemasangan fisik, backup Library/Application Support/C67TripIntegration-v1, hash per file, dan pastikan binary C67TripIntegration.app asli tersedia. `scripts/device-run.py` menolak menjalankan tanpa direktori backup. Jangan uninstall. Setelah pengujian, instal kembali binary asli, buka tanpa argumen, lalu bandingkan hash data sebelum/sesudah. Lihat `scripts/restore-device.py` untuk langkah yang dapat direproduksi.

## REST aktual

Saat implementasi, kredensial ini belum tersedia; tidak ada panggilan provider live yang dilakukan. `.env.example` hanya memuat nama field:

- APPLE_TEAM_ID
- MAPS_KEY_ID dan MAPS_KEY_PATH (file private .p8 di Mac)
- WEATHER_KEY_ID, WEATHER_KEY_PATH dan WEATHER_SERVICE_ID

Aktifkan/configure Maps dan WeatherKit melalui akun pengembang yang berwenang. Entitlement WeatherKit native bukan kredensial REST. Jangan mengirim private key/token melalui chat atau memasukkannya ke client/Git. File `.env*`, `.p8`, dan konfigurasi token diabaikan Git.

`planner-bench preflight` memeriksa kehadiran konfigurasi tanpa menampilkan nilainya. Bila siap, `planner-bench probe` melakukan satu search, satu ETA dan fetch cuaca+atribusi; budget probe delapan call dan satu ETA cell. Simpan kegagalannya; jangan melakukan probe loop. Probe dan server harus menghormati sisa quota akun yang sebenarnya, bukan menebaknya dari kuota umum.

Server REST: `python3 scripts/start.py --mode rest`. Tidak ada fallback native/mocked provider. JWT ES256 Maps ditukar menjadi access token dan diperbarui mendekati expiry; 401 menginvalidasi token untuk operasi berikutnya. Weather JWT memakai Team/Service ID. ETA REST maks sepuluh tujuan per asal/moda/departure persis sama. B/C berbagi pacing ETA 1,2 detik antarpanggilan; concurrency 1. 429 berhenti, Retry-After membatasi panggilan berikutnya. Tidak ada retry tanpa batas.

Cache respons provider lintas-job nonaktif. Izin/expiry provider harus diperiksa sebelum kebijakan tersebut diubah. Metadata atribusi cuaca dibawa dalam result; pemetaan REST diuji dengan stub, belum dengan kredensial aktual.

Siapkan manifest live dengan `scripts/prepare-live.py --replay artifacts/replay-final --output <manifest> --confirm-provider-allowance` setelah quota benar-benar dikonfirmasi dan fakta sumber yang kedaluwarsa diverifikasi ulang. Jangan memajukan checkedAt saja. Script membekukan subset sesuai budget dan menolak launch jika gate belum dipenuhi. `device-run.py --live-manifest <manifest>` memerlukan status prepared dan manifest berumur <15 menit. Live tidak dijalankan otomatis oleh perintah replay.

## Menghentikan dan memulihkan

`python3 scripts/stop.py` menghentikan PID server yang cocok dan menghapus token run; tidak menghapus SQLite, vektor atau bukti. Script restore memulihkan aplikasi asli tanpa menghapus container. Simpan semua percobaan yang gagal/terputus. Tidak ada commit, push atau deploy otomatis.

## Detail konfigurasi environment

Lab tidak otomatis membaca file `.env.local`. Setelah mengisinya, jalankan dari folder lab:

```sh
set -a
source .env.local
set +a
.build/debug/planner-bench preflight
```

Private `.p8` cukup disimpan di file pada Mac; tidak perlu dipasang ke Keychain atau client iPhone. `MAPS_KEY_PATH` dan `WEATHER_KEY_PATH` menunjuk file tersebut. Untuk shell config yang berada di folder lab, nilai path dapat memakai `"$PWD/.local/keys/maps.p8"` dan `"$PWD/.local/keys/weather.p8"`. Kedua file tidak disertakan di repository atau app bundle.

JWT developer Maps sekarang menyertakan `scope: server_api`; WeatherKit memakai header `id=TeamID.ServiceID` dan claim `sub=ServiceID`. Tes signing lokal lulus, sementara keberhasilan akses aktual tetap menunggu probe memakai key asli.
