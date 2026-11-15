# Algoritme dan pembanding routing — PoC iOS C67

Implementasi **3 November 2026**, pada `<LOCAL_HOME>/Programming/software/ios/poc-c67`. Ini satu aplikasi dengan pilihan engine native dan layar pembandingan; OR-Tools berjalan pada helper Mac yang bertukar file dengan aplikasi, bukan dibundel di iPhone.

## Memakai pada itinerary sendiri

Di **Pengaturan → Algoritme itinerary**, pilih:

- **Hybrid · durasi trip** (default): cheapest insertion, beberapa seed termasuk batas waktu, dan multi-start swap/relocate dalam budget bersama.
- **Baseline geografis**: konstruksi kandidat sebelumnya, nearest-neighbor geografis + perbaikan pembalikan segmen, paling banyak dua kandidat lalu ETA pada jam tiap ruas.
- **Multi-start + local search**: beberapa seed urutan (termasuk nearest ETA dan urutan acak), kemudian swap/relocate, tiga pass per seed.
- **Cheapest insertion + local**: konstruksi penyisipan termurah yang mengevaluasi awal–akhir, kemudian perbaikan lokal.
- **Beam berbasis waktu**: mempertahankan beberapa prefix dengan propagasi waktu, durasi singgah dan tunggu buka. Tidak hanya mengambil keputusan berikutnya satu kali.
- **ALNS**: penghancuran acak atau berdasarkan kedekatan, cheapest repair, pembobotan operator adaptif dan penerimaan simulated annealing. Semua tujuan dikembalikan ke kandidat.
- **Enumerasi urutan ≤8**: semua permutasi sampai batas evaluasi/waktu; tidak dijalankan untuk lebih dari 8 tujuan.

Default sekarang **Hybrid**. Alur lanjutan memeriksa baseline live terlebih dahulu dan tetap menyertakannya pada pemilihan akhir. Snapshot berarah menghasilkan finalis menurut total durasi trip serta kandidat rendah perjalanan/tunggu; kandidat baru diperiksa sesuai jam setiap ruas, lalu observasi dimasukkan kembali untuk pencarian berikutnya. Maksimal empat putaran, mengikuti sisa budget CPU/evaluasi/request. Snapshot tetap perkiraan; sampel validasi non-walking hanya mengganti interval keberangkatan 1 ms yang diamati. [Implementasi dan fair benchmark sebelum/sesudah](verification/ROUTING_TIME_AWARE_BENCHMARK_2026-11-03.md).

Batas request ETA default **96**, dapat diubah sampai **1024**. Ini batas aplikasi, bukan kuota resmi Apple. Sebagian anggaran disisihkan untuk validasi kandidat. Pengambilan snapshot mendahulukan satu urutan berbasis batas waktu jika ada jam operasional, lalu baseline, tetangga dan pasangan lain; ruas yang tidak terambil tetap unknown. Anggaran kecil pada banyak tujuan dapat membuat hasil kurang baik atau belum lengkap. Pencarian tidak diulang tanpa batas. Batas request, cache dan pembatasan layanan tetap berlaku.

CPU default: seed 67, maksimal 100.000 evaluasi, 3 detik, beam 8, ALNS 150 iterasi; Alur refinement berbagi batas evaluasi/waktu antarputaran. Nilai eksperimen dapat diatur di layar pembanding. Perhitungan CPU berjalan pada actor terpisah; akuisisi layanan dan validasi ETA terpisah dari waktu CPU.

## Membandingkan dalam aplikasi

Dari Rencana, buka **Bandingkan algoritme**.

