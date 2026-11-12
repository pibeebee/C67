# Statistik pengujian Pocket Engine tanpa Google — 12 November 2026

Rekap artefak yang telah dijalankan, tanpa menjalankan eksperimen baru. Hasil final masing-masing suite digunakan; pengulangan selama pengembangan tidak ditambahkan sebagai sampel independen. Eksperimen versi sebelumnya ditandai terpisah. Tidak ada satu persentase keberhasilan yang mewakili semua lapisan.

## Cakupan final

| Lapisan | Hasil final | Lingkup |
|---|---:|---|
| Core XCTest | 12/12 | Logika engine, host Mac |
| Regresi independen | 5/5 | Tema, bukti, wilayah, validasi, deduplikasi |
| Diagnostik identitas | 1/1 | Dua OSM Taman Literasi menjadi satu kandidat |
| Proxy advisory dengan transport tiruan | 4/4 | Model, JSON/ID, timeout, tidak ada fallback |
| Replay sintetis | 18/18 kasus | Lima pengukuran per kasus |
| XCUITest UI final | 1/1 | iPhone 17e Simulator iOS 27.2 |
| Integrasi app setelah perbaikan | 1/1 | Tiga tempat ditentukan fixture; jam/akses hipotetis |
| Build app Simulator final | Berhasil | Tidak membuktikan perangkat fisik/produksi |
| Build release replay lengkap | Gagal | dsymutil ditolak sandbox setelah executable ter-link |

Core, replay dan proxy bukan tes lapangan. Build release yang gagal tetap dicatat meskipun executable yang ter-link berhasil menjalankan replay.

## Rincian replay final

108 rekaman = 18 warm-up + 90 pengukuran. Ada dua kasus ranking dan 16 kasus planner. Semua 18 kasus memenuhi assertion; empat kasus memang mengharapkan penolakan jadwal.

| Kasus | Hasil yang diamati | Median ms (5 run) | ETA/run* | Terpotong |
|---|---|---:|---:|---|
| Syarat membaca wajib | Ranking sesuai harapan | 0.024 | 0 | Tidak |
| Membaca sebagai preferensi lunak | Ranking sesuai harapan | 0.018 | 0 | Tidak |
| Lima tempat termasuk pin koordinat | Jadwal memenuhi assertion | 1.106 | 18 | Ya |
| Batas pulang termasuk perjalanan kembali | Penolakan sesuai harapan | 0.090 | 2 | Tidak |
| Enam tujuan; satu tutup lebih awal | Jadwal memenuhi assertion | 0.487 | 19 | Ya |
| Berangkat fleksibel untuk makan malam | Jadwal memenuhi assertion | 0.196 | 11 | Tidak |
| Kontrol: berangkat tetap | Jadwal memenuhi assertion | 0.076 | 3 | Tidak |
| Makan malam sebagai tujuan terakhir | Jadwal memenuhi assertion | 0.150 | 7 | Tidak |
| Janji museum tepat waktu | Jadwal memenuhi assertion | 0.197 | 13 | Tidak |
| Lima tempat dengan waktu museum lunak | Jadwal memenuhi assertion | 0.529 | 18 | Ya |
| Memilih slot setelah cuaca aman | Jadwal memenuhi assertion | 0.070 | 2 | Tidak |
| Cuaca wajib belum diketahui | Penolakan sesuai harapan | 0.054 | 1 | Tidak |
| ETA berubah menurut waktu | Jadwal memenuhi assertion | 0.117 | 5 | Tidak |
| ETA permanen tidak tersedia | Penolakan sesuai harapan | 0.059 | 1 | Tidak |
| ETA sementara gagal lalu pulih | Jadwal memenuhi assertion | 0.044 | 3 | Tidak |
| Melewati tujuan opsional tanpa bukti akses | Jadwal memenuhi assertion | 0.080 | 2 | Tidak |
| Jam tujuan wajib kedaluwarsa | Penolakan sesuai harapan | 0.041 | 0 | Tidak |
| Jam khusus tanggal dan sesi terpisah | Jadwal memenuhi assertion | 0.047 | 2 | Tidak |

*ETA dan cuaca di replay adalah transport tiruan, bukan panggilan Apple/WeatherKit. Nilai panggilan per kasus berasal dari ringkasan final.

- Dari 90 pengukuran: 60 menghasilkan itinerary, 20 menolak sesuai harapan, dan 10 hanya menguji ranking.
- Pelanggaran wajib yang ditemukan evaluator replay: 0. Ini terbatas pada assertion dan fixture yang diuji.
- Jadwal dengan searchTruncated=true: 15/60 (25%), dari tiga skenario. Hasil valid tidak membuktikan optimum global.
- Pemanggilan ETA tiruan: 535; kegagalan ETA yang sengaja disuntikkan: 10; pemanggilan cuaca tiruan: 60.

| Kelompok waktu komputasi host | n | Median ms | P95 ms | Minimum–maksimum ms |
|---|---:|---:|---:|---:|
| Seluruh pengukuran | 90 | 0.083 | 1.094 | 0.015–1.230 |
| Menghasilkan itinerary | 60 | 0.146 | 1.102 | 0.037–1.230 |
| Menolak itinerary | 20 | 0.060 | 0.106 | 0.020–0.108 |
| Ranking saja | 10 | 0.023 | 0.032 | 0.015–0.032 |

