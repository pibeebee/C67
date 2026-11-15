# Hasil benchmark itinerary — 6 November 2026

Pengujian terpisah pada **iPhone 17 / iOS 27.0.1 (24A446)**, memakai salinan persis model aplikasi dan package yang sama. Tidak ada pengembangan fitur atau perubahan algoritme PoC. Mode Debug memakai E5 lokal, MapKit dan WeatherKit aktual; fallback Open-Meteo dimatikan. Tanggal rencana 7 November 2026, Jakarta/WIB.

**Hasil:** 17 kasus selesai di iPhone. Audit independen mendukung 15 kasus sesuai kriteria; MIX5 gagal memperoleh itinerary dan TIGHT5 belum konklusif untuk penanganan deadline karena data ETA tidak lengkap. Replay Mac memenuhi 17/17 ekspektasi, tetapi waktunya tidak mewakili latensi provider di iPhone.

## Waktu menghasilkan itinerary yang layak

Tiap keluarga berikut memiliki tiga pengulangan: satu pipeline baru dan dua pengulangan dengan pipeline yang sama. Angka mengukur pemanggilan create/revise sampai proposal selesai disimpan, dengan resolusi polling sekitar 50 ms. Waktu build, pemasangan, load awal, acceptance, audit dan ekspor benchmark dikeluarkan.

| Tujuan | Pipeline baru | Ulang 1 | Ulang 2 | Median | Rentang | Request ETA/run |
| --- | ---: | ---: | ---: | ---: | --- | ---: |
| 1 | 3,53 dtk | 2,42 dtk | 2,51 dtk | 2,51 dtk | 2,42–3,53 dtk | 2 |
| 3 | 28,86 dtk | 28,33 dtk | 28,09 dtk | 28,33 dtk | 28,09–28,86 dtk | 23 |
| 4 | 51,11 dtk | 47,88 dtk | 48,53 dtk | 48,53 dtk | 47,88–51,11 dtk | 39 |
| 5 | 67,12 dtk | 65,13 dtk | 65,39 dtk | 65,39 dtk | 65,13–67,12 dtk | 53 |

Seluruh 12 hasil di atas mempertahankan seluruh tujuan, memenuhi audit jam layanan, durasi dan deadline, serta mempunyai E5 dan cuaca WeatherKit lengkap. N1/N3 berangkat 09.00; N4/N5 berangkat 07.00, semuanya kembali paling lambat 19.00. Ini perbandingan skenario dengan tempat/jam berbeda, bukan eksperimen jumlah tujuan sebagai satu-satunya variabel.

## Routing dan jeda permintaan

| Skenario awal | Preferensi/E5 | Pencarian | Cuaca | Routing | Perkiraan jarak antar-request `(n−1) × 1,2` |
| --- | ---: | ---: | ---: | ---: | ---: |
| N1 | 0,66 dtk | 1,36 dtk | 0,04 dtk | 1,42 dtk | 1,20 dtk |
| N3 | 0,61 dtk | 1,59 dtk | 0,01 dtk | 26,58 dtk | 26,40 dtk |
| N4 | 0,61 dtk | 1,94 dtk | 2,59 dtk | 45,90 dtk | 45,60 dtk |
| N5 | 0,79 dtk | 2,70 dtk | 0,87 dtk | 62,69 dtk | 62,40 dtk |

Kode produksi mempertahankan jarak awal minimal **1,2 detik antar-request ETA**, termasuk saat menjalankan alternatif. Pada N3, 23 request memberi perkiraan 26,4 detik dan routing terukur sekitar 26,6 detik. Pada N5, 53 request memberi perkiraan 62,4 detik dan routing terukur sekitar 62,7 detik. Kedekatan ini mendukung bahwa banyaknya request dan pacing merupakan sumber utama waktu tunggu pada skenario berhasil. Rumus tersebut bukan dekomposisi eksak waktu SDK, bukan klaim komputasi native nol, dan bukan bukti seluruh waktu berasal dari server Apple.

Pipeline hangat memakai ulang E5 dan cache cuaca, sedangkan routing membuat service/cache ETA baru pada setiap plan sesuai implementasi produksi. Karena itu, pengulangan tetap melakukan 23/39/53 request pada keluarga N3/N4/N5. Mengganti model E5 belum didukung sebagai solusi utama dari data ini. Pacing dan algoritme tidak diubah dalam benchmark.

## Kasus tambahan dan kegagalan yang dipertahankan

| Kasus | Waktu | Request ETA | Audit independen |
| --- | ---: | ---: | --- |
| Lima tujuan, tambah 30 menit pada kunjungan terakhir | 55,67 dtk | 45 | Memenuhi kriteria |
| Lima tujuan, durasi 45/90/45/60/30 menit | 76,09 dtk | 60 | Gagal memperoleh itinerary |
| Lima tujuan × 90 menit, rentang 07.00–13.00 | 63,30 dtk | 48 | Belum konklusif: ETA tidak lengkap |
| Meminta enam venue unik | 0,73 dtk | 0 | Memenuhi kriteria |
| Cikini dengan Wi-Fi wajib tanpa bukti | 0,58 dtk | 0 | Memenuhi kriteria |

