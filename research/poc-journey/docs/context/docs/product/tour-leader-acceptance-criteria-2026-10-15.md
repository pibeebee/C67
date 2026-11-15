# Acceptance Criteria — Tour Leader Group Management

Versi 0.1 · 15 Oktober 2026. Semua AC di bawah merupakan usulan gate P0, **belum dieksekusi atau lulus**. Fitur P1/P2 tidak termasuk.

Rujukan: [Feature Specification](tour-leader-feature-specification-2026-10-15.md) · [User Flow](tour-leader-user-flow-2026-10-15.md).

Gunakan format Given–When–Then. E/V/U/X/O mengikuti definisi spesifikasi. Data di bawah sintetis; pengujian tidak memakai data peserta nyata. Setelah perangkat sasaran diputuskan, AC harus dieksekusi pada build dan versi OS yang dicatat. Error persistence memerlukan injection/harness, bukan sekadar mematikan internet.

## F01 — Trip

**AC01 — Validasi dan penyimpanan trip.** Given form trip baru; When nama kosong/whitespace dan Simpan dipilih; Then simpan ditolak dengan pesan pada field, input lain dipertahankan. When nama valid disimpan; Then satu trip Draft muncul dan tetap tersedia setelah relaunch.

**AC02 — Siklus arsip.** Given trip dengan sesi aktif; When TL mencoba arsip; Then ditolak dengan tautan kembali ke sesi. Given semua sesi ditutup; When diarsipkan; Then trip muncul di Arsip dengan roster/riwayat utuh. When dipulihkan; Then trip kembali ke daftar aktif tanpa mengubah status sesi lama.

## F02 — Roster

**AC03 — Paste dan preview.** Given input berisi `Ayu`, baris kosong, ` Budi `, dan `Ayu`; When dipreview; Then ada tiga peserta, whitespace tepi dibuang dan kedua Ayu dipertahankan dengan ID/nomor pembeda. When preview dibatalkan; Then roster tidak berubah. When dikonfirmasi; Then tepat tiga entri tersimpan.

**AC04 — Field dan kontak opsional.** Given tambah/edit peserta; When nama kosong; Then simpan ditolak. When nama valid tanpa kontak; Then simpan, pemeriksaan dan follow-up manual tetap tersedia; app tidak meminta akses address book.

**AC05 — Identitas dan snapshot.** Given dua peserta bernama sama dan satu sesi aktif; When nama roster pertama diedit atau peserta dikeluarkan dari roster utama; Then ID keduanya tetap berbeda, snapshot sesi aktif/historis tidak berubah diam-diam, dan preview sesi mendatang memakai roster terbaru.

**AC06 — Fixture 100 peserta.** Given roster sintetis 100 peserta; When disimpan, direlaunch, dicari dan difilter; Then semua ID utuh, tidak ada entri hilang/ganda, peserta pertama/tengah/terakhir dapat dibuka. Ini gate fungsi, bukan klaim performa terukur.

## F03 — Session dan keikutsertaan

**AC07 — Prasyarat sesi.** Given trip tanpa peserta atau nama sesi kosong; When aktivasi dicoba; Then ditolak dengan alasan yang sesuai. Given satu sesi aktif; When sesi kedua hendak diaktifkan pada trip sama; Then ditolak dan sesi pertama tidak berubah.

**AC08 — Reset lintas sesi.** Given sesi sebelumnya mempunyai peserta diperiksa, tidak ikut, dan kasus terbuka; When sesi baru dibuat; Then roster terkini dipreview dengan semua default Diharapkan/Belum diperiksa, tanpa follow-up yang disalin. Riwayat sesi lama tetap utuh.

**AC09 — Tidak ikut dan kembali ikut.** Given N=40, E=40, V=10, U=30, X=0; When satu peserta yang telah diperiksa dijadikan tidak ikut tanpa alasan/pengaturan; Then ditolak. When alasan dan pengaturan diisi dan perubahan dikonfirmasi; Then E=39, V=9, U=30, X=1 dan jejak lama tetap ada. When dikembalikan menjadi Diharapkan; Then E=40, V=9, U=31, X=0; pemeriksaan baru diperlukan.

**AC10 — Penambahan ke sesi aktif.** Given sesi aktif dengan snapshot 40 peserta; When peserta baru hanya ditambahkan ke roster utama; Then N sesi tetap 40. When TL secara eksplisit menambahkan peserta itu ke sesi dan mengonfirmasi; Then N/E/U masing-masing bertambah satu, V tidak berubah dan ada event penambahan. Menambahkan ID yang sudah ada ditolak tanpa duplikasi.

**AC11 — Waktu dan zona waktu.** Given batas waktu sesi disimpan beserta zona waktu; When zona waktu perangkat berubah atau batas terlewati; Then waktu absolut tersimpan tidak berubah, UI tetap menampilkan zona yang dimaksud dan indikator lewat waktu sesuai; tidak ada attendance atau penutupan otomatis.

