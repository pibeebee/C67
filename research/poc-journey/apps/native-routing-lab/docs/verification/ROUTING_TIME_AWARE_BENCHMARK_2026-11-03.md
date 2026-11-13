# Routing berbasis total durasi trip: implementasi dan benchmark

Tanggal: 3 November 2026. Repo: `<LOCAL_HOME>/Programming/software/ios/poc-c67`.

Snapshot sebelum perubahan disimpan pada commit **`f55d1ecfdce973f8f1b387cba128441c92f3afe7`**. Implementasi berada pada branch `gi/itinerary-time-aware`.

Pada benchmark replay ini, hybrid baru menemukan rencana layak pada **63/66 run**, dibanding **51/66** pada default lama dan **63/66** pada local search lama. Pada pasangan yang sama-sama layak, median pengurangan total durasi trip adalah **11,45%** terhadap default lama dan **5,29%** terhadap local search lama. Ini hasil pada 22 kasus terpilih, bukan estimasi keberhasilan di seluruh perjalanan nyata. Biaya request bertambah dibanding default lama.

## Perubahan yang diterapkan

1. **Tujuan optimasi `elapsed_v2`.** Kelayakan terhadap tujuan wajib, jam operasional yang diketahui dan batas satu hari didahulukan. Setelah itu bandingkan total perjalanan + menunggu buka + singgah sampai titik akhir. Perjalanan dan menunggu menjadi pemecah seri. Semua tujuan tetap wajib.
2. **Hybrid sebagai default.** Cheapest insertion, seed geografis, nearest ETA, urutan berbasis jam buka/tutup dan beberapa seed acak; perbaikan swap/relocate dalam budget bersama. Baseline geografis tetap dapat dipilih. Tujuh metode native tersedia, dengan evaluator total durasi yang sama. Enumerasi ≤8 tetap acuan model, dan OR-Tools tetap helper Mac.
3. **Fallback diperiksa sebelum matriks.** Satu atau dua kandidat geografis diperiksa sesuai jam keberangkatan setiap ruas. Kandidat lengkap tersebut selalu ikut pemilihan hasil. Snapshot tidak boleh mengambil seluruh budget yang dibutuhkan untuk satu validasi tambahan.
4. **Akuisisi lebih terarah.** Jika tersedia jam operasional, ambil ruas dari satu urutan berbasis batas waktu secara utuh lebih dahulu, lalu ruas baseline, tetangga terdekat dan pasangan lain. Pasangan yang belum diambil tetap unknown.
5. **Refinement terbatas.** Solusi snapshot menghasilkan finalis menurut elapsed serta kandidat rendah perjalanan/tunggu. Finalis mencakup kandidat cuaca bila datanya cukup. Satu kandidat yang belum diperiksa divalidasi, data aktualnya dimasukkan kembali, kemudian pencarian dapat diulang sampai empat putaran. Evaluasi dan waktu pencarian dibagi antarputaran; request tetap dibatasi. Ini tidak menjamin seluruh finalis sempat diperiksa.
6. **Data waktu tidak dibuat pasti.** Sampel validasi non-walking mengganti hanya interval 1 ms pada waktu keberangkatan yang diamati. Waktu lain tetap memakai perkiraan snapshot yang ditandai sebagai model. Walking tetap mengikuti asumsi cache yang sudah ada. Tidak mengekstrapolasi hasil validasi menjadi kepastian ETA sepanjang hari.
7. **Konteks mobil eksplisit.** Mobil pribadi membandingkan strategi seluruh ruas dengan mobil atau seluruh trip tanpa mobil, sehingga kendaraan tidak berpindah sendiri setelah pengguna berjalan. Park-and-walk belum dimodelkan. Taksi/ride-hailing boleh dipilih per ruas, tetapi waktu pemesanan/tunggu/akses belum tersedia. Draft lama dengan mobil aktif tanpa konteks memakai kebijakan konservatif mobil pribadi. Pilihan mobil tetap harus diaktifkan sendiri.
8. Ringkasan UI, statistik pengulangan, ekspor teks dan helper OR-Tools mengikuti total durasi trip. Log mencatat baseline/hasil elapsed, kandidat validasi, refinement, request dan batas pencarian.

