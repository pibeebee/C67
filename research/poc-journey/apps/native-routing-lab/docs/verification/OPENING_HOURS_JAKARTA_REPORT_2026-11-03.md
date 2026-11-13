# Pengujian jam operasional PoC — Jakarta, 3 November 2026

**Jam buka Kelapa Gading berhasil diterapkan, tetapi kualitas optimasi jadwal masih bermasalah.** Enam algoritme menyelesaikan pembandingan snapshot; alur itinerary baseline dan enumerasi juga berhasil dijalankan melalui UI. Baseline live menempatkan Kelapa Gading terakhir dan kembali pukul **11.13.40 WIB**. Enumerasi live masih menempatkannya pertama, menunggu **148,02 menit**, lalu kembali pukul **13.33.40 WIB**. Ini bukan bukti bahwa enumerasi secara umum lebih buruk: ruang kandidat snapshot dan validasi dinamis saat ini berbeda dan terbatas.

## Input dan pelaksanaan

- Titik pergi/pulang: **Stasiun Sudirman**. Tujuan: **Monas, Grand Indonesia, Summarecon Mall Kelapa Gading, Kota Tua Jakarta**. Pin/alamat sama dengan run Jakarta setelah perbaikan, tanpa pencarian ulang lokasi.
- Tanggal **5 November 2026**, berangkat **07.00 Asia/Jakarta**; singgah **30 menit tiap tujuan**, semua tujuan wajib, selesai sebelum tengah malam.
- Jalan kaki, transit, dan mobil diaktifkan; batas berjalan **45 menit/ruas**. Mobil adalah pilihan eksplisit dari input terdahulu. Semua perpindahan yang akhirnya dipilih pada run ini memakai **mobil**.
- Hanya jam buka **Kelapa Gading 10.00** yang diisi, berdasarkan informasi pengguna. Jam tutupnya dan seluruh jam operasional tujuan lain **belum diketahui**. Tidak mengambil jam operasional otomatis dari MapKit dan tidak melakukan verifikasi eksternal terhadap informasi jam buka.
- Build berhasil pada Simulator **iPhone 18 Pro, iOS 27.0**. Minimum deployment tetap iOS 18. Build melalui XcodeBuildMCP, interaksi nyata melalui aksesibilitas Device Hub (`cua_repl`); kontrol tap XcodeBuildMCP tidak memicu perpindahan UI pada lingkungan ini.
- Membuka input lewat **Muat input JSON**, memeriksa editor jam operasional, menekan **Bandingkan semua metode native**, kemudian **Hitung itinerary** dengan baseline dan enumerasi. Pengujian tidak memakai injeksi state tersembunyi atau menjalankan solver di luar aplikasi.
- Sumber: [input persis](opening-hours-jakarta-2026-11-03/input.json), [metadata build/run](opening-hours-jakarta-2026-11-03/run-metadata.json), [build log](opening-hours-jakarta-2026-11-03/build.log).

## Pembanding enam algoritme — snapshot yang sama

Cakupan **20/20 pasangan berarah** memiliki setidaknya satu moda layak. Mobil **20/20** tersedia; transit **0/20** tersedia; jalan kaki menghasilkan ETA untuk 20 pasangan, tetapi hanya **4/20** memenuhi batas 45 menit. **60 request ETA provider**, akuisisi **76.00 detik**; tidak memanggil MapKit ulang untuk masing-masing algoritme. Seed 67, satu pengulangan, maksimum 100.000 evaluasi dan 3 detik/metode, beam 8.

| Algoritme | Perjalanan (menit) | Menunggu (menit) | Selesai WIB | Evaluasi | Status |
|---|---:|---:|---|---:|---|
| Baseline geografis | 107.37 | 148.02 | 13:15:23 | 2 | completed |
| Multi-start + local search | 107.37 | 148.02 | 13:15:23 | 500 | completed |
| Cheapest insertion + local | 107.37 | 148.02 | 13:15:23 | 71 | completed |
| Beam berbasis waktu | 107.37 | 148.02 | 13:15:23 | 50 | completed |
| ALNS | 107.37 | 148.02 | 13:15:23 | 1,653 | completed |
| Enumerasi ≤8 | 107.37 | 148.02 | 13:15:23 | 26 | completed |

Seluruhnya memilih **Sudirman → Kelapa Gading → Kota Tua → Monas → Grand Indonesia → Sudirman**. Singgah total 120 menit dan lima ruas lengkap, tanpa konflik terhadap batas yang diketahui. Tiba di Kelapa Gading **07.31.59**, mulai kunjungan **10.00.00**, lanjut **10.30.00**; menunggu **2 jam 28 menit 1 detik**. Waktu selesai snapshot **13.15.23**.

