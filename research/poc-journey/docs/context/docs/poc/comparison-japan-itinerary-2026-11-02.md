# Laporan perbandingan PoC — input, hasil sebelumnya, dan hasil sekarang

Tanggal pengujian: 2 November 2026. Tanggal perjalanan: **5 Desember 2026**, zona waktu **JST / Asia/Tokyo**. Seluruh jam itinerary pada laporan ini adalah JST.

**Kesimpulan:** pipeline baru berhasil dijalankan, termasuk browser, simulasi waktu berurutan dan satu repair otomatis. Perbaikan menghilangkan dua konflik yang dideteksi kode, tetapi hasil akhir belum menjadi itinerary terverifikasi. Jadwal baru lebih panjang, data kereta/restoran masih kurang, browser belum menghasilkan fakta baru berkutip, dan AI masih dapat mengubah alokasi perjalanan tanpa bukti rute.

## 1. Lingkup dan kesetaraan perbandingan

- Input semantik sama persis dengan baseline: **true**, diperiksa dengan deep equality atas objek input tersimpan.
- Seluruh hash file TypeScript src tetap sama dari awal sampai akhir pengujian: **true**. Tidak menerapkan usulan native tool calling, reviewer terpisah, atau perubahan algoritme berikutnya.
- Baseline adalah hasil final eksperimen tanpa jam sebelumnya, bukan audit bertanggal 5 November yang memiliki 24 timestamp.
- Memakai model yang sama: `nvidia/nemotron-3.5-super-vl:free`, reasoning on, plafon konteks 1.000.000 token.
- Run pertama memakai completion 16.384. Setelah tiga keluaran terpotong, satu run diagnostik memakai completion 32.768 melalui environment per perintah; file .env dan kode tidak diubah. Snapshot evidence run pertama digunakan ulang.
- Model nondeterministik, jumlah putaran berbeda, kebijakan buffer berbeda, serta diagnostik mengubah completion budget. Ini perbandingan kasus teramati, bukan benchmark terkontrol atau bukti keunggulan umum model.
- Chromium dipasang untuk menjalankan pipeline browser. Tidak menjalankan ulang suite unit test atau melakukan implementasi fitur berikutnya.

## 2. Input pengguna

| Komponen | Input |
|---|---|
| Tanggal | 5 Desember 2026 |
| Lama trip | Satu hari; kembali pada tanggal yang sama |
| Titik awal dan akhir | JR Funabashi Station |
| Jam berangkat/kunjungan/pulang | Tidak diberikan |
| Durasi tiap kunjungan | Tidak diberikan |
| Aktivitas | 14 aktivitas dari daftar sebelumnya, termasuk Oiwayamichi yang opsional |
| Moda | Kereta dan jalan kaki, enam pasangan transit dipertahankan |
| Coastal walk | Shichirigahama → Kamakurakokomae, WALK |
| Restoran/toko/detail spot | Sebagian belum ditentukan; tidak dipilih diam-diam oleh sistem |

Enam pasangan kereta: Funabashi→Kamakura; Kamakura→Inamuragasaki; Inamuragasaki→Shichirigahama; Kamakurakokomae→Enoshima; Katase-Enoshima→Fujisawa; Fujisawa→Funabashi.

## 3. Ringkasan output

