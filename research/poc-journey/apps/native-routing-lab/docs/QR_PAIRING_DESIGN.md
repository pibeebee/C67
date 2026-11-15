# POC v3 — desain pairing QR

15 Oktober 2026. Act / iOS build. Input: pengguna menginginkan scan QR dan koneksi otomatis sebagai peningkatan POC v2; runtime dua iPhone POC sebelumnya dilaporkan berhasil oleh pengguna.

## Hipotesis yang diuji

| Rantai | Keputusan |
|---|---|
| Temuan/masalah | Setup lama memerlukan Run ID, pemilihan fixture, undangan manual dan binding TL. Ini beban yang terlihat dari alur kode; tingkat kesulitan pengguna belum diukur. |
| Requirement | Peserta dapat bergabung dari satu QR TL, tetap mengetahui penerima/durasi lokasi dan dapat Stop. |
| Hipotesis | Peserta bisa menyelesaikan onboarding tanpa bertukar Run ID/tautan secara manual. |
| Artifact | Scanner, konfirmasi, bootstrap lokal, undangan CloudKit privat otomatis, roster dinamis. |
| Evaluasi teknis | Parser, gambar QR, challenge/signature, binding/roster/persistence, UI, build signed; pengujian fisik masih diperlukan. |
| Evaluasi pengguna berikutnya | 1 TL + 2 peserta, tanpa coaching setelah instruksi awal. Catat waktu dari scan sampai lokasi pertama, kegagalan izin, bantuan, salah identitas, dan keberhasilan Stop. Jangan menyamakan pairing berhasil dengan manfaat operasional tervalidasi. |

## Alternatif dan pilihan

- QR yang hanya membawa Run ID/tautan share mengurangi copy/paste tetapi mempertahankan undangan manual. Tidak memenuhi arah UX yang diminta.
- Satu share grup TL dengan read-write untuk semua peserta memudahkan join, tetapi model izin CKShare bukan pembatas tulis per record peserta. Tidak dipilih untuk lokasi pribadi.
- Backend pairing dapat mendukung onboarding jarak jauh dan model akses khusus, tetapi menambah infrastruktur. Tidak ditambahkan pada POC ini.
- **Dipilih:** QR TL + Multipeer Connectivity untuk pertukaran bootstrap; satu CKShare privat milik setiap peserta dengan TL read-only. Core Location dan CloudKit tetap jalur posisi.

## Urutan

1. TL memeriksa akun iCloud, membuat token/public key sementara dan mengiklankan service `_c67-pair._tcp` dengan hash token (tanpa nama/ID akun di Bonjour).
2. Peserta membaca QR, memeriksa penerima dan memberikan consent. Akun iCloud diperiksa; akun TL dan peserta tidak boleh sama.
3. Peserta menemukan service berdasarkan hash, mengirim konteks undangan dan menghubungkan MCSession encryption required. Nama perangkat asli tidak dipakai sebagai peer display name.
4. Peserta mengirim nama, akun CloudKit dan challenge baru. TL memberi ID peserta unik (atau memakai anggota aktif dari akun yang sama) serta respons bertanda tangan.
5. Peserta memvalidasi key pada QR, challenge, akun/run/invite, lalu menyimpan referensi cleanup sebelum penulisan cloud.
6. Peserta membuat share privat; akun TL diambil melalui `shareParticipant(forUserRecordID:)`, mendapat read-only, dan URL dikembalikan lewat koneksi lokal.
7. TL memvalidasi pemilik share, private permission, container, run dan ID; menerima share; menyimpan roster/reference secara atomik; mengirim receipt bertanda tangan.
8. Peserta memvalidasi receipt, memeriksa accepted recipient dari CloudKit, lalu memulai sesi lokasi sesuai consent. Izin Core Location tetap dikendalikan iOS.
9. Transport lokal ditutup di peserta. Posisi memakai CloudKit; QR ditutup/expired tidak mencabut share yang sudah selesai.

## Penyimpanan dan pemulihan

Format SwiftData SavedRun tetap berisi snapshot JSON tunggal. Field QR ditambahkan secara optional agar payload v1/v2 tetap dapat dibaca. QR token/private key tidak disimpan; TTL lima menit dan sesi bootstrap hilang ketika background/relaunch. Referensi share, akun anggota dan nama disimpan lokal agar dapat reconnect/poll setelah relaunch. Tidak ada auto-resume GPS.

TL mempunyai daftar share privat dan cache terpisah per peserta. Cache diperiksa run/epoch/sequence; expiry/revoke menghapus sampel aktif. Nama sama tidak berarti akun/ID sama. Verifikasi kehadiran dan tindak lanjut tidak dipengaruhi status pairing/lokasi.

Stop membatalkan bootstrap dan menunggu penulisan bootstrap yang sedang berjalan sebelum menghapus zone privat, untuk mencegah prepare terlambat membuat ulang zone sesudah cleanup. Stop lokal tetap dilakukan sebelum menunggu jaringan. Jika cleanup gagal, owner reference dipertahankan untuk retry.

## Batas POC

20 koneksi anggota, maksimal enam peer lokal bersamaan (batas app), disarankan pairing satu per satu. Polling seluruh share serial saat Rombongan foreground. Tidak ada jaminan update 15 detik untuk setiap peserta. Roster pemeriksaan mempertahankan anggota yang aksesnya diputus; belum ada penghapusan/merge anggota dinamis oleh TL. Rejoin setelah TL menghapus koneksi dapat menciptakan ID baru. Ekspor/screenshot pihak lain tidak dapat dicabut.

Nama TL dalam QR bukan identitas terverifikasi resmi. QR adalah akses ke sesi onboarding; siapa pun yang memiliki QR dan berdekatan dapat meminta bergabung selama aktif. Tanda tangan mengikat koneksi ke QR yang dipindai, tidak mengesahkan siapa orang yang menampilkan QR. Belum ada moderasi approval individu dari TL atau klaim audit keamanan menyeluruh.

## Referensi Apple

- [CloudKit shared records](https://developer.apple.com/documentation/cloudkit/shared-records): private invite dan acceptance.
- [CKContainer](https://developer.apple.com/documentation/cloudkit/ckcontainer): lookup participant melalui user record ID.
- [CKShare permissions](https://developer.apple.com/documentation/cloudkit/ckshare/participantpermission): read-only/read-write.
- [Multipeer Connectivity](https://developer.apple.com/documentation/multipeerconnectivity): bootstrap antar-perangkat.
- [TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy): Jaringan Lokal dan deklarasi Bonjour.
- [DataScannerViewController](https://developer.apple.com/documentation/visionkit/datascannerviewcontroller): scanner kamera; periksa dukungan/availability.

Referensi diperiksa pada sesi implementasi; hasil build bukan bukti runtime akun CloudKit terpisah atau persetujuan App Review.
