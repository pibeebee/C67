# Verifikasi C67 0.6 — integrasi dynamic destination routing

19 Oktober 2026 · versi 0.6 build 8 · deployment iOS 18+ · Xcode 27.1 (27A9275), SDK iOS 27.1. Runtime pengujian: iPhone 18 Pro Simulator iOS 27.0 (24A434). Project utama di <LOCAL_HOME>/Programming/software/ios/poc-c67; PoC DDS asal tetap terpisah dan tidak diubah.

## Hasil akhir

| Pemeriksaan | Hasil | Bukti dan batas |
|---|---|---|
| Regresi XCTest lengkap | **121/121 passed, 0 failed, 0 skipped** | Satu run final: 92 unit/integrasi + 29 UI. [Ringkasan mesin](test-summary-v6.json). |
| Unit/integrasi | **92 passed** | Domain 23, Demo 7, GroupMap 15, JourneyPlan 19, QR 13, GroupRouting 15. Data/transport pengganti dan store in-memory. |
| UI native | **29 passed** | Seluruh 25 kasus sebelumnya + 4 routing/Lab baru: start/stop tujuan peserta, routing TL dengan self ditolak, pembukaan/penutupan DDS, dan stage 3→5 tanpa memulai GPS. |
| Harness model DDS | **40 checks passed** | Geometri, policy, single request, latest sample, cancellation, reset, cooldown, backoff, stale completion, live-input gate. [Output](dds-model-checks-v6.txt). |
| Harness kanal DDS | **24 checks passed** | Freshness/quality, pairing, enkripsi, framing dan dua peer Bonjour/TCP nyata di Mac yang sama. Wrong key/tamper, disconnect/reconnect. [Output](dds-channel-checks-v6.txt). |
| Build Simulator | **Passed** | arm64 + x86_64, signing dimatikan. SDK 27.1 dengan deployment 18.0. |
| Build iPhone signed | **Passed** | Konfigurasi Team/container lama dipertahankan, versi produk 0.6 (8), minimum 18.0. Tidak memasang pada iPhone fisik. |
| Signature iPhone | **Passed** | codesign --verify --deep --strict. [Ringkasan build](build-summary-v6.txt). |
| MapKit pada peta terintegrasi | **Smoke test berhasil** | Rute berasal dari layanan Apple, input orang dari demo sintetis. [Screenshot run final](../../../../docs/missing-evidence.md#missing-73558b92de5a). Ini bukan pengukuran CloudKit/GPS fisik. |
| Data lama dan pemeriksaan | **Regresi passed** | Snapshot lama, QR v3, ACL model, rundown/Calendar dan count/status tetap terpisah dari lokasi/routing. Pengujian server multi-akun belum dilakukan. |

Tidak ada warning source Swift pada build akhir; tool AppIntents mencatat metadata dilewati karena framework itu tidak dipakai. Xcode test runner juga mencatat pesan tooling SDK build/debugger, tetapi bundle final berstatus TEST SUCCEEDED tanpa runtime warning pada summary. Run pendahuluan 96/96 passed sebelum seluruh Lab disatukan; angka 121 di atas berasal dari satu run final, bukan penjumlahan tes ulang.

[Hash source aplikasi yang dibuild](source-sha256-v6.txt). Result bundle lengkap sementara: /tmp/c67-routing-merge-final-tests.xcresult. Bukti ringkas disimpan dalam repo; bundle/log sementara dapat dibersihkan OS.

## Integrasi yang diuji

- Peta mengambil sumber yang sudah boleh tampil pada masing-masing peran. Peserta tidak mendapat tujuan peserta lain; self-route ditolak.
- Peta utama memerlukan sample valid dari run yang sama, umur ≤60 detik, toleransi jam masa depan 5 detik, akurasi ≤65 m, tanpa reduced accuracy. Sampel sintetis ditolak dalam run nyata.
- Lokasi stale masih dapat ditampilkan sebagai pin, tetapi tidak memulai route. Input stale membatalkan request; respons lama tidak boleh masuk.
- Pergantian asal/tujuan terbaru menghormati cooldown, epoch dan scope. Run baru, revisi titik tetap dan penghapusan kegiatan/lokasi diperiksa.
- Background membatalkan request dan menahan routing; foreground dapat melanjutkan setelah data layak/cooldown. GPS/cloud sharing tetap dikelola sesi sebelumnya.
- Peta dan semua tahap Lab berbagi engine/cooldown/backoff. Membangun state SwiftUI tidak mereset engine aktif; keluar dari tahap lama tidak membatalkan tahap baru.
- Routing tidak mengubah attendance, memulai GPS sharing, atau membuat CloudKit share baru.
- Semua tahap DDS tersedia di tab Lab. Entry diblokir selama GPS/pengiriman utama aktif agar feed eksperimen tidak dijalankan bersamaan.
- API MapKit baru memiliki fallback compiler untuk iOS 18–25; runtime OS tersebut belum dijalankan.

## Reproduksi

Project memakai scheme poc-c67. Regresi final dijalankan pada satu Simulator dengan parallel testing dinonaktifkan:

    xcodebuild test -project poc-c67.xcodeproj -scheme poc-c67 -destination 'platform=iOS Simulator,id=B774448D-6569-46E0-9833-669540D094D0' -derivedDataPath /tmp/c67-routing-merge-final -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO

Siapkan grant When In Use khusus app uji dan input lokasi Simulator bergerak untuk testRealMapShowsLocalGPSWithoutStartingSharing; tes itu memang memerlukan Core Location sintetis. Seluruh store tes menggunakan in-memory. Sesudah run ini, input lokasi dibersihkan dan grant lokasi uji dikembalikan ke prompt; ini bukan pengujian dialog izin pertama.

Harness DDS:

    bash scripts/check-routing-model.sh
    bash scripts/check-routing-channel.sh

CLI compiler plugin, CoreSimulator dan Bonjour memerlukan akses layanan macOS yang sesuai; shell sandbox yang melarang sandbox-exec/layanan Simulator dapat memberi error lingkungan. Pemeriksaan di atas menggunakan akses toolchain yang diperlukan, tanpa mengubah proteksi project.

## Yang belum dibuktikan

- CloudKit pada dua/lebih akun iCloud nyata: propagation lokasi, ACL server, expiry/revocation end-to-end dan latensi.
- GPS walking/road matching, jitter indoor/outdoor, background socket dua iPhone, lock screen, baterai, jangkauan peer-to-peer tanpa access point dan OS minimum iOS 18.
- Seluruh UI routing pada ukuran aksesibilitas, VoiceOver, iPad dan landscape. Regresi ukuran teks besar hanya mencakup alur pemeriksaan lama.
- Background GPS DDS pada app gabungan belum diulang di perangkat fisik. Smoke test 27 callback background pada project DDS asal adalah bukti historis Simulator, bukan validasi lapangan versi gabungan.
- Tidak ada prediction/interception, panduan suara atau navigation engine lengkap, route offline, maupun sinkronisasi cloud setiap detik.

[Langkah menjalankan dan uji dua kanal](../DYNAMIC_ROUTING.md). Keberhasilan route/tes tidak mengesahkan kehadiran peserta atau manfaat operasional.