| Aspek | Sebelumnya: pipeline tanpa browser | Sekarang: default 16.384 | Sekarang: diagnostik 32.768 |
|---|---|---|---|
| Hasil | Proposal lengkap, belum terverifikasi | no_valid_proposal | needs_information |
| Proposal AI dalam run | Baseline tersimpan berasal dari repair; keseluruhan proses lama 2 panggilan | 3, semuanya finish_reason=length | 2, keduanya selesai; hasil kedua dipilih |
| Aktivitas yang dijadwalkan | 14/14 | Belum ada proposal valid | 14/14 |
| Pasangan kereta / coastal walk | 6/6, coastal walk ada | Belum dapat dinilai | 6/6, coastal walk ada |
| Berangkat–kembali | 07:00–22:00 | Belum ada | 04:30–23:26 |
| Lama rentang trip | 15 jam | Belum ada | 18 jam 56 menit |
| Walking punya estimasi | 11/21 seluruh perpindahan | Evidence awal tersedia, simulasi belum berjalan | 10/20 seluruh perpindahan |
| Perpindahan belum terverifikasi | 6 transit + 4 terkait restoran | Sama pada evidence awal | 6 transit + 4 terkait restoran |
| Walking dengan sisa alokasi <1 menit | 8/11 | Belum dapat dinilai | 0/10; alokasi dikenal memenuhi buffer >=5 menit |
| Propagasi waktu | Belum ada | Belum mencapai simulasi | Berjalan; perubahan sebelumnya menggeser kegiatan berikutnya |
| Repair otomatis | Belum ada; perbaikan lama dijalankan manual | Percobaan ulang terjadi, tetapi keluaran tetap terpotong | 1 repair berbasis hasil simulasi |
| Cuaca/sunset | Tidak tersedia pada evidence | Di luar horizon | Di luar horizon; tidak dikarang |
| Bukti browser baru | Tidak ada browser runtime | 4/7 halaman terbaca; 0 klaim baru | Snapshot sama; 0 klaim baru |

Jumlah walking yang punya estimasi turun dari 11 ke 10 karena pola perpindahan berubah: hasil lama melewati Katase-Enoshima sebelum makan malam, sementara hasil baru langsung dari Sea Candle ke restoran yang belum diketahui. Ini bukan bukti provider menjadi lebih buruk. Jumlah kategori unknown total juga tidak dibandingkan langsung karena cakupan pemeriksaan versi baru lebih luas.

## 4. Perbandingan setiap aktivitas

Kolom input sengaja tidak mempunyai jam. Kolom sekarang memakai hasil simulasi proposal kedua pada run 32.768, bukan draf awal yang masih berkonflik. Baris perpindahan/wait antara aktivitas tersedia pada laporan mentah.

| Tempat / kegiatan dari input | Jam input | Output sebelumnya | Output sekarang |
|---|---|---|---|
| Berangkat dari Stasiun Funabashi | Tidak diberikan | 07:00 | 04:30 |
| Stasiun Kamakura & Komachi Street | Tidak diberikan | 08:25–09:00 | 06:21–07:01 |
| Tsurugaoka Hachimangu & Perempatan | Tidak diberikan | 09:10–10:00 | 07:17–08:07 |
| Makan Siang Pagi (Area Kamakura) | Tidak diberikan | 10:10–11:00 | 08:22–09:22 |
| Kamakura Seaside Park (Cape Inamuragasaki) | Tidak diberikan | 11:30–12:00 | 11:02–11:42 |
| Shichirigahama Beach (Depan Sekolah) | Tidak diberikan | 12:25–13:05 | 13:15–13:55 |
| Coastal walk Shichirigahama → Kamakurakokomae | Tidak diberikan | 13:05–13:23 | 13:55–14:18 |
| Kamakurakokomae Station (Foto Area Stasiun) | Tidak diberikan | 13:23–13:50 | 14:23–14:53 |
| Toko Suvenir Enoshima Station | Tidak diberikan | 14:10–14:30 | 15:28–15:48 |
| Fujisawa City Tourist Center | Tidak diberikan | 14:40–15:30 | 16:08–16:38 |
| Enoshima Ohashi Bridge (Video & Jalan Santai) | Tidak diberikan | 15:35–16:00 | 16:53–17:23 |
| Oiwayamichi Street (Opsional) & Naik ke Atas | Tidak diberikan | 16:15–16:45 | 17:48–18:18 |
| Tiba di Area Enoshima Sea Candle | Tidak diberikan | 16:53–17:25 | 18:36–18:56 |
| Menyaksikan Illumination | Tidak diberikan | 17:35–18:20 | 18:56–19:56 |
| Turun dari Pulau & Makan Malam di Enoshima | Tidak diberikan | 18:54–19:50 | 20:11–21:11 |
| Seichi Junrei Malam Stasiun Fujisawa (Menara Jam) | Tidak diberikan | 20:10–20:40 | 21:56–22:26 |
| Kembali ke Stasiun Funabashi | Tidak diberikan | 22:00 | 23:26 |

## 5. Apa yang benar-benar berhasil diperbaiki secara otomatis

