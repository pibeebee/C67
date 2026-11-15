# Feature Specification — Tour Leader Group Management

Versi 0.1 · 15 Oktober 2026 · Draft untuk review tim dan prototype.

**Keputusan pengguna:** tim sepakat pivot ke tour leader. **Usulan spesifikasi:** MVP satu TL pada satu iPhone, local-first, tanpa akun atau aplikasi wajib pada peserta. Scope ini belum disetujui tim sebagai keputusan produk final. Tidak ada implementasi atau hasil pengujian pada dokumen ini.

Dokumen pendamping: [User Flow](tour-leader-user-flow-2026-10-15.md) · [Acceptance Criteria](tour-leader-acceptance-criteria-2026-10-15.md).

## 1. Tujuan dan landasan

Membantu TL mengetahui **siapa yang seharusnya ikut perpindahan ini, siapa yang sudah diperiksa, dan tindak lanjut apa yang masih terbuka**. Pemeriksaan dicatat per sesi; status sesi sebelumnya tidak menjadi bukti sesi berikutnya. Produk tidak menjamin keselamatan, keberadaan fisik secara otomatis, atau pencegahan peserta tertinggal.

Sumber dasar: [review fitur 14 Oktober](../../../missing-evidence.md#missing-d4659e1d2db7), E01–E06; [findings tour leader](../../../missing-evidence.md#missing-ce2b8c674908), TL-F24–27; [penguatan akademik](../../../missing-evidence.md#missing-5806a0ce04a5), A01–A02. Findings mendukung konteks memantau peserta, keterlambatan, dan perpisahan; belum membuktikan kebutuhan delapan fitur ini atau keunggulan atas praktik existing.

| ID hipotesis | Yang diuji | Fitur terkait |
|---|---|---|
| H01 | Pemeriksaan bernama per sesi mengurangi salah penggunaan status lama | F03–F04 |
| H02 | Daftar kasus terbuka mempermudah tindak lanjut tanpa mencentang hadir terlalu cepat | F05–F06 |
| H03 | Perubahan peserta yang diharapkan terlihat dan dapat dijelaskan | F03, F06 |
| H04 | TL memperoleh manfaat tanpa peserta memasang aplikasi | F01–F08 |

Pembanding evaluasi adalah roster/headcount, WhatsApp, location sharing, serta attendance app existing yang dapat diakses. Daftar fitur ini bukan klaim kebaruan.

## 2. Pengguna, konteks, dan scope

Pengguna primer: TL yang memimpin rombongan multi-stop. Asumsi ukuran untuk prototype: 40 peserta; fixture verifikasi hingga 100 peserta per trip, bukan batas bisnis yang tervalidasi. Peserta adalah subjek roster, bukan pengguna aplikasi MVP. Driver/local guide adalah pihak yang mungkin dihubungi secara manual, bukan role aplikasi.

**P0 / MVP:** F01–F08. **P1 / kandidat berikutnya:** input roster CSV dengan preview, ringkasan melalui Apple Watch/Live Activities, kartu meeting point yang dibagikan secara manual. **P2 / perlu riset dan scope baru:** aplikasi peserta, laporan diri, acknowledgment meeting point, kolaborasi multi-TL dan sinkronisasi. P1/P2 tidak termasuk acceptance gate MVP.

Live GPS, geofence, Bluetooth/UWB otomatis, AR, AI, face recognition, pengambilan lokasi Find My, broadcast darurat, dan backend tidak menjadi dependency MVP. Jika nanti dipilih, masing-masing memerlukan feasibility dan validasi tersendiri.

## 3. Model status dan aturan produk

### Trip dan roster

Trip: Draft → Aktif → Diarsipkan. Nama trip wajib. Participant mempunyai ID stabil, nama tampil wajib, label pembeda opsional (misalnya nomor peserta), serta kontak opsional. Nama sama diperbolehkan; UI menampilkan label/nomor unik agar dapat dibedakan. Tidak meminta paspor, tanggal lahir, foto, atau data kesehatan untuk menjalankan alur inti.

### Session

Session: Draft → Aktif → Ditutup. Satu session aktif maksimum per trip. Session wajib memiliki nama; jenis pilihan: naik kendaraan, pindah lokasi, regrouping, atau lainnya. Lokasi deskriptif dan batas waktu opsional. Batas waktu menyimpan waktu absolut dan zona waktu pilihan; UI selalu menampilkan zona waktu. Lewat batas waktu hanya memberi indikator, tidak mengubah attendance atau menutup sesi.

Pada aktivasi, session menyalin roster sebagai snapshot. Tambahan/perubahan roster berikutnya berlaku untuk sesi mendatang; sesi aktif hanya berubah lewat tindakan eksplisit di sesi itu. Peserta di snapshot tetap mempunyai ID yang sama walaupun nama roster kemudian diedit. Tambahan peserta ke sesi aktif dibuat sebagai entri baru berstatus belum diperiksa; jumlah ringkasan segera dihitung ulang.

### Dua dimensi status peserta

- **Keikutsertaan:** `Diharapkan` atau `Tidak ikut sesi ini`. Tidak ikut memerlukan alasan dan catatan pengaturan yang disepakati TL; ini catatan TL, bukan verifikasi persetujuan pihak lain. Bisa diubah kembali selama sesi aktif.
- **Pemeriksaan:** `Belum diperiksa` atau `Diperiksa TL`. Diperiksa berarti TL mengonfirmasi melalui tindakan eksplisit bahwa peserta telah dilihat pada titik pemeriksaan sesi tersebut. Timestamp dan sumber `TL` disimpan. Pesan “sedang kembali”, telepon, GPS, atau QR tidak otomatis menjadi pemeriksaan.

Keikutsertaan dan pemeriksaan tidak digabung menjadi label “aman”. Mengubah peserta menjadi tidak ikut tidak menghapus jejak pemeriksaan; jika dikembalikan menjadi diharapkan, pemeriksaan perlu diulang. Dalam ringkasan aktif, hanya pemeriksaan terbaru setelah perubahan keikutsertaan terakhir yang berlaku.

### Follow-up

Satu kasus follow-up aktif maksimum per participant per session. Status kasus: `Terbuka`, `Sedang ditangani`, `Selesai`. Catatan alasan, tindakan dan hasil dicatat. Selesai kasus tidak otomatis mencentang peserta. Mencentang peserta tidak otomatis menutup kasus; TL tetap meninjau hasil. Pengaturan ini mencegah kebutuhan bantuan lain tersapu oleh status hadir.

### Angka dan penutupan

`N = semua peserta dalam snapshot` · `E = diharapkan` · `X = tidak ikut` · `V = diperiksa TL yang masih berlaku dalam E` · `U = E − V` · `O = kasus follow-up belum selesai`, termasuk kasus peserta tidak ikut.

Selalu berlaku `N = E + X` dan `E = V + U`. O terpisah dan tidak dijumlahkan sebagai kategori attendance. Filter/search hanya mengubah daftar tampilan, bukan ringkasan sesi.

Sesi dapat ditutup biasa jika E > 0, U = 0, dan O = 0. Jika U > 0 atau O > 0, TL harus meninjau daftar serta memilih tindakan eksplisit **Tutup dengan catatan** dan mengisi alasan; status akhir menyatakan pengecualian, tidak mengubah peserta menjadi diperiksa. Jika E = 0, hanya penutupan dengan catatan tersedia. Batas ini adalah usulan desain untuk diuji bersama prosedur TL.

Istilah UI adalah “Tutup pemeriksaan”, bukan izin bus berangkat. App tidak mengirim perintah ke driver. Sesi ditutup bersifat read-only; kesalahan kemudian dicatat sebagai koreksi beralasan pada riwayat, dengan nilai awal tetap dapat dilihat. Sesi berikutnya selalu mulai baru.

## 4. Feature specifications

### F01 — Buat dan kelola trip

**User story:** Sebagai TL, saya ingin memisahkan daftar dan pemeriksaan setiap perjalanan.

Input: nama trip wajib; tanggal/rute opsional. Output: trip tersimpan lokal, berstatus Draft. Trip menjadi Aktif setelah sesi pertama dimulai. Home menampilkan trip aktif dan arsip. Pengarsipan ditolak saat ada sesi aktif; dapat dilanjutkan setelah menutup sesi. Mengarsipkan tidak menghapus data.

**AC:** AC01–02.

### F02 — Roster peserta

**User story:** Sebagai TL, saya ingin mengidentifikasi peserta yang sedang diperiksa dengan benar.

Tambah satu peserta atau paste daftar satu nama per baris; tampilkan preview dan jumlah sebelum commit. Abaikan baris kosong, trim whitespace, jangan otomatis menggabungkan nama sama. Tambahkan label/nomor pembeda stabil. Kontak opsional; ketidakadaan kontak tidak menghalangi pemeriksaan. Edit/hapus roster hanya mengubah sesi mendatang. Penghapusan roster adalah keluarkan dari roster, bukan menghapus snapshot historis.

**AC:** AC03–06.

### F03 — Buat sesi dan tetapkan peserta yang diharapkan

**User story:** Sebagai TL, saya ingin daftar pemeriksaan sesuai perpindahan saat ini.

Dari trip, buat sesi dengan nama, jenis dan waktu/lokasi opsional; preview semua peserta default Diharapkan dan Belum diperiksa. Tandai tidak ikut dengan alasan/pengaturan, lalu aktifkan. Tidak boleh aktif jika roster kosong. Mulai sesi berikutnya tidak menyalin pemeriksaan atau follow-up sesi lama. Perubahan peserta selama sesi aktif meminta review jumlah sebelum disimpan; tidak dilakukan dari layar ringkasan hanya untuk membuat angka lengkap.

**AC:** AC07–11.

### F04 — Pemeriksaan peserta

**User story:** Sebagai TL, saya ingin mencatat dan mengoreksi pemeriksaan peserta dengan cepat.

Layar menampilkan nama, pembeda, status, sumber/waktu terakhir dan aksi “Tandai diperiksa”. Aksi bersifat set, bukan toggle; tap ulang tidak menambah count atau entri verifikasi ganda. Koreksi melalui aksi terpisah “Batalkan pemeriksaan”, dengan alasan wajib. Search nama/label dan filter Belum diperiksa tersedia. Tidak ada “Tandai semua hadir” pada MVP.

**AC:** AC12–15.

### F05 — Tindak lanjut peserta

**User story:** Sebagai TL, saya ingin mengetahui tindakan yang sudah dilakukan untuk peserta yang belum jelas statusnya.

Dari peserta, buka follow-up; pilih konteks seperti belum kembali, perlu bantuan, atau lainnya, dengan catatan opsional. Laporan via telepon dicatat sebagai laporan, bukan kehadiran. Tambahkan tindakan, ubah Sedang ditangani, lalu Selesai dengan catatan hasil wajib. Jika kontak tersedia, TL dapat membuka composer panggilan; panggilan dilakukan di aplikasi sistem dan hasil tidak ditebak otomatis. Jika tidak tersedia, tampilkan opsi mencatat kontak manual. Multi-PIC realtime tidak termasuk MVP.

**AC:** AC16–19.

### F06 — Review dan tutup pemeriksaan

**User story:** Sebagai TL, saya ingin meninjau seluruh ketidakpastian sebelum mengakhiri pemeriksaan.

Review menampilkan E, V, U, X, O, daftar U, daftar X beserta alasan, dan semua kasus terbuka. Semua baris dapat dibuka untuk koreksi selama sesi aktif. TL memilih penutupan normal atau dengan catatan menurut aturan di atas. Simpan snapshot penutupan dan waktu. Label akhir: “Ditutup—semua peserta yang diharapkan diperiksa” atau “Ditutup dengan catatan”. Kedua label tidak menyatakan keamanan atau keputusan keberangkatan.

**AC:** AC20–23.

### F07 — Riwayat dan koreksi

**User story:** Sebagai TL, saya ingin memahami apa yang dicatat pada setiap perpindahan.

Riwayat per trip berisi sesi, waktu, ringkasan akhir, alasan tidak ikut, follow-up dan koreksi. Event menyimpan ID, participant/session terkait, timestamp, jenis aksi, nilai lama/baru, dan alasan bila disyaratkan. Tidak memakai event lokal sebagai bukti forensik atau tanda tangan resmi. Koreksi sesi ditutup membuat revisi baru dan mempertahankan ringkasan asli; ringkasan versi terbaru diberi label revisi. Koreksi tidak membuka kembali sesi dan tidak mengubah sesi lain.

**AC:** AC24–25.

### F08 — Penyimpanan, pemulihan dan aksesibilitas

**User story:** Sebagai TL, saya ingin pemeriksaan tetap dapat dilakukan tanpa jaringan dan data tidak hilang diam-diam.

Semua aksi P0 menggunakan data lokal. Tampilkan “Tersimpan di perangkat ini”; jangan menampilkan “tersinkron” karena tidak ada sync. Setelah commit berhasil, data bertahan saat app ditutup. Jika gagal simpan, jangan menampilkan sukses; tampilkan error dengan Retry, simpan input sementara dan cegah penutupan berdasar perubahan yang belum tersimpan. App tidak menjamin pemulihan jika perangkat hilang/rusak atau app dihapus. Penghapusan seluruh trip meminta konfirmasi spesifik; tidak tersedia saat sesi aktif, lalu menghapus data turunan lokal. Tidak mengklaim backup cloud.

Status selalu memakai teks dan ikon, bukan warna saja. Kontrol memiliki label VoiceOver spesifik, urutan fokus masuk akal, dan tetap terbaca pada ukuran teks aksesibilitas. Peserta tanpa ponsel tercakup dalam alur yang sama.

**AC:** AC26–30.

## 5. Layar dan data minimum

| Layar | Isi / aksi utama |
|---|---|
| S01 Trips | Trip aktif/arsip, buat trip |
| S02 Trip Detail | Roster, sesi aktif, riwayat |
| S03 Roster Editor | Input/paste, preview, label pembeda |
| S04 Session Setup | Jenis/nama, expected roster, alasan tidak ikut |
| S05 Active Session | Ringkasan E/V/U/X/O, daftar, search/filter, pemeriksaan |
| S06 Participant Detail | Status, catatan, follow-up, kontak opsional, koreksi |
| S07 Review | Daftar belum diperiksa/pengecualian/kasus, tutup |
| S08 History Detail | Snapshot, event, revisi beralasan |
| S09 Trip Data Controls | Arsip dan hapus lokal |

Entitas minimum: Trip, Participant, Session, SessionParticipant snapshot, FollowUp, Event, ClosureSnapshot dan CorrectionRevision. Relasi memakai ID, bukan nama. Penyimpanan update state dan event satu aksi harus atomik: tidak boleh count berubah tanpa event atau event ada tetapi state tidak berubah. Tentukan teknologi penyimpanan saat implementation planning.

## 6. Arah Apple dan release gate

Usulan basis iOS: SwiftUI dan penyimpanan lokal. OS minimum, perangkat sasaran, batas roster final dan pilihan persistence belum diputuskan. P0 tidak memerlukan izin lokasi, kamera, mikrofon atau kontak; nomor dapat diinput sukarela dan composer panggilan dapat dipakai tanpa membaca address book. Apple Watch/ActivityKit bukan release gate P0. Dokumen ini tidak melakukan verifikasi API atau App Review baru.

**Gate correctness:** seluruh AC P0 lulus pada build/perangkat sasaran, tanpa status stale lintas sesi, penghitungan ganda atau sukses penyimpanan palsu. **Gate usability/value:** TL relevan mencoba skenario normal dan pengecualian, dibandingkan praktik existing; catat waktu setup, waktu pemeriksaan, ketepatan identifikasi dan salah status. Target perbaikan waktu ditetapkan setelah baseline, bukan direkayasa sekarang. Lulus AC bukan bukti dampak dunia nyata.

## 7. Pertanyaan sebelum scope dibekukan

- Apakah TL sasaran memeriksa saat naik bus, regrouping, atau keduanya? Apa arti selesai menurut prosedur mereka?
- Seberapa sering daftar peserta yang diharapkan berbeda dan siapa berwenang menyepakatinya?
- Apakah mencentang nama justru lebih lambat daripada cara sekarang? Bagaimana peserta bernama sama dibedakan?
- Apakah satu perangkat memadai atau kolaborasi co-leader merupakan kebutuhan inti?
- Apakah pencatatan pengecualian membantu atau menciptakan rasa percaya diri yang keliru?

Jika jawaban mengubah konteks inti, revisi spesifikasi dan AC bersamaan sebelum implementasi. Status dokumen tetap draft; fitur di sini tidak otomatis menjadi keputusan tim.
