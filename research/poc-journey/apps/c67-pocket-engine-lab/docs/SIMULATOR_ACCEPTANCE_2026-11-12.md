# Pocket Engine · implementasi dan acceptance Simulator

12 November 2026, WIB. Pengerjaan mengikuti keputusan `grill-me` dan batas pengujian iPhone Simulator. Agent utama mengubah kode dan mengevaluasi hasil. Agent GPT-6.1 Terra Medium menyiapkan acuan, menjalankan pengujian, dan menyimpan bukti.

**Ambang 10 dari 12 skenario belum tercapai.** Empat skenario yang punya setidaknya tiga kandidat dalam acuan tetap menghasilkan nol rekomendasi. Katalog sumber terbuka meningkatkan jumlah kandidat, sementara bukti syarat wajib masih menjadi penghambat. Angka kandidat yang lolos aturan mesin di bawah belum menyatakan kecocokan faktual seluruh tempat.

## Implementasi

- Pencarian Apple berdasarkan minat masuk ke model rekomendasi yang sama dengan katalog independen. Data Apple bersifat sesi. Kueri Jepang atau sushi sendiri tidak mengubah kategori hasil Apple menjadi bukti masakan Jepang.
- Rekomendasi dibatasi poligon administratif Jakarta Selatan, OSM relation 5802438. Perluasan sekitar 5 km dari batas meminta pilihan pengguna. Minimum tiga kandidat, cakupan minat, dan status hasil kurang ditampilkan. Pemilihan wakil minat menggunakan pencocokan agar satu tempat berbeda tersedia per minat yang dapat dipenuhi.
- Kandidat OSM, Overture, dan Apple dipadankan menurut nama/alias dan jarak. Padanan ambigu ditahan. Identitas yang dipadankan dihitung satu kali. Ambang 125 meter tetap heuristik, sehingga alias yang berbeda dan cabang dekat memerlukan audit.
- Kategori sumber dan bukti syarat wajib diperlakukan sesuai kontrak. Syarat tanpa keanggotaan mendapat field terpisah. Impor identitas tidak bisa menyisipkan fakta atau jam. Server menyediakan impor atomik, pemeriksaan bentuk katalog, serta masa periksa identitas 30 hari. Bukti tetap mengikuti impor yang ditinjau dan masa berlaku per field.
- Target jumlah kunjungan terpisah dari tujuan wajib. Tujuan yang baru dipilih bersifat opsional. Planner dapat menawarkan jadwal lebih pendek dengan tetap memelihara tujuan dan waktu wajib serta perjalanan pulang. Tawaran perlu diterima sebelum menjadi jadwal yang dipakai.
- Tujuan makan malam terakhir memerlukan konfirmasi batas mulai. Planner memiliki batas bawah kunjungan, terpisah dari jam tepat dan jam yang diutamakan. Waktu tunggu perlu izin pengguna. Pilihan tambahan waktu tunggu dapat diperiksa dan ditawarkan dengan durasinya.
- Pencarian Apple dibatasi waktu dan dapat dibatalkan. Log engine mencatat durasi, jumlah permintaan, jumlah kandidat, kode kesalahan pencarian, serta statistik jadwal. Harness debug opt-in menjalankan metode model aplikasi yang sama untuk uji berulang di Simulator.

## Acuan dan data

Dua belas brief dikunci sebelum pencarian engine. Sebelum run live, koreksi input A01 menjadi `japanese_cuisine` dan A02 menjadi `sushi` dicatat sebagai versi kedua. Acuan penilai tetap di luar proses aplikasi. Sepuluh brief memiliki minimal tiga kandidat acuan, sedangkan A08 dan A12 belum mempunyai bukti cukup untuk semua syarat. Acuan dibuat melalui pemeriksaan dokumen operator/pemerintah oleh agent, dengan koordinat OSM baru. Sebagian unit toko hanya memiliki titik gedung, sehingga ketepatan pintu dan unit belum diverifikasi lapangan.

Data tambahan berisi 14.832 identitas sebelum penggabungan dan penyaringan area. Inputnya adalah 1.000 record mentah dari pengambilan OSM baru dan ekstrak geografis Overture release 2026-10-21.0 yang tersimpan lokal. Beberapa kategori Overture berasal dari `basic_category` dan `taxonomy`. Setiap record mempertahankan atribusi sumber. Ekstrak Overture memakai bbox yang lebih sempit daripada keseluruhan batas administratif Jakarta Selatan. Perbedaan tanggal dan cakupan sumber memengaruhi hasil.

Tidak ada fakta syarat wajib atau jam yang dimasukkan ke katalog pembanding ini. Angka nol pada skenario wajib menunjukkan bahwa identitas/kategori sumber belum cukup untuk memenuhi kontrak. Perbandingan ini mencakup penemuan kandidat dan penilaian dari data identitas. Layanan `luna-provider.example` dan kolektor web belum dipanggil oleh jalur rekomendasi Pocket pada run ini. Kontribusi pengayaan web perlu diukur pada kumpulan kandidat yang sama setelah bukti tersedia. Hasil identitas ini belum menguji pengganti lengkap alur Google Places dan Jev.