- Pada proposal pertama run 32.768, kode memperpanjang sembilan alokasi berjalan agar mencakup estimasi provider dan buffer. Perubahan dipropagasikan ke kegiatan berikutnya.
- Simulasi menemukan Tourist Center selesai 17:08, melewati batas 17:00, dan kepulangan pada 00:27 tanggal 6 Desember, melanggar trip satu hari.
- Proposal kedua memindahkan keberangkatan dari 05:00 ke 04:30, mengubah beberapa alokasi, menempatkan Tourist Center 16:08–16:38, serta mengembalikan kepulangan ke 23:26 tanggal 5 Desember.
- Simulasi kedua mencatat nol penambahan waktu dan nol konflik jam/tanggal yang diketahui. Seluruh tujuan tetap ada. Ini bukti jalur proposal–simulasi–repair otomatis benar-benar dieksekusi pada run ini.
- Status akhir tetap needs_information karena bukti pendukung belum lengkap. Tidak ada klaim seluruh perjalanan terverifikasi.

## 6. Masalah kualitas yang masih terlihat

### 6.1 Durasi transit berubah tanpa bukti baru

Fujisawa→Funabashi dialokasikan 80 menit pada hasil lama, 60 menit pada draf awal run baru, lalu 55 menit setelah repair. Seluruh query terkait tetap no_route. Jadi keberhasilan kembali pada tanggal yang sama belum membuktikan waktu pulangnya realistis. Model dapat membuat jadwal tampak muat dengan mengganti angka yang belum punya dasar. Ini memerlukan pemeriksaan semantik dan kebijakan alokasi unknown yang lebih kuat.

### 6.2 Jadwal lebih panjang dan beberapa aktivitas terlalu awal untuk dinilai sesuai pengalaman

Berangkat 04:30 dan kembali 23:26 membentuk rentang 18 jam 56 menit, lebih panjang 3 jam 56 menit daripada hasil lama. Komachi ditempatkan 06:21–07:01, sementara aktivitas berlabel makan siang ditempatkan 08:22–09:22. Belum ada bukti jam toko/restoran yang membuat waktu tersebut sesuai. Ini belum dinyatakan mustahil, tetapi belum cukup untuk merekomendasikannya sebagai pengalaman yang baik.

### 6.3 Buffer berpotensi dihitung berlapis

Ada 125 menit baris wait eksplisit pada proposal kedua, di samping buffer yang sudah berada di alokasi movement. Contoh: Kamakura Station→Komachi sudah 11 menit (estimasi sekitar 5,7 + buffer 5), lalu ada wait tambahan 5 menit berlabel buffer jalan kaki. Ini indikasi buffer berlapis yang perlu ditinjau, bukan bukti semua waktu tunggu tidak diperlukan.

### 6.4 Browser berjalan, tetapi belum menghasilkan fakta tambahan yang dapat dipakai

- Empat halaman terbaca: Tourist Center, beranda Enoden, halaman timetable Enoden, dan beranda Hachimangu. Halaman timetable HTML yang terbaca bukan otomatis data jadwal kereta yang berhasil diekstrak.
- Dua halaman Sea Candle mendapat HTTP 200 tetapi pembaca gagal mengekstrak teks. Ini kegagalan pembacaan pada run ini, bukan bukti situs tidak dapat diakses secara umum. JR East mendapat HTTP 403.
- Kedua pencarian Bing berstatus unavailable. Penyebab spesifik seperti CAPTCHA, selector, consent, atau filtering tidak dapat ditetapkan dari pesan generik yang disimpan.
- Nol klaim diterima dan nol klaim ditolak: model tidak mengirim kandidat klaim yang kemudian ditolak validator pada kedua putaran riset yang selesai. Jam/acara yang dipakai masih bersumber dari file konteks awal.
- Riset berhenti pada putaran kedua meski trace masih memuat aksi read lanjutan, termasuk Odakyu yang tidak terbaca dalam daftar halaman. Inferensi dari trace dan kondisi kode: flag done menghentikan proses sebelum aksi pada respons yang sama dijalankan. Respons mentah flag tersebut tidak disimpan, sehingga ini merupakan inferensi kode, bukan kutipan respons mentah.
- Permintaan membaca ulang halaman Sea Candle yang gagal mengembalikan entry cache unavailable pada implementasi sekarang; permintaan itu tidak otomatis menjadi percobaan navigasi baru.

