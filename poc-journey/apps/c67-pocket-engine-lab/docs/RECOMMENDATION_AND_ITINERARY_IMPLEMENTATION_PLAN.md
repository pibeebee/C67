# Pocket Engine · rencana implementasi rekomendasi dan itinerary

Keputusan sesi `grill-me`, 11 November 2026 WIB. Dokumen ini memuat rencana dan keputusan yang dikunci sebelum implementasi. Pada 12 November 2026, pengguna mengizinkan implementasi dan pengujian melalui iPhone Simulator. Verifikasi perangkat fisik menjadi pekerjaan lanjutan.

## Tujuan dan titik awal

Validasi alur dari preferensi sampai itinerary awal yang layak digunakan di iPhone. Utamakan pencarian dan routing Apple, gunakan OSM dan Overture untuk melengkapi kandidat, dan gunakan bukti independen untuk menilai kecocokan tempat. Seluruh pekerjaan berjalan tanpa Google Maps/Places API, tanpa daftar 982 tempat lama, dan tanpa label Jev dari daftar tersebut. Pengaturan ulang manual dan rerouting sesudahnya berada di luar cakupan rencana ini.

Revisi planner lulus 18 dari 18 skenario sintetis dengan kandidat, ETA, dan cuaca yang telah disiapkan. Pilot data independen mendapati nol dari dua perpustakaan lolos syarat membaca lewat pengayaan otomatis. Kedua tempat lolos setelah bukti dari sumber resmi dimasukkan secara manual. Karena itu, prioritas pertama adalah membuktikan kemampuan aplikasi menemukan dan meloloskan tiga tempat yang cocok secara otomatis. Lihat [revisi planner](PLANNER_REVISION_2026-11-11.md) dan [laporan pilot independen](../.local/no-google-independent-20261111-153758/REPORT.md).

## Perilaku yang disepakati

| Kondisi | Perilaku aplikasi |
| --- | --- |
| Area yang dipilih pengguna | Cari dan rekomendasikan di dalam area tersebut. Tawarkan perluasan jika hasil kurang. Jalankan pencarian dengan area baru setelah pengguna menyetujuinya. |
| Minimum rekomendasi | Tampilkan daftar rekomendasi jika ada setidaknya tiga tempat berbeda yang valid. Jika jumlahnya kurang, jelaskan hasilnya dan tawarkan langkah yang relevan. Pencarian nama tetap dapat menampilkan satu atau dua hasil. |
| Lebih dari satu minat | Dahulukan satu tempat berbeda per minat yang bisa terwakili. Bila ada minat yang belum terwakili, daftar boleh tampil jika tiga tempat valid tersedia. Tunjukkan minat yang belum terpenuhi. |
| Syarat wajib | Hanya lolos jika ada bukti yang mendukung syarat pada cabang yang benar. Bedakan bukti yang bertentangan dari bukti yang belum tersedia, kedaluwarsa, atau berkonflik. Pengguna dapat memilih melonggarkan syarat secara eksplisit. |
| Makan malam sebagai penutup | Pertahankan tujuan tersebut sebagai kunjungan terakhir. Jika batas awal makan malam belum diberikan, sarankan jam yang bisa pengguna konfirmasi atau ubah. Masukkan batas yang dikonfirmasi dan ETA pulang ke perhitungan. Jika keduanya bentrok, minta pengguna memilih batas yang boleh digeser. |
| Jumlah kunjungan tidak muat | Tawarkan jadwal dengan jumlah terbesar yang berhasil divalidasi dalam jendela waktu, dengan tetap menjaga tujuan wajib, jam wajib, dan batas pulang. Jelaskan pengurangan dan minta persetujuan sebelum jadwal dipakai. Ambang tiga berlaku untuk daftar rekomendasi. |
| ETA tetap gagal setelah retry | Boleh tawarkan jadwal lebih pendek jika hanya tujuan opsional yang terlewat dan semua ruas jadwal pengganti tervalidasi. Catat ETA tidak tersedia sebagai penyebab tersendiri. Jika tujuan wajib atau perjalanan pulang tetap tidak dapat divalidasi, tampilkan kegagalan dan opsi mencoba lagi. |
| Hujan dan waktu tunggu | Coba ubah urutan atau waktu berangkat dalam batas yang disetujui. Jika jadwal yang mempertahankan tujuan membutuhkan waktu tunggu yang belum diizinkan, tampilkan durasinya dan minta pengguna memilih untuk menunggu atau melewati tujuan itu. |

## 1. Bekukan brief dan acuan

