# POC 0.5 — satu QR untuk bergabung ke perjalanan

15 Oktober 2026 · iOS 18+ · versi 0.5 build 7.

Fitur peta/lokasi TL: [panduan 0.4](MAP_AND_LEADER_LOCATION.md). Protokol QR versi 3 (meeting point boleh kosong): update kedua sisi dan scan ulang untuk mengaktifkan arah lokasi TL.

Navigasi terbaru: [peta UI terbaru](UI_NAVIGATION.md). Iterasi QR ini mematangkan POC v2 dengan onboarding QR dan roster dinamis. Tujuan uji: menghilangkan salin Run ID, pilihan ID fixture dan pengiriman tautan undangan secara manual. Ini belum bukti bahwa onboarding berhasil digunakan TL di lapangan.

## Persiapan

- Install build Debug yang sama dari Xcode ke dua atau lebih iPhone fisik. Gunakan satu iPhone sebagai TL dan sisanya sebagai peserta.
- Setiap iPhone memakai akun iCloud berbeda, termasuk antar-peserta. Keduanya perlu internet. CloudKit Development tetap dipakai pada Debug.
- Saat pairing: perangkat berdekatan, Wi-Fi/Bluetooth aktif, app foreground, izin Jaringan Lokal diizinkan. Untuk percobaan pertama, gunakan jaringan Wi-Fi yang sama tanpa isolasi klien. Dukungan peer-to-peer di tempat lain perlu diuji.
- Scan melalui **scanner di dalam aplikasi**, bukan kamera bawaan iPhone. Tidak diperlukan domain/deep-link server.
- Bila masih ada share POC v1/v2, peserta menekan Hentikan/cleanup dan TL memutuskan share sebelum membuat perjalanan baru. Update aplikasi sendiri tidak menghapus run lama.

## Di iPhone TL

1. Buka **Rombongan → Undang peserta lewat QR**.
2. Isi nama perjalanan dan nama TL. Pilih **Buat perjalanan QR → Ganti & buat perjalanan**. Langkah ini mengganti pemeriksaan/riwayat lokal setelah konfirmasi, dan memulai roster kosong.
3. Izinkan Jaringan Lokal ketika diminta. Tunggu QR muncul. Jika perjalanan QR sudah ada, cukup pilih **Tampilkan QR undangan**.
4. Tunjukkan QR kepada peserta. QR berlaku lima menit; layar ini harus tetap terbuka selama onboarding. Satu QR dapat dipakai beberapa peserta, disarankan satu per satu untuk uji pertama.
5. Nama peserta masuk ke daftar setelah share privat diterima dan disimpan. Tutup layar QR untuk kembali ke dashboard. Koneksi lokasi yang sudah tersimpan tidak diputus ketika layar QR ditutup.
6. Peserta baru selalu **belum diperiksa**. Konfirmasi kehadiran tetap tindakan TL yang terpisah dari pairing maupun lokasi GPS.

## Di iPhone peserta

1. Buka **Peserta → Scan QR perjalanan**.
2. Isi nama Anda → **Buka kamera & scan QR**. Izinkan Kamera jika diminta.
3. Scan QR yang ditampilkan langsung oleh TL. Periksa nama perjalanan/TL, lalu pilih **Gabung perjalanan**. Nama TL adalah label yang diisi pembuat perjalanan, bukan verifikasi identitas resmi.
4. Pada pop-up **Persetujuan lokasi**, pilih durasi dan opsi layar terkunci, lalu **Setuju & gabung**. Tombol ini juga mengonfirmasi penggantian run/riwayat lokal pada iPhone peserta. **Batal** atau menutup pop-up tidak memulai pairing/GPS. Tidak ada centang persetujuan permanen di form scan.
5. Izinkan Jaringan Lokal. Tunggu proses: mencari TL → koneksi lokal → membuat undangan privat iCloud → TL menerima otomatis → memulai sesi lokasi.
6. Izinkan lokasi When In Use bila diminta. Persetujuan scan tidak menggantikan izin iOS. Status sensor/sampel menentukan apakah GPS sudah menghasilkan posisi.
7. Setelah berhasil, layar dapat ditutup dan peserta boleh menjauh. **Koneksi lokal hanya bootstrap**; lokasi selanjutnya dikirim lewat CloudKit, tidak bergantung jarak Bluetooth terhadap TL.
8. Berhenti melalui **Hentikan berbagi & putuskan koneksi**. Pengiriman lokal langsung dihentikan. Jika offline, pencabutan cloud belum dikonfirmasi sampai cleanup online berhasil.

## Beberapa peserta dan perjalanan berikutnya

