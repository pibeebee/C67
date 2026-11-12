# Pengukuran awal engine itinerary — 11 November 2026

## Cakupan dan metode

Replay membandingkan `ItineraryPlanner` Pocket Engine aktual dengan `ContextItineraryPlanner` Context Lab aktual (`firstFeasible`, lebar beam default, shortlist slot default). Keduanya dikompilasi `release` dan dijalankan pada Mac yang sama. Tidak ada panggilan Google Places. Representasi objek Context memakai struktur fixture sintetis yang namanya historis, tanpa data Google aktual atau request provider.

Kedua engine menerima 1–6 tujuan wajib, durasi 60 menit per tempat, keberangkatan pukul 09.00 WIB, pulang ke titik awal, ETA sintetis **10 menit setiap ruas**, anggaran maksimum **60** request, cuaca tidak diaktifkan, dan batas tunggu 120 menit. Kasus longgar menutup semua tempat pukul 20.00; kasus batas ketat berakhir pukul 15.00; kasus jam terbatas menutup tujuan terakhir pada pukul 11.00 dan lainnya pukul 20.00. Identitas/akses Pocket dipasok melalui konfirmasi sintetis; Context menerima fixture jam sintetis dan identitas dikonfirmasi.

Pada kasus longgar: satu run pemanasan dan 10 run per engine dan ukuran; pada dua kasus tambahan: satu pemanasan dan lima run per engine dan ukuran. Waktu adalah median run setelah pemanasan, memakai `ContinuousClock`; pemanggilan ETA hanya closure lokal instan, tidak termasuk jaringan. Run berurutan Pocket lalu Context sehingga hasil mikrodetik rentan beban sistem, bukan perbandingan performa produksi.

Perbedaan yang memengaruhi interpretasi: Pocket menjadwalkan tepat ketika tiba, sedangkan Context memakai grid 15 menit dan dapat menunggu pada tiap pemberhentian. Batas menunggu Pocket berlaku per pemberhentian, sedangkan Context dalam percobaan ini dibatasi total 120 menit. Pocket mengeksplorasi urutan sambil mengutamakan jumlah kunjungan lalu waktu selesai; Context memakai first-feasible dan pemilihan slot. Dengan demikian, masukan ETA dan jendela sama tetapi ruang solusi dan kebijakan **tidak identik**. Tidak mengukur ranking rekomendasi atau kecocokan manusia.

## Hasil kasus longgar

| Jumlah tujuan wajib | Pocket median ms | Context median ms | Pocket ETA | Context ETA | Pocket selesai setelah mulai | Context selesai setelah mulai |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 0,066 | 0,511 | 2 | 4 | 80 menit | 85 menit |
| 2 | 0,072 | 0,779 | 6 | 9 | 150 menit | 160 menit |
| 3 | 0,150 | 1,003 | 18 | 13 | 220 menit | 235 menit |
| 4 | 0,429 | 1,448 | 44 | 16 | 290 menit | 310 menit |
| 5 | 0,538 | 2,360 | 60 | 19 | 360 menit | 385 menit |
| 6 | 0,474 | 4,091 | 60 | 22 | 430 menit | 460 menit |

Semua run menghasilkan seluruh tujuan wajib. Pocket melaporkan pencarian terpotong untuk 5–6 tujuan. Context melaporkan terpotong pada seluruh ukuran karena kebijakan slot/order yang dibatasi. Selisih waktu selesai terutama berasal dari pembulatan slot Context 15 menit, bukan perbedaan ETA atau bukti preferensi.

## Kasus batas ketat dan jam terbatas

| Kasus | Pocket | Context |
| --- | --- | --- |
| Batas 15.00, 5 tujuan | Ditemukan; 60 ETA, selesai tepat 15.00, pencarian terpotong | Tidak ditemukan dalam pencarian; 59 ETA, terpotong. Grid Context memerlukan tambahan tunggu pada fixture ini |
| Batas 15.00, 6 tujuan | Tidak ditemukan; 60 ETA, terpotong | Tidak ditemukan; 58 ETA, terpotong. Secara aritmetika durasi minimum 6×60 + 7×10 = 430 menit, melebihi 360 menit |
| Satu tujuan tutup 11.00, 5 tujuan | Ditemukan; 60 ETA, terpotong | Ditemukan; 54 ETA, terpotong |
| Satu tujuan tutup 11.00, 6 tujuan | Tidak ditemukan; 60 ETA, terpotong | Ditemukan; 60 ETA, terpotong |

Dalam kasus enam tujuan dengan tutup 11.00, jadwal Context adalah bukti adanya jadwal yang layak menurut model slot dan ETA sintetis yang digunakan. Kegagalan Pocket adalah kegagalan pencarian dalam anggaran pada fixture ini, bukan bukti tidak ada jadwal. Output belum diperiksa dengan oracle independen atau dataset kondisi nyata. Pada kasus tanpa rencana, harness mencatat durasi dan jumlah closure ETA serta apakah pesan Pocket menunjukkan batas tercapai.

## Pengukuran Apple ETA terpisah

Tiga permintaan MapKit `calculateETA` berurutan dari Mac menggunakan koordinat publik Jakarta dan keberangkatan sekitar 24 jam ke depan berhasil: **265,10 ms; 120,24 ms; 160,29 ms**. Ini hanya latency tiga ruas tunggal pada satu kondisi jaringan, bukan latency engine end-to-end, bukan pengujian iPhone, dan bukan representasi distribusi atau SLA. ETA hasil Apple tidak digunakan dalam replay komparatif. Detail ada pada `apple-eta.log`.

Waktu proses gabungan seluruh replay skenario tambahan di Mac terukur 0,33 detik wall dan 0,33 detik user, tetapi `/usr/bin/time -l` tidak dapat membaca statistik lanjutan karena `sysctl` dibatasi. Tidak ada pengukuran memori, konsumsi baterai, atau suhu iPhone. Perkalian latency ETA dengan jumlah call tidak disajikan sebagai hasil end-to-end karena jaringan dan cache bervariasi.

## Artefak dan kelanjutan

- `.local/engine-bench/baseline.csv`: 132 run termasuk pemanasan pada kasus longgar.
- `.local/engine-bench/constraints.csv`: 144 run termasuk pemanasan pada dua kasus batas.
- `.local/engine-bench/Sources/Bench/main.swift`: harness terakhir untuk kasus batas; `Sources/Context` adalah salinan sumber Context Lab saat benchmark. Harness awal kasus longgar tersimpan pada riwayat kerja benchmark; baseline CSV adalah hasil awal.
- `.local/engine-bench/build.log`, `constraints-build.log`, `resource.log`, dan `apple-eta.log`: log diagnosa.

Prioritas berikutnya adalah memperbaiki kebijakan Pocket agar lebih cepat mencapai satu jadwal layak dan mempertimbangkan batas tutup yang mendesak, lalu mengulang fixture yang sama dengan pemeriksa kelayakan independen. Lanjutkan dengan kasus opsional, bentrok syarat, ETA gagal, cuaca, jadwal tak mungkin, dan replay jaringan terkontrol. Pengukuran iPhone fisik diperlukan untuk CPU/memori/baterai dan waktu menyeluruh. Tidak mengubah algoritme produksi pada kampanye ini.