1. Siapkan 12 brief baru untuk Jakarta Selatan. Cakup permintaan umum dan spesifik, seperti makanan Jepang, hewan/seni/taman, serta tempat membaca dengan syarat masuk tertentu. Tetapkan batas area yang bisa diuji pada koordinat, kueri per minat, kriteria wajib dan disukai, serta tanggal, titik awal, waktu, dan tujuan wajib bila berlaku. Bekukan juga batas permintaan provider, waktu tunggu respons, dan jumlah hasil yang akan diaudit sebelum melihat keluaran engine.
2. Verifikasi minimal tiga tempat valid untuk setiap brief dari sumber independen. Catat identitas cabang, koordinat, kecocokan minat, bukti per syarat wajib, URL, dan waktu pengecekan. Periksa jam dan pengecualian tanggal untuk brief yang menjadikannya syarat. Simpan manifest dan hash sebelum pengujian. Pisahkan acuan penilai dari input yang boleh dibaca engine.
3. Buat kontrol terpisah untuk kumpulan kandidat yang hanya punya dua tempat valid, kandidat di luar area, duplikat cabang, dan kandidat dengan syarat wajib yang belum terbukti atau bertentangan. Gunakan kumpulan terkontrol untuk menguji perilaku ketika hanya ada dua hasil valid, karena pencarian live yang menemukan dua hasil belum membuktikan tidak ada tempat ketiga.

## 2. Implementasikan dan ukur rekomendasi

1. **Hubungkan pencarian ke rekomendasi.** Saat ini `PocketModel.assessments` membaca katalog, sementara hasil pencarian Apple berada di `appleHits`. Hubungkan kandidat dari pencarian Apple dan katalog independen ke jalur penilaian yang sama. Batasi hasil memakai koordinat dan batas area yang disepakati. Pertahankan pencarian nama. Deduplicasi berdasarkan identitas cabang dan koordinat, simpan asal kandidat, dan tahan penggabungan yang ambigu. Tambahkan adaptor pembacaan data OSM dan Overture pada katalog independen sesuai kebutuhan pilot.
2. **Lengkapi bukti untuk kandidat yang relevan.** Pakai server katalog yang ada dan ikuti [kontrak impor bukti](../Server/CONTRACT.md). Untuk data yang boleh disimpan, gunakan ulang bukti yang masih segar dan hindari pengambilan ulang sebelum kedaluwarsa. Batas kesegaran maksimal 30 hari. Waktu pengambilan yang masih segar tidak memperluas cakupan jam reguler ke tanggal khusus. Simpan rujukan per cabang dan per atribut. Impor hasil pengayaan setelah peninjauan. Catat kegagalan kolektor terpisah dari atribut yang tidak diketahui. Data Apple yang bersifat sesi tetap diperlakukan sesuai batas retensi yang berlaku untuk sumber tersebut.
3. **Perbarui ranking dan status tampilan.** Gunakan `Recommender.assess` sebagai pintu kelayakan. Setelah penyaringan, pilih tempat berbeda untuk memaksimalkan jumlah minat yang terwakili, lalu pakai skor dan ID stabil untuk pemeringkatan. Tempat yang cocok dengan beberapa minat tetap dihitung sebagai satu tempat. Kirim jumlah kandidat valid, minat yang terwakili, dan sebab utama hasil kurang ke `DiscoverViews.swift`. Ukur kontrol untuk minimum tiga, cakupan minat, area, dan kelayakan sebelum run live.
4. **Bandingkan sumber dengan masukan yang sama.** Ambil satu respons Apple per kueri untuk penilaian kualitas. Bandingkan Apple saja dengan respons Apple yang sama ditambah OSM/Overture, memakai batas area, aturan pencocokan cabang, dan jatah keluaran yang sama. Pada kumpulan kandidat tetap, ukur perubahan kelayakan setelah bukti situs resmi ditambahkan. Ukur durasi tiap jalur sesuai pekerjaan yang benar-benar dijalankan dan tandai cache hit, timeout, atau layanan yang gagal. Audit kandidat baru yang belum ada di acuan menggunakan rubrik yang sama. Laporkan ketidakpastian secara eksplisit jika bukti masih kurang.

## 3. Implementasikan dan uji itinerary dari hasil aplikasi

