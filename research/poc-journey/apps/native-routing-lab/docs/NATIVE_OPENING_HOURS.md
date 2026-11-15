# Jam operasional tujuan — PoC C67

Perubahan kode 3 November 2026 awalnya disimpan tanpa pengujian, sesuai instruksi saat itu. Setelah pengguna meminta testing, build Simulator, pembandingan enam algoritme dan alur live baseline/enumerasi dijalankan melalui UI pada hari yang sama. Jam buka diterapkan, tetapi optimasi masih dapat memilih waktu menunggu panjang. Lihat [laporan pengujian dan keterbatasannya](verification/OPENING_HOURS_JAKARTA_REPORT_2026-11-03.md). Hasil uji Jakarta sebelum penambahan jam operasional tetap menjadi catatan historis terpisah.

## Mengisi melalui aplikasi

1. Buka **Rencana → pilih tujuan → Jam operasional**. Form hanya ditampilkan untuk peran **Kunjungan**; titik transfer tidak memakai batas kunjungan.
2. Aktifkan **Jam buka diketahui** dan isi waktunya. Jika hanya mengetahui jam buka, biarkan **Jam tutup diketahui** nonaktif. Berlaku juga sebaliknya.
3. Jika jam tutup diketahui, aktifkan dan isi waktunya. Gunakan **Tutup pukul 24.00** untuk akhir hari. Tempat yang diketahui buka sepanjang hari dapat diisi 00.00–24.00.
4. Isi **Catatan sumber** bila tersedia, misalnya informasi pengguna atau tautan situs resmi. Catatan ini bukan tanda bahwa sistem telah memverifikasi sumber tersebut.
5. Tekan **Simpan**. Ringkasan jam ditampilkan pada daftar tujuan dan pada layar pembanding MapKit.

Data diisi manual untuk tanggal dan zona waktu trip; belum ada pengambilan jam operasional otomatis dari layanan lain. Pengisian satu batas tidak membuat sistem mengarang batas lainnya. Menonaktifkan kedua batas menghapus data jam operasional tujuan.

Jam baru disimpan dengan `serviceDate` dan `timeZoneID`. Jika tanggal atau zona waktu trip berubah, perhitungan ditolak sampai jam diperiksa dan dikonfirmasi ulang di detail tujuan. JSON lama yang hanya berisi `opensMinute` dan `closesMinute` tetap dapat dibaca; tanpa metadata tanggal, batas manual lama berlaku untuk tanggal trip pada draft tersebut. Editor menampilkan catatan agar pengguna memeriksanya; penyimpanan berikutnya mencatat tanggal/zona.

## Pengaruh pada perhitungan

- Jam buka yang diketahui: `mulai singgah = max(waktu tiba, jam buka)`. Selisihnya menjadi waktu menunggu, lalu diteruskan ke perhitungan ruas berikutnya.
- Jam tutup yang diketahui: akhir singgah harus paling lambat jam tutup. Kunjungan yang melampauinya mendapat konflik, meskipun tiba sebelum tutup.
- Jam buka atau tutup belum diisi: hanya batas yang diketahui diterapkan. Batas yang belum diketahui tetap muncul sebagai ketidakpastian pada hasil; tidak diklaim terbuka sepanjang hari.
- Rentang di luar hari yang sama atau jam tutup tidak setelah jam buka ditolak. Satu rentang per tanggal didukung; hari tutup total, jeda operasional, jadwal mingguan, batas masuk terakhir, dan operasi lintas tengah malam belum dimodelkan.

Alur itinerary MapKit dan tujuh algoritme native pada pembanding menerima batas yang sama. Snapshot menyimpan jam buka/tutup sebagai detik relatif terhadap keberangkatan. Perhitungan itinerary tetap memeriksa ulang ETA sesuai jam setiap ruas. OR-Tools tetap menggunakan mekanisme ekspor/impor yang sudah ada; dukungan batas parsial pada runtime helper belum diuji pada perubahan ini.

**Pembaruan optimasi berikutnya:** evaluator kini mengutamakan kelayakan lalu total perjalanan + menunggu buka + singgah (`elapsed_v2`). Default hybrid mempertahankan baseline yang diperiksa langsung, lalu mencari dan memvalidasi kandidat tambahan. Laporan UI lama di atas tetap catatan perilaku sebelum pembaruan; [laporan implementasi dan fair benchmark](verification/ROUTING_TIME_AWARE_BENCHMARK_2026-11-03.md) membandingkan source sebelum/sesudah dengan ETA yang sama.

## Contoh Jakarta dengan jam buka Kelapa Gading

[Input Jakarta dengan jam buka](examples/jakarta-opening-hours.json) adalah salinan input Jakarta sebelumnya, dengan satu tambahan berdasarkan informasi pengguna: **Summarecon Mall Kelapa Gading buka pukul 10.00**. Tanggal trip tetap **5 November 2026**, berangkat 07.00 **Asia/Jakarta**. Jam tutup Kelapa Gading dan jam operasional tujuan lain tetap belum diisi. Data ini belum diverifikasi ke sumber eksternal; sudah dijalankan pada pengujian Simulator yang ditautkan di atas.

Untuk memuatnya, buka **Muat input JSON** dan tempel seluruh isi file. Tidak mengganti file bukti pengujian Jakarta terdahulu.

Contoh bagian `opening` pada sebuah tujuan:

```json
{
  "opensMinute": 600,
  "serviceDate": "2026-11-05",
  "timeZoneID": "Asia/Jakarta",
  "sourceNote": "Jam buka 10.00 berdasarkan informasi pengguna; jam tutup belum diketahui."
}
```

`opensMinute` dan `closesMinute` memakai menit sejak tengah malam dalam zona trip. Contoh 10.00 = 600, 22.00 = 1320, dan tutup 24.00 = 1440. Untuk data yang belum diketahui, hilangkan field atau gunakan `null`; jangan gunakan nol sebagai pengganti unknown.

## Hasil dan log

`input.stop_saved`, `input.replaced` dan `input.snapshot` menyertakan kedua batas yang diketahui beserta metadata sumber/tanggal. Ekspor laporan teks menyertakan ringkasan jam operasional, mulai singgah, lanjut, dan waktu menunggu buka. Rincian ruas di UI juga memisahkan waktu tiba dari mulai singgah agar kedatangan awal tidak disalahartikan sebagai kunjungan sebelum buka.

Penyimpanan log mengikuti retensi lokal yang sudah ada. Perubahan ini tidak menambahkan penyimpanan draft lintas peluncuran aplikasi atau menjalankan ulang kasus pengujian.
