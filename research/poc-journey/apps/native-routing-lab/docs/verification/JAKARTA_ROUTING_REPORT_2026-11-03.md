# Laporan perbaikan dan uji routing Jakarta — 3 November 2026

Enam algoritme native berhasil menghasilkan itinerary lengkap, masing-masing 5/5 ruas. Run akhir memiliki ETA yang dapat dipakai pada **20/20 pasangan berarah**; seluruh metode mendapat perpindahan **107.37 menit**. Enumerasi memeriksa seluruh 24 permutasi empat tujuan dan memperoleh `exhaustive_fixed_evaluator`. Ini bukti optimum untuk snapshot/evaluator yang sama, bukan optimum lalu lintas dunia nyata.

## Input dan lingkungan

- Awal/pulang: Stasiun Sudirman, Jakarta. Tanggal 5 November 2026, berangkat 07.00 WIB (`Asia/Jakarta`).
- Empat tujuan: National Monument/Monas, Grand Indonesia, Summarecon Mall Kelapa Gading, Kota Tua.
- Singgah default 30 menit per tujuan; batas jalan kaki **tetap 45 menit/ruas**. Trip berakhir sebelum tengah malam. Tidak ada jam operasional yang diisi.
- Simulator iPhone 18 Pro, iOS 27.0; build memakai Xcode 27.2, minimum iOS 18. Enam metode menerima satu snapshot MapKit yang sama.
- Seed 67, satu pengulangan, 100.000 evaluasi maksimum, 3 detik CPU/metode, beam 8, ALNS 150 iterasi, kuota 96 request ETA.
- Aksi uji dilakukan melalui UI dengan `cua_repl`: pemulihan input dari log, pemilihan ulang lokasi, pengaktifan mobil, pemilihan MapKit, dan tombol perbandingan. `simctl` dipakai untuk instalasi/launch; shell membaca log/artefak. Tidak menjalankan XCTest atau helper OR-Tools.

## Penyebab yang terbukti

