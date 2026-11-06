# C67 POC 0.6 build 10 — Weather Lab dan itinerary Jakarta

**Weather Lab, 4 November:** layar awal eksperimen cuaca terpisah dengan diagnosis satu titik, kelompok radius 3 km, cache 15 menit, timeout 8 detik/provider, pemutus autentikasi dan cadangan Open-Meteo. Tab **Rencana** mempertahankan planner Jakarta; source routing/penyimpanan tidak diubah. 100 XCTest lokal (23 Weather Lab) +26 Jakarta lulus. Uji Simulator live: 6 titik →4 kelompok, 1 request WeatherKit gagal autentikasi lalu 4 request Open-Meteo berhasil (~2,29 detik); pengulangan menghasilkan 4 cache hit tanpa request baru. Autentikasi iPhone belum terbukti. [Cara mencoba, laporan dan bukti](docs/verification/WEATHER_LAB_2026-11-04.md).

**Perbaikan Jakarta, 4 November:** profil baru Jakarta/WIB dengan mobil/taksi, pemeriksaan pin wilayah, pemilihan cabang/nama yang lebih ketat, dan konteks pencarian kota yang diperbaiki. Open-Meteo dipakai langsung; data lama meminta konversi eksplisit. 77 XCTest lokal +26 Jakarta lulus. Uji MapKit/Open-Meteo aktual pada macOS menghasilkan lima tujuan lengkap, replan +30, skip/end-only dan restore;103 XCTest total. Build iOS/layar awal Simulator terverifikasi, interaksi UI lengkap dan iPhone fisik belum. Motor belum tersedia. [Laporan dan cara mencoba](docs/verification/JAKARTA_ROUTING_FIX_2026-11-04.md).

**P2A–P2B native:** perjalanan aktif manual, tambah durasi, skip/deadline dan review/apply/reject sisa rencana tersedia dengan penyimpanan, revision, idempotensi dan cancellation. 59 XCTest lokal + 26 Jakarta lulus; 144 run replay tanpa error auditor. 18 pasangan lebih singkat, 48 seri, 0 lebih lama; request adaptif lebih tinggi. Alur +30/apply/relaunch dan skip/end-only diuji di Simulator. [Laporan hasil dan batas bukti](docs/verification/NATIVE_TRIP_REPLANNING_P2_2026-11-04.md) · [Runner](checks/active/README.md). Provider live/iPhone fisik dan pengguna tetap P3/P4.

**P0–P1 native lokal:** deadline tiba di endpoint, simpan draft/itinerary pilihan dan pemulihan lintas sesi tersedia. Peluncuran native default melewati database fitur rombongan lama. 24 XCTest baru + 26 XCTest Jakarta lulus; simpan, failure/retry dan relaunch diuji di Simulator. Status replanning aktif terbaru tersedia pada laporan P2 di atas. [Laporan hasil](docs/verification/NATIVE_LOCAL_P0_P1_2026-11-03.md).

**Hybrid adaptif:** baseline divalidasi lebih dahulu; pencarian insertion + multi-start local search dijalankan bila diperlukan. Pada replay Jakarta empat tujuan, request turun **88 → 30** dengan jadwal sama. Penghematan total benchmark **2,42%**; 132 pasangan hasil layak tetap sama, tanpa regresi pada suite final. Build iOS, 26 XCTest dan 34 pemeriksaan lokal lulus. [Laporan implementasi dan pengujian](docs/verification/ADAPTIVE_ROUTING_REPORT_2026-11-03.md).

**Peta seluruh itinerary:** garis jalur mobil/jalan kaki untuk semua ruas kandidat, termasuk pulang, dibedakan dengan warna/nomor, ikon moda dan pola garis. Pilih ruas untuk sorot/zoom; cache sementara, retry terbatas dan log disertakan. Build serta UI Jakarta 5/5 ruas dan contoh jalan kaki 2/2 ruas terverifikasi di Simulator. [Panduan peta](docs/NATIVE_ROUTE_MAP.md) · [Bukti pengujian](docs/verification/NATIVE_ROUTE_MAP_2026-11-03.md).