1. Pilih **Sintetis statis**, **Sintetis berubah waktu**, atau **Tempat saya · MapKit**.
2. Untuk sintetis, pilih 1–20 tujuan. Data dibuat deterministik dari seed dan tidak merepresentasikan lokasi nyata. Varian dinamis mengganti biaya berarah setelah +120 menit untuk menguji propagasi waktu.
3. Atur seed, pengulangan 1–5, lebar beam, batas CPU/evaluasi dan request ETA. Pengulangan memakai satu kasus yang sama, dengan seed pencarian bertambah.
4. Tekan **Bandingkan semua metode native**. Semua metode menerima **problem/snapshot dan evaluator yang sama**. Tidak memanggil MapKit ulang untuk setiap kandidat atau metode.
5. Buka hasil untuk urutan, moda, waktu relatif, durasi perjalanan/menunggu/singgah, jumlah ruas diketahui, konflik dan status penghentian. Jika acuan exact selesai dan layak, tampilkan selisih biaya terhadap acuan itu.
6. Bila berulang, ringkasan memuat jumlah run layak, median/rentang total durasi trip dan median CPU. Hasil parsial tidak ikut statistik kualitas.
7. **Ekspor seluruh perbandingan (.json)** menyimpan kasus, hasil, konfigurasi, statistik dan biaya akuisisi untuk analisis/debugging.

Layar pembanding menilai **model snapshot**, bukan otomatis menghasilkan rundown MapKit yang telah diverifikasi ulang. Untuk memakai engine pada alur sebenarnya, pilih metode lewat Pengaturan lalu **Hitung itinerary**. Kasus MapKit memerlukan semua koordinat sudah dipilih; input kosong ditolak sebelum menghubungi WeatherKit/ETA. Pembandingan dihentikan saat layar ditinggalkan atau aplikasi tidak aktif; data yang selesai tetap terlihat selama sesi layar.

## Evaluator dan arti klaim hasil

- **Pembaruan input jam operasional:** jam buka dan tutup dapat diisi secara terpisah pada detail tujuan. Snapshot menerima batas yang diketahui; waktu menunggu dan konflik melewati tutup diterapkan seperti pada alur itinerary. Jam yang belum diisi tetap unknown. Prioritas `elapsed_v2`: kelayakan, lalu total perjalanan + menunggu + singgah; perjalanan dan menunggu menjadi pemecah seri. [Panduan dan contoh Jakarta](NATIVE_OPENING_HOURS.md). [Uji UI Jakarta](verification/OPENING_HOURS_JAKARTA_REPORT_2026-11-03.md) memverifikasi enam metode pada snapshot dan alur live baseline/enumerasi, sekaligus menemukan kelemahan prioritas waktu serta pemangkasan finalis. Pengujian ini tidak memvalidasi seluruh variasi jam operasional.
- Seluruh occurrence tujuan dipertahankan; awal/akhir tetap. Kunjungan berulang di lokasi sama tetap node berbeda.
- Biaya berarah dan, jika kasus menyediakan interval, biaya sesuai waktu keberangkatan. Waktu tiba/singgah/tunggu dipropagasikan sampai akhir. Jam operasional hanya dipakai untuk kunjungan, sama dengan engine live.
- **Mobil pribadi** membandingkan strategi seluruh ruas dengan mobil atau tanpa mobil; park-and-walk belum dimodelkan. **Taksi/ride-hailing** boleh dipilih per ruas, tanpa estimasi waktu pesan/tunggu kendaraan. Draft mobil lama tanpa konteks menggunakan kebijakan konservatif mobil pribadi.
- Di dalam strategi yang diizinkan, evaluator memilih moda tersedia dengan ETA terkecil per ruas; saat seri mendahulukan jalan kaki. Tidak mengoptimalkan penundaan berangkat disengaja atau seluruh kombinasi moda sebagai variabel terpisah.
- Tujuan wajib tetap mendapat durasi singgah. Jam tutup diperiksa terhadap akhir singgah, bukan sekadar saat tiba. Perjalanan ke titik akhir ikut biaya dan batas selesai.
- Data ETA hilang tidak menjadi nol. Pencarian yang belum tuntas tidak membuktikan infeasible. Durasi hasil yang terputus ditandai parsial.
- Paparan hujan memakai cakupan prakiraan yang tersedia; detail transit tetap unknown. Alternatif cuaca hanya dipilih bila data paparan cukup dan berada dalam batas tambahan waktu/selesai. Pool alternatif terbatas 12; ini bukan bukti optimum cuaca global.
- `exhaustive_fixed_evaluator`: seluruh urutan diperiksa pada model dan aturan moda/waktu di atas, tanpa data hilang. Bukan bukti optimum rute dunia nyata. Jika semua urutan melanggar batas, kesimpulan hanya untuk model tersebut.
- `not_proven`: tidak ada klaim optimum. `search_limit`: budget habis. `data_incomplete`: ada evaluasi yang tidak didukung data. `unsupported_size`: enumerasi dilewati karena >8 tujuan. Sebuah heuristik dapat selesai tanpa membuktikan bahwa tidak ada solusi lain.