## F04 — Pemeriksaan

**AC12 — Pemeriksaan eksplisit dan idempotensi.** Given peserta Diharapkan/Belum diperiksa; When TL memilih Tandai diperiksa dan commit sukses; Then status menjadi Diperiksa TL, sumber/waktu tercatat, V bertambah satu dan U berkurang satu. When aksi sama ditap dua kali atau di-Retry dengan ID sama; Then hanya satu perubahan dan satu event pemeriksaan tersimpan.

**AC13 — Koreksi salah centang.** Given peserta telah diperiksa; When Batalkan pemeriksaan dipilih tanpa alasan; Then tidak tersimpan. When alasan diberikan dan dikonfirmasi; Then peserta kembali Belum diperiksa, V berkurang dan U bertambah satu, dengan nilai lama/baru tercatat. Aksi pembatalan dialog tidak mengubah data.

**AC14 — Search/filter dan ringkasan global.** Given 40 peserta dan dua Ayu dengan nomor berbeda; When mencari Ayu atau salah satu nomor; Then entri sesuai dapat dibedakan dan dibuka tanpa mengubah peserta lain. When filter aktif hanya menampilkan dua peserta; Then ringkasan masih memakai seluruh sesi dan selalu memenuhi N=E+X serta E=V+U.

**AC15 — Tidak ikut bukan pemeriksaan.** Given peserta Tidak ikut sesi ini; When detail dibuka; Then Tandai diperiksa untuk ringkasan E tidak tersedia sampai keikutsertaan dikembalikan menjadi Diharapkan. Riwayat pemeriksaan sebelumnya tetap bisa dilihat, dengan label tidak berlaku pada status sekarang.

## F05 — Follow-up

**AC16 — Satu kasus aktif dan kontak fallback.** Given peserta tanpa kontak; When Buat tindak lanjut dipilih; Then kasus manual dapat dibuat tanpa memanggil aplikasi telepon. When dipilih lagi sebelum kasus selesai; Then kasus aktif yang sama terbuka, bukan kasus duplikat. Given kontak tersedia; When Hubungi dipilih; Then composer panggilan dapat dibuka, dan attendance/hasil kasus tidak berubah otomatis.

**AC17 — Laporan bukan hadir.** Given peserta Belum diperiksa dengan follow-up Terbuka; When catatan “peserta menelepon, sedang kembali” disimpan dan status menjadi Sedang ditangani; Then U/V tidak berubah, kasus tetap termasuk O dan sumber laporan terlihat sebagai catatan TL.

**AC18 — Penyelesaian independen.** Given peserta dengan kasus aktif; When ditandai diperiksa; Then kasus tidak otomatis selesai. When kasus selesai dengan catatan hasil wajib; Then O berkurang satu tanpa mengubah attendance. When mencoba selesai tanpa hasil; Then ditolak. Kasus pada peserta yang dijadikan Tidak ikut tetap masuk O sampai ditutup eksplisit.

**AC19 — Tindakan dan retry.** Given kasus Sedang ditangani; When tindakan baru disimpan; Then timestamp dan isi muncul berurutan di detail. When penyimpanan gagal lalu Retry; Then tindakan tersimpan sekali, tidak hilang/ganda, dan status berhasil hanya muncul setelah commit.

## F06 — Review dan penutupan

**AC20 — Penutupan normal.** Given E=38, V=38, U=0, X=2, O=0; When membuka Review; Then nama/alasan dua peserta tidak ikut terlihat dan penutupan normal tersedia. When dikonfirmasi dan disimpan; Then sesi read-only, snapshot sesuai angka itu dan status Ditutup—semua peserta yang diharapkan diperiksa. App tidak mengirim perintah keberangkatan atau menyatakan semua aman.

**AC21 — Kasus terbuka walau hitungan lengkap.** Given E=38, V=38, U=0, O=1; When Review dibuka; Then penutupan normal tidak tersedia dan kasus terbuka terlihat. TL dapat kembali menyelesaikan kasus atau memilih Tutup dengan catatan.

**AC22 — Pengecualian wajib ditinjau.** Given U>0 atau O>0; When Tutup dengan catatan dipilih tanpa alasan; Then penutupan ditolak. When alasan diisi dan dikonfirmasi; Then snapshot menyimpan daftar dan angka yang belum selesai, status Ditutup dengan catatan, tanpa mengubah attendance/kasus menjadi selesai. Given E=0; Then hanya penutupan dengan catatan tersedia, dengan informasi tidak ada peserta diharapkan.

**AC23 — Cancel dan konsistensi snapshot.** Given Review terbuka; When dialog tutup dibatalkan; Then sesi tetap aktif. When data sesi berubah sebelum commit penutupan; Then ringkasan dihitung ulang dan harus ditinjau lagi, atau penutupan ditolak untuk review ulang. Tidak boleh menyimpan ringkasan yang berbeda dari state committed saat ditutup.

