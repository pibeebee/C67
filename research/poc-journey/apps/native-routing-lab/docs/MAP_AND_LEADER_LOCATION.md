> **Pembaruan 0.6, 19 Oktober 2026:** peta ini menyediakan routing ke orang/kegiatan/meeting point melalui posisi yang sudah tersedia. Lihat [panduan dynamic routing](DYNAMIC_ROUTING.md).

# POC 0.5 — peta rombongan interaktif & lokasi TL

15 Oktober 2026 · Asia/Jakarta · versi 0.5 build 7 · iOS 18+.

## TL melihat semua peserta

Buka **Rombongan → Peta rombongan**. Peta layar penuh mendukung geser, cubit untuk zoom, putar dan tilt. Tombol **Lihat semua** memusatkan kamera pada meeting point dan semua lokasi tersedia; **Meeting point** kembali ke pin; **Satelit/Peta standar** mengganti tampilan. Memilih peserta tidak menyembunyikan pin peserta lain. Kamera tidak otomatis dipusatkan ulang setiap kali polling selesai.

Ketuk pin atau **Daftar → nama peserta** untuk fokus ke posisi tersebut dan membaca waktu pengukuran, umur serta akurasi. Pin TL berwarna ungu, peserta hijau, posisi sendiri di sisi peserta biru; lokasi berumur lebih dari 60 detik berwarna oranye dengan label **Lama**. Status juga tersedia sebagai teks, tidak bergantung warna saja. Lingkaran akurasi hanya untuk pin yang dipilih agar peta tidak penuh overlay.

Peserta yang belum mengirim GPS, izinnya belum tersedia, sesi lease berakhir atau aksesnya dicabut tidak dibuatkan koordinat perkiraan. Mereka tetap ada di **Daftar → Belum ada lokasi**. Umur lokasi dihitung dari timestamp pengukuran, bukan waktu fetch. Lokasi lama dapat tampil sebagai posisi terakhir selama lease berbagi masih aktif; lokasi itu tidak dianggap posisi saat ini.

## Lokasi saya

Tombol **Lokasi saya** memusatkan kamera pada posisi iPhone ini. Pada TL pin berlabel **Anda · TL**; pada peserta **Anda**. Selama sesi berbagi aktif, peta memakai sensor sesi tersebut. Jika tidak ada sesi aktif, peta memakai sensor lokal sendiri dengan izin When In Use, tanpa callback upload atau sesi background. Sensor lokal berhenti ketika peta ditutup atau app masuk background. Stop berbagi tidak mencegah posisi lokal muncul kembali saat peta dibuka.

Membuka peta dapat memunculkan izin lokasi iOS. Tanpa izin/sampel, tombol Lokasi saya disabled dan status ditampilkan. Tidak ada koordinat perkiraan pengganti. Jika peta awal kosong, lokasi pertama difokuskan sekali; pembaruan berikutnya tidak merebut kamera saat pengguna menggeser peta. Lokasi lokal dari Simulator tetap ditandai sebagai simulasi dan bukan bukti GPS iPhone fisik.

## Peserta melihat TL

1. Install **0.6 build 8 pada semua iPhone**. Pairing QR kini memakai protokol versi 3.
2. Pairing baru harus memakai 0.4.1 pada kedua sisi karena QR v1/v2 ditolak. Koneksi 0.4 yang sudah lengkap tetap tersimpan. Untuk koneksi 0.3/0.3.1, peserta Stop/cleanup koneksi lama lalu scan QR TL terbaru. Roster/riwayat tidak direset oleh update aplikasi; pairing lama tetap tidak mempunyai kanal lokasi TL sampai dihubungkan ulang.
3. Saat pairing, aplikasi menyiapkan dua arah secara privat: peserta → TL, dan TL → peserta. **Persiapan share tidak memulai GPS TL.**
4. Setelah peserta tersambung, TL membuka **Rombongan → Bagikan lokasi saya ke peserta**, memilih durasi/background, memberi consent lalu **Mulai berbagi lokasi TL**. TL juga perlu memberikan izin lokasi iOS.
5. Peserta membuka **Peserta → Lihat posisi tour leader**. Peta memuat TL ketika sampel tersedia, serta posisi sendiri ketika sesi sensor peserta aktif. Lokasi peserta lain tidak dikirim ke peserta ini.
6. TL dapat **Hentikan lokasi TL** kapan saja. Sensor/upload lokal dihentikan; setelah cloud pause berhasil, payload koordinat TL dibersihkan. Undangan tetap tersimpan sehingga TL dapat memulai sesi baru tanpa seluruh peserta scan ulang.
7. Jika stop cloud belum dikonfirmasi, UI meminta retry saat online. Peserta mungkin masih memiliki posisi terakhir sebelumnya beserta umurnya hingga pause ter-fetch atau lease berakhir. Screenshot pihak lain tidak dapat ditarik kembali.

Consent TL berlaku untuk peserta yang dihubungkan pada perjalanan itu, termasuk peserta baru yang bergabung saat sesi lokasi TL masih aktif, sampai durasi berakhir. GPS TL tidak otomatis dilanjutkan setelah relaunch.

## Hentikan, keluar, atau ganti perjalanan