- Ulangi scan dari iPhone peserta lain menggunakan akun iCloud masing-masing. POC membatasi 20 koneksi peserta per perjalanan; batas ini belum merupakan hasil uji 20 perangkat.
- Setiap peserta memiliki share lokasi privat sendiri. Peserta lain tidak mendapat akses ke share tersebut. TL diundang sebagai read-only, bukan read-write.
- Dashboard memuat roster dinamis, termasuk nama yang sama dengan ID singkat berbeda. Lokasi tambahan dapat dibuka pada detail tiap peserta.
- Pada **Peta rombongan**, seluruh lokasi tersedia tampil bersama; ketuk pin atau nama dalam Daftar untuk fokus/detail. Diagnostik Lab tetap mengukur binding lokasi yang tersimpan; pilihan pin peta tidak mengubah scope diagnostik. Polling berjalan ketika tab Rombongan foreground, sekitar 15 detik ditambah durasi fetch seluruh peserta; ini bukan realtime dengan SLA tetap.
- Menutup sesi lalu memulai sesi berikutnya mempertahankan nama/ID roster dengan pemeriksaan baru. Riwayat sesi lama tetap tersimpan.
- Setelah relaunch, roster dan referensi share tersimpan, tetapi GPS tidak otomatis dimulai. Peserta memilih **Lanjutkan berbagi lokasi**. Pop-up memeriksa koneksi tersimpan, lalu menawarkan durasi dan tombol **Setuju & mulai berbagi**. Tombol disabled sampai koneksi dikonfirmasi; tidak ada consent yang otomatis diingat.
- TL dapat memutus akses per peserta pada layar QR setelah QR ditutup. Tindakan ini tidak menghapus orang dari riwayat/roster pemeriksaan. Peserta tetap harus menghentikan sesi lokalnya sendiri.
- Untuk menghubungkan ulang setelah share dicabut, peserta cleanup lalu scan QR baru. Selama anggota masih terdaftar pada TL, akun yang sama memakai ID yang sama tanpa duplikasi. Setelah TL memutus/menghapus koneksi, scan ulang dapat membuat ID baru; roster lama tetap ada sebagai riwayat dan perlu ditinjau TL.

## Jika pairing belum berhasil

| Keadaan | Langkah |
|---|---|
| QR kedaluwarsa | TL tutup undangan lalu tampilkan QR baru. Scan ulang. |
| Kamera tidak tersedia/izin ditolak | Izinkan Kamera di Pengaturan. Scanner tidak tersedia di Simulator; input isi QR manual tersedia untuk pengujian payload. |
| TL tidak ditemukan | Pastikan layar QR TL masih terbuka, kedua app foreground, Wi-Fi/Bluetooth dan Jaringan Lokal aktif. Coba Wi-Fi yang sama. Pairing peserta timeout setelah dua menit atau saat QR kedaluwarsa. |
| Akun sama | Gunakan akun iCloud berbeda untuk TL dan setiap peserta. |
| Gagal setelah share dibuat | Peserta Hentikan/cleanup sampai selesai, lalu scan ulang. TL mungkin sudah menyimpan anggota; reconnect akun sama tidak menggandakan anggota aktif. |
| Sesi pemeriksaan TL sudah ditutup | Mulai sesi berikutnya sebelum membuka QR lagi. |
| Ditutup/masuk background sebelum selesai | Pairing lokal dihentikan. Koneksi cloud yang sudah jadi tetap tersimpan; share parsial di peserta tetap dapat di-cleanup melalui tombol Stop. |
| GPS tidak muncul | Periksa izin lokasi, status sensor, koneksi internet dan umur sampel. Bergabung tidak menjamin langsung ada sampel GPS. |

## Cara kerja dan batas akses

QR memuat identitas perjalanan, ID akun CloudKit TL yang terikat pada container app, token undangan berumur pendek dan public key sementara. Private key hanya di memori TL. Multipeer Connectivity menggunakan encryption required; respons TL ditandatangani dan dikaitkan dengan challenge peserta serta public key pada QR.

Peserta membuat satu CKShare privat dan menambahkan akun TL dari QR secara programatis dengan izin read-only. URL dikirim lewat koneksi lokal. TL memeriksa container, pemilik, run dan ID peserta sebelum menyimpan referensi. Akses publik “anyone with link” tetap dilarang. Lokasi tidak dimasukkan ke QR atau transport bootstrap.

QR berfungsi sebagai undangan. Tampilkan langsung kepada peserta yang dimaksud; orang di dekat TL yang memperoleh QR valid dapat mencoba bergabung. Belum ada persetujuan individual dari TL, verifikasi nama resmi, Android/web client, atau pairing dari jauh. Tidak ada server khusus atau infrastruktur baru yang perlu dijalankan.

[Arsitektur dan keputusan](QR_PAIRING_DESIGN.md) · [Verifikasi v3](verification/VERIFICATION_V3.md) · [Demo sintetis v2](DEMO_GUIDE.md).

## Lokasi TL

Pairing 0.4 juga menyiapkan share TL read-only terpisah untuk akun peserta. Persiapan ini tidak memulai GPS TL. TL memberi consent/start melalui Rombongan; peserta membuka Lihat posisi tour leader. Stop peserta juga keluar dari share TL; stop TL membersihkan payload namun menyimpan undangan untuk resume. Lihat panduan peta 0.4 untuk cleanup dan batas update meeting point.

Meeting point perjalanan baru kosong dan tidak menghalangi pairing. Kedua sisi harus memakai 0.4.1 untuk pairing baru. Pengiriman lokasi peserta tetap membutuhkan persetujuan pop-up, dan pengiriman lokasi TL tetap membutuhkan Start TL sendiri. [Verifikasi 0.4.1](verification/VERIFICATION_V41.md).

**0.5:** QR tetap versi 3. Koneksi 0.4.1 yang lengkap dapat dipakai kembali untuk rundown. TL menyiapkan snapshot rundown di share privat sebelum URL diberikan; peserta mengambilnya setelah pairing. Update rundown/meeting point berikutnya tidak memerlukan scan ulang. [Panduan rundown dan Calendar](ITINERARY_GUIDE.md).