1. **Pin Kota Tua salah wilayah.** Log awal menyimpan `(1.0078258, 99.4048783)` dengan alamat Tapanuli Selatan, Sumatra Utara. Ini sekitar 1.145 km dari titik terdekat rencana. Query `Kota Tua Jakarta` melalui UI menghasilkan alamat Jalan Kali Besar Timur No. 10, Jakarta Barat, koordinat `(-6.1347997, 106.8130414)`, yang dipilih untuk run selanjutnya.
2. **Transit tidak tersedia pada permintaan kasus ini.** Seluruh 20 permintaan transit setiap run mendapat error MapKit `MKErrorDomain`, kode 4, deskripsi `Directions Not Available`. Indonesia juga tidak tercantum dalam daftar cakupan [Maps: Transit Apple](https://www.apple.com/ios/feature-availability/#maps-transit). Tidak ada durasi transit buatan atau pengganti yang diberi label transit.
3. **Batas jalan kaki menghilangkan sebagian besar opsi.** Run awal memiliki 12 ETA berjalan dari provider, delapan melampaui 45 menit dan delapan ruas lainnya gagal terkait pin salah. Setelah pin diperbaiki, semua 20 ETA berjalan tersedia, tetapi 16 melampaui batas. Hanya empat pasangan tetap dapat dipakai.
4. **Kegagalan tambahan bersifat tidak konsisten antarrun.** Run mobil pertama mendapat 16/20 ETA mobil, sementara tiga ETA berjalan yang tersedia pada run kontrol kembali gagal. Kode lama menyimpan hasil gagal dalam cache sepanjang run. Tidak ada bukti cukup untuk menyatakan penyebab server pasti throttling; kode error yang terlihat adalah 4, bukan `.loadingThrottled`.

## Perubahan kode

- Alamat MapKit terpilih sekarang terlihat pada input, disertai peringatan titik yang berjarak lebih dari 200 km dari semua titik lain. Ini peringatan heuristik untuk diperiksa pengguna; perjalanan jauh tetap diizinkan.
- Pemilihan otomatis bulk membutuhkan kecocokan konteks alamat atau berada dalam area pencarian eksplisit. Nama yang unik/sama persis tanpa konteks geografis tetap membutuhkan pilihan pengguna.
- Menambahkan **Mobil · ETA** melalui [mode automobile MapKit](https://developer.apple.com/documentation/mapkit/mkdirectionstransporttype/automobile). Default mati; diaktifkan secara eksplisit pada Pengaturan untuk run ini. Request, cache sesuai jam keberangkatan, ikon, catatan, dan tautan Apple Maps mengikuti moda yang dipilih.
- Request ETA diberi jarak minimum 1,2 detik antarwaktu mulai. Setelah snapshot, pasangan yang belum memiliki moda layak dapat mencoba ulang kegagalan non-transit sekali, dengan jeda tiga detik, cache sukses dipertahankan, dan kuota/reserve validasi tetap berlaku. Transit gagal tidak diulang otomatis. **Retry tidak terpicu pada run akhir**, karena pacing sudah menghasilkan semua pasangan yang diperlukan.
- Diagnostik membedakan pasangan yang belum diminta, moda gagal, opsi yang dikeluarkan karena batas berjalan, dan moda yang tersedia. Ruas pertama yang menghentikan evaluasi dijelaskan; angka itu tidak lagi menyerupai total ETA kosong.
- Input JSON dari `input.snapshot` dapat dipulihkan melalui UI setelah validasi. Snapshot dan hasil lengkap terakhir otomatis disimpan di `Application Support/NativeTripRouting/last-comparison.json`; log JSONL dan ekspor perbandingan tetap tersedia.

## Perbandingan run

| Tahap | Request ETA | Akuisisi | Pasangan layak | Itinerary lengkap | Status pencarian |
|---|---:|---:|---:|---:|---|
| Awal: pin Sumatra, jalan kaki + transit | 40 | 29.09 dtk | 4/20 | 0/6 | seluruhnya `data_incomplete` |
| Pin Jakarta benar, moda tetap | 40 | 30.09 dtk | 4/20 | 0/6 | seluruhnya `data_incomplete` |
| Mobil diaktifkan, pacing lama | 60 | 39.70 dtk | 16/20 | 6/6 | baseline selesai; lima metode masih menjumpai ETA kosong |
| Akhir: mobil + pacing baru + kebijakan retry | 60 | 73.36 dtk | 20/20 | 6/6 | seluruhnya `completed` |

Run akhir: mobil tersedia 20/20; jalan kaki terambil 20/20 dengan empat opsi layak dan 16 dikeluarkan karena batas; transit tersedia 0/20. Jadi matriks lengkap berarti **setiap pasangan memiliki setidaknya satu moda yang dapat dipakai**, bukan semua moda tersedia.

Akuisisi lebih lama merupakan biaya pacing dan tiga moda. Waktu tersebut dipisahkan dari CPU solver, dan angka durasi itinerari tidak diberi penambahan fiktif karena pacing aplikasi.

## Hasil setiap algoritme

| Algoritme | Perpindahan (menit) | Ruas lengkap | Evaluasi | CPU (ms) | Status |
|---|---:|---:|---:|---:|---|
| Baseline geografis | 107.37 | 5/5 | 2 | 0.191 | completed |
| Multi-start + local search | 107.37 | 5/5 | 500 | 9.256 | completed |
| Cheapest insertion + local | 107.37 | 5/5 | 71 | 2.241 | completed |
| Beam berbasis waktu | 107.37 | 5/5 | 50 | 2.248 | completed |
| ALNS | 107.37 | 5/5 | 1,653 | 15.550 | completed |
| Enumerasi urutan ≤8 | 107.37 | 5/5 | 26 | 0.319 | completed |

Seluruh hasil memiliki nol konflik pada batas yang diketahui, singgah 120 menit, dan selesai setelah +227.37 menit. Urutannya sama: **Sudirman → Kelapa Gading → Kota Tua → Monas → Grand Indonesia → Sudirman**. Selisih terhadap optimum enumerasi snapshot adalah 0% untuk keenamnya.

Lima heuristik sendiri tetap berlabel `not_proven`; hasil exact menjadi acuannya. Kasus empat tujuan serta warm start baseline yang dibagi belum cukup untuk menentukan algoritme terbaik pada 10–20 tujuan. CPU submilidetik dari satu run juga bukan benchmark performa yang stabil.

## Rundown hasil snapshot

| Ruas | Perpindahan | Moda terpilih | Durasi menit | Berangkat WIB | Tiba WIB | Singgah menit |
|---|---|---|---:|---|---|---:|
| 1 | Stasiun sudirman → Summarecon Mall Kelapa Gading | Mobil | 31.98 | 07:00:00 | 07:31:59 | 30 |
| 2 | Summarecon Mall Kelapa Gading → Kota Tua | Mobil | 33.48 | 08:01:59 | 08:35:28 | 30 |
| 3 | Kota Tua → National Monument | Mobil | 26.72 | 09:05:28 | 09:32:11 | 30 |
| 4 | National Monument → Grand Indonesia | Mobil | 8.12 | 10:02:11 | 10:10:18 | 30 |
| 5 | Grand Indonesia → Stasiun sudirman | Mobil | 7.07 | 10:40:18 | 10:47:22 | 0 |

Total perpindahan 107.37 menit + singgah 120 menit; perkiraan kembali **10:47:22 WIB**. Tabel ini mempropagasikan waktu dari ETA snapshot jam 07.00. Tidak mengambil ulang ETA untuk setiap jam keberangkatan ruas.

## Verifikasi dan batas hasil

- Build iOS Simulator: **BUILD SUCCEEDED**. Pemeriksaan format Swift dan `git diff --check`: lulus.
- Sepuluh pemeriksaan kebijakan input dan 15 pemeriksaan routing lokal macOS: lulus. Termasuk kasus nama Kota Tua ambigu, konteks geografis, kompatibilitas draft lama, mobil opt-in, matriks tidak lengkap, batas berjalan, dan enam solver dengan ruas mobil yang layak.
- UI: JSON tidak lengkap ditolak, peringatan pin Sumatra tampil, Kota Tua Jakarta dapat dipilih, mobil awalnya mati dan dapat diaktifkan, konfigurasi jam/tanggal benar, 20/20 pasangan tampil, keenam metode berstatus selesai, detail exact menunjukkan 5/5 ruas dan bukti enumerasi.
- WeatherKit beralih ke Open-Meteo: lima titik, 85 interval total (17 jam per titik) dalam snapshot. Paparan kunjungan belum diisi dan paparan mobil/transfer belum dimodelkan, sehingga tidak ada klaim rute optimum cuaca.
- Jam buka tujuan, termasuk mal, **belum dimasukkan**. Hasil ini dapat menjadwalkan mal sebelum buka. Klaim layak hanya terhadap batas yang diberikan, bukan rundown wisata siap digunakan.
- ETA mobil belum mencakup mencari kendaraan, parkir, akses berjalan dari parkir atau tarif. Bukan ETA motor. Transit Jakarta belum terselesaikan; untuk itinerary wajib transportasi umum dibutuhkan sumber transit lain.
- OR-Tools merupakan helper Mac dengan alur ekspor/impor, sehingga tidak dijalankan dalam pengujian UI-only ini. Tidak ada klaim validasi iPhone fisik.

## Bukti yang disimpan

[Input asli](jakarta-routing-2026-11-03/original-input.json), [ringkasan hasil asli](jakarta-routing-2026-11-03/original-summary.json), [kontrol lokasi benar](jakarta-routing-2026-11-03/corrected-location-control.json), [run mobil pertama](jakarta-routing-2026-11-03/first-automobile-run.json), [input akhir](jakarta-routing-2026-11-03/final-input.json), [perbandingan akhir lengkap](jakarta-routing-2026-11-03/final-comparison.json), dan [diagnostik akhir](jakarta-routing-2026-11-03/final-diagnostics.json).

[Hasil pemeriksaan input](jakarta-routing-2026-11-03/input-checks.log) dan [hasil pemeriksaan routing](jakarta-routing-2026-11-03/routing-checks.log).