## F07 — Riwayat

**AC24 — Immutability dan revisi.** Given sesi ditutup; When dibuka; Then aksi pemeriksaan langsung tidak tersedia. When TL menambahkan koreksi beralasan; Then revisi dengan nilai awal/baru, waktu dan alasan tersimpan, ringkasan awal tetap dapat dibaca, versi terbaru ditandai revisi, dan sesi lain tidak berubah. Koreksi tanpa alasan ditolak.

**AC25 — Jejak aksi dan isolasi.** Given aksi committed berupa pemeriksaan, pembatalan, keikutsertaan, penambahan peserta, follow-up, atau penutupan; When riwayat dibuka; Then event terkait mempunyai ID, session/participant yang benar, waktu dan perubahan relevan. Given trip lain; Then daftar/angka/riwayatnya tidak ikut berubah.

## F08 — Penyimpanan, pemulihan, dan akses

**AC26 — Offline tanpa izin tambahan.** Given airplane mode, izin lokasi/kamera/mikrofon/kontak tidak diberikan; When TL menjalankan F01–F07 menggunakan data lokal; Then alur inti tetap bekerja, tanpa permintaan izin tersebut. Composer panggilan tidak dijadikan syarat karena tidak berfungsi di semua kondisi. UI menyatakan Tersimpan di perangkat ini, bukan tersinkron.

**AC27 — Relaunch setelah commit.** Given sesi aktif mempunyai pemeriksaan, pengecualian dan follow-up berhasil disimpan; When app dihentikan dan dibuka lagi; Then sesi aktif yang sama dapat dilanjutkan dengan angka, waktu dan event utuh. Draft input yang belum disimpan tidak dianggap data committed.

**AC28 — Kegagalan persistence dan atomicity.** Given simpan dipaksa gagal melalui harness; When TL mengubah status atau menutup sesi; Then tidak ada pesan sukses, perubahan count/snapshot/event tidak committed sebagian, input tetap tersedia dan error/Retry terlihat. Penutupan tidak memakai perubahan yang gagal. When Retry berhasil; Then state dan event committed bersama tepat satu kali.

**AC29 — Penghapusan trip.** Given sesi masih aktif; When Hapus trip dicoba; Then ditolak. Given trip tanpa sesi aktif; When Hapus dipilih; Then dialog menyebut nama trip dan cakupan roster/sesi/riwayat lokal. Cancel tidak mengubah data. Konfirmasi menghapus semua data turunan trip tersebut setelah commit sukses, tetap tidak menghapus trip lain, dan relaunch tidak mengembalikannya. Tidak menjanjikan pemulihan atau penghapusan salinan eksternal.

**AC30 — Aksesibilitas alur inti.** Given VoiceOver dan ukuran teks aksesibilitas pada perangkat sasaran; When TL menjalankan setup, pemeriksaan, koreksi, follow-up dan review; Then kontrol dapat ditemukan/dijalankan, nama dan pembeda peserta dibacakan, status bukan warna saja, angka dan error terbaca, tombol tidak saling menutupi, dan teks tidak memotong informasi penting tanpa cara membacanya. Verifikasi manual pada perangkat/Simulator dicatat, bukan hanya inspeksi source.

## Skenario end-to-end dan status evaluasi

| ID | Fixture/skenario | AC terkait | Status |
|---|---|---|---|
| T01 | 40 peserta, dua tidak ikut, 38 diperiksa, tutup normal | 03, 08–09, 12, 20, 25 | Belum diuji |
| T02 | Nama sama, salah centang, koreksi, search | 05, 12–15 | Belum diuji |
| T03 | Dua belum diperiksa, satu lapor sedang kembali, follow-up | 16–19, 21–22 | Belum diuji |
| T04 | Peserta kembali ikut dan peserta baru ditambahkan saat aktif | 09–10, 14, 23 | Belum diuji |
| T05 | Airplane mode, relaunch, simpan gagal dan retry | 12, 19, 26–28 | Belum diuji |
| T06 | Tutup dengan catatan, revisi riwayat, sesi berikutnya | 08, 22, 24–25 | Belum diuji |
| T07 | Semua tidak ikut, arsip/pulihkan, hapus/cancel | 02, 22, 29 | Belum diuji |
| T08 | 100 peserta dan alur aksesibilitas | 06, 14, 30 | Belum diuji |

## Evaluasi manfaat terpisah dari acceptance

Saat concept/usability test, rekam waktu setup dan waktu per sesi, ketepatan menentukan peserta yang diharapkan, identifikasi peserta belum diperiksa, salah status, tindak lanjut duplikat, dan usaha koreksi. Bandingkan dengan alat TL yang biasa dipakai pada skenario setara dan variasikan urutan percobaan. Tentukan ambang manfaat setelah baseline. Tidak menafsirkan preferensi, AC yang lulus, atau simulasi singkat sebagai bukti mencegah orang tertinggal.
