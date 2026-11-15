# Pocket Engine · benchmark dari sudut pandang pengguna

11 November 2026, WIB. Putusan untuk cakupan ini: Pocket memenuhi dasar penyusunan jadwal dari kandidat yang sudah tersedia. Brief yang menyatakan jam fleksibel, momen kunjungan, atau tujuan terakhir masih memerlukan intervensi pengguna.

## Metode

- Dua skenario ranking dan 16 skenario itinerary. Masing-masing satu pemanasan dan lima pengukuran pada paket Swift Release, macOS arm64, Swift 6.4.2. Hasil dinilai per skenario, sehingga lima pengulangan deterministik tidak dihitung sebagai lima bukti independen.
- Input sintetis dibekukan sebelum runner dimulai (SHA-256 `10942d20acf829e491d833048ffe9e038247a1feaeed18279a493d57c376616b`). Kandidat, fakta dan jam tersedia sebagai input. ETA serta cuaca diinjeksi melalui API produksi Pocket. Tidak ada request provider, data Google, atau impor katalog produksi.
- Kode Swift memakai `Recommender.assess` dan `ItineraryPlanner.make` dari package aktual. Penyortiran ranking mengikuti PocketModel. Toleransi jam yang disukai dan batas tunggu 30 menit adalah parameter fixture. Syarat yang belum bisa dinyatakan oleh API planner diperiksa terhadap hasilnya.
- Pemeriksa Python memeriksa jumlah dan keunikan tujuan, tujuan wajib, nama dan koordinat, rantai waktu, ETA, durasi, jam operasional, akses, cuaca, waktu kembali dan anggaran ETA. Ia mencari jadwal pembanding dengan enumerasi urutan, pilihan menit mulai pada kasus janji/cuaca, serta langkah lima menit untuk keberangkatan fleksibel. Ia memastikan ketujuh kasus gagal punya contoh solusi dalam model fixture. Untuk gangguan sementara, contoh solusi mengasumsikan satu percobaan tambahan yang berhasil sesuai skrip provider.
- Enam kontrol keluaran yang sengaja dirusak tertangkap oleh pemeriksa: label pin berubah, ETA salah, perjalanan kembali salah, tujuan wajib hilang, anggaran dilewati, dan kandidat tanpa bukti keliru dinyatakan layak.

## Hasil

**11/18 skenario lulus.** Hasil setiap skenario konsisten dalam lima pengulangan. Tidak ditemukan pelanggaran terhadap batas dasar yang diperiksa pada jadwal yang dikembalikan. Empat kegagalan berupa tidak adanya jadwal padahal ada solusi acuan. Tiga lainnya berupa jadwal yang mengabaikan waktu atau urutan yang diminta. Empat penolakan yang diharapkan lulus.