**Routing berbasis total durasi trip:** default hybrid memadukan insertion dan multi-start local search, mempertahankan baseline live, melakukan refinement ETA terbatas, dan membedakan mobil pribadi dari taksi. Benchmark replay 22 kasus × 3 seed × 4 lengan selesai; laporan memuat kualitas, biaya request, temuan iterasi awal, dan batas validasinya. [Implementasi dan benchmark](docs/verification/ROUTING_TIME_AWARE_BENCHMARK_2026-11-03.md).

**Unit test Jakarta:** 26 XCTest lulus pada evaluator, tujuh metode dan pipeline dengan ETA rekaman yang tetap. Pemeriksaan mencakup jam operasional, input acak, data hilang dan batas satu hari. [Laporan terbaru, itinerary dan biaya request](docs/verification/adaptive-routing-2026-11-03/jakarta/REPORT.md) · [Riwayat 17 tes awal](docs/verification/jakarta-unit-tests-2026-11-03/REPORT.md) · [Cara menjalankan](checks/jakarta/README.md).

**Catatan historis input jam operasional:** build Simulator dan skenario Jakarta berhasil untuk enam metode pada snapshot serta alur live baseline/enumerasi. Jam buka Kelapa Gading dipatuhi, tetapi prioritas waktu perjalanan dan pemilihan finalis masih dapat menghasilkan waktu menunggu panjang. Jam tujuan lain tetap belum diisi. [Hasil dan batas pengujian](docs/verification/OPENING_HOURS_JAKARTA_REPORT_2026-11-03.md) · [Panduan jam operasional](docs/NATIVE_OPENING_HOURS.md).

**Uji routing Jakarta diperbaiki:** alamat/pin diberi diagnostik, mobil MapKit tersedia sebagai pilihan eksplisit, request diberi pacing dan retry terbatas. Run akhir menyelesaikan enam algoritme dengan 20/20 pasangan ETA layak. [Laporan dan bukti](docs/verification/JAKARTA_ROUTING_REPORT_2026-11-03.md).

**Cadangan cuaca:** WeatherKit → Open-Meteo otomatis; sumber/penyebab fallback dicatat pada hasil dan log. Tidak perlu API key tambahan untuk PoC. [Panduan fallback](docs/NATIVE_WEATHER_FALLBACK.md).

**Algoritme routing dan pembanding:** tujuh metode native termasuk hybrid, baseline, local search, insertion, beam, ALNS dan enumerasi kecil; evaluator mengutamakan kelayakan lalu total durasi trip. Layar **Bandingkan algoritme** memakai evaluator/snapshot bersama; OR-Tools terhubung melalui helper Mac ekspor/impor. [Panduan algoritme](docs/NATIVE_ROUTING_LAB.md).

**UI minimal dan log otomatis (sebelum build 10):** layar Rencana; pengaturan rinci terpisah. Log pencarian/ETA/cuaca/input/error disimpan lokal lintas sesi dan bisa diekspor melalui **Log → Ekspor log (.txt)**. Retensi maksimal sekitar 20 MB. [Panduan log dan verifikasi](docs/NATIVE_LOGGING.md).

**Perbaikan pencarian native:** timeout, offline, throttling dan hasil kosong dibedakan per tempat; query Jepang diberi area pencarian; bulk mempertahankan hasil yang sudah dipilih; tersedia diagnostik dan pilihan pin manual. [Panduan diagnosis pencarian](docs/NATIVE_PLACE_SEARCH_FIX.md).

**Perencana itinerary native ditambahkan (riwayat):** tab **Rencana** memakai MapKit untuk pencarian/ETA dan WeatherKit sebagai sumber cuaca utama, dengan Open-Meteo sebagai cadangan otomatis saat gagal atau tidak mencakup waktu trip, tanpa AI atau backend baru. Mulai dari rencana kosong: tambahkan tempat satu per satu atau tempel daftar sendiri. Titik awal/akhir, tanggal/jam, konteks area dan zona waktu bebas diisi; contoh 15 tempat Jepang tersedia lewat menu. Eksperimen Jejak dan lab lama dipertahankan melalui argumen peluncuran; tampilan default saat itu hanya Rencana. Transit MapKit hanya ETA; jam operasional diisi manual; autentikasi WeatherKit dan ETA Jepang masih memerlukan uji perangkat. [Panduan perencana native](docs/NATIVE_ITINERARY.md).