## Pengujian versi stabil

- Build dan peluncuran aplikasi berhasil pada **iPhone 17e Simulator, iOS 27.2**. Hash sumber sebelum dan setelah build final cocok. Percobaan awal dengan perubahan sumber selama build disimpan sebagai diagnosis dan dikecualikan dari hasil versi final.
- **11 dari 11 XCTest** paket lulus pada macOS. Kasus tambahan memeriksa wakil minat berbeda, kandidat yang hanya cocok pada facet tetapi tidak cocok kategori, deduplikasi, batas administratif, serta jadwal lebih pendek dengan batas awal makan malam dan ETA pulang.
- **18 dari 18 skenario regresi planner** lulus dalam lima pengulangan terukur per skenario. ETA dan cuaca pada replay bersifat sintetis.
- Pengujian Simulator menjalankan **12 dari 12 brief live**. Setiap kueri Apple dijalankan sekali untuk satu minat dan hasil sesi yang sama digunakan pada kedua lengan. Anggaran satu kueri per minat, maksimum enam minat, 25 detik per kueri, dan 60 detik total dikunci sebelum hasil. Audit keluaran dibatasi 12 tempat per brief.

| Brief | Permintaan | Kandidat Apple yang lolos mesin | Kandidat gabungan yang lolos mesin | Acuan |
| --- | --- | --- | --- | --- |
| A01 | Makanan Jepang | 0 | 503 | Siap |
| A02 | Sushi | 0 | 87 | Siap |
| A03 | Kopi wajib | 0 | 0 | Siap |
| A04 | Outdoor wajib | 0 | 0 | Siap |
| A05 | Museum dan sejarah | 14 | 45 | Siap |
| A06 | Seni dan museum | 5 | 150 | Siap |
| A07 | Membaca dan akses publik wajib | 0 | 0 | Siap |
| A08 | Membaca dan tenang wajib | 0 | 0 | Belum cukup bukti |
| A09 | Kafe dan galeri | 25 | 3.099 | Siap |
| A10 | Hewan dan taman | 13 | 441 | Siap |
| A11 | Kegiatan anak wajib | 0 | 0 | Siap |
| A12 | Membaca dan akses kursi roda wajib | 0 | 0 | Belum cukup bukti |

Gabungan sumber menghasilkan sedikitnya tiga kandidat yang lolos mesin pada enam dari sepuluh brief beracuan siap. Seluruh 113 posisi hasil teratas yang dicatat pada kedua lengan berstatus belum dinilai kecocokan faktualnya dalam artefak audit. Enam brief tersebut masih membutuhkan audit kecocokan cabang dan hasil teratas. Jumlah ini tidak mengukur precision atau jumlah keberhasilan yang terverifikasi. Empat kegagalan beracuan siap membuat jumlah keberhasilan maksimum delapan dari dua belas, sekalipun kedua brief yang belum siap nantinya lulus. Karena itu ambang 10/12 sudah terlewat pada putaran ini.

Durasi fase Apple yang dicatat aplikasi sekitar 0,40–0,73 detik per brief, dengan satu atau dua kueri. Penggabungan dan penilaian katalog lokal sekitar 3,85–4,37 detik ketika katalog dimuat untuk setiap brief. Angka berasal dari build debug di Simulator, dengan respons Apple yang dipakai bersama. Durasi sumber terbuka tidak mencakup pengunduhan awal OSM/Overture. Konsumsi energi dan latensi perangkat fisik belum diukur.

Pemeriksaan data sumber menemukan nama cabang `Sushi groove Paris Van Java` pada koordinat Jakarta Selatan di sumber Overture. Konflik identitas ini perlu diselidiki sebelum tempat dinyatakan valid. Label masakan Jepang pada sebuah kafe juga membutuhkan bukti menu agar kecocokan permintaan makanan dapat dinilai. Hasil Apple yang hanya disimpan sebagai hash nama tidak cukup untuk mengesahkan identitas cabang atau memutuskan apakah dua nama yang sama merupakan duplikat.

## Diagnosis itinerary di Simulator

Pada 5 Desember 2026, tester memilih tiga hasil rekomendasi museum yang benar-benar muncul di aplikasi. Titik awal memakai Basoeki Abdullah Museum, dengan keberangkatan fleksibel mulai 09.00, batas pulang 18.00, target tiga tujuan, waktu tunggu nol, dan penghindaran hujan nonaktif. Titik awal berbeda dari pusat area pada manifest brief, sehingga diagnosis ini memiliki input tersendiri.