Semua metode mempertahankan kandidat baseline sebagai warm start. Karena itu perbandingan mengukur peningkatan pencarian di atas baseline yang sama, bukan tujuh konstruksi yang sepenuhnya terisolasi. Seed dan jumlah evaluasi dicatat; waktu CPU bisa berubah menurut perangkat dan beban sistem.

## OR-Tools dalam alur yang sama

OR-Tools 9.15.6755 disediakan sebagai **helper offline Mac**, menggunakan cheapest insertion + Guided Local Search. Tidak ada backend atau API key baru.

1. Setelah pembandingan selesai di iPhone, tekan **Ekspor kasus OR-Tools (.json)** dan pindahkan file ke Mac.
2. Di repo, buat virtualenv terpisah dan pasang dependency:

```sh
python3 -m venv /tmp/c67-ortools
/tmp/c67-ortools/bin/python -m pip install -r scripts/requirements-routing-ortools.txt
/tmp/c67-ortools/bin/python scripts/solve-routing-ortools.py case.json --output result.json --seconds 3
```

3. Kembalikan `result.json` ke iPhone, buka kasus yang sama, lalu **Impor hasil OR-Tools (.json)**. Jangan membuat kasus baru sebelum impor; ID kasus harus sama.
4. Aplikasi memeriksa schema/ID kasus/seluruh tujuan, lalu **menghitung ulang metrik**. Angka biaya atau klaim optimum dari file eksternal tidak dipercaya langsung.

Helper meminimalkan span dimensi waktu (total durasi), memakai matriks statis pada t=0, pembulatan durasi ke detik ke atas, jam operasional dan deadline; semua node wajib. Mobil pribadi membandingkan dua strategi konsisten dengan separuh budget masing-masing. Untuk kasus dinamis hasil diberi `static_projection` dan tetap dinilai ulang pada model dinamis aplikasi. Seed/budget pencarian native bukan parameter OR-Tools; helper memakai `--seconds` dan merekam versi/elapsed sendiri. Hasil `no_solution_found` bukan bukti infeasible. Bagian ini adalah pembanding eksternal, bukan implementasi native OR-Tools atau exact solver time-dependent.

