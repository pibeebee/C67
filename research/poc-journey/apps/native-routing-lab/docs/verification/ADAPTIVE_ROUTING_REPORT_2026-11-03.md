# Routing hybrid adaptif — implementasi dan hasil pengujian

Tanggal: 3 November 2026 (WIB). Repository: `<LOCAL_HOME>/Programming/software/ios/poc-c67`, branch `gi/itinerary-time-aware`.

**Sudah diimplementasikan dan diuji secara lokal.** Jakarta empat tujuan memakai **30 request dibanding 88** pada hybrid penuh (turun **65,91%**), dengan itinerary dan total durasi tetap **4 jam 17 menit 47 detik**. Pada seluruh benchmark, hasil adaptif sama dengan hybrid penuh pada **132 pasangan yang sama-sama layak**; tiga pasangan lain merupakan satu kasus sengaja mustahil yang diulang dengan tiga seed. Penghematan total request adalah **228 dari 9.429 (2,42%)**. Penghematan besar pada contoh Jakarta belum berlaku merata pada seluruh kasus.

Kode yang diuji adalah **working tree**, belum commit baru. Pembanding penuh diambil langsung dari commit `712f036b222839173d7ea82bb736dd57aaeed6f5`, bukan implementasi ulang. Hash source final pada [manifest benchmark](adaptive-routing-2026-11-03/benchmark/manifest.json) dan [manifest XCTest](adaptive-routing-2026-11-03/jakarta/manifest.json) cocok dengan file saat laporan dibuat.

## Perilaku yang diterapkan

1. Ambil cuaca dan validasi kandidat baseline dengan ETA sesuai jam keberangkatan tiap ruas. Pertahankan kandidat lengkap yang sudah diperiksa.
2. Jalankan pemeriksaan adaptif tanpa request ETA tambahan. Hasilnya menentukan perlu tidaknya snapshot dan optimizer; perkiraan pemeriksaan ini tidak masuk cache ETA, snapshot provider, ataupun itinerary hasil.
3. Satu/dua tujuan dapat langsung memakai baseline jika seluruh kemungkinan urutan sudah divalidasi.
4. Untuk lebih dari dua tujuan, jalankan hybrid penuh bila baseline tidak layak/tidak lengkap, waktu tunggu besar, margin jam tutup sempit, strategi mobil pribadi perlu dibandingkan, atau tersedia prakiraan untuk pencarian alternatif cuaca.
5. Tidak ada dugaan penghematan dari jarak bukan bukti bahwa jalan nyata tidak memiliki shortcut. Karena itu, bila kunjungan terakhir tidak sedang menunggu jam buka, pencarian tetap dijalankan. Pemeriksaan untuk berhenti lebih awal dibatasi pada kasus waktu tunggu terakhir yang dapat menyerap percepatan kunjungan sebelumnya.
6. Pada kasus yang memenuhi pemeriksaan tersebut, estimasikan tetangga urutan melalui swap/relocate, dengan biaya pasangan teramati serta jarak yang dikalibrasi dari ETA baseline. Lanjutkan bila perkiraan penghematan cukup besar, model tidak cocok, data tidak cukup, atau budget pemeriksaan habis. Jika tidak, pakai baseline yang tervalidasi.
7. Pencarian yang dilanjutkan tetap memakai cheapest insertion + multi-start local search, maksimal empat putaran refinement, batas request bersama dan validasi ETA per ruas. Baseline selalu ikut pemilihan akhir.

Parameter eksperimen saat ini:

| Aturan | Nilai |
|---|---|
| Waktu tunggu yang memicu pencarian penuh | ≥20 menit |
| Margin akhir singgah terhadap jam tutup yang dianggap sempit | <15 menit |
| Peluang penghematan berarti | ≥maksimum(5 menit, 3% total durasi baseline) |
| Ketidakcocokan estimasi baseline | >maksimum(5 menit, 5% durasi aktual baseline) |
| Pemeriksaan ringan | Maksimal 512 evaluasi atau 10% budget evaluasi; maksimal 50 ms atau 10% budget CPU |
| Anggaran benchmark semua alur | 96 request; 12.000 evaluasi; 3 detik pencarian |

Angka tersebut adalah **kebijakan PoC yang belum dikalibrasi**, bukan probabilitas keberhasilan. Waktu/evaluasi pemeriksaan dikurangkan dari budget pencarian lanjutan. Keputusan dicatat melalui event `routing.adaptive_decision`: alasan, estimasi penghematan, evaluasi, waktu, parameter, dan jumlah request baseline.

Draft lama dengan `routingAdaptive` tidak ada tetap terbaca dan memakai adaptif untuk metode `hybrid`. `"routingAdaptive": false` mempertahankan hybrid penuh untuk perbandingan terkontrol. Metode lain dan solver murni pada layar perbandingan algoritme tetap dapat dijalankan secara eksplisit; lapisan adaptif adalah kebijakan pipeline itinerary, bukan nama solver kedelapan.

## Hasil pengujian

