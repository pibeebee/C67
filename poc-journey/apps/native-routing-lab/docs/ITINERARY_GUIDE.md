# POC 0.5 — rundown, lokasi kegiatan & Apple Calendar

15 Oktober 2026 · versi 0.5 build 7 · iOS 18+.

## Di iPhone tour leader

1. **Rombongan → Rundown perjalanan → +**.
2. Isi nama kegiatan, waktu mulai/selesai dan catatan opsional. Zona waktu disimpan bersama kegiatan; editor menampilkan waktu dalam zona kegiatan tersebut. Batas POC 50 kegiatan, judul 80 karakter, catatan 2000 karakter; total payload maksimal 200 KB.
3. Pilih **Pilih lokasi di peta**. Cari tempat/alamat dan pilih hasil, atau ketuk peta. Alternatif akses tombol: geser peta lalu **Pilih titik tengah**. Beri nama lokasi seperti “Parkir B, pintu keluar”. **Lokasi saya** memusatkan peta pada sampel lokal jika izin/GPS tersedia. Lokasi opsional; tanpa lokasi kegiatan tetap bisa disimpan dan diekspor ke Calendar.
4. **Gunakan lokasi → Simpan**. Membatalkan pemilih/editor tidak menyimpan draft. Titik kegiatan tidak otomatis menjadi meeting point.
5. Ketuk kegiatan untuk membuka detail. **Lihat pada peta** memfokuskan pin kegiatan pada peta rombongan. Pin kegiatan berbentuk kalender/flag persegi indigo; pin orang tetap lingkaran. **Daftar** pada peta menyediakan daftar kegiatan dan orang, termasuk kegiatan tanpa koordinat (tidak dibuatkan pin perkiraan).
6. Jika kegiatan menjadi titik berkumpul, pilih **Jadikan titik berkumpul aktif → Jadikan aktif**. Lokasi kegiatan menjadi meeting point dan waktu mulai ditampilkan sebagai waktu berkumpul. Tindakan ini tidak menandai peserta hadir, tidak membuat pemeriksaan baru, dan tidak menghapus pemeriksaan sesi berjalan.
7. Edit/hapus dari detail kegiatan. Mengedit lokasi/waktu kegiatan aktif ikut memperbarui titik/waktu aktif; menghapus kegiatan aktif atau menghapus lokasinya mengosongkan meeting point. Memilih meeting point manual melepaskan hubungan ke kegiatan aktif.

## Meeting point tanpa kegiatan

**Ikon pengaturan kanan atas Rombongan → Pilih meeting point di peta → Gunakan lokasi → Simpan meeting point**. Pilih radius indikator dan nama tempat; tidak perlu memasukkan koordinat. **Hapus meeting point** mengosongkannya. Perjalanan baru tetap tidak mempunyai pin bawaan. Titik/riwayat lama tetap dimuat. Jika perangkat sedang bergabung sebagai peserta, pengaturan TL ini tidak dapat menulis data.

## Di iPhone peserta

Setelah QR terhubung, buka **Peserta → Rundown perjalanan**. Peserta dapat melihat jadwal, catatan, lokasi, kegiatan aktif dan detail pin peta, serta menambahkan salinan ke Calendar sendiri. Peserta tidak dapat mengedit rundown atau memilih kegiatan aktif untuk rombongan.

**Rundown dan meeting point kini diperbarui melalui CloudKit**, tanpa pairing ulang hanya karena jadwal berubah. Kanalnya terpisah dari payload GPS dalam share privat TL yang sama. TL tidak perlu memulai GPS untuk mengirim rundown. Menghentikan sesi lokasi TL membersihkan koordinat GPS, tetapi rundown tetap tersedia selama koneksi share masih tersimpan. Menghapus koneksi TL/Stop peserta mencabut kanalnya; salinan rundown lokal dapat tetap ada sebagai riwayat, dengan status pembaruan terakhir.