## Desain benchmark yang adil

**Kode lama dijalankan dari commit, bukan ditulis ulang.** Script mengambil lima berkas engine/model/bridge/core/cuaca melalui `git show f55d1ec:...`; executable baru memakai source working tree termasuk planner baru. Kedua executable dikompilasi `swiftc -O`, Swift 5, target macOS 14 pada host arm64 yang sama. Adapter deterministik menggantikan lapisan layanan saja; kode pipeline tetap utuh.

Empat lengan menerima JSON input, oracle ETA, batas request dan seed yang sama:

| Lengan | Peran |
|---|---|
| `old-default` | Default sebelum perubahan: kandidat geografis live, tujuan waktu perjalanan |
| `old-local` | Pipeline lanjutan sebelumnya: snapshot → local search → finalis terbatas → validasi, tujuan waktu perjalanan |
| `new-baseline` | Kandidat geografis dengan evaluator baru; memisahkan pengaruh perubahan tujuan dari pencarian tambahan |
| `new-hybrid` | Pipeline dan metode default baru secara lengkap |

- **22 kasus × 3 seed × 4 lengan = 264 run.** Ini 22 kasus, bukan 66 perjalanan independen. Seed pencarian: 11, 67, 101. Urutan eksekusi lama/baru dibalik bergantian. Cache direset per run.
- Satu kasus memakai **matriks MapKit Jakarta yang sudah direkam**, dibekukan untuk semua waktu pada replay. Enam belas kasus sintetis meliputi 4/8/12/20 tujuan, dua seed geometri, biaya statis atau biaya berarah meningkat setelah +120 menit. Empat kasus tambahan 8/12 tujuan memiliki satu jam tutup ketat. Satu kasus sengaja mustahil: singgah 30 menit dalam jendela buka satu menit.
- Seluruh lengan dibatasi **96 request**, **12.000 evaluasi**, dan **3 detik pencarian**. Batas evaluasi benchmark lebih kecil dari default aplikasi 100.000, sama untuk semua lengan. Waktu/iterasi yang benar-benar dipakai dicatat; tidak ada solver yang melampaui batas evaluasi. Default lama tidak menggunakan solver CPU, tetapi tetap mempunyai plafon request yang sama.
- Seluruh moda Jakarta sama; konteks mobil ditetapkan **taksi/ride-hailing** pada kedua lengan agar perubahan kebijakan kendaraan tidak menjadi pengganggu. Sintetis memakai automobile saja. Uji kebijakan mobil pribadi dilakukan terpisah.
- Oracle memberi ETA yang sama untuk pasangan/moda/waktu yang sama, termasuk status unavailable dan batas walking. Adapter meniru cache key produksi, cache kegagalan, pengecualian walking, retry dan request cap. Tidak ada jaringan, latensi provider, throttling nyata atau pacing ETA 1,2 detik.
- Tidak ada cuaca pada kedua lengan. Benchmark ini menguji routing/jadwal, bukan kualitas prakiraan, skor cuaca atau fallback provider.
- **Auditor Python terpisah** menghitung ulang seluruh kandidat lengkap dan hasil terpilih: semua tujuan/akhir, moda, ETA pada keberangkatan, tiba, tunggu, singgah, jam tutup, deadline dan jumlah request. Tidak mempercayai angka yang dilaporkan engine. **0 kesalahan audit**.
- Semua permutasi kasus empat tujuan diperiksa oleh auditor sebagai acuan elapsed. Tidak memakai klaim optimum solver sebagai ground truth. Kasus >4 tujuan tidak diberi klaim gap optimum independen.

## Hasil keseluruhan