| Verifikasi | Hasil |
|---|---|
| XCTest evaluator, solver, pipeline, kebijakan adaptif | **26/26 lulus**, 0 gagal, 0 dilewati |
| Pemeriksaan routing murni | **18/18 lulus** |
| Pemeriksaan full pipeline | **6/6 lulus** |
| Pemeriksaan input/kompatibilitas draft | **10/10 lulus** |
| Build Debug iOS Simulator, arm64 + x86_64 | **Berhasil**, `CODE_SIGNING_ALLOWED=NO` |
| Format Swift, syntax shell/Python, diff whitespace | Lulus |
| Audit independen benchmark | **0 kesalahan**, tanpa pelampauan batas request/evaluasi |

Total **60 tes/pemeriksaan** di atas menggabungkan XCTest serta harness lokal, bukan 60 XCTest. Build memiliki satu warning tooling: `Metadata extraction skipped, no AppIntents.framework dependency found`; tidak ada error kompilasi. Tidak menambahkan dependency atau mengubah signing.

Delapan tes adaptif baru mencakup penghematan Jakarta, override penuh, seluruh urutan satu/dua tujuan, waktu tunggu besar, shortcut yang belum diketahui, margin tutup, cuaca/mobil pribadi dan budget kecil. Satu tes tambahan memakai **fixture sintetis terarah**: peluang penghematan memicu optimizer, lalu itinerary hasil yang benar-benar divalidasi lebih singkat daripada baseline. Fixture ini bukan ETA provider atau jam buka tempat nyata. Tes ketidaklayakan yang sudah ada juga memeriksa alasan pemicu adaptif.

[Laporan XCTest, daftar tes dan jadwal lengkap](adaptive-routing-2026-11-03/jakarta/REPORT.md), [JUnit](adaptive-routing-2026-11-03/jakarta/junit.xml), [log XCTest](adaptive-routing-2026-11-03/jakarta/test.log).

## Benchmark berpasangan

**45 kasus × 3 seed × 3 alur = 405 run**: hybrid penuh dari commit, hybrid adaptif, dan baseline saat ini. Untuk membandingkan penuh/adaptif terdapat 135 pasangan. Setiap alur memakai input, oracle ETA, seed, plafon request/evaluasi/waktu dan kondisi cache awal yang sama. Urutan eksekusi dibalik bergantian. Tidak ada jaringan, pacing 1,2 detik, cuaca, atau latensi layanan dalam benchmark.

- 22 kasus lama: satu rekaman MapKit Jakarta, 16 kasus sintetis 4/8/12/20 tujuan statis/dinamis, empat jam tutup ketat, dan satu kasus sengaja mustahil.
- 12 tambahan: geometri seed 103/149, 4/6/10 tujuan, statis/dinamis; set seed 103 tanpa jam operasional. Kasus ini mengungkap regresi pada kebijakan awal.
- Delapan kasus setelah revisi kebijakan: geometri seed 211/307, 4/6 tujuan, statis/dinamis, jam buka lebih ringan.
- Tiga subset Jakarta: Monas–Grand Indonesia, Kota Tua–Kelapa Gading, dan Monas saja.

Auditor Python yang terpisah dari engine menghitung ulang semua kandidat lengkap dan hasil terpilih: tujuan/akhir, moda, ETA pada jam keberangkatan, tiba/tunggu/singgah, jam tutup, batas sehari dan request. Kasus sampai enam tujuan juga mempunyai acuan enumerasi tersendiri. Acuan model kecil tidak dijadikan klaim optimum dunia nyata. Seed adalah pengulangan pencarian pada kasus yang sama, bukan perjalanan independen.

| Kelompok | Pasangan | Layak penuh / adaptif | Durasi sama / lebih lama | Request dihemat | Penghematan total |
|---|---:|---:|---:|---:|---:|
| 22 kasus lama | 66 | 63 / 63 | 63 / 0 | 174 | 3.21% |
| 12 kasus tambahan | 36 | 36 / 36 | 36 / 0 | 0 | 0.00% |
| 8 geometri baru + jam buka lebih ringan | 24 | 24 / 24 | 24 / 0 | 0 | 0.00% |
| 3 subset Jakarta satu/dua tujuan | 9 | 9 / 9 | 9 / 0 | 54 | 30.00% |
| Total | 135 | 132 / 132 | 132 / 0 | 228 | 2.42% |

Baseline saja layak pada **120/135 run**; hybrid penuh dan adaptif sama-sama **132/135**. Adaptif melewati pencarian tambahan pada **12/135 run**: empat skenario Jakarta dengan tiga seed masing-masing. Pada 123 run lainnya jumlah request tetap sama. Kebijakan akhir sengaja konservatif; belum ada penghematan pada 20 kasus sintetis tambahan dalam suite ini.

## Jakarta dengan ETA rekaman yang sama

5 November 2026, mulai 07.00 WIB dari Sudirman dan kembali ke Sudirman; singgah 30 menit per tujuan. Konteks mobil adalah taksi/ride-hailing. Pada contoh empat tujuan urutannya tetap **Grand Indonesia → Monas → Kota Tua → Kelapa Gading → Sudirman**; selesai **11.17.47 WIB**, perjalanan 121,02 menit, tunggu 16,77 menit, singgah 120 menit.