- **REV5:** jadwal layak baru dihasilkan; referensi baseline, set tujuan dan tambahan durasi benar. Baseline yang diterima dipertahankan saat usulan ditolak. Ada tiga ETA alternatif gagal, tetapi kandidat final mempunyai semua ruas provider yang valid. Waktu revisi lebih pendek karena permintaan yang dijalankan lebih sedikit, bukan karena durasi kunjungan lebih pendek.
- **MIX5:** 60 panggilan ETA provider gagal dengan `MKErrorDomain code 4 / Directions Not Available`; nol respons ETA berhasil. WeatherKit tetap lengkap. Setelah 76,09 detik, aplikasi mengeluarkan konflik data transportasi dan tidak mengarang ETA atau menghapus tujuan. Ini kegagalan menghasilkan itinerary; bukan bukti kombinasi durasinya mustahil.
- **TIGHT5:** 12 dari 48 panggilan ETA gagal; 36 berhasil. Hasil menyebut data transportasi belum cukup dan tidak semua tujuan berhasil dijadwalkan. Walaupun 450 menit kunjungan secara matematis tidak muat dalam 360 menit, run ini tidak membuktikan aplikasi menolak karena deadline. Harness semula menghitung status generik conflicted sebagai pass; audit independen memperketat interpretasinya menjadi belum konklusif.
- **SIX:** berhenti untuk koreksi sebelum pencarian/routing; katalog hanya mempunyai lima venue unik yang dapat dijadwalkan pada snapshot ini. Waktu 0,73 detik adalah waktu menampilkan kebutuhan koreksi, bukan waktu membuat itinerary enam tujuan.
- **UNKNOWN:** berhenti sebelum pencarian/routing; tujuan wajib tetap dipertahankan. Waktu 0,58 detik adalah penanganan fakta yang belum cukup.

Penyebab dasar kegagalan MapKit belum dipastikan. Log tidak secara eksplisit membuktikan throttling atau kuota. Kegagalan mulai terlihat pada sebagian alternatif REV5, meluas pada MIX5, dan sebagian request berhasil kembali pada TIGHT5. Tidak ada penggantian provider, retry eksperimen baru, atau perubahan source produksi untuk mengejar kelulusan.

## Audit bukti dan pemulihan

- Audit Python memeriksa status/matriks, pilihan tetap, durasi penuh, grid 15 menit, jendela mulai bersumber, deadline hasil ready, jumlah ruas, metadata E5, sumber cuaca, mode live/replay, serta request pada raw routing report versus log sesi terkait.
- Snapshot log pipeline yang dipakai ulang juga membawa sesi sebelumnya. Auditor mengisolasi sesi routing terakhir, bukan menjumlahkan semua sesi. ETA alternatif yang gagal dihitung terpisah dari kandidat final yang valid. Penyesuaian ini memperbaiki analisis, tanpa mengubah artefak device atau ekspektasi matriks.
- Source/masukan produksi yang di-hash sebelum dan sesudah: **66 file identik**. Salinan IntegrationModel juga identik byte demi byte.
- Binary aplikasi asli dibangun, dipasang ulang dan diluncurkan normal sesudah benchmark. **Sembilan file penyimpanan perjalanan asli identik** sebelum dan sesudah pengujian.
- Run awal `D1FDD0FE-E392-4EA3-B42E-939D4F93DC27` terputus ketika mekanisme peluncuran otomatis dan retry manual berurutan meluncurkan ulang aplikasi. Tiga hasil N1 dan status N3 yang terputus tetap disimpan, dikeluarkan dari ringkasan utama. Run utama lengkap adalah `A0A6EC2D-C0DF-457C-94BF-5415FF735F01`.
- Seluruh thermal state pada 17 kasus utama tercatat nominal. RAM, baterai, Low Power Mode, variasi jaringan, kondisi background, rendering UI dan distribusi lintas perangkat tidak diukur.

## Batas kesimpulan

Angka sekitar 30 detik didukung untuk skenario tiga tujuan ini. Skenario empat tujuan sekitar 48–51 detik dan lima tujuan sekitar 65–67 detik. Waktu dan keberhasilan juga bergantung pada respons provider serta constraint, sehingga jumlah tempat saja tidak menentukan durasi. Tiga pengulangan berurutan dan satu perangkat tidak mendukung klaim p95, SLA, atau kecepatan umum seluruh Jakarta. Pipeline baru bukan jaminan cache OS/provider kosong; urutan fixed dan run awal juga dapat menghangatkan cache sistem.

## Artefak

- [Protokol dan matriks](PROTOCOL.md)
- [Analisis JSON utama](artifacts/iphone-final/A0A6EC2D-C0DF-457C-94BF-5415FF735F01/analysis.json)
- [CSV semua kasus](artifacts/iphone-final/A0A6EC2D-C0DF-457C-94BF-5415FF735F01/metrics.csv)
- [Status asli iPhone](artifacts/iphone-final/A0A6EC2D-C0DF-457C-94BF-5415FF735F01/status.json)
- [Hasil replay dan auditnya](artifacts/replay-initial/analysis.json)
- [Bukti integritas penyimpanan](artifacts/normal-store-preservation.json)
- [Manifest source awal](original-source-manifest.json)

Seluruh hasil disimpan lokal; tidak ada commit, push atau deployment. Log build/perangkat serta data mentah lokal belum dipersiapkan sebagai paket publik.