Enumerasi memeriksa 24 permutasi ditambah dua warm start, mendapat `exhaustive_fixed_evaluator`. Ini membuktikan minimum **waktu perjalanan sesuai evaluator snapshot**, bukan minimum total durasi trip atau optimum lalu lintas sepanjang hari. Semua metode memakai warm start baseline yang sama; satu kasus empat tujuan tidak cukup untuk memilih algoritme terbaik secara umum.

Snapshot sebelum dan setelah penambahan jam buka memiliki **arc/ETA yang identik** pada run yang tersimpan. Urutan dan waktu perjalanan tetap **107,37 menit**, tetapi penambahan jam buka mengubah tunggu dari **0 menjadi 148,02 menit**, dan selesai dari **10.47.22 menjadi 13.15.23**. Jadi pergeseran ini dapat ditelusuri ke batas jam buka, bukan perubahan matriks ETA pada dua artefak tersebut.

Dalam pool alternatif yang **sudah dikeluarkan aplikasi**, ada urutan **Sudirman → Grand Indonesia → Monas → Kota Tua → Kelapa Gading → Sudirman**, dengan perjalanan **121,02 menit**, tunggu **16,77 menit**, selesai **11.17.47** pada snapshot yang sama. Ini pembacaan alternatif tersimpan, bukan run provider tambahan dan bukan hasil utama yang dipilih algoritme. Alternatif ini selesai **1 jam 57 menit 36 detik lebih awal** daripada pemenang snapshot, tetapi kalah karena evaluator mendahulukan waktu perjalanan daripada menunggu.

Bukti: [JSON perbandingan lengkap](opening-hours-jakarta-2026-11-03/comparison.json), [ringkasan metrik dan coverage](opening-hours-jakarta-2026-11-03/comparison-summary.json), [log operasi](opening-hours-jakarta-2026-11-03/comparison-events.json), [screenshot enam hasil](opening-hours-jakarta-2026-11-03/comparison-results.jpg), [detail enumerasi](opening-hours-jakarta-2026-11-03/enumeration-detail.jpg).

## Alur itinerary utama — ETA pada jam tiap ruas

### Baseline geografis

Baseline mengevaluasi dua kandidat dengan ETA sesuai jam berangkat tiap ruas. Run selesai dengan **30 request provider**, tanpa retry, seluruh tujuan dan ruas kembali lengkap.

Urutan terpilih: **Sudirman → Grand Indonesia → Monas → Kota Tua → Kelapa Gading → Sudirman**.

| No. | Ruas mobil | Perjalanan (menit) | Tiba WIB | Mulai singgah WIB | Lanjut WIB |
|---:|---|---:|---|---|---|
| 1 | Stasiun sudirman → Grand Indonesia | 3.95 | 07:03:57 | 07:03:57 | 07:33:57 |
| 2 | Grand Indonesia → National Monument | 21.00 | 07:54:57 | 07:54:57 | 08:24:57 |
| 3 | National Monument → Kota Tua | 18.13 | 08:43:05 | 08:43:05 | 09:13:05 |
| 4 | Kota Tua → Summarecon Mall Kelapa Gading | 35.60 | 09:48:41 | 10:00:00 | 10:30:00 |
| 5 | Summarecon Mall Kelapa Gading → Stasiun sudirman | 43.67 | 11:13:40 | 11:13:40 | 11:13:40 |

Perjalanan **122,35 menit** + singgah **120 menit** + menunggu **11,32 menit** = total **253,67 menit**, kembali **11.13.40 WIB**. Kelapa Gading dikunjungi **10.00–10.30**, setelah tiba **09.48.41**.

Kandidat sebaliknya, dengan Kelapa Gading pertama, menghasilkan perjalanan **125,65 menit**, tunggu **148,02 menit**, dan kembali **13.33.40**. Baseline memilih kandidat pertama karena waktu perjalanannya setelah ETA dinamis diperiksa juga lebih kecil. **Ini tidak berarti prioritas algoritme sudah berubah menjadi optimasi total durasi.**

Bukti: [laporan teks aplikasi](opening-hours-jakarta-2026-11-03/live-baseline-report.txt), [log lengkap](opening-hours-jakarta-2026-11-03/live-plan-events.json), [ringkasan UI](opening-hours-jakarta-2026-11-03/live-baseline-summary.jpg), [rincian Kelapa Gading](opening-hours-jakarta-2026-11-03/live-baseline-kelapa.jpg).

### Enumerasi melalui bridge snapshot → validasi ETA

Engine enumerasi selesai dengan **75 request provider**: **61** pada akuisisi snapshot, termasuk satu retry mobil **Kelapa Gading → Grand Indonesia** yang berhasil, lalu **14** request baru saat memvalidasi finalis. Log juga memuat **18 respons cache**; jumlah event `eta.requested` bukan jumlah panggilan provider.

Snapshot tetap memiliki 20/20 pasangan layak dan enumerasi selesai. Dua finalis yang divalidasi adalah:

1. **Kelapa Gading → Kota Tua → Monas → Grand Indonesia**.
2. **Monas → Kelapa Gading → Kota Tua → Grand Indonesia**.

Kandidat **Grand Indonesia → Monas → Kota Tua → Kelapa Gading**, yang menghasilkan baseline live lebih baik, **tidak termasuk dua finalis ini**. Bridge memilih finalis berdasarkan peringkat snapshot yang memprioritaskan waktu perjalanan.

Hasil akhir enumerasi live tetap **Kelapa Gading pertama**, perjalanan **125,65 menit**, tunggu **148,02 menit**, singgah **120 menit**, selesai **13.33.40 WIB**. Kunjungan Kelapa Gading baru dimulai **10.00**, jadi batas buka dipatuhi. Namun hasil ini **2 jam 20 menit lebih lambat** daripada baseline live yang turut diuji. Klaim optimum enumerasi tidak berlaku pada tahap validasi ETA dinamis yang hanya memeriksa finalis terbatas.

Bukti: [laporan aplikasi](opening-hours-jakarta-2026-11-03/live-exact-report.txt), [log operasi termasuk solver dan retry](opening-hours-jakarta-2026-11-03/live-exact-events.json), [screenshot](opening-hours-jakarta-2026-11-03/live-exact-summary.jpg), [ringkasan kedua run dan timeline dari log](opening-hours-jakarta-2026-11-03/live-summary.json).

## Pemeriksaan input dan sumber cuaca

| Pemeriksaan melalui UI | Hasil yang diamati |
|---|---|
| Jam buka 10.00 tanpa jam tutup | Diterima; UI menampilkan jam tutup belum diisi; snapshot `opens = 10800` detik sejak 07.00 dan tidak memiliki `closes`. |
| Tiba sebelum buka | Waktu mulai singgah ditunda sampai 10.00; menunggu diteruskan ke jam ruas berikutnya dan laporan. |
| Jam tutup 09.00 dengan buka 10.00 | Ditolak: “Jam tutup harus setelah jam buka pada hari yang sama.” |
| Jam untuk 4 November pada trip 5 November | Ditolak: tanggal/zona waktu berubah dan perlu konfirmasi ulang. |
| Impor invalid | Draft dan hasil valid sebelumnya tetap tersedia; tidak menimpa rencana. |
| WeatherKit gagal autentikasi pada Simulator | Open-Meteo berhasil menjadi cadangan untuk lima titik, 17 interval per titik. |

Screenshot: [editor jam parsial](opening-hours-jakarta-2026-11-03/opening-hours-editor.jpg), [rentang invalid ditolak](opening-hours-jakarta-2026-11-03/invalid-closing-rejected.jpg), [tanggal berbeda ditolak](opening-hours-jakarta-2026-11-03/stale-hours-rejected.jpg). [Pemeriksaan konsistensi artefak](opening-hours-jakarta-2026-11-03/verification.json).

Paparan cuaca tempat masih `unknown`, akses/parkir mobil juga belum diketahui. Alternatif cuaca ditunda; tidak ada klaim rute sudah optimal terhadap cuaca. Nilai nol paparan yang tercatat bukan bukti bebas risiko hujan.

## Kesimpulan dan perubahan berikutnya

**Implementasi jam buka bekerja pada skenario yang diuji**, termasuk propagasi waktu dan penolakan data tidak valid. Build dan interaksi Simulator berhasil. **Optimasi jadwal belum memadai**: jam buka dapat menghasilkan waktu menunggu panjang tanpa mengubah pemenang snapshot. Pemangkasan ke dua finalis juga dapat membuat engine lanjutan melewatkan urutan yang lebih baik setelah ETA diperbarui.

Perbaikan yang disarankan berikutnya adalah mendahulukan **total durasi trip (perjalanan + tunggu + singgah)** setelah batas wajib terpenuhi, serta memasukkan kandidat baseline live dan kandidat selesai lebih awal ke tahap revalidasi. Ini saran dari temuan pengujian; **tidak mengubah source algoritme pada turn pengujian ini**.

Hasil ini belum menjadi itinerary wisata siap pakai: **Grand Indonesia dijadwalkan tiba 07.03.57 tanpa jam operasional**, sementara Monas dan Kota Tua juga belum memiliki batas operasional. Jam tutup Kelapa Gading belum diketahui. Isi dan verifikasi data semua tempat sebelum menyimpulkan jadwal dapat diikuti.

Tidak menjalankan XCTest, OR-Tools, atau pengujian iPhone fisik. Alur live untuk local/insertion/beam/ALNS belum dijalankan; keenamnya diuji pada pembanding snapshot yang sama. Konflik melewati jam tutup pada rute nyata belum diuji karena kasus ini hanya memasukkan batas buka. Uji validasi rentang tidak valid bukan pengganti pengujian seluruh variasi jam operasional.
