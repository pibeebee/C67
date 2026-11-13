# Dynamic destination routing pada C67

19 Oktober 2026 · C67 0.6 build 8 · deployment target iOS 18+. Integrasi dengan PoC DDS; project DDS asal tetap tersedia untuk pembanding.

## Alur utama: posisi perjalanan yang sudah dibagikan

1. Pasang build C67 yang sama pada perangkat TL dan peserta. Ikuti pairing QR dan consent sebelumnya. Lokasi jarak jauh memakai CloudKit; kode DDS tidak digunakan pada alur ini.
2. Agar peserta dapat menuju TL, TL memulai **Bagikan lokasi saya ke peserta**. Peserta membuka **Lihat posisi tour leader**, memilih pin TL atau melalui Daftar, lalu **Ikuti posisi tour leader**.
3. Agar TL dapat menuju peserta, peserta memulai sesi lokasinya. TL membuka **Peta rombongan**, memilih orang yang dituju, lalu **Ikuti posisi peserta ini**.
4. Tombol memulai routing atau menunggu input yang layak. Membuka peta/memilih pin tidak otomatis meminta route. Kamera tetap dapat digeser; **Lihat rute** memusatkan hasil.
5. Pin kegiatan menyediakan **Rute ke kegiatan ini**. Ketika tidak ada orang/kegiatan dipilih dan meeting point tersedia, panel menyediakan **Rute ke meeting point**.
6. **Hentikan rute** mengakhiri routing pada peta. Sesi GPS/sharing tetap terpisah; gunakan tombol Stop berbagi sebelumnya untuk berhenti membagikan posisi.

Lokasi sendiri memakai sensor yang sudah aktif, atau sensor lokal peta bila tidak berbagi. Routing tidak memulai upload baru, mengganti penerima, atau menandai peserta hadir. Peserta tidak dapat merutekan dirinya ke peserta lain yang tidak terlihat melalui akses petanya.

## Data dan kebijakan request

- MapKit menghitung rute berjalan kaki saat app aktif dan membutuhkan internet. Jarak/ETA adalah snapshot, bukan remaining distance atau prediksi waktu bertemu.
- Pada peta utama, sampel orang harus valid untuk run yang sama, umur ≤60 detik, tidak lebih dari 5 detik di masa depan, akurasi ≤65 m dan Precise Location aktif. Sampel sintetis ditolak pada run nyata. Umur 60 detik mengikuti freshness C67; Lab DDS lokal memakai 30 detik.
- Pin lama tetap dapat tampil sesuai aturan peta. Input hilang, expired, dicabut atau tidak presisi membatalkan request aktif dan menahan route; route terakhir menjadi abu-abu disertai alasan.
- Pemicu awal: target bergeser ≥30 m, asal ≥60 m, atau asal bertambah jauh dari polyline ≥40 m dibanding offset awal yang sudah disesuaikan MapKit ke jalan. Minimum 10 detik waktu nyata antarrequest.
- Satu request aktif. Perubahan selama kalkulasi dievaluasi menggunakan koordinat terbaru pada tick berikutnya; tidak membatalkan setiap update.
- Error memakai backoff 15/30/60/120 detik; throttling setidaknya 60 detik. Ini heuristic PoC, bukan kuota resmi Apple. Peta dan Lab berbagi satu engine sehingga berpindah layar tidak menghapus cooldown/backoff.
- Tujuan baru, perubahan run/mode/peran atau epoch sumber baru membuang route lama dan menolak respons terlambat. Edit lokasi tetap mengubah revision koordinat; hapus kegiatan/lokasinya menahan routing.
- Background menjeda MapKit. Kembali foreground pada peta yang masih terbuka mempertahankan pilihan tujuan dan melanjutkan ketika input segar tersedia. Menutup peta mengakhiri routing; relaunch tidak otomatis melanjutkan.

CloudKit tetap memakai upload sekitar 20 detik dan polling foreground sekitar 15 detik ditambah jaringan/backoff. Routing tidak menaikkan frekuensi CloudKit atau menjamin update setiap detik. GPS background mengikuti consent, durasi dan batas iOS sebelumnya. Uji terkunci, jitter, latensi serta baterai pada perangkat tetap diperlukan.

## Lab DDS 0–5 di dalam app

Buka **Lab → Lab rute dinamis** ketika GPS/pengiriman utama sudah berhenti. Lab tidak mereset run/roster/koneksi CloudKit. Engine routing dipakai bersama; GPS dan transport eksperimen terpisah dari share perjalanan.

| Tahap | Input | Yang diuji |
|---|---|---|
| 0 · Statis | A/B sintetis Jakarta, Singapura atau Tokyo | Availability untuk pasangan titik tertentu |
| 1 · B bergerak | A tetap; B sintetis | Target update/reroute |
| 2 · A + B | Dua lintasan sintetis | Asal, tujuan dan off-route |
| 3 · GPS nyata | Core Location A; B sintetis dekat fix pertama | GPS → routing; Simulator tetap ditandai sintetis |
| 4 · Dua iPhone | GPS B ke A di jaringan lokal | Pairing terenkripsi, freshness, reconnect; foreground |
| 5 · Background | GPS dengan sesi background yang dimulai pengguna | Delivery lokasi dan pemulihan; MapKit tetap foreground |