- Update kedua sisi ke **0.5 build 7**. QR tetap protokol versi 3; koneksi 0.4.1 yang sudah lengkap dipakai kembali. Tidak perlu mengganti perjalanan/mereset roster untuk mendapatkan fitur ini.
- Pairing baru menyiapkan versi rundown awal pada share TL. Setelah koneksi selesai, peserta mencoba mengambilnya.
- TL menerbitkan perubahan saat app aktif; retry otomatis sekitar 15 detik ketika tab Rombongan aktif. Peserta memeriksa pembaruan sekitar 15 detik ditambah waktu jaringan saat tab Peserta foreground, termasuk layar rundown/peta di dalamnya. **Sinkronkan sekarang/Refresh** meminta percobaan ulang.
- Status **tersimpan lokal** berbeda dari **tersimpan di kanal cloud**. Berhasil menulis cloud tidak membuktikan semua peserta sudah membaca/mengakui perubahan. Tidak ada tanda sudah dibaca pada iterasi ini.
- Saat offline, perubahan TL tersimpan lokal untuk percobaan berikutnya. Peserta mempertahankan salinan terakhir dengan peringatan mungkin lama. Jangan menganggap jadwal sudah diterima hanya karena penyimpanan lokal berhasil.
- Penghapusan meeting point/kegiatan disebarkan melalui snapshot versi lebih baru, sehingga perangkat peserta yang kembali online dapat mengosongkan pin lama. Versi lebih lama tidak menimpa snapshot lebih baru. Data dengan run salah, ID duplikat, waktu/lokasi invalid atau konflik versi ditolak.
- Tidak ada push/background sync baru. Perubahan kalender, rundown dan lokasi tidak dijanjikan realtime. Jika TL offline, jadwal tidak bisa sampai ke peserta sampai koneksi pulih.

## Tambahkan ke Apple Calendar

Dari detail kegiatan: **Tambahkan ke Calendar → editor native Apple → Add/Simpan**. Pengguna meninjau nama, waktu, catatan, lokasi dan kalender tujuan. **Cancel/Batal** tidak mencatat ekspor sebagai berhasil.

Implementasi memakai `EKEventEditViewController` pada iOS 18+ tanpa meminta full calendar access atau membaca event pribadi lain. Kegiatan tetap sumber utama di aplikasi. Calendar menyimpan salinan lokal sesuai pilihan pengguna, bukan kanal sinkronisasi antaranggota.

- App menyimpan receipt ekspor pada iPhone itu hanya setelah callback `.saved`, bukan setelah editor dibuka. Receipt tidak ikut dikirim ke peserta lain.
- Jika pernah diekspor, tombol berikutnya menyebut **Tambahkan salinan baru** dengan konfirmasi kemungkinan duplikat. App tidak membaca apakah event lama masih ada di Calendar.
- Perubahan/hapus kegiatan aplikasi tidak otomatis mengedit/hapus salinan Calendar. Perubahan di Calendar juga tidak diimpor ke rundown. Pengguna dapat mengedit field di editor native, sehingga salinan bisa berbeda dari kegiatan aplikasi.
- Izin Calendar yang ditolak atau kalender tujuan yang tidak tersedia tidak boleh menghalangi penggunaan rundown/peta; hanya hasil penyimpanan editor yang dianggap konfirmasi. Kegagalan izin/save dan receipt pada Calendar akun nyata masih perlu pengujian perangkat fisik.
- Ekspor dari demo diberi catatan **SIMULASI**. Jangan memakai data demo sebagai jadwal perjalanan nyata.

## Demo satu perangkat

**Rombongan → Demo → Satu peserta belum kembali → Muat skenario demo**. Rundown demo berisi **Kembali ke bus**, **Kunjungan museum**, dan **Waktu bebas** (tanpa lokasi). Buka detail, pilih lokasi melalui peta, aktifkan kegiatan dengan konfirmasi, dan lihat pin orang/kegiatan bersama. Tab Peserta dalam Simulasi menyediakan tampilan rundown baca-saja untuk demo. Demo bukan bukti CloudKit/GPS fisik.