1. Pisahkan target jumlah kunjungan dari tujuan yang benar-benar wajib di `PocketModel` dan kontrak `TripInput`/`StopChoice`. Saat ini tujuan yang baru ditambahkan default wajib. Pada alur rekomendasi baru, pengguna bisa menetapkan tujuan wajib dan target jumlah secara terpisah. Jaga kompatibilitas rencana tersimpan. Kembalikan jadwal lengkap, tawaran jadwal lebih pendek, atau hasil gagal beserta alasan yang dapat ditampilkan. Jika anggaran pencarian habis, jelaskan bahwa sebagian alternatif belum diperiksa.
2. Gunakan batas awal makan malam yang dikonfirmasi sebagai batas bawah, dan `lastVenueID` untuk posisi terakhir. Pertahankan arti jam kunjungan yang tepat dan jam yang diutamakan. Di `PlanViews.swift`, tampilkan konflik waktu, alasan pengurangan, dan pilihan untuk menerima jadwal lebih pendek. Simpan persetujuan waktu tunggu secara eksplisit. Gunakan penjadwalan tanpa tambahan waktu tunggu yang belum diizinkan untuk percobaan awal, lalu tawarkan opsi yang menyebutkan durasinya jika diperlukan.
3. Gunakan ETA MapKit untuk waktu aktual setiap ruas dan WeatherKit saat kondisi cuaca relevan. Pertahankan retry terbatas yang sudah ada. Bedakan tujuan tutup, jendela waktu terlalu sempit, prakiraan kurang, ETA tidak tersedia, dan pencarian terpotong. Route tempat dengan koordinat terverifikasi jika pencarian nama Apple tidak menemukannya. Label pin tetap berasal dari nama tempat di aplikasi.
4. Tambah kasus regresi di `Tests/PocketEngineTests` dan `Benchmarks/Acceptance` sesuai kontrak baru. Jalankan ulang skenario sintetis yang relevan, termasuk tutup awal, makan malam terakhir, waktu tunggu hujan, ETA sementara/permanen, dan batas pulang. Pada pekerjaan saat ini gunakan iPhone Simulator sesuai arahan 12 November. Pada verifikasi perangkat fisik berikutnya, jalankan alur mulai dari preferensi dan rekomendasi asli sampai itinerary. Jika satu brief gagal, jalankan ulang dengan kandidat yang telah diverifikasi manual untuk melokalisasi masalah. Catat run tersebut sebagai diagnosis terpisah dari hasil otomatis. Pengujian di simulator atau build saja tidak memenuhi verifikasi perangkat.

## Pelaporan dan keputusan TestFlight internal

- **Ambang rekomendasi** — Minimal **10 dari 12** brief yang terbukti punya sedikitnya tiga tempat valid menghasilkan setidaknya tiga rekomendasi valid. Catat cakupan minat dan hasil kontrol secara terpisah. Jadwal empat dari lima tetap dicatat sebagai pemenuhan parsial.
- **Syarat wajib** — Satu rekomendasi yang bertentangan dengan syarat wajib atau lolos tanpa bukti untuk syarat tersebut menahan TestFlight. Kontrol di bawah minimum harus menampilkan status hasil kurang dan pilihan yang sesuai.
- **Verifikasi perangkat** — Tunjukkan alur rekomendasi hingga itinerary awal pada iPhone fisik dengan layanan live, termasuk validasi jam buka, waktu dan posisi kunjungan wajib, serta ETA pulang. Catat versi build, kondisi layanan, hasil, dan batas pengujian.
- **Artefak** — Simpan brief dan acuan terkunci, keluaran mentah yang boleh disimpan, hasil audit, serta log latensi per tahap, waktu sampai hasil tampil, jumlah panggilan/retry, cache hit, dan alasan kandidat atau jadwal tertahan. Pakai ID skenario untuk log. Hindari token, lokasi pribadi, dan penyimpanan respons provider yang tidak diizinkan. Letakkan hasil lokal di `.local/` dengan direktori per run.

Sesuai pembagian tugas yang sudah dipakai, perubahan kode dan evaluasi akhir dipegang agent utama. Agent GPT-6.1 Terra Medium menjalankan pengujian dan menyimpan hasil. Prioritaskan tahap 1–2. Jika daftar sering gagal mencapai tiga kandidat valid, gunakan hasil audit untuk menentukan apakah yang perlu diperbaiki lebih dulu adalah cakupan pencarian, kecocokan cabang, ketersediaan bukti, atau ranking.


## Arahan lanjutan 12 November 2026

Perbandingan lengkap taksonomi tersimpan di [audit 62 label](LABEL_COMPARISON_62_2026-11-12.md). Pengguna meminta perbandingan luna-provider.example dan Foundation Models pada pekerjaan berikutnya. Samakan tugas, kandidat, sumber bukti, format output, dan validator sebelum membandingkan hasil. Implementasi pencatatan waktu penyusunan dan pencarian rute juga dijadwalkan untuk pekerjaan berikutnya, mencakup waktu sampai jadwal pertama, waktu pencarian selesai, setiap ETA/retry/cache, serta pemuatan geometri.