**Baru di 0.6 build 8:** routing terintegrasi dengan peta rombongan. Peserta dapat mengikuti posisi TL, TL dapat menuju peserta, dan kedua peran dapat menuju kegiatan/meeting point. Alur utama memakai GPS/CloudKit yang sudah ada. **Lab → Lab rute dinamis** memuat DDS 0–5, termasuk koneksi lokal terenkripsi untuk pembanding. Minimum iOS 18 dan container/QR/data lama dipertahankan. [Panduan routing](docs/DYNAMIC_ROUTING.md) · [Verifikasi integrasi](docs/verification/VERIFICATION_V6.md).

**Dari 0.5 build 7:** rundown kegiatan dengan waktu/catatan/lokasi, pemilihan tempat atau titik langsung pada peta, pin kegiatan yang dapat dipilih, titik berkumpul aktif dengan konfirmasi TL, sinkronisasi rundown/meeting point ke peserta melalui share privat yang sudah ada, dan ekspor ke Apple Calendar melalui editor native. [Panduan rundown](docs/ITINERARY_GUIDE.md) · [Verifikasi 0.5](docs/verification/VERIFICATION_V5.md).

**Dari 0.4.1:** posisi sendiri tersedia saat peta terbuka tanpa memulai berbagi lokasi, meeting point perjalanan baru kosong, dan persetujuan peserta dipindah ke pop-up dengan tombol Setuju & gabung. [Verifikasi 0.4.1](docs/verification/VERIFICATION_V41.md).

**Dari 0.4:** peta layar penuh menampilkan semua lokasi peserta yang tersedia, mendukung geser/zoom/putar, pemilihan pin, daftar tanpa lokasi dan tampilan satelit. Peserta dapat melihat lokasi TL setelah TL memberi consent dan memulai sesi sendiri. [Panduan peta & lokasi TL](docs/MAP_AND_LEADER_LOCATION.md) · [Verifikasi 0.4](docs/verification/VERIFICATION_V4.md).

**Penting untuk uji:** update semua perangkat ke 0.6; koneksi QR 0.4.1 yang sudah lengkap tetap dipakai, tidak perlu scan ulang hanya untuk perubahan jadwal; untuk pairing baru gunakan QR terbaru; data pemeriksaan lama tetap terbaca. Pairing memakai protokol QR versi 3 (mendukung meeting point kosong). Alur utama tetap QR; alat manual tetap di Lab.

**UI diperbarui:** QR menjadi alur utama. Run ID, undangan manual dan reset fixture dipindah ke Lab; durasi/consent hanya muncul saat bergabung atau melanjutkan. [Peta navigasi](docs/UI_NAVIGATION.md) · [Verifikasi perapihan](docs/verification/VERIFICATION_UI_CLEANUP.md).

**Alur utama:** TL menampilkan satu QR → peserta isi nama dan scan → Gabung perjalanan → pop-up durasi/penerima → Setuju & gabung → undangan iCloud privat diterima otomatis → sesi lokasi dimulai setelah izin iOS. Tidak perlu salin Run ID, memilih fixture P01, atau mengirim tautan secara manual.

**Mulai di dua atau lebih iPhone:** TL membuka **Rombongan → Undang peserta lewat QR → Buat perjalanan QR**; peserta membuka **Peserta → Scan QR perjalanan**. [Panduan penggunaan lengkap](docs/QR_PAIRING_GUIDE.md) · [Desain dan batas akses](docs/QR_PAIRING_DESIGN.md) · [Bukti verifikasi v3](docs/verification/VERIFICATION_V3.md).

Saat onboarding, iPhone berdekatan, app foreground, internet/Wi-Fi/Bluetooth aktif dan izin Jaringan Lokal diizinkan. Setiap perangkat menggunakan akun iCloud berbeda. Sesudah tersambung, lokasi menggunakan CloudKit dan tidak bergantung jarak Bluetooth ke TL. QR berlaku lima menit; POC membatasi 20 koneksi anggota, belum hasil uji 20 perangkat.

