# C67 Context Lab v0.3 (3): Jelajah, cuaca otomatis, dan peta rute

9 November 2026 · Simulator iPhone 18 Pro Max · C67 Context Lab, server lokal Mac.

- **Jelajah:** `Cari lainnya` menambahkan hasil Google Places dan mengecualikan ID yang sudah ditampilkan dalam sesi. Tujuan yang dipilih sebelumnya tetap dapat dirutekan. Hasil dimuat hingga enam kartu per putaran, maksimal delapan putaran pada pilot, dengan kemungkinan berhenti lebih awal jika sumber atau anggaran layanan habis. Enam tujuan tetap merupakan batas rencana, bukan batas daftar rekomendasi. Ganti area/waktu/minat untuk pencarian baru, atau pilih reset secara eksplisit dari pengaturan perjalanan. Daftar aktif bukan penyimpanan lintas peluncuran.
- **Cuaca:** park/garden yang didukung tipe tempat langsung diperlakukan sebagai kegiatan outdoor. Saat menyusun urutan, planner menerima preferensi mengurangi peluang hujan tanpa masukan tambahan. Pengguna boleh mengoreksi paparan atau menonaktifkan penyesuaian di pengaturan lanjutan. Paparan tempat yang belum jelas dan prakiraan yang tidak ada tetap tidak diketahui. Hujan bukan larangan dan prediksi bukan jaminan.
- **Peta:** garis ruas mobil diminta ke MapKit setelah jadwal tersedia, memakai identitas Apple yang dikonfirmasi dan urutan serta waktu ruas dari jadwal, termasuk kembali ke titik awal. UI bisa membuka ruas pertama di aplikasi Apple Maps. Jika sebagian garis tidak tersedia, peta menunjukkan titik, garis yang ada, dan opsi muat ulang. Garis di UI adalah hasil permintaan petunjuk arah terpisah dari ETA server; respons keduanya bisa berbeda.
- **UI:** dua tab utama, **Jelajah** dan **Rencana**. Bukti tempat, preferensi, serta durasi dan batas menunggu tersedia saat dibutuhkan. Tampilan personal lama masih bisa dibuka dengan `--personal-full-layout`; lab manual dengan `--context-legacy`. Bukti durasi, waktu buka, batas menunggu, dan identitas Apple masih diperiksa.

## Pengujian

UI test aktual menyiapkan minat kopi, budaya, dan outdoor, perjalanan Gambir Jakarta pada 10 November 2026, 09.00–19.00 WIB. Memilih Taman Pandang Istana sebagai tujuan wajib pada halaman pertama, memuat halaman kedua, lalu menyusun perjalanan dari dan kembali ke Hotel Indonesia Kempinski. Pengujian tidak mengubah setelan hujan. Peta menampilkan garis Apple Maps untuk dua ruas (pergi dan pulang).

| Ukuran | Run ini |
|---|---:|
| Halaman awal sampai tampil | 15,00 detik · 6 tempat |
| Halaman berikut sampai tampil | 5,98 detik · 6 tempat baru, tanpa ID ganda |
| Total tempat yang tampil setelah dua halaman | 12 unik |
| Susun rencana, termasuk validasi ETA | 3,04 detik · 3 panggilan ETA, 0 tidak tersedia |
| Kunjungan wajib | Taman Pandang Istana 09.15–10.15 WIB, kembali 10.26 WIB |
| Menunggu | 1,55 menit dari batas 30 menit |
| WeatherKit | Tersedia, maksimum peluang hujan selama kunjungan 4% |
| Garis rute | 2 dari 2 ruas mobil, dimuat terpisah setelah jadwal |

Kedua halaman memakai E5 aktual (`en-v1`) dan OpenRouter tanpa biaya LLM. Audit JSON mengecek kandidat antarhalaman, tujuan dari halaman pertama tetap sah dengan bukti terbaru, identitas, jam buka, ETA, durasi, menunggu, dan batas pulang. Dua kontrol negatif menolak bukti halaman awal yang hilang dan kandidat ganda. Dari 102 kasus pengujian paket, 101 lulus dan satu benchmark opsional dilewati karena membutuhkan konfigurasi eksperimen eksplisit. Satu UI test end-to-end lulus.

- [Tangkapan layar Jelajah](../artifacts/personal-simplified-2026-11-09/screenshots/01-jelajah.png)
- [Tangkapan layar sesudah Cari lainnya](../artifacts/personal-simplified-2026-11-09/screenshots/02-cari-lainnya-pilihan-tetap.png)
- [Tangkapan layar hasil dengan peta](../artifacts/personal-simplified-2026-11-09/screenshots/03-rencana-dan-rute-apple-maps.png)
- [Ringkasan audit](../artifacts/personal-simplified-2026-11-09/audit-summary.json)

Satu pengujian live membuktikan alur, tidak mengukur peningkatan kecepatan dibanding build lama, kecocokan rekomendasi niche, atau seberapa sering cuaca mengubah urutan. Kata area di pencarian adalah konteks pencarian di Jakarta, bukan geofence kelurahan. Peta dan penyesuaian cuaca belum diverifikasi pada iPhone fisik untuk build ini.