## Perbandingan routing yang diminta berikutnya

Pengguna meminta pembandingan Apple Maps, pembanding berbasis OSM, dan Valhalla berbasis OSM. Data OSM dapat dipakai oleh beberapa routing engine. Untuk membuat pembanding OSM terdefinisi, rencana ini memilih OSRM dengan profil mobil standar sebagai baseline. Pilihan OSRM adalah keputusan perencanaan yang perlu dicatat pada laporan hasil.

| Lengan | Sumber jaringan jalan | Metode akses pada uji Simulator |
| --- | --- | --- |
| Apple Maps | Data dan layanan Apple | MapKit calculateETA dan calculate |
| OSRM | Ekstrak OSM yang dikunci | Service lab pada Mac/server, profil mobil standar |
| Valhalla | Ekstrak OSM yang sama dengan OSRM | Service lab pada Mac/server, costing auto |

1. Kunci versi engine, konfigurasi profil, tanggal dan hash ekstrak OSM. Gunakan ekstrak wilayah yang cukup luas untuk rute keluar-masuk Jakarta Selatan. API layanan publik dengan dataset atau konfigurasi yang tidak diketahui tidak cukup untuk mengisolasi perbedaan OSRM dan Valhalla. Pembangunan graph, ukuran data, dan kebutuhan RAM dicatat sebagai resource penyiapan.
2. Uji routing jalan dengan koordinat origin/destination atau urutan waypoint yang sama, moda mobil, aturan tol/ferry dan opsi yang dapat disejajarkan. Simpan titik hasil snapping serta jaraknya dari input. Cakup ruas pendek/panjang, dua arah, jalan satu arah, akses terbatas, titik pintu masuk, serta kasus rute tidak ditemukan. Nilai kelayakan jalur menggunakan bukti independen yang tersedia.
3. Ukur waktu respons dari Simulator, waktu pemrosesan layanan jika tersedia, jarak, ETA, jumlah kegagalan, dan geometri. Laporkan cold/warm run, retry, cache, dan request count. Jangan menyimpulkan akurasi ETA hanya dari perbedaan antarlayanan. Verifikasi akurasi waktu tempuh aktual memerlukan observasi perjalanan.
4. Untuk perilaku bergantung waktu, pakai departure time yang sama pada layanan yang mendukung. Catat layanan dan konfigurasi yang statis. Data traffic historis/live Valhalla membutuhkan input tersendiri. Bedakan pengaruh graph/profile, penempatan layanan/jaringan, dan cakupan traffic. Detail internal Apple tidak diasumsikan sama dengan kedua engine terbuka.
5. Setelah routing per ruas diuji, tukar adaptor ETA/geometri pada planner Pocket yang sama. Bekukan kandidat, jam, akses, durasi kunjungan, batas pulang, aturan menunggu, dan anggaran pencarian. Ukur waktu sampai jadwal pertama, waktu selesai, jumlah tujuan, urutan, ETA total, dan pelanggaran batas. Perbandingan ini menguji pengaruh routing provider terhadap itinerary.
6. Pertahankan konfigurasi LLM yang sama pada ketiga lengan. Perbandingan luna-provider.example dan Foundation Models memakai eksperimen tersendiri agar perubahan model tidak ikut mengubah pembandingan routing. Pertahankan cakupan iPhone Simulator sampai ada arahan berikutnya.

Dokumen ini mencatat rencana pengujian berikutnya. Benchmark routing tersebut belum dijalankan.

Rujukan primer — [routing OSM](https://wiki.openstreetmap.org/wiki/Routing), [API OSRM](https://project-osrm.org/docs/v5.24.0/api/), [repositori Valhalla](https://github.com/valhalla/valhalla), [API Valhalla](https://valhalla.github.io/valhalla/api/route/api-reference/), dan [sumber kecepatan Valhalla](https://valhalla.github.io/valhalla/concepts/speeds/).


## Hasil pengerjaan lanjutan

Taksonomi 62 label, impor bukti per label, dan pencatatan waktu planner telah ditambahkan. Run Simulator mencakup satu perbandingan routing dengan Apple Maps serta OSRM dan Valhalla lokal dari ekstrak OSM identik. Pengayaan dengan bukti yang ditinjau menghasilkan tiga rekomendasi outdoor pada percobaan terkontrol. Acceptance 10/12 masih terbuka. Perbandingan model belum menghasilkan keluaran yang bisa dinilai dari sisi hosted. Rincian dan batas masing-masing pengujian tersimpan di [laporan lanjutan](FOLLOWUP_2026-11-12.md).