P95 menggunakan nearest-rank. Angka sub-milidetik ini mengecualikan jaringan, UI, katalog besar dan LLM; bukan latensi aplikasi pengguna.

## Perbandingan model: 12 kasus sintetis diperluas

Input dan acuan dibekukan sebelum pengujian. Masing-masing model mendapat satu run per kasus, tanpa fallback. Foundation Models berjalan di Simulator; Luna melalui provider jarak jauh.

| Model | Benar | ID/format dapat dibaca | Median ms | Min–maks ms |
|---|---:|---:|---:|---:|
| Foundation Models | 3/12 (25%) | 12/12 | 432.61 | 405.23–1498.51 |
| Luna Max | 12/12 (100%) | 12/12 | 2610.82 | 1861.34–4658.84 |

Foundation Models memakai structured generation; Luna mengembalikan JSON. Kelulusan ID tidak membuktikan keputusan benar.

| ID | Kasus | Acuan | Foundation Models | Luna Max |
|---|---|---|---|---|
| S01 | early closing | A | A | A |
| S02 | return leg | B | A | B |
| S03 | split hours | C | A | C |
| S04 | missing required evidence | NONE | A | NONE |
| S05 | rain and evidence coverage | A | A | A |
| S06 | waiting consent | B | A | B |
| S07 | dated exception | C | B | C |
| S08 | branch identity | NONE | A | NONE |
| S09 | soft preference | A | A | A |
| S10 | last stop and deadline | B | A | B |
| S11 | unavailable travel estimate | C | B | C |
| S12 | incompatible time windows | NONE | B | NONE |

- Luna meminta cx/gpt-6-luna(max), provider melaporkan gpt-6-luna(max); alias tidak membuktikan upstream internal.
- Total token yang dilaporkan hanya untuk arm Luna 12 kasus: 1.896 input + 874 completion = 2.770 token.
- Rerun tiga kasus awal: kedua model 3/3. Median Foundation Models 439,51 ms; Luna 1.841,13 ms. Tidak digabung menjadi sampel 15 kasus independen.
- Sampel kecil dan sintetis; tidak membuktikan akurasi populasi, kualitas pengetahuan tempat, atau manfaat tambahan Luna dibanding planner Swift.

## Integrasi HTTP dan aplikasi Simulator

Log server fase integrasi berisi status: {'200': 8, '401': 2, '422': 1}. 401/422 adalah pengujian penolakan yang diharapkan. Dua permintaan Luna fase ini berhasil; tidak termasuk 12-call benchmark model di atas.

| Permintaan Luna fase integrasi | Pilihan | Latensi provider | Hasil |
|---|---:|---:|---|
| HTTP sintetis | 2 | 3.810,50 ms | 200, S1 |
| Alur normal app | 3 | 5.235,30 ms | 200, S1, divalidasi ulang |

| Percobaan pengembangan app | Durasi detik | Hasil |
|---|---:|---|
| 1: diagnostik awal | 5.21 | Katalog integrasi tidak berhasil diunduh. |
| 2: pesan diagnostik diperjelas | 17.45 | Katalog integrasi tidak berhasil diunduh: ID fixture tidak tersedia |
| 3: pencocokan cabang | 17.84 | Fixture tidak memiliki satu padanan cabang pada pool: osm-way-28198231 |
| 4: setelah perbaikan produksi | 35.22 | Berhasil |

Tiga kegagalan awal tidak mencapai ETA/Luna. Hasil 1 berhasil dari 4 percobaan pengembangan bukan estimasi reliabilitas produk: kode/harness diperbaiki antarpercobaan. UI juga sempat gagal pada target tap switch; run berikutnya dengan hit area switch lulus.

- Alur final: 35,22 detik termasuk sinkronisasi 14.835 identitas, canonicalization, konfigurasi, ETA, dan advisory.
- Nature pada ekstrak ini: 417 kandidat lolos di Jakarta Selatan, 0 di Kemayoran. Nol bukan bukti tidak ada tempat alam di Kemayoran.
- 3 kunjungan, 16 ETA Apple langsung, searchTruncated=true. Jam dan akses disimulasikan sebagai konfirmasi pengguna.
- Cuaca tidak tersedia. Titik awal sama dengan tujuan terakhir sehingga ruas pulang tambahan 0; nonzero return diuji secara sintetis, bukan dalam live run ini.
- Perangkat fisik: 0; perjalanan lapangan dengan waktu aktual: 0; distribusi p50/p95 end-to-end belum tersedia.

## Routing: eksperimen tiga ruas terpisah

OSRM dan Valhalla memakai ekstrak OSM lokal yang sama. Apple remote; profil dan traffic tidak ekuivalen. ETA bukan waktu tempuh aktual yang diobservasi.