| Lengan | Layak / 66 | Median request terpakai | Median komputasi pipeline tanpa jaringan |
|---|---:|---:|---:|
| Default lama | 51 | 22 | 0,94 ms |
| Local search lama | 63 | 88 | 12,07 ms |
| Baseline dengan tujuan baru | 51 | 22 | 1,17 ms |
| Hybrid baru | 63 | 95 | 23,48 ms |

Waktu tersebut adalah wall time proses perencanaan pada Mac dengan adapter, tidak termasuk startup executable, serialisasi hasil, maupun jaringan. Bukan latensi aplikasi iPhone. Perbedaan waktu kecil dapat dipengaruhi beban host; tidak diinterpretasikan sebagai keunggulan performa perangkat. Akuisisi layanan tetap berpotensi jauh lebih mahal daripada CPU.

| Pembanding terhadap hybrid baru | Pasangan sama-sama layak | Lebih singkat / seri / lebih lama | Median pengurangan elapsed | Tambahan run layak |
|---|---:|---:|---:|---:|
| Default lama | 51 | 33 / 18 / 0 | 11,45% atau 40,95 menit | 12 |
| Local search lama | 63 | 45 / 18 / 0 | 5,29% atau 31,00 menit | 0 |
| Baseline dengan tujuan baru | 51 | 30 / 21 / 0 | 5,29% atau 31,00 menit | 12 |

Persentase dan menit adalah median perbedaan berpasangan, bukan hasil pembagian median seluruh run. Kelayakan dilaporkan terpisah agar kegagalan tidak hilang dari perbandingan kualitas. Ketiga seed pada kasus mustahil tetap tidak layak pada semua lengan. Default lama juga gagal pada 12 run dengan jam tutup ketat; hybrid dan local lama menemukan solusi untuk run tersebut.

Pada **semua kasus 20 tujuan** dalam suite ini, hybrid **seri dengan baseline**. Budget 96 request belum cukup memberi peningkatan yang terlihat. Kesimpulan peningkatan tidak boleh digeneralisasi ke semua ukuran. Tidak ada regresi elapsed pada pasangan layak di suite akhir ini; itu bukan jaminan terhadap setiap input.

Pada kelima kasus empat tujuan yang layak (Jakarta + empat sintetis), hybrid mencapai elapsed acuan enumerasi independen pada seluruh 15 run. Ini hanya optimum pada oracle/model tersebut.

## Contoh Jakarta, sumber ETA yang sama

Contoh memakai seed 67. Trip 5 November 2026, Sudirman pergi/pulang, mulai 07.00 WIB, singgah 30 menit per tujuan. Hanya jam buka Kelapa Gading 10.00 yang diketahui; jam tutupnya dan jam operasional tujuan lain tetap belum diverifikasi.

| Metrik | Default / local lama | Baseline dengan tujuan baru | Hybrid baru |
|---|---:|---:|---:|
| Urutan setelah Sudirman | Kelapa Gading → Kota Tua → Monas → Grand Indonesia | Grand Indonesia → Monas → Kota Tua → Kelapa Gading | Grand Indonesia → Monas → Kota Tua → Kelapa Gading |
| Perjalanan | 107,37 menit | 121,02 menit | 121,02 menit |
| Menunggu buka | 148,02 menit | 16,77 menit | 16,77 menit |
| Singgah | 120 menit | 120 menit | 120 menit |
| Total durasi trip | 375,38 menit | 257,78 menit | 257,78 menit |
| Selesai | 13.15.23 WIB | 11.17.47 WIB | 11.17.47 WIB |
| Request | 30 / 74 | 30 | 88 |

Penghematan **117,60 menit (31,33%)** pada kasus ini datang dari **perubahan tujuan penilaian**; hybrid tidak memperbaiki lagi hasil baseline baru. Tambahan request hybrid tidak memberi manfaat tambahan pada kasus Jakarta ini. Pengaruh pencarian tambahan terlihat pada kasus sintetis lain, bukan diklaim dari contoh ini.