## Implementasi & batas verifikasi

Tidak ada server/dependency baru. SwiftData menyimpan snapshot/version/receipt lokal. CloudKit menyimpan record anak `JourneyPlan` dengan tipe record `LatestLocation` dan field `payload` yang sudah ada, parent pada root share TL. Payload rundown tidak memuat roster, posisi peserta, receipt Calendar atau koordinat GPS TL. Akses peserta tetap read-only. Record rundown tidak dibersihkan oleh Begin/Stop GPS yang hanya menyentuh record lokasi.

Belum ada impor Calendar, sinkronisasi Calendar dua arah, push notifikasi, ETA/rute, persetujuan sudah membaca perubahan, atau pemeriksaan kehadiran otomatis. Skala 20 perangkat, penambahan child record ke share lama, ACL server, geocoding/search jaringan, konflik nyata dan sinkronisasi dua akun tetap perlu uji iPhone. [Verifikasi 0.5](verification/VERIFICATION_V5.md) memisahkan tes model, UI native, dan cloud fisik.

## Rujukan Apple

- [MapReader](https://developer.apple.com/documentation/mapkit/mapreader) dan [MKLocalSearch](https://developer.apple.com/documentation/mapkit/mklocalsearch): pemilihan koordinat serta pencarian tempat.
- [Akses EventKit](https://developer.apple.com/documentation/eventkit/accessing-the-event-store): editor EventKitUI tanpa akses luas kalender pada iOS 17+.
- [EKEvent.structuredLocation](https://developer.apple.com/documentation/eventkit/ekevent/structuredlocation): koordinat kegiatan.
- [EKEventEditViewDelegate](https://developer.apple.com/documentation/eventkitui/ekeventeditviewdelegate): membedakan saved dan canceled.

## Uji dua iPhone yang perlu dilakukan

1. TL dan peserta memakai akun iCloud berbeda dan build/environment CloudKit Development yang sama. Gunakan koneksi QR 0.4.1 yang sudah lengkap untuk menguji kompatibilitas, atau hubungkan lewat QR baru.
2. TL menambahkan kegiatan dengan lokasi sementara **GPS TL tetap OFF**. Buka rundown peserta, pilih Sinkronkan sekarang; nama/waktu/tempat harus sama dan dapat dipilih di peta.
3. TL menjadikan kegiatan aktif. Peserta harus menerima titik dan waktu berkumpul terbaru tanpa scan ulang. Catat waktu perubahan dan waktu peserta menerima; ini bukan klaim interval tetap.
4. Putus jaringan TL, edit kegiatan, pastikan status menyatakan tersimpan lokal/belum terkirim. Sambungkan lagi, sinkronkan, lalu refresh peserta. Tidak boleh menampilkan versi lama sebagai perubahan terbaru.
5. Hapus titik/kegiatan aktif pada TL. Setelah peserta berhasil mengambil versi baru, pin aktif harus hilang. Kegiatan lain dan pemeriksaan tidak boleh berubah.
6. Start kemudian Stop GPS TL. Rundown tetap bisa diambil, sementara koordinat GPS mengikuti aturan Stop/expiry yang sudah ada.
7. Putuskan kanal satu peserta. Akun itu tidak boleh mengambil update baru; peserta lain tetap menerima rundown. Uji akun ketiga yang tidak diundang untuk membuktikan ACL server.
8. Ekspor kegiatan di iPhone ke Calendar dengan konfirmasi nyata, lalu cek Calendar tujuan. Ulangi Batal dan penolakan/kegagalan penyimpanan; aplikasi tidak boleh mengklaim saved. Ubah kegiatan dan cek pesan salinan Calendar belum diperbarui, tanpa mengedit event lama secara diam-diam.