### Tahap lokal dua perangkat

1. B: buka tahap 4 atau 5, pilih **B · Target**, lalu **Mulai sesi**.
2. Bagikan kode lengkap hanya kepada Navigator melalui Share Sheet. Kode mengandung kunci acak 256-bit.
3. A: buka tahap yang sama, pilih **A · Navigator**, tempel kode, lalu Mulai sesi.
4. Izinkan GPS dan Local Network. Gunakan Wi-Fi lokal yang sama untuk uji awal. Bonjour menemukan sesi; payload lokasi memakai AES-GCM, epoch/challenge baru dan sequence per koneksi.
5. Gerakkan B dan amati marker/rute serta umur/akurasi. Ambang Lab: umur 30 detik, akurasi 65 m. Pengiriman paling cepat 2 detik ketika bergerak ≥3 m, atau setelah 10 detik untuk fix yang masih segar.
6. Tahap 4 berhenti saat app background. Tahap 5 mempertahankan sesi Core Location maksimal 30 menit; Diagnostik mencatat GPS/paket background. Hentikan atau menutup Lab melepas GPS dan koneksi.
7. Putus jaringan/Stop B: A menahan routing dan menandai snapshot lama. A mencari peer kembali selama sesi B yang sama masih aktif. Setelah B memulai sesi baru, gunakan kode baru pada A.

Ini kanal lokal eksperimen. CloudKit perjalanan tidak dipakai pada tahap 4–5 Lab; jarak jauh/jaringan berbeda memerlukan relay. Kode Lab tidak bergabung ke roster, membuat share iCloud, atau menjadi QR perjalanan. Pairing QR lama tetap dipertahankan untuk kompatibilitas. Dua Bonjour service memiliki namespace sendiri.

Peer-to-peer diaktifkan untuk link yang didukung; jangkauan/koneksi tanpa access point belum diukur. Background Location tidak menjamin socket atau proses terus hidup. Force quit/crash/relaunch memerlukan Start baru; modul DDS tidak menyimpan kode/koordinat di disk. Laporan berisi metadata/timestamp dan error, bukan kode/koordinat.

### Argumen reproduksi Lab

Argumen DDS memakai awalan khusus: **--dds-stage 0…5**, **--dds-area jakarta|singapore|tokyo**, **--dds-autorun**, **--dds-live-role navigator|target**, **--dds-pair-code**, dan **--dds-live-diagnostics**. Buka layar Lab DDS agar argumen diterapkan. Untuk penggunaan biasa, pilih tahap dan Mulai; izin diminta saat diperlukan. Hindari menyimpan kode sesi pribadi dalam shell history.

## Uji perangkat

- CloudKit: TL/peserta bergerak dengan akun iCloud masing-masing. Catat umur sumber, request dan route. Ulangi indoor/outdoor, Precise off, offline, Stop/expiry/revocation serta epoch baru.
- Background utama: B berbagi sesuai consent, A foreground; kemudian A background dan kembali. Catat gap/waktu pemulihan. Tidak ada polling CloudKit baru saat A terkunci.
- Lab lokal: B background/A foreground, A background/B foreground, keduanya background, jaringan terputus dan Force quit. Catat GPS/paket background dan umur sumber.
- Pastikan routing tidak mengubah pemeriksaan atau membuka lokasi peserta lain.
- Uji OS/perangkat minimum; deployment iOS 18 yang lolos compiler bukan hasil runtime iOS 18.

## Struktur integrasi

**RoutingService, SimulationModels dan RouteLab** berasal dari DDS. Provider memakai MKMapItem modern pada iOS 26+ dengan fallback iOS 18–25. **GroupRouting** mengambil sumber yang sudah berhak tampil di peta, menegakkan quality/freshness/context dan mengelola pilihan tujuan. **GroupMapScreen/GroupRouteStatusView** menyediakan overlay serta kontrol. **POCController** memiliki engine untuk mempertahankan cooldown.

**RoutingExperimentView** memuat seluruh tahap DDS. **LiveExperiment, GPSFeed, LocalLocationChannel dan LiveLocationModels** menjadi alat lokal; tidak menulis SessionStore/CloudKit. Inisialisasi state SwiftUI tidak mereset engine aktif; keluar tahap lama tidak membatalkan tahap baru. GPS/koneksi dimulai lewat Start dan berhenti ketika ditutup.

Tidak ada migrasi struktur snapshot atau perubahan schema/ACL CloudKit. Koneksi QR v3 yang sudah lengkap tidak wajib scan ulang. [Verifikasi](verification/VERIFICATION_V6.md) memisahkan tes otomatis dari uji lapangan.

Referensi Apple: [MKDirections](https://developer.apple.com/documentation/mapkit/mkdirections), [Core Location background](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background), [Network peer-to-peer](https://developer.apple.com/documentation/network/nwparameters/includepeertopeer).