Angka di atas adalah replay statis, **bukan run MapKit live terbaru** dan bukan perbandingan langsung dengan angka live pada laporan historis. Kelayakan hanya terhadap batas yang dimasukkan; tidak memastikan semua tempat sungguh buka pada jadwal tersebut.

## Temuan dari iterasi awal yang tetap disimpan

Implementasi pertama memeriksa baseline sebelum matriks tetapi masih memprioritaskan ruas geografis. Pada suite yang sama, hybrid hanya layak **54/66**, di bawah local lama **63/66**: sembilan run jam tutup ketat kehilangan alternatif yang layak. Setelah menambahkan urutan dan akuisisi berbasis batas waktu, seluruh 264 run diulang tanpa mengubah kasus, seed, request cap atau budget pencarian; hasil menjadi 63/66.

[Artefak iterasi awal](routing-time-aware-2026-11-03/initial/summary.json), data mentah dan source yang terkait disimpan. [Hasil akhir](routing-time-aware-2026-11-03/final/summary.json) menggunakan source hash pada manifest akhir. Perbaikan dibuat setelah melihat kasus suite ini; hasil masih merupakan pengembangan pada suite yang sama, **belum validasi pada himpunan uji independen**.

## Verifikasi dan batas yang tersisa

- Build iOS Simulator final **berhasil**, tanpa warning/error, XcodeBuildMCP `build_sim`, 3 November 2026. Build log disimpan bersama artefak.
- **18 pemeriksaan routing murni**, **6 pemeriksaan full pipeline** dengan adapter, dan **10 pemeriksaan kebijakan input** lulus di macOS. Pemeriksaan baru meliputi tujuan elapsed, prioritas kelayakan, mobil pribadi, baseline retention, budget kecil, ETA hilang, interval observasi dan cancellation.
- OR-Tools 9.15.6755 asli: round trip output → evaluator Swift lulus; dua pemeriksaan tambahan memvalidasi elapsed terhadap enumerasi independen dan kebijakan mobil pribadi. Helper tetap proyeksi statis dengan pembulatan detik, bukan pembuktian optimum jadwal dinamis.
- `swift-format --strict`, syntax shell/Python dan `git diff --check` lulus.
- Build awal sempat di-launch, tetapi **alur UI final dan live MapKit/WeatherKit belum diuji pada perubahan ini**: Mac terkunci ketika kontrol UI akan dimulai. Tidak mengubah alur pengujian menjadi injeksi plan lewat shell. Tidak menjalankan XCTest atau validasi iPhone fisik.
- Data jam operasional tetap manual. Tidak ada informasi golden hour, acara, detail transit, waktu pesan taksi atau parkir baru. Model memilih moda tercepat yang tersedia pada waktu itu; belum mencari penundaan keberangkatan disengaja atau seluruh kombinasi moda. Snapshot dan sampel terbatas bisa salah memeringkat kandidat pada trafik nyata. Baseline yang divalidasi tetap menjadi fallback.

## Reproduksi

Dari root repo, dengan Xcode command-line tools aktif:

```sh
./scripts/benchmark-routing-pipeline.sh /tmp/c67-pipeline-benchmark
./scripts/check-native-trip-routing.sh
./scripts/check-native-trip-pipeline.sh
C67_ORTOOLS_PYTHON=/tmp/c67-routing-lab-20261103/ortools-venv/bin/python ./scripts/check-native-trip-routing.sh
```

Virtualenv OR-Tools bersifat lokal; buat sendiri melalui `scripts/requirements-routing-ortools.txt` jika path contoh tidak ada.

[Manifest source/config akhir](routing-time-aware-2026-11-03/final/manifest.json), [metrik per run](routing-time-aware-2026-11-03/final/metrics.csv), [trace mentah dan seluruh kandidat](routing-time-aware-2026-11-03/final/runs.jsonl), kasus JSON, dan referensi enumerasi disimpan. Nilai UUID internal model/timing dapat berubah saat dijalankan ulang; input, oracle, seed, plafon, hasil urutan dan metrik kualitas dapat diperiksa kembali dari berkas tersebut.
