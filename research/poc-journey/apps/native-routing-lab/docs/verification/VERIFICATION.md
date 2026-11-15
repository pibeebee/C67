# Verifikasi POC C67

15 Oktober 2026 · Asia/Jakarta · source di `<LOCAL_HOME>/Programming/ios/poc-c67`.

## Hasil yang sudah diperoleh

| Pemeriksaan | Hasil dan batas |
|---|---|
| Build Debug Simulator | Berhasil pada Xcode 27 / iOS Simulator 27 |
| Build iPhone tanpa signing | Berhasil; jalur compile perangkat fisik tersedia |
| Build Debug iPhone signed | Berhasil dengan automatic provisioning dan sertifikat pengembangan yang tersedia di Mac ini |
| Binary signed | `CloudKit`, container `iCloud.giovanchristoffel.poc-c67`, environment `Development` terverifikasi melalui codesign |
| Unit/integration | **20 tes lulus, 0 gagal**; termasuk SwiftData snapshot + rollback/reload |
| UI Simulator | **3 tes lulus, 0 gagal**; alur manual/simulasi, penutupan/reset sesi, ukuran teks accessibility3 |
| Source/config di folder asli | Build signed dan seluruh tes terakhir dijalankan dari folder proyek asli, bukan hanya salinan sementara |

Hambatan awal automatic provisioning adalah pembaruan Program License Agreement. Pengguna menyatakan telah meninjau dan menerima pembaruan; percobaan ulang berhasil mendapatkan profil App ID POC. Tidak ada password/private key yang disimpan dalam repository.

Environment dibuat eksplisit: Debug = Development; Release = Production. Verifikasi binary signed terakhir memastikan Debug memakai Development. Build Release/Production dan deployment schema Production **belum dilakukan**; gunakan scheme Run Debug untuk POC ini.

## Cakupan tes otomatis

Unit/integration: identitas bernama sama, verifikasi idempotent, alasan pembatalan, keikutsertaan dan pemeriksaan ulang, satu kasus follow-up aktif, kasus peserta tidak ikut, aturan closure normal/exception/all-excluded, isolasi sesi berikutnya, umur lokasi dari measuredAt, clock skew/akurasi invalid, sequence/epoch/run/duplikat, consent/expiry/retry guard, proximity uncertainty, rollback state+event, reload committed state, pemisahan simulasi, Start tanpa consent, dan proteksi reset saat share masih tersimpan.

UI: sampel simulasi tidak memverifikasi peserta; tombol manual mengubah V; sampel lama berlabel kedaluwarsa; penutupan dengan catatan tidak memalsukan unresolved; sesi berikutnya reset; pemeriksaan manual dapat dioperasikan pada ukuran teks accessibility3. Ini bukan audit penuh VoiceOver/HIG.

## Status acceptance POC

Semua 15 AC rancangan tetap membutuhkan bukti sesuai cakupannya; tes komponen tidak otomatis meluluskan AC perangkat.

| AC | Bukti saat ini | Sisa uji |
|---|---|---|
| P01 | Kanal CloudKit diimplementasikan, compile/sign berhasil | Dua iPhone/akun, delivery dan gate H1 |
| P02 | Private/read-only sharing, binding guard, write probe diimplementasikan | Enforcement server, akun ketiga, mismatch nyata |
| P03 | Consent guard diuji unit; izin ditangani dalam kode | Deny/revoke/reduced pada perangkat |
| P04 | Background session/configuration compile | Uji locked/background tanpa debugger, gate H2 |
| P05 | Freshness/duplikat diuji unit; stale label diuji UI | Cache/fetch jaringan nyata dan resume |
| P06 | Invalid/sequence/run/epoch/clock/simulasi diuji unit | Payload/network/lifecycle nyata |
| P07 | Stop/expiry/cancellation/cleanup diimplementasikan | In-flight, expiry dan revocation online/offline nyata |
| P08 | Pemeriksaan lokal diuji; kanal tidak menjadi syarat lokal | Airplane mode/reconnect dua perangkat |
| P09 | GPS/simulasi tidak mengubah V; follow-up independen diuji | Uji TL dan peserta tanpa aplikasi |
| P10 | Hitungan, nama sama, idempotensi, pembatalan diuji | Usability pada roster lebih besar |
| P11 | Keikutsertaan/follow-up diuji unit | Prosedur TL di lapangan |
| P12 | Closure normal/exception diuji unit dan UI | Kesesuaian prosedur TL |
| P13 | Reset/riwayat sesi diuji unit dan UI | Alur nyata dengan lokasi yang tetap tersedia |
| P14 | Failure/rollback/reload/retry diuji pada container SwiftData in-memory | Force-quit/relaunch on-disk pada perangkat; disk failure sesungguhnya |
| P15 | Alur manual ukuran teks accessibility3 diuji UI | VoiceOver dan semua surface secara manual |

## Bukti dan reproduksi

Ringkasan mesin disimpan di [test-summary.json](test-summary.json). Result bundle lengkap berada di `/private/tmp/c67-final.xcresult` pada Mac ini; tidak dimasukkan ke Git. Log pengujian `/private/tmp/c67-final-tests.log`; log build signed terakhir `/private/tmp/c67-final-entitlements.log`. Folder sementara dapat dibersihkan oleh OS; ringkasan repository adalah bukti ringkas yang dipertahankan.

```sh
xcodebuild -project poc-c67.xcodeproj -scheme poc-c67 \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath /tmp/c67-derived CODE_SIGNING_ALLOWED=NO test
```

Sesuaikan nama Simulator pada Mac lain. Panduan uji mandiri perangkat berada di [README](../../README.md).

## Kesimpulan terbatas

Implementasi POC siap dicoba, lolos build dan tes otomatis di atas, serta dapat dibuat sebagai binary iPhone signed dengan entitlement CloudKit yang sesuai. **H1/H2 belum tervalidasi**: belum ada pengukuran pengiriman antar-akun, GPS lapangan/background, baterai atau skala 40 perangkat. Aplikasi belum diunggah ke TestFlight/App Store.