- **Peserta Stop:** sensor/pengiriman sendiri berhenti dan share milik peserta dihapus; aplikasi juga keluar dari share lokasi TL. Jika cleanup gagal, referensi tetap tersimpan untuk retry.
- **TL putuskan satu peserta:** hentikan lokasi TL dahulu, tutup QR, kemudian Putuskan akses TL pada anggota. Kanal lokasi TL ke akun itu dihapus, dan TL keluar dari share peserta. Riwayat pemeriksaan orang tersebut tetap ada.
- **TL mengganti perjalanan:** hentikan lokasi TL, tutup QR, putuskan seluruh koneksi peserta. Jika masih ada share TL dari pairing parsial, buka **Berbagi lokasi TL → Hapus seluruh koneksi lokasi TL**. Reset/membuat perjalanan baru tetap diblokir selama ada referensi aktif/cleanup yang belum selesai.
- Menghapus seluruh koneksi TL tidak menghapus lokasi peserta/roster; peserta perlu scan ulang untuk kembali menerima lokasi TL. Gunakan untuk cleanup atau sebelum mengganti perjalanan, bukan untuk stop sesi biasa.

## Meeting point dan kegiatan

Perjalanan baru tetap memiliki `meetingPoint = nil`. TL memilih titik melalui peta pada pengaturan atau menambahkan lokasi pada kegiatan rundown. Titik lama yang pernah disimpan tetap dimuat. Pin kalender indigo adalah kegiatan; lingkaran adalah orang. Ketuk pin kegiatan atau pilih dari Daftar untuk membuka nama/waktu dan Detail kegiatan.

**Rombongan → Rundown perjalanan → kegiatan → Jadikan titik berkumpul aktif** membutuhkan konfirmasi. Lokasi/waktu kegiatan menjadi tujuan berkumpul, tanpa mengubah status pemeriksaan. Rundown/meeting point dibagikan melalui kanal privat TL dan diperbarui saat online; tidak lagi hanya snapshot pairing. Lokasi GPS TL tetap pin terpisah. Saat offline atau TL versi lama, peserta mempertahankan salinan terakhir dengan status bahwa pembaruan belum dikonfirmasi.

[Panduan rundown, sinkronisasi dan Calendar](ITINERARY_GUIDE.md) menjelaskan edit/hapus, retry, read-only peserta dan batas ekspor Calendar. Tidak ada push/background sync baru. Penulisan cloud bukan tanda peserta sudah membaca.

## Demo satu perangkat

**Rombongan → Demo → Satu peserta belum kembali → Muat skenario demo**, lalu buka Peta rombongan. Fixture memuat empat posisi peserta berbeda, satu posisi TL, dan satu peserta dengan lokasi lama. Peta peserta dalam mode simulasi menampilkan TL dan posisi sendiri sintetis. Label DEMO/SIMULASI tetap terlihat. Demo tidak membuktikan GPS, koneksi fisik atau manfaat operasional.

## Desain akses & batas

Setiap peserta tetap memiliki share lokasi sendiri dengan TL read-only. Untuk arah balik, TL membuat **satu share privat terpisah per akun peserta**, berisi hanya posisi TL; peserta read-only. Tidak ada share grup berisi koordinat semua peserta, akses publik, atau server baru. Root/schema record menggunakan tipe POC yang sudah ada, tetapi referensi lokal ditambah secara optional agar snapshot lama tetap terbaca.

URL kanal TL dan meeting point disertakan dalam respons pairing yang ditandatangani; peserta memeriksa signature/challenge, container, owner akun TL, run dan label record TL sebelum menyimpan akses. Private key tetap sementara. Akses TL ke peserta lain tidak berpindah ke akun peserta.

Upload TL mengirim sampel terakhir ke kanal masing-masing, dibatasi sekitar 20 detik ditambah jaringan/backoff. Polling peserta dan TL hanya ketika tab peran terkait foreground, sekitar 15 detik ditambah waktu fetch. Skala 20 iPhone dan interval data tidak dijamin; biaya operasi per sampel TL bertambah sesuai jumlah kanal. Tidak ada antrean route offline. Waktu ukur, stale/expiry dan status akses tetap penting.

Belum ada tracking setelah force-quit, notifikasi lokasi TL background untuk peserta, Android, route turn-by-turn, impor/sinkronisasi Calendar dua arah atau verifikasi kehadiran otomatis. [Verifikasi 0.4.1](verification/VERIFICATION_V41.md) memisahkan tes Simulator dari uji fisik yang masih perlu dilakukan.

## Rujukan dan keputusan UI

Panduan [Apple HIG Maps](https://developer.apple.com/design/human-interface-guidelines/maps), diperiksa 15 Oktober 2026, mendukung interaksi peta yang familier, pilihan pin yang terlihat jelas, kontras kontrol, serta keterlihatan logo/legal Apple Maps. Implementasi memakai MapKit native dengan gesture `.all`, pin terpilih ber-outline, kontrol di area safe inset dan daftar teks sebagai alternatif pemilihan. Logo/legal diperiksa dari screenshot iPhone Simulator. Ini perbaikan UX terarah, bukan audit HIG menyeluruh atau klaim App Review.

[MapInteractionModes](https://developer.apple.com/documentation/mapkit/mapinteractionmodes) dan [CloudKit addParticipant](https://developer.apple.com/documentation/cloudkit/ckshare/addparticipant(_:)) menjadi rujukan API. Pin yang saling berdekatan belum di-cluster; gunakan zoom dan daftar untuk memilih orang yang bertumpuk. Pengujian VoiceOver lengkap, iPad dan skala 20 posisi fisik belum dijalankan.
