# Benchmark simulator live — 6 November 2026

## Hasil utama

**51 observasi utama selesai:**17 kasus × 3 varian.42 itinerary layak dan9 outcome non-ready sesuai kasus; seluruh51 lolos auditor independen. Seluruh hasil ready mempunyai E5 aktual, WeatherKit tersedia, semua tujuan/durasi/jam/deadline yang valid. Tidak ada ETA gagal pada dataset utama.

Varian **A** menjalankan orkestrasi/package native asli di simulator. **B** menjalankan engine setara lewat server Mac dengan ETA REST single-pair. **C** memakai server/engine yang sama dengan batching snapshot dan passage embedding yang dipersiapkan. Tidak ada LLM judge.

**Lingkup yang terbukti adalah perencanaan dengan pin tempat nyata yang sudah sama. Pencarian end-to-end REST belum lolos untuk seluruh venue.** Benchmark ini tidak membuktikan waktu discovery-to-itinerary produk secara penuh, dan bukan pengganti pengukuran iPhone fisik.

| Tujuan | A native simulator | B server dasar | C server optimasi | Pengurangan paired C/A |
| --- | ---: | ---: | ---: | ---: |
| 1 | 2,13 | 1,96 | 2,25 | — |
| 3 | 27,41 | 27,54 | 20,34 | 26,85% |
| 4 | 46,68 | 46,76 | 31,08 | 33,43% |
| 5 | 63,44 | 63,52 | 35,98 | 43,39% |

Angka waktu dalam detik; tiga pengulangan fresh per keluarga. Persentase memakai median rasio per pasangan, bukan rasio dua median. C mengurangi waktu untuk3–5 tujuan, sedangkan B tidak menunjukkan percepatan berarti terhadap A pada keluarga tersebut. C belum memberi manfaat pada satu tujuan yang hanya memerlukan dua ETA.

Target awal adalah pengurangan≥30% pada **setiap** keluarga N3/N4/N5. Hasil N3 sekitar26,9%, N4 sekitar33,4%, N5 sekitar43,4%. Jadi target keseluruhan **belum tercapai**, meskipun N4/N5 memenuhi ambangnya. Sampel ini tidak mendukung p95, SLA, signifikansi populasi atau optimum global.

## Mengapa angka dapat disejajarkan dengan benchmark sebelumnya

Tujuan, katalog/fakta, tanggal trip7 November2026, WIB, Bundaran HI sebagai awal/akhir, durasi, deadline dan objective elapsed_v2 dipertahankan. Keenam nama serta koordinat pin **identik** dengan N5-R3 iPhone sebelumnya. Tidak ada tujuan dibuang atau ETA pengganti sintetis. Seluruh66 file source/input acuan tetap identik, dan salinan IntegrationModel byte-identik.

| Tujuan | iPhone17 sebelumnya, E2E | A simulator sekarang, pin siap |
| --- | ---: | ---: |
|1|2,51|2,13|
|3|28,33|27,41|
|4|48,53|46,68|
|5|65,39|63,44|

Tabel historis membantu menilai konsistensi pola, bukan menghitung klaim percepatan perangkat. Run lama memakai iPhone17/iOS27.0.1, live search, satu pipeline baru+dua reuse. Run baru memakai simulator iPhone18ProMax/iOS27.2 pada Mac Apple M5/24GiB/macOS27.2, pin disiapkan, dan tiga pipeline fresh. Cache OS/provider serta aktivitas background tidak dikendalikan. iPhone fisik tidak dipakai pada pekerjaan ini.

Timer monotonic client dari create/revise hingga hasil lengkap tersimpan; B/C mencakup loopback HTTP, antrean, polling100ms, transfer dan persist. A juga mencakup adapter/export client di luar penyimpanan asli. Build, precompute dan acceptance baseline berada di luar timer. Run lama mengecualikan load awal/audit/export benchmark; karena itu perbandingan utama yang adil adalah **A/B/C simulator dalam blok berpasangan**, bukan persentase terhadap kolom iPhone.

## ETA, pacing dan variasi

| Kasus | Call A | Call B | Call C | Median cells A/B/C |
| --- | ---: | ---: | ---: | --- |
| N1 | 2 | 2 | 2 | 2 / 2 / 2 |
| N3 | 23 | 23 | 17 | 23 / 23 / 23 |
| N4 | 39 | 39 | 26 | 39 / 39 / 39 |
| N5 | 53 | 53 | 30 | 53 / 53 / 52 |