### 6.5 Angka nol konflik mempunyai cakupan terbatas

Issue akhir: {"ROUTE_UNVERIFIED":6,"PARTIAL_PLACE_MATCH":2,"OPENING_HOURS_UNCONFIRMED":11,"MISSING_LOCATION":4,"FORECAST_UNAVAILABLE":4}. Enam transit, empat perpindahan terkait restoran, dua kecocokan lokasi parsial, sebelas aktivitas tanpa constraint jam buka, serta empat area forecast belum lengkap. Nol konflik berarti tidak ada pelanggaran pada pemeriksaan yang memiliki data, bukan semua kebutuhan nyata telah dipenuhi.

## 7. Hasil konfigurasi dan penggunaan AI

| Proses | Panggilan AI | Total token dilaporkan | Hasil |
|---|---:|---:|---|
| Proses lama: generasi + repair manual | 2 | 37.555 | Proposal akhir lengkap, belum terverifikasi |
| Pipeline baru default 16.384 | 5 | 94.765 | Riset 2 panggilan; 3 proposal terpotong |
| Ulang proposal dengan 32.768, evidence reuse | 2 | 68.292 | Dua proposal lengkap; repair dijalankan |
| Total dua run baru | 7 | 163.057 | Riset tidak diulang pada diagnostik |

Completion mencakup reasoning dan jawaban akhir. Tiga proposal default menghabiskan 16.384 completion masing-masing dengan finish_reason length; ini bukan plafon konteks 1M yang tercapai. Dengan 32.768, proposal pertama memakai completion 21.883 dan kedua 14.235. Tidak ada klaim bahwa sekadar menambah token menyelesaikan kualitas fakta.

Request Google baru: 16 pada run default dan 13 pada run diagnostik. Jumlah request bukan estimasi tagihan. Kedua run tidak meminta forecast yang diketahui di luar horizon.

## 8. Penilaian terhadap tujuan PoC

**Lebih baik dalam pemeriksaan aritmetika dan pemulihan konflik:** buffer, propagasi waktu, deteksi melewati jam tutup/tanggal, serta repair otomatis terbukti berjalan.

**Belum lebih baik sebagai rekomendasi perjalanan siap pakai:** data kereta belum terselesaikan, browser belum memberi fakta baru berkutip, jadwal menjadi sangat panjang, dan angka transit tanpa bukti masih dapat diganti agar jadwal muat. Hasil ini memperkuat prioritas pengelolaan kebutuhan bukti, validasi applicability sumber, peninjauan semantik dan penghentian riset berbasis kelengkapan yang sudah dibahas. Usulan tersebut belum diimplementasikan pada pengujian ini.

## 9. Artefak untuk diperiksa

- [Input yang digunakan](../../../../apps/ai-trip-planner/results/japan-2026-12-05-researched-run1/user-input.json)
- [Hasil lama](../../../../apps/ai-trip-planner/results/japan-2026-12-05-untimed-run2/report.md)
- [Hasil baru default, tanpa proposal valid](../../../../apps/ai-trip-planner/results/japan-2026-12-05-researched-run1/report.md)
- [Hasil baru 32.768: tabel simulasi lengkap](../../../../apps/ai-trip-planner/results/japan-2026-12-05-researched-run2-32k/report.md)
- [Riset browser dan trace](../../../../apps/ai-trip-planner/results/japan-2026-12-05-researched-run1/research.json)
- [Proposal kedua + metadata](../../../../apps/ai-trip-planner/results/japan-2026-12-05-researched-run2-32k/attempt-2/ai.json)
- [Simulasi kedua](../../../../apps/ai-trip-planner/results/japan-2026-12-05-researched-run2-32k/attempt-2/simulation.json)
- [Perbandingan mesin dan hash kode awal](../../../../apps/ai-trip-planner/results/japan-2026-12-05-researched-run2-32k/comparison.json)

Direktori results diabaikan Git; tautan memerlukan artefak lokal. Laporan ini menampilkan observasi run dan penilaian manual, bukan hasil reviewer AI baru atau validasi perjalanan lapangan.