Perjalanan QR memulai roster kosong dan menambah peserta dengan ID unik. Nama sama tetap terpisah. Pairing/lokasi **tidak** menandai kehadiran; pemeriksaan dan tindak lanjut tetap tindakan TL. Peta menampilkan semua posisi tersedia sekaligus; memilih peserta membuka detail dan fokus kamera. Format snapshot lama tetap terbaca; update tidak otomatis mereset run. Membuat perjalanan/gabung baru meminta tindakan eksplisit karena mengganti pemeriksaan/riwayat lokal.

**Tidak ada server khusus atau dependency pihak ketiga.** SwiftUI, SwiftData lokal, Core Location, CloudKit Sharing privat, Multipeer Connectivity untuk pairing QR lama, Network untuk Lab DDS lokal, CryptoKit, VisionKit, MapKit dan EventKitUI. Minimum iOS 18; build menggunakan Xcode 27. Versi 0.6 build 8. Lokasi setiap peserta dibagikan melalui share privat sendiri dengan TL read-only, bukan share grup read-write.

Demo sintetis v2 tetap tersedia: **Rombongan → Demo → pilih skenario → Muat skenario demo**. [Panduan demo 3 menit](docs/DEMO_GUIDE.md). Ini bukan demo koneksi QR/GPS fisik. Alur manual v1/v2 di bawah dipertahankan untuk fallback. [Verifikasi v1](docs/verification/VERIFICATION.md) dan [v2](docs/verification/VERIFICATION_V2.md) adalah riwayat, bukan bukti runtime QR v3.

## Coba cepat di Simulator

1. Buka `poc-c67.xcodeproj`, pilih scheme **poc-c67**, pilih iPhone Simulator, lalu Run.
2. Instalasi baru di Simulator mulai dalam **Simulasi**. Jika data lama masih mode perangkat nyata, buka **Lab → Pairing manual → Reset fixture pengujian**, pilih Simulasi dan **Reset ke roster fixture…**. Reset mengganti riwayat lokal dan meminta konfirmasi.
3. Coba **Sampel dekat/jauh/kedaluwarsa/reduced accuracy**. Angka V tetap 0: lokasi tidak mengonfirmasi kehadiran.
4. Buka **P01 · Ayu → Tandai diperiksa**. Angka V menjadi 1. P03 Ayu mempunyai ID berbeda.
5. Coba tidak ikut (alasan dan pengaturan wajib), kembali ikut (perlu pemeriksaan baru), serta tindak lanjut (hasil wajib saat selesai).
6. **Review pemeriksaan**: unresolved memerlukan **Tutup dengan catatan** beserta alasan. **Mulai sesi berikutnya** mengembalikan semua peserta ke Diharapkan/Belum diperiksa tanpa mewarisi kasus.
7. **Lab → Gagalkan SATU simpan lokal berikutnya**, lalu coba suatu aksi pemeriksaan. Count/event tidak berubah, input tetap ada dan error terlihat; coba lagi untuk menyimpan.

Alur utama Simulator memulai mode Simulasi dan tidak mengunggah sampel sintetis ke CloudKit. Uji sensor lokal dan Lab DDS dapat membaca input Core Location Simulator yang ditandai sintetis. QR dapat dibuat/dibaca sebagai gambar dan payload pada tes, tetapi pairing akun nyata tetap memerlukan iPhone fisik. Simulasi diberi label pada layar dan laporan; bukan bukti H1/H2.

## Routing terintegrasi