| Ruas | Apple ETA detik | OSRM detik | Valhalla detik |
|---|---:|---:|---:|
| R01-tebet-literasi | 1692.0 | 503.2 | 504.7 |
| R02-literasi-bendera | 207.0 | 132.4 | 123.0 |
| R03-bendera-tebet | 1443.0 | 574.1 | 609.5 |

12/12 permintaan pembanding ruas berhasil (Apple ETA dan geometry dihitung terpisah). Tiga penyusunan itinerary juga berhasil, masing-masing 16 percobaan ETA, 0 retry, semua pencarian terpotong.

| Engine | Jadwal pertama ms | Penyusunan selesai ms | Estimasi perjalanan detik |
|---|---:|---:|---:|
| apple | 575.00 | 2764.94 | 3416.00 |
| osrm | 13.40 | 42.48 | 1209.70 |
| valhalla | 56.52 | 141.74 | 1237.14 |

Satu run per provider. Latensi lokal vs jaringan remote tidak dapat dipakai menyimpulkan engine lokal lebih akurat atau lebih cepat pada topologi yang sama. Tidak ada acuan waktu lapangan untuk memilih ETA yang paling tepat.

## Data dan kelengkapan bukti

| Katalog seed yang diuji terakhir | Jumlah |
|---|---:|
| Identitas sumber | 14,835 |
| Fakta | 10 |
| Identitas memiliki setidaknya satu fakta | 5 (0.0337%) |
| Identitas memiliki objek jam operasional | 0 |

Ini statistik katalog seed tersebut, bukan seluruh pipeline pengayaan pada chat lain. Identitas bukan unique venue dan kategori sumber bukan bukti seluruh syarat. Empat usulan kopi dan dua fakta historis baru ditahan; sepuluh fakta aktif berasal dari pilot sebelumnya.

Eksperimen cakupan lama memakai input/source berbeda dari run integrasi final. Angka berikut menunjukkan jumlah kandidat lolos filter, bukan precision atau recall terverifikasi.

| Brief | Apple sesi full-index | +14.832 identitas (eksperimen awal) | Pilot 5 identitas tanpa fakta | Pilot yang sama +10 fakta |
|---|---:|---:|---:|---:|
| A01 | 0 | 503 | 0 | 0 |
| A02 | 0 | 87 | 0 | 0 |
| A03 | 0 | 0 | 0 | 0 |
| A04 | 0 | 0 | 0 | 3 |
| A05 | 14 | 45 | 14 | 14 |
| A06 | 5 | 150 | 5 | 5 |
| A07 | 0 | 0 | 0 | 0 |
| A08 | 0 | 0 | 0 | 0 |
| A09 | 25 | 3099 | 25 | 25 |
| A10 | 13 | 441 | 16 | 16 |
| A11 | 0 | 0 | 0 | 0 |
| A12 | 0 | 0 | 0 | 0 |
| B01 | — | — | 0 | 0 |
| B02 | — | — | 0 | 0 |

Apple sesi pilot terpisah: A05=14, A06=5, A09=25, A10=13, sisanya 0. A10 bertambah menjadi 16 melalui tiga identitas taman. A04 bertambah 0→3 hanya setelah fakta outdoor ditambahkan pada pilot.

- Eksperimen awal full-index: 6/12 brief memiliki sedikitnya tiga kandidat; precision top results belum diaudit, bukan 6/12 brief lulus kualitas.
- Pilot terbaru 14 brief: 5/14 memiliki sedikitnya tiga kandidat setelah penambahan fakta; ini availability 35,7%, bukan accuracy. Satu pencarian B02 gagal.
- Empat kebutuhan penting: kopi wajib (A03), outdoor wajib (A04), membaca+publik (A07), anak (A11). Pada pilot hanya A04 pulih menjadi 3; tiga lainnya tetap 0.
- Referensi awal: 10 brief ready, A08/A12 unready. B01/B02 tambahan juga belum ready. Tidak ada pengesahan bahwa target 10/12 rekomendasi nyata sudah tercapai.
- Menambah identitas tidak otomatis menyediakan bukti. Katalog final memiliki 0 objek jam operasional; uji itinerary masih memakai konfirmasi jam hipotetis.

## Sumber artefak dan batas statistik

- .local/implementation-20261112/testing-agent/{REPORT.md,acceptance-final.json,raw-final.jsonl,core-test.log,swift-test.log,http-result.json,http-server.log}
- .local/implementation-20261112/ui-agent/{REPORT.md,integration/flow-output*.json}
- .local/followup-20261112/visit-advice-expanded-20261112/{apple.json,hosted.json,visit-advice-reference.json}
- .local/followup-20261112/{routing-output-local.json,acceptance-output-final.json}
- .local/simulator-acceptance-20261111/{reference.json,run-final-01/output.json}

Biaya rupiah total, total token seluruh proyek, penggunaan CPU/RAM/energi perangkat, reliabilitas banyak pengguna, dan akurasi ETA terhadap perjalanan nyata belum diukur. Persentase limit akun Codex dipakai untuk pengawasan operasional, bukan ukuran konsumsi engine. Tidak ada Google API atau dataset 982 lama dalam pengujian yang direkap di sini.