| Skenario | Hasil Pocket |
| --- | --- |
| Bukti kegiatan wajib | Lulus. Kategori saja dan konflik bukti tidak meloloskan kandidat. |
| Bukti kegiatan disukai | Lulus. Kandidat dengan bukti didukung berada di atas kategori saja dan bukti bertentangan. |
| Lima tempat dan label pin lokal | Lulus. Lima tujuan, nama dan koordinat utuh, pulang 14.35. Mencapai 60 panggilan ETA dan pencarian terpotong. |
| Deadline mencakup perjalanan pulang | Lulus. Kunjungan muat, perjalanan pulang melampaui batas, rencana ditahan. |
| Enam tempat, satu tutup lebih awal | Gagal. Tidak ada hasil setelah 60 panggilan. Acuan mendatangi tempat yang tutup awal pukul 09.10 dan pulang 16.10. |
| Berangkat kapan saja untuk makan malam | Gagal. Pocket hanya mencoba pukul 08.00. Jadwal acuan berangkat 17.40, makan 17.50, dan kembali 18.50 dalam batas toleransi fixture. |
| Kontrol keberangkatan tetap | Lulus. Setelah input keberangkatan diatur 17.50, makan 18.00 dan kembali tepat 19.00. |
| Makan malam sebagai tujuan terakhir | Gagal. Pocket menaruhnya pertama pukul 17.00. Acuan menaruhnya terakhir pukul 18.00 dan kembali 18.55. |
| MACAN tepat 14.00 | Gagal. Jadwal tiga tempat memulai MACAN pukul 12.40. Acuan memulai MACAN 14.00. |
| MACAN sekitar 14.00, lima tempat | Gagal pada preferensi waktu. Lima tempat terjadwal, MACAN pukul 12.40. Acuan memulai pukul 13.50 dalam toleransi fixture ±20 menit. |
| Tunggu hingga slot cuaca lebih baik | Gagal. Engine berhenti pada kunjungan 10.40 yang hujan. Acuan menunggu 20 menit dan mulai pukul 11.00. |
| Prakiraan tidak diketahui | Lulus sebagai penolakan. Pesan menyebut ambang hujan tanpa menjelaskan bahwa data tidak tersedia. |
| ETA berubah sesuai waktu dan arah | Lulus. Memilih urutan B → A yang sesuai batas pulang. |
| ETA terus tidak tersedia | Lulus sebagai penolakan. Satu panggilan gagal; tidak ada ETA buatan. |
| ETA sementara gagal lalu pulih | Gagal. Berhenti pada panggilan pertama dan tidak memanfaatkan kesempatan retry. |
| Tujuan opsional dengan akses belum terbukti | Lulus. Dilewati, tujuan wajib tetap dijadwalkan. |
| Jam tujuan wajib kedaluwarsa | Lulus sebagai penolakan, sebelum panggilan ETA. |
| Jam bertanggal khusus dan sesi terpisah | Lulus. Mengikuti sesi kedua hari itu, mulai 10.00. |

Median lokal terbesar dari skenario yang diukur sekitar 1,98 ms, termasuk evaluasi ranking dan ETA/cuaca sintetis. Angka ini tidak mengukur latensi MapKit atau WeatherKit. Jumlah permintaan ETA naik sampai 60 bahkan pada satu kasus lima tujuan yang menghasilkan jadwal. Benchmark tidak mengukur waktu sampai jadwal pertama, konsumsi energi, atau perilaku iPhone. Empat XCTest yang sudah ada lulus.

## Evaluasi pengguna

Saya bisa memakai Pocket untuk memeriksa rute setelah kandidat, jam dan akses tersedia. Untuk menyusun hari dari brief, saya belum akan mengandalkan versi ini. Kemampuan mendahulukan tujuan dengan jam tutup sempit, memilih keberangkatan dari jendela, dan mempertahankan waktu atau posisi tujuan perlu masuk ke perhitungan. Pada kegagalan provider, perlu dibedakan kasus yang bisa dicoba lagi dari ruas yang memang tidak tersedia. Aplikasi juga perlu menjelaskan saat hanya memiliki empat dari lima tujuan, atau menyarankan jam jauh dari preferensi.

Hasil ini belum mengukur kualitas pencarian atau rekomendasi dari seluruh Jakarta. Benchmark memakai kandidat yang sudah tersedia dan fakta sintetis. Pada pilot data independen terdahulu, pengayaan otomatis dan ketepatan pencarian cabang masih merupakan batas terpisah. Hasil saat ini belum cukup untuk menyatakan alur lengkap siap menggantikan Google Places.

## Reproduksi

Dari folder `poc/c67-pocket-engine-lab`, siapkan direktori hasil baru.

```sh
mkdir -p .local/acceptance-replay
python3 Benchmarks/Acceptance/benchmark.py freeze .local/acceptance-replay/fixtures.json
swift build --package-path Benchmarks/Acceptance --scratch-path .local/acceptance-replay/build -c release --product AcceptanceBench --disable-sandbox
.local/acceptance-replay/build/release/AcceptanceBench .local/acceptance-replay/fixtures.json 5 > .local/acceptance-replay/raw.jsonl
python3 Benchmarks/Acceptance/benchmark.py score .local/acceptance-replay/fixtures.json .local/acceptance-replay/raw.jsonl
```

Run awal tersimpan di `.local/acceptance-2026-11-11/` dengan manifest, 108 baris keluaran mentah, log build dan tes, hasil audit, serta kontrol negatif. Build Release memerlukan akses yang memadai untuk cache Swift dan `dsymutil` pada Mac ini.
