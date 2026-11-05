# C6 Travel Diary — PoC “Same Place, Different Time”

Tanggal: 20 Oktober 2026. Acuan produk: `C6-travel-diary-cerita-lengkap-cbl-2026-10-20.md` di workspace C6.

## Yang dapat dicoba

1. Buka satu peta kenangan dan ketuk pin foto atau kartu di bagian bawah.
2. Baca foto/ilustrasi serta cerita pembuat. Aktifkan lokasi saat ingin mencoba kehadiran di pin.
3. Di luar radius, tombol menambahkan jejak terkunci. Saat posisi cukup akurat dan berada di area pin, panel berubah warna dan tombol tersedia.
4. Pilih foto galeri atau ambil foto dengan kamera. Foto tidak harus baru, tidak harus memiliki EXIF lokasi, dan tidak harus meniru sudut pembuat.
5. Isi nama dan tekan **Unggah jejak**. Aplikasi memeriksa posisi saat tombol ditekan, kemudian menunggu sampel GPS baru yang diukur setelah penekanan itu. Sampel kedatangan sebelumnya tidak dipakai sebagai izin unggah permanen.
6. Bila validasi dan penulisan lokal berhasil, lihat kartu **Then vs. Now**. Hasil diberi keterangan tersimpan lokal dan belum dikirim ke teman/server.

## Menyiapkan lokasi uji sendiri

Jalankan scheme `poc-c67` seperti biasa. Layar awal sekarang adalah Travel Diary.

- Pilih **Atur pin uji** di toolbar.
- Isi nama tempat, pembuat, tanggal, cerita, dan foto pembuat dari perjalanan lama jika ada. Tanpa foto, tampil ilustrasi yang diberi label jelas.
- Pilih **Tentukan pin di peta** lalu geser peta dan konfirmasi titik. Alternatif: **Pakai lokasi saya sekarang**, setelah lokasi aktif dan akurat.
- Radius awal 100 m, dapat diubah 50–300 m untuk eksperimen. Nilai ini belum merupakan keputusan radius produk.
- Simpan. Coba dari luar area, mendekat ke pin, lalu tambahkan foto.

Mengubah koordinat/radius membuat identitas pin aktif yang baru. Jejak lama tetap ada dalam arsip lokal dengan koordinat dan identitas sebelumnya; tidak dipindahkan ke lokasi baru. PoC belum menyediakan layar penjelajah arsip pin lama.

## Aturan lokasi dan penyimpanan

- Izin lokasi hanya diminta setelah pengguna mengaktifkan lokasi. Pengambilan lokasi baru ini hanya berjalan ketika app aktif; dihentikan saat app tidak aktif atau berada di background.
- Umur sampel maksimum 5 detik. Sampel invalid, waktu terlalu jauh di masa depan, atau Lokasi Tepat yang tidak aktif tidak membuka tombol unggah.
- Akurasi horizontal harus <= minimum(35 m, setengah radius pin). Untuk mengurangi penerimaan di batas, jarak + akurasi harus berada dalam radius; area yang tumpang tindih batas menjadi keadaan “belum cukup pasti”. Ini kebijakan eksperimen, bukan jaminan akurasi GPS.
- Saat unggah, posisi di layar diperiksa lagi. Selanjutnya hanya sampel bertimestamp >= waktu penekanan unggah yang bisa diterima; jika tidak ada sampel baru dalam 15 detik, tampil kegagalan dan foto pratinjau tetap tersedia untuk dicoba lagi.
- Pemeriksaan akhir dilakukan lagi sebelum penulisan. Kegagalan penulisan tidak menampilkan sukses. Tidak ada antrean yang otomatis mengunggah ketika sudah meninggalkan lokasi.
- Foto disimpan sebagai JPEG yang dinormalisasi. Arsip JSON lokal terpisah di `Application Support/C6TravelDiary/memories-v1.json`; tidak memakai atau mengubah penyimpanan eksperimen lama. Ini belum implementasi SwiftData atau sinkronisasi CloudKit.
- Semua lokasi di iOS Simulator, serta sumber yang ditandai sebagai simulasi oleh Core Location, diberi label simulasi. Hasil simulator tidak membuktikan kunjungan fisik.
- Ini pengujian berbasis estimasi posisi perangkat, bukan mekanisme anti-spoofing atau pengesahan server.