Referensi: [OR-Tools routing options](https://developers.google.com/optimization/routing/routing_options), [OR-Tools time windows](https://developers.google.com/optimization/routing/vrptw), [versi paket](https://pypi.org/project/ortools/).

## Log dan verifikasi

Log otomatis yang sudah ada tetap dipakai. Kategori `optimizer` menambah `routing.snapshot`, `routing.solver_result`, `routing.comparison_started/result/failed/cancelled` dan `routing.ortools_imported`; `routing.live_candidate`, `routing.refined_snapshot` dan `routing.pipeline_completed` mencatat finalis, model hasil refinement, baseline/hasil elapsed dan request; konfigurasi, seed, ID kasus, evaluasi dan alasan berhenti ikut direkam. Ekspor kasus/perbandingan memberi dataset lengkap ketika field log terlalu panjang dan dipotong oleh batas log.

Pemeriksaan lokal:

```sh
./scripts/check-native-trip-routing.sh
./scripts/check-native-trip-pipeline.sh
./scripts/benchmark-routing-pipeline.sh /tmp/c67-pipeline-benchmark
C67_ORTOOLS_PYTHON=/tmp/c67-ortools/bin/python ./scripts/check-native-trip-routing.sh
```

Pemeriksaan mencakup biaya berarah dengan optimum yang diketahui, tujuh metode native, jam buka/akhir singgah, akhir berbeda, propagasi waktu, unknown ETA, anggaran, repeatability, cuaca unknown, impor asing/tidak lengkap, pembatalan, struktur kasus, 20 tujuan dan statistik pengulangan. Pengujian OR-Tools memakai package asli di virtualenv terpisah dan memvalidasi hasilnya kembali melalui Swift.

Catatan verifikasi awal tersimpan di [bukti historis](verification/NATIVE_ROUTING_LAB_2026-11-03.json). Pembaruan hybrid lulus build Simulator, format, 18 pemeriksaan routing dan 6 pemeriksaan full pipeline macOS; benchmark menjalankan pipeline lama/baru dengan oracle yang sama. Live provider/UI final belum diuji ulang karena Mac terkunci. Detail dan batas klaim terdapat pada [laporan benchmark](verification/ROUTING_TIME_AWARE_BENCHMARK_2026-11-03.md).

## Cadangan cuaca

Akuisisi cuaca pada snapshot MapKit dan alur itinerary memakai WeatherKit, lalu Open-Meteo jika sumber utama gagal/tidak mencakup waktu trip. Field opsional `weatherSources` (ID titik → provider) dan `weatherAttribution` ikut diekspor pada kasus JSON; kasus lama tanpa metadata tetap terbaca. Kasus sintetis tidak memanggil layanan cuaca. Lihat [panduan fallback](NATIVE_WEATHER_FALLBACK.md).


## Pembaruan diagnosis ETA Jakarta — 3 November 2026

[Uji Jakarta setelah perbaikan](verification/JAKARTA_ROUTING_REPORT_2026-11-03.md) memperoleh 20/20 pasangan berarah layak dan enam metode native selesai. Pilihan **Mobil · ETA** harus diaktifkan sendiri di Pengaturan; draft lama tetap default jalan kaki/transit. Ini menambah moda MapKit yang tersedia, bukan menyediakan transit Jakarta.

Layar pembanding kini menampilkan cakupan pasangan/mode dan alasan ruas tidak layak. Pin terpencil mendapat peringatan di input; alamat pilihan selalu ditampilkan. Request ETA diberi pacing 1,2 detik, dengan satu retry terbatas untuk kegagalan non-transit pada pasangan tanpa moda layak, mengikuti kuota dan reserve. ETA yang melebihi batas berjalan tetap dikeluarkan.

Untuk mereproduksi kasus dari log, buka **Muat input JSON**, tempel objek JSON dalam field `json` dari event `input.snapshot`, lalu **Gunakan input JSON**. Validasi dilakukan sebelum mengganti input. Perbandingan terakhir juga tersimpan lengkap secara lokal pada `Application Support/NativeTripRouting/last-comparison.json`; ekspor perbandingan melalui UI tetap tersedia.


## Kebijakan hybrid adaptif — 3 November 2026

Pipeline itinerary sekarang memvalidasi baseline terlebih dahulu, lalu memutuskan perlu tidaknya akuisisi snapshot dan pencarian lanjutan. Satu/dua tujuan dapat selesai setelah semua urutan diperiksa. Untuk kasus lebih besar, baseline tidak layak, waktu tunggu besar, margin tutup sempit, cuaca, mobil pribadi atau biaya ruas yang belum cukup diketahui tetap memicu hybrid penuh. Perkiraan jarak hanya dipakai untuk pemeriksaan awal; hasil itinerary tetap memakai ETA provider yang divalidasi per ruas.

Default `hybrid` memakai kebijakan adaptif; draft lama tetap kompatibel. Field input JSON opsional `"routingAdaptive": false` memilih pipeline hybrid penuh untuk perbandingan. Solver murni pada layar **Bandingkan algoritme** tetap dijalankan eksplisit pada snapshot yang sama; kebijakan adaptif bukan metode solver tambahan. Event `routing.adaptive_decision` mencatat alasan, estimasi penghematan, waktu/evaluasi dan request baseline.

Parameter awal serta batasnya tersedia pada [laporan implementasi](verification/ADAPTIVE_ROUTING_REPORT_2026-11-03.md). Uji final: 26 XCTest, 34 pemeriksaan lokal dan build iOS lulus; benchmark 45 kasus × 3 seed × 3 alur mempertahankan seluruh hasil layak hybrid penuh. Penghematan Jakarta empat tujuan 65,91%, tetapi total suite hanya 2,42%; layanan live belum diuji ulang.

```sh
./scripts/test-native-trip-jakarta.sh /tmp/c67-adaptive-jakarta-new
./scripts/benchmark-adaptive-routing.sh /tmp/c67-adaptive-benchmark-new
```