B/C mempertahankan pacing1,2 detik antarpanggilan dan concurrency1; A mempertahankan implementasi aslinya. C mengemas maksimal10 tujuan dengan asal/moda/departure persis sama. Ruas final tetap divalidasi pada departure setelah kunjungan sebelumnya. Perbedaan kecil cell pada live diperlihatkan; provider native/REST dapat memberi ETA berbeda dan mengubah keputusan pencarian. Parity algoritme dinilai pada oracle replay bersama, bukan memaksa objective live identik.

Pada dataset utama: **1286 panggilan ETA tingkat aplikasi /1453 cells**, nol ETA gagal. Native SDK dapat mempunyai traffic internal yang tidak terlihat; jumlah HTTP REST dan logical SDK calls bukan jumlah paket jaringan yang identik.

Satu run B N4-R3 memerlukan97,21 detik, dibanding dua run B lain sekitar46,7 detik. Cuaca lengkap,39 ETA tersedia. Raw log memperlihatkan beberapa respons ETA9–18 detik; penyebab dasar tidak dipastikan. Outlier ini tetap dihitung. Tidak diberi label throttling/quota dan tidak diulang untuk menggantinya.

## Kasus tambahan

| Kasus | A detik | B detik | C detik | Outcome |
| --- | ---: | ---: | ---: | --- |
| Tambah30 menit | 63,87 | 64,72 | 36,03 | Ready ketiganya |
| Durasi campuran | 68,19 | 68,34 | 34,69 | Ready ketiganya |
| 450 menit kunjungan /360 menit tersedia | 46,75 | 46,80 | 0,17 | A/B no_feasible_candidate; C lower-bound proof |
| Enam venue diminta | 0,70 | 0,18 | 0,15 | needs_places ketiganya |
| Wi-Fi wajib tanpa bukti | 0,63 | 0,16 | 0,14 | needs_places ketiganya |

REV5 memperpanjang kunjungan terakhir baseline varian itu sendiri30 menit. Auditor memeriksa base accepted ID, set tujuan dan hanya durasi yang dimaksud berubah. SQLite B/C tetap menyimpan accepted N5-R3 revision3 setelah proposal revisi/kasus lain; proposal tidak otomatis diterapkan.

TIGHT5 pada C menyimpan proof27000>21600 detik tanpa ETA. A/B hanya menyatakan pencarian terbatas belum menemukan kandidat layak; ini bukan sertifikat global infeasible. SIX/UNKNOWN adalah waktu meminta koreksi, bukan itinerary enam tujuan. MIX5 pada benchmark iPhone lama gagal mendapatkan ETA; keberhasilannya sekarang tidak membuktikan server menghilangkan outage provider.

## Pencarian end-to-end yang ditemukan

Blok awal menghasilkan13 observasi: empat A ready dan sembilan B/C needs_locations. Adapter REST awal belum memakai filter POI sehingga respons berupa area/jalan. Perbaikan menambahkan resultTypeFilter=poi dan region Jakarta45km seperti native. API juga menolak searchLocation+searchRegion bersamaan; kini hanya region dikirim. Tes regression ditambahkan.

Setelah perbaikan, preflight REST memastikan Cikini, BDT, Erasmus dan Ragunan, tetapi origin masih ambigu dan GBK tidak ditemukan. Tidak ada cabang yang dipilih manual hanya untuk B/C. Snapshot bersama berasal dari **enam hasil native MapKit aktual yang tidak ambigu**, lalu diterapkan pada A/B/C. Resolusi lokal snapshot tetap melewati identity policy. Angka mapkit_search.requests pada raw plan adalah jumlah lookup logis ke snapshot, bukan HTTP search; network discovery tidak termasuk timer blok terkontrol.

Temuan ini membatasi kesimpulan produk: batching mempercepat perencanaan sesudah identitas lokasi tersedia; jalur discovery REST masih perlu diperbaiki sebelum mengklaim percepatan E2E penuh.

## Host sleep, timeout dan pemilihan blok