- **Peserta:** Lihat posisi tour leader → pilih pin/Daftar TL → **Ikuti posisi tour leader**.
- **TL:** Peta rombongan → pilih pin/Daftar peserta → **Ikuti posisi peserta ini**.
- **Tujuan tetap:** pilih kegiatan → **Rute ke kegiatan ini**, atau Lihat semua → **Rute ke meeting point**.
- **Lab:** tab Lab → **Lab rute dinamis**. Hentikan GPS/pengiriman utama dahulu. Tahap 0–2 sintetis; tahap 3 GPS + target sintetis; tahap 4–5 dua perangkat lokal. Lab tidak mengubah roster atau membuat share CloudKit.
- Rute berjalan kaki dihitung saat foreground. Lokasi harus segar/presisi; rute lama menjadi abu-abu ketika input menua/berakhir. Hentikan rute tidak menghentikan berbagi lokasi dan tidak menandai kehadiran.

[Panduan routing dan perbedaan dua kanal](docs/DYNAMIC_ROUTING.md).

## Signing dan persiapan iPhone

- Gunakan dua iPhone iOS 18+ dengan **akun iCloud berbeda**, internet aktif, serta iCloud Drive/akses iCloud untuk app diizinkan. TL perlu izin lokasi untuk menampilkan posisi sendiri di peta atau membagikannya kepada peserta. Melihat posisi peserta saja tidak memulai pengiriman lokasi TL.
- Signing Team dikonfigurasi ke `DP5XP7C2AM`, sesuai sertifikat pengembangan yang ditemukan di Mac ini. Jika memakai team lain, ubah di Signing & Capabilities untuk app dan target tes.
- App menggunakan bundle ID `giovanchristoffel.poc-c67` dan container **`iCloud.giovanchristoffel.poc-c67`**. Jika bundle/container diubah, sesuaikan juga `CloudLocationChannel.containerID` dan `Configuration/poc-c67.entitlements`.
- Pastikan akun Developer sudah menerima perjanjian terbaru; automatic provisioning dapat gagal dengan `PLA Update available` bila belum. Xcode menggunakan account yang sudah terpasang; tidak ada password/token dalam source.
- Signing & Capabilities: automatic signing, iCloud → CloudKit dan container di atas. Background Modes → Location updates sudah dideklarasikan. Jika container belum dibuat oleh provisioning, buat/pilih melalui tombol `+` di bagian iCloud pada Xcode.
- Pasang build melalui Xcode Run pada kedua iPhone; gunakan container dan environment **Development yang sama**. Aktifkan Developer Mode bila diminta iOS. Jalankan app dari Home Screen setelah Stop debugger untuk uji background.
- Tidak perlu TestFlight. Jika kelak memakai TestFlight, schema harus dideploy ke Production; jangan mencampurkan build Development dan Production pada dua sisi.

## Fallback manual dan uji sensor

Alat manual terpusat pada **Lab → Pairing manual**. Pilih peran Tour leader untuk menyalin Run ID/menerima tautan/binding, atau Peserta untuk memasukkan Run ID, memilih fixture dan mengirim undangan. Reset fixture pengujian berada di layar yang sama dengan konfirmasi penggantian data. Jalur ini tidak dipakai untuk onboarding QR biasa.

Setelah koneksi peserta tersimpan, buka **Peserta → Lanjutkan berbagi lokasi** untuk memeriksa penerima dan memberikan consent baru. Saat sesi aktif, gunakan **Hentikan berbagi & putuskan koneksi** di halaman Peserta.

Percobaan sensor tanpa upload tersedia pada **Lab → GPS & iCloud**. Pilih meeting point langsung pada peta melalui ikon kanan atas Rombongan. Rundown kegiatan berada pada Rombongan → Rundown perjalanan; peserta membukanya dari tab Peserta. Peta baru dibuka melalui Peta rombongan. Meeting point perjalanan baru kosong; isi jika diperlukan. Titik lama yang pernah disimpan tetap terbaca. Skenario demo memakai fixture Monas secara eksplisit. TL tetap foreground untuk polling; upload dibatasi sekitar 20 detik dan bukan jaminan interval posisi.

## Pengukuran dan failure cases