| Tujuan | Request hybrid penuh | Request adaptif | Berkurang | Total durasi kedua alur |
|---|---:|---:|---:|---|
| Empat tujuan | 88 | 30 | 65.91% | 4:17:47 |
| Monas + Grand Indonesia | 26 | 18 | 30.77% | 1:32:51 |
| Kota Tua + Kelapa Gading | 26 | 18 | 30.77% | 4:17:47 |
| Monas | 8 | 6 | 25.00% | 0:58:05 |

Jam buka Kelapa Gading 10.00 berasal dari input fixture; jam operasional lain dan jam tutup belum diverifikasi. ETA rekaman dibekukan untuk replay. Tabel bukan prakiraan trafik terbaru, bukan bukti semua tempat buka, dan bukan hasil MapKit live baru.

## Temuan awal yang diperbaiki

Kebijakan pertama terlalu mudah menerima baseline ketika estimasi jarak tidak menunjukkan keuntungan. Pada 12 kasus tambahan, **18/36 pasangan** menjadi lebih lama, dengan selisih maksimum **8,47 menit**. Semua masih layak, tetapi kualitas itinerary menurun. Kebijakan tersebut **tidak dipakai sebagai hasil akhir**.

Perbaikannya: untuk kasus tanpa penyangga waktu tunggu pada kunjungan terakhir, biaya jalan yang belum diamati dianggap alasan untuk menjalankan pencarian penuh. Seluruh kasus diuji ulang, lalu ditambah delapan kasus geometri baru. Pada hasil final tidak ada regresi durasi/kelayakan dalam suite ini. [Ringkasan percobaan awal](adaptive-routing-2026-11-03/initial-policy/summary.json) dan [metrik awal](adaptive-routing-2026-11-03/initial-policy/metrics.csv) tetap disimpan. Penyesuaian kebijakan menggunakan temuan suite; ini belum validasi eksternal yang independen.

## Batas hasil dan implikasi

- Penghematan 65,91% berlaku pada contoh Jakarta empat tujuan dengan data ini; penghematan seluruh suite hanya **2,42%**. Belum ada bukti penghematan merata untuk trip besar.
- Waktu CPU median sekitar 18 ms pada kedua hybrid di Mac. Itu komputasi adapter tanpa jaringan, bukan waktu tunggu pengguna di iPhone. Pengurangan request berpotensi mempercepat layanan live, tetapi **belum diukur**.
- Saat prakiraan tersedia untuk pencarian cuaca atau strategi mobil pribadi masih perlu dibandingkan, kebijakan ini tetap menjalankan hybrid penuh. Angka penghematan replay tanpa cuaca tidak boleh dianggap hasil run WeatherKit/MapKit live.
- Estimasi awal menggunakan hubungan jarak/ETA yang dapat keliru pada jalan satu arah, tol, akses lokasi atau trafik berubah. Hasil yang dipilih selalu berasal dari validasi, tetapi memilih untuk tidak mencari lagi tetap bisa melewatkan rute yang lebih baik pada input lain. Tidak ada jaminan optimum global atau jaminan tanpa regresi untuk seluruh input.
- Tidak menjalankan UI Simulator, MapKit/WeatherKit live atau iPhone fisik pada pekerjaan ini. Perubahan hanya pada logika perencanaan, kontrak draft opsional, tes dan dokumentasi; build iOS membuktikan kompilasi, bukan perilaku layanan.
- Kemampuan rekomendasi AI/backend dan recalculation selama trip aktif mempunyai lingkup terpisah dan tidak dianggap selesai oleh perubahan routing ini.

## Reproduksi

Dari root repository, dengan Xcode command-line tools aktif dan direktori output baru:

```sh
./scripts/test-native-trip-jakarta.sh /tmp/c67-adaptive-jakarta-new
./scripts/benchmark-adaptive-routing.sh /tmp/c67-adaptive-benchmark-new
./scripts/check-native-trip-routing.sh
./scripts/check-native-trip-pipeline.sh
./scripts/check-native-trip-input.sh
xcodebuild -project poc-c67.xcodeproj -scheme poc-c67 -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/c67-adaptive-build-new CODE_SIGNING_ALLOWED=NO build
```

[Ringkasan benchmark final](adaptive-routing-2026-11-03/benchmark/summary.json), [metrik per run](adaptive-routing-2026-11-03/benchmark/metrics.csv), [seluruh trace dan kandidat](adaptive-routing-2026-11-03/benchmark/runs.jsonl), [acuan enumerasi](adaptive-routing-2026-11-03/benchmark/references.json), serta [log pemeriksaan/build](../../../../docs/missing-evidence.md#missing-530816b7fe6e) disimpan bersama laporan. Artefak sebelum peninjauan akhir tetap tersedia di `adaptive-routing-2026-11-03/before-final-review/`; kesimpulan di atas memakai manifest dan hasil final yang ditautkan.