Blok terkontrol pertama menyelesaikan18 observasi N3/N4 sebelum sleep. Pada20.20WIB Mac memasuki Idle Sleep; sampler kemudian mempunyai gap154/107/299 detik dan dua job N5 timeout. Ketiganya didukung log pmset. Seluruh hasil, termasuk tiga N5 awal yang ready dan dua timeout, dipertahankan sebagai bukti terpisah. Timeout adalah censored; tidak menjadi nilai itinerary berhasil.

Aturan pemulihan dibekukan **sebelum blok lanjutan**: pertahankan seluruh keluarga N3/N4 yang selesai sebelum sleep; ulang seluruh keluarga N5, termasuk hasil awal yang berhasil; jalankan seluruh keluarga yang belum dieksekusi. Ini bukan memilih hanya retry yang berhasil. Blok lanjutan33 observasi memakai caffeinate sementara; interval sampling maksimum5,08 detik, tanpa gap panjang. Tidak ada pengaturan daya permanen diubah.

Dataset utama=18 observasi sebelum sleep+33 observasi lanjutan. Pin dan source engine identik antarkedua blok; satu perubahan harness hanya memilih keluarga kasus sesuai manifest pemulihan. Kondisi daya host berubah dari AC ke baterai pada rentang gangguan; pasangan A/B/C masing-masing keluarga berada dalam bloknya sendiri. Raw block, selection manifest, seluruh timeout dan outlier tetap tersedia.

Satu percobaan startup terkontrol sebelumnya timeout pada capabilities dengan nol observasi/provider call. Itu juga dipertahankan, terpisah dari pengukuran.

## Resource dan budget

Server satu worker/satu runtime E5 CPU, tanpa homelab/cloud/GPU. Pada blok lanjutan,186 sampel ps interval5 detik menunjukkan RSS maksimum457,5MiB dan maksimum%CPU yang dilaporkan ps29,1. Ini observasi satu proses, bukan kebutuhan RAM produksi atau profiler CPU/energi. Simulator dan server berbagi Mac, dan cache/provider/background belum terkontrol.

Ledger gabungan+cadangan awal adalah **1925 dari batas3000 panggilan aplikasi**; sisa quota akun Apple sendiri tidak diketahui. Tidak ada429. Ledger mencakup blok awal, diagnosis, blok terganggu dan kelanjutan; SDK weather diukur sebagai invocation grup, bukan HTTP internal. Warm/priming tambahan di luar17 kasus tidak dijalankan.

Preflight setelah adaptasi meluluskan62 tes lokal(27 XCTest+35 Swift Testing). Auditor merekonstruksi waktu, sesi sumber, durasi utuh, deadline kembali, sel final dan native log sesi terkait, accounting, weather coverage dan revisi. Enam negative controls dipalsukan lalu ditolak. Tidak ada perubahan runtime/source selama pengukuran dalam masing-masing blok; auditor/postprocessing diperketat tanpa mengubah hasil mentah.

## Pemulihan dan artefak

Server dihentikan, token sementara dicabut, assertion caffeinate dilepas, dan aplikasi simulator asli dipasang/dibuka kembali. Tidak ada uninstall, perubahan source produksi, akses homelab, commit/push atau deploy.

- Ringkasan JSON (original local evidence, omitted from this publication)
- CSV per observasi (original local evidence, omitted from this publication)
- CSV historis (original local evidence, omitted from this publication)
- Audit independen (original local evidence, omitted from this publication)
- Aturan penggabungan blok (original local evidence, omitted from this publication)
- Sumber pin historis yang identik (original local evidence, omitted from this publication)
- Ledger budget (original local evidence, omitted from this publication)
- Verifikasi sumber (original local evidence, omitted from this publication)
- Resource (original local evidence, omitted from this publication)
- Raw E2E awal (original local evidence, omitted from this publication)
- Raw blok terganggu (original local evidence, omitted from this publication), sleep/wake (original local evidence, omitted from this publication)
- Raw kelanjutan33 (original local evidence, omitted from this publication), manifest kelanjutan (original local evidence, omitted from this publication)
- Layar kelanjutan selesai (original local evidence, omitted from this publication)
- Benchmark iPhone sebelumnya (original local evidence, omitted from this publication)

Filter/region REST mengacu pada [parameter search resmi Apple](https://developer.apple.com/documentation/applemapsserverapi/-v1-search); ketidakcocokan parameter dan hasil lokasi juga tersimpan sebagai bukti respons aktual dalam folder diagnosis awal.