## Cakupan

PoC ini sengaja hanya satu peta/satu pin aktif, dengan kamera/galeri, perubahan keadaan berdasarkan jarak, validasi lokasi ketika unggah, penyimpanan lokal, dan kartu kenangan berpasangan. Peta dasar dapat memerlukan internet/cache sistem. Belum ada berbagi lintas perangkat, daftar banyak peta, impor EXIF otomatis, Live Activities, kalender, cuaca, atau pengingat. Tidak ada poin, badge, leaderboard, likes, follower counts, atau komentar.

## File dan cara membuka eksperimen sebelumnya

`ContentView.swift` sekarang mengarahkan ke `TravelDiaryView`. Implementasi awal `ContentView`, termasuk `ErrorNotice`, dipertahankan di `Features/TravelDiary/LegacyPOCView.swift`; hanya nama tipe layar awal yang diganti untuk menghindari duplikasi. File fitur/core lama dan entry point app tidak dihapus.

Untuk membuka kembali eksperimen sebelumnya, tambahkan launch argument `--legacy-poc` di **Edit Scheme → Run → Arguments**. Hapus argument itu untuk kembali ke Travel Diary. UI tests lama yang mengharapkan tampilan awal sebelumnya memerlukan argument tersebut; bukan bagian dari tes Travel Diary.

Teks izin lokasi/kamera diperbarui untuk mencakup alur baru. Deployment target iOS 18 dan konfigurasi signing yang sudah ada dipertahankan.

## Demo UI tanpa berjalan ke lokasi (Debug saja)

Tambahkan launch arguments:

```text
--ui-testing --diary-ui-testing --diary-demo inside --diary-seed-photo
```

Ganti `inside` dengan `outside` atau `uncertain` untuk melihat keadaan terkunci. `--diary-seed-photo` menyiapkan gambar fixture hanya pada mode UI testing. Mode demo memakai arsip in-memory, diberi label simulasi, dan tidak menulis ke arsip kenangan normal. Jangan memakai hasilnya sebagai bukti uji GPS.

Untuk mencoba Core Location melalui Simulator, hilangkan `--diary-demo ...`, aktifkan izin lokasi dan tentukan lokasi Simulator melalui Xcode atau `simctl`. Tes callback unggah memerlukan update baru, bukan hanya satu sampel lama. Gunakan lintasan lambat yang tetap berada di sekitar pin:

```sh
xcrun simctl location <SIMULATOR_UDID> start --speed=0.05 --interval=1 -- -6.175392,106.827153 -6.175592,106.827153
```

## Uji lanjutan pada iPhone fisik

Gunakan pin yang dapat dicapai dengan aman dan foto milik peserta uji. Coba di luar/dalam/dekat batas radius, tutup-buka app, izin lokasi ditolak, Lokasi Tepat dimatikan, serta keluar area setelah membuka pratinjau foto. Catat apakah pengguna yang benar-benar hadir sering terhalang akurasi GPS; parameter radius dan akurasi perlu disesuaikan berdasarkan temuan lapangan.

Dua hal dinilai terpisah: (1) mekanik GPS dan penyimpanan bekerja; (2) apakah orang ingin menyusul kenangan temannya dan merasa kartu hasilnya bermakna. Build atau simulator yang berhasil hanya menjadi bukti untuk lapisan yang diuji.

## Rujukan implementasi

- [Core Location delegate dan penanganan sampel cache](https://developer.apple.com/documentation/corelocation/cllocationmanagerdelegate)
- [Akurasi horizontal lokasi](https://developer.apple.com/documentation/corelocation/cllocation/horizontalaccuracy)
- [Siklus requestLocation dan continuous updates](https://developer.apple.com/documentation/corelocation/cllocationmanager/requestlocation())
- [Photos picker untuk SwiftUI](https://developer.apple.com/documentation/photokit/bringing-photos-picker-to-your-swiftui-app)