Tanpa konfirmasi perjalanan, planner menahan ketiga tempat karena akses publik belum didukung bukti. Sesudah tester memberi konfirmasi hipotetis akses dan interval 09.00–17.00 per tujuan, aplikasi menampilkan hasil berikut.

| Tahap | Jadwal / ETA yang ditampilkan |
| --- | --- |
| Basoeki Abdullah Museum | 09.00–10.00, titik awal sama dengan tempat pertama |
| Ciputra Artpreneur Museum | 10.28–11.28, berkendara 29 menit |
| Betawi Museum | 12.07–13.07, berkendara 39 menit |
| Kembali ke titik awal | 29 menit, tiba 13.36 |

Jam 09.00–17.00 dan izin akses merupakan asumsi pengujian khusus perjalanan. Keduanya belum menjadi bukti operasional yang terverifikasi. Diagnosis ini menunjukkan metode planner dan ETA MapKit dapat tersambung melalui UI Simulator ketika masukan tersebut tersedia. Ketepatan jam buka dan akses aktual tetap harus diperiksa. App menampilkan paparan outdoor belum diketahui. Run ini tidak memverifikasi prakiraan WeatherKit.

Bukti gambar tersimpan di [penolakan saat bukti kurang](../.local/simulator-acceptance-20261111/run-final-01/plan-no-evidence.jpg), [jadwal dengan input tester](../.local/simulator-acceptance-20261111/run-final-01/manual-plan-visible.jpg), dan [perjalanan pulang](../.local/simulator-acceptance-20261111/run-final-01/manual-plan-return.jpg).

Pengujian server terbaru memakai SQLite dan seed kosong yang terisolasi. Impor baru, perlindungan data segar, pembaruan setelah 31 hari, pemeliharaan bukti saat identitas tetap sama, pengosongan bukti saat identitas berubah, penolakan batch cacat secara atomik, serta penolakan penyisipan fakta/jam melalui jalur identitas semuanya lulus. Konverter diuji dengan schema kategori Overture lama dan baru, GeoJSON dan NDJSON, alamat, hash sumber, serta timestamp manifest. Pemeriksaan kompilasi Python juga lulus.

## Pemakaian limit

Limit 5H dipantau lewat informasi penggunaan akun. Ketika mencapai 86% pekerjaan substantif disimpan dan agent menunggu. Pemeriksaan selama menunggu menunjukkan 93%, lalu penantian dilanjutkan sampai reset. Setelah reset terkonfirmasi 0%, pemeriksaan akhir dilanjutkan. Kredit reset akun tetap tersedia. Limit mingguan tetap mengikuti jendela akun dan tidak ikut reset 5H.

## Evaluasi dan urutan perbaikan

1. Hubungkan pengayaan bukti cabang ke kandidat hasil pencarian. Prioritaskan empat kelompok yang gagal dengan acuan memadai. Ukur perubahan setelah pengayaan pada ID kandidat yang tetap, dengan peninjauan sumber dan kesegaran 30 hari. Kategori kafe, taman, atau perpustakaan belum memenuhi sendiri syarat eksplisit pada kontrak saat ini.
2. Perbaiki validasi identitas dan sumber sebelum mengejar tambahan jumlah kandidat. Retain alamat, cabang, sumber, kategori, tanggal dataset, dan konflik yang ditemukan. Tahan keputusan positif ketika bukti syarat wajib belum tersedia.
3. Audit relevansi dan keberagaman hasil teratas. Angka 503 atau 3.099 tidak menetapkan kualitas rekomendasi. Lengkapi acuan A08/A12, dengan riwayat penambahan yang jelas. Uji perbaikan pada brief baru selain replay skenario yang sudah diketahui.
4. Ukur ulang waktu sampai hasil tampil setelah katalog nyata tersambung, lalu lanjutkan validasi itinerary dan cuaca live di Simulator. Verifikasi perangkat fisik menjadi tahap lanjutan setelah data dan perilaku utama memadai.

## Artefak

Manifest brief versi pertama/kedua, acuan, poligon dan SHA-256 tersimpan di `.local/simulator-acceptance-20261111/`. Keluaran final, source hashes, log XCTest, replay dan impor server berada di `run-final-01/`. [Laporan agent](../.local/simulator-acceptance-20261111/run-final-01/TEST_REPORT.md) mencatat batas tiap pengujian. Input sumber dan katalog gabungan berada di `.local/implementation-20261111/`.

Lihat juga [rencana implementasi](RECOMMENDATION_AND_ITINERARY_IMPLEMENTATION_PLAN.md), [revisi planner sebelumnya](PLANNER_REVISION_2026-11-11.md), dan [kontrak server](../Server/CONTRACT.md). Hasil ini mendukung pengembangan dan diagnosis engine. Kesiapan pengganti Google Places dan Jev di produksi masih membutuhkan bukti lebih lanjut.