- Pada TL buka **Lab**, pilih skenario, **Mulai ulang pengukuran**, lalu segera kembali ke tab Rombongan. Warm-up 60 detik; foreground berjalan 10 menit setelah warm-up, background berjalan 20 menit setelah warm-up. Jangan membiarkan TL di tab Lab atau terkunci selama pengukuran utama.
- **Ekspor laporan metadata .txt** setelah pengukuran. Laporan berisi observasi umur data, jumlah sampel, gap, baterai dan error; tidak berisi koordinat/email. Coverage yang kurang menghasilkan inconclusive. Posisi lama tidak diremajakan ketika record yang sama di-fetch ulang.
- Ulangi dengan airplane mode peserta/TL, Precise off, izin ditolak/dicabut, stationary, indoor, serta app di-force-quit/reboot. Jangan menyamakan lock screen dengan force-quit.
- **Hentikan berbagi & putuskan koneksi** menghentikan sensor dan antrean lokal. Operasi cloud yang sudah berjalan direkonsiliasi dengan penghapusan zone privat run tersebut. Bila offline/gagal, UI menyatakan pencabutan cloud belum dikonfirmasi; retry setelah online.
- TTL aplikasi mencegah upload dan pemakaian posisi setelah expiry. TTL bukan penghapusan server otomatis. Sampel yang kedaluwarsa tidak diputar ulang saat reconnect; setelah app diluncurkan ulang, GPS tidak dilanjutkan tanpa Start baru.
- **Uji penolakan write TL** mencoba menulis field probe pada record POC peserta; server harus menolak. Jika berhasil, hentikan sharing dan perbaiki izin. Akun ketiga yang tidak diundang perlu dicoba terpisah melalui tautan share privat.
- Setelah sharing dicabut/dihapus dan TL menerima penolakan akses, cache koordinat TL dibersihkan. Error jaringan biasa mempertahankan posisi terakhir beserta umurnya. Putuskan binding yang tidak lagi tersedia sebelum membuat run baru.

## Cleanup dan batas POC

Sebelum selesai/uninstall: peserta menekan STOP sampai cleanup cloud dikonfirmasi; TL keluar dari share; kemudian boleh membuat run lokal baru. Hanya custom zone `C67-…` privat milik run POC yang dibersihkan. Status/event manual tersimpan lokal hingga reset/uninstall. Tidak ada backup otomatis. Screenshot/ekspor eksternal tidak ikut terhapus.

Pemeriksaan disimpan sebagai satu snapshot JSON typed berikut audit events dalam SwiftData lokal, agar state dan event berada dalam commit yang sama. Ini penyederhanaan POC dibanding model relasional pada rancangan, bukan event store forensik. Injected save failure mengubah payload lalu melakukan rollback sebelum commit; tes memeriksa state/event dan reload.

POC belum membuktikan akurasi di kabin bus, continuous tracking setelah force-quit, pengiriman 40 perangkat serentak, kemampuan Android, notifikasi TL background, manfaat bagi TL, atau kelulusan App Review. Pengujian otomatis tidak menggantikan uji GPS/akun/ACL dan baterai di perangkat nyata. VoiceOver perlu pemeriksaan manual; tes UI ukuran teks aksesibilitas hanya memeriksa bagian alur manual.

## Jalankan tes

```sh
xcodebuild -project poc-c67.xcodeproj -scheme poc-c67 \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath /tmp/c67-derived CODE_SIGNING_ALLOWED=NO test
```

Pemeriksaan tambahan DDS menggunakan source di app gabungan:

    bash scripts/check-routing-model.sh
    bash scripts/check-routing-channel.sh

Pemeriksaan kanal menggunakan Bonjour/TCP dua peer pada Mac yang sama. Tes UI GPS lokal memerlukan input sintetis dan izin When In Use khusus app uji melalui simctl; lihat [verifikasi 0.6](docs/verification/VERIFICATION_V6.md).

Pilih nama Simulator yang tersedia di Mac Anda. `--ui-testing` membuat store in-memory dan mode Simulasi; `--large-text` mengaktifkan ukuran teks accessibility3 untuk tes. Kedua argumen tidak ditambahkan pada scheme Run normal.

Rujukan Apple: [Core Location background](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background), [CKShare](https://developer.apple.com/documentation/cloudkit/ckshare), [penerimaan undangan pada SwiftUI](https://developer.apple.com/documentation/coredata/accepting-share-invitations-in-a-swiftui-app), [schema CloudKit](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema).
