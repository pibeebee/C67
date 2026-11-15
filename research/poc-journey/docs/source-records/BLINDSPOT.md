# Blind spot PoC itinerary: temuan, solusi, dan rencana pembuktian

Tanggal dokumentasi: **8 November 2026, Asia/Jakarta**.

Dokumen ini menggabungkan pembahasan blind spot pada sistem dan pengujian PoC itinerary, usulan perbaikannya, benturan antarsolusi, serta urutan eksperimen berikutnya. Bahasa dan contoh mengikuti diskusi bersama pengguna.

**Status awal:** dokumentasi analisis dan usulan. Pembuatan awal dokumen ini tidak menerapkan solusi, menjalankan benchmark baru, atau mengubah aplikasi. Pembaruan implementasi setelahnya tercatat pada bagian berikut. Kondisi implementasi yang dijelaskan mengacu pada kode dan laporan kampanye 7–8 November 2026; dampak yang belum diuji dinyatakan sebagai hipotesis.

## Pembaruan implementasi personal, 8 November 2026

PoC personal di lab terisolasi kini menambahkan onboarding minat/ritme yang dipakai ulang, discovery Google dinamis, E5 di device sebagai pembantu, LLM OpenRouter gratis yang wajib berhasil, validasi alasan berbasis bukti, keragaman minat, pembelajaran facet di dalam minat eksplisit, dan pemilihan tujuan wajib/opsional. Pemeriksaan nama serta jarak Google–Apple ditambahkan setelah review visual menemukan padanan museum/kedai yang keliru. Ini menangani sebagian blind spot; tidak berarti seluruh butir di dokumen ini selesai.

[Laporan implementasi dan batas bukti](../../apps/c67-local-server-lab/docs/PERSONAL_RECOMMENDATION_RESULTS_2026-11-08.md) dan [protokol pengujian](../../apps/c67-local-server-lab/docs/PERSONAL_RECOMMENDATION_PROTOCOL_2026-11-08.md) membedakan kelulusan aturan, operasi provider, kecocokan selera, dan validitas lapangan. Penilaian manusia, manfaat learning/LLM, sentimen publik, last entry, antrean, tiket dan akses nyata masih memerlukan data tambahan. Uraian “tidak ada LLM” di analisis awal berikut mengacu pada planner lama; LLM baru menilai kandidat, sedangkan kelayakan rute tetap dihitung oleh kode.

## Bukti baru dari user simulasi, 8 November 2026

[Tiga persona baru](../../apps/c67-local-server-lab/docs/SYNTHETIC_USER_RESULTS_2026-11-08.md) dijalankan dengan kebutuhan yang dibekukan sebelum hasil, tanpa tuning engine/prompt. Temuannya memperkuat S01/S02/S10 (kategori belum menangkap kegiatan dan syarat seperti vegetarian, tenang, akses atau harga), S04 (alias mungkin ditolak tetapi tenant mal dapat diterima), serta S08 (kontrol dua kegiatan kehilangan satu kegiatan pada grid15 tetapi mempertahankan dua pada grid5). Ditemukan pula alasan penghilangan opsional yang memakai status sukses `operating_hours_options`, sehingga tidak menjelaskan penyebab keputusan.

Dua rencana diagnostik kuliner tersedia: satu ditolak sebagai bukti karena asalnya tenant, satu memakai entitas mal yang benar dan lolos aritmetika. Kecocokan diet/harga/akses tetap unknown. Evaluator adalah assistant yang mengetahui implementasi; ini membantu menemukan kelemahan dan **tidak** menjadi angka akurasi manusia. Seluruh percobaan yang terputus/ditolak dipertahankan dalam artefak, bukan dihapus atau diubah menjadi keberhasilan. Perbaikan engine atas temuan ini belum diterapkan dalam eksperimen tersebut.

## Rencana tindak lanjut dan E5, 9 November 2026

[Rencana perbaikan bertahap](../../apps/c67-local-server-lab/docs/REMEDIATION_PLAN_2026-11-09.md) memisahkan perbaikan kode sekarang dari kebutuhan data tambahan. Input E5 jalur personal sudah dinormalisasi ke bahasa Inggris versi `en-v1`, dengan model/bobot tetap; tiga tes input dan satu tes simulator lulus. Ini belum bukti peningkatan akurasi. Perbaikan identitas, alasan penghilangan, TripIntent/bukti, perluasan kandidat dan slot waktu masih rencana, bukan pekerjaan yang sudah selesai.

## 1. Konteks dan batas pemahaman

Fokus aktif adalah eksperimen terisolasi di `poc/c67-local-server-lab`, menggunakan server lokal Mac dan aplikasi Simulator C67 Context Lab. Penggabungan seluruh PoC menjadi produk bukan lingkup aktif pembahasan ini. Hasil Simulator tidak dianggap sebagai validasi iPhone fisik atau perjalanan lapangan.

Definisi yang dipakai:

- **Kecepatan:** lama pemrosesan rute atau urutan, termasuk validasi ETA yang diperlukan.
- **Akurasi:** apakah hasil sesuai dengan keinginan pengguna.
- **Waktu perjalanan:** durasi pengguna berpindah, menunggu, berkunjung, sampai kembali; dilaporkan terpisah dari kecepatan aplikasi.
- **Batas wajib:** aturan yang tidak boleh dilanggar, seperti waktu pulang, tujuan wajib, durasi minimum yang disepakati, dan batas menunggu.
- **Preferensi:** keinginan yang dapat dikompromikan dalam batas yang diketahui pengguna.
- **Belum diketahui:** informasi yang tidak tersedia atau belum cukup kuat. Status ini tidak otomatis berarti baik, buruk, aman, atau tidak memungkinkan.

Brief pengguna yang sudah diberikan adalah **“Taman sore; museum fleksibel; menunggu maksimal 30 menit.”** Pengguna sebelumnya menerima kunjungan taman 14.45–15.45 sebagai sesuai maksudnya. Rentang **mulai 15.00–16.00** pada kampanye terakhir merupakan operasionalisasi soft preference yang lebih ketat oleh operator; bukan batas wajib baru dari pengguna.

Google Places telah diizinkan untuk data pendukung dalam lab ini. Konfirmasi pengguna atas kecocokan tempat Google dan Apple tetap diperlukan pada jalur dinamis sekarang. Tidak ada LLM judge pada planner saat ini. Kemampuan retrieval E5 tidak boleh disamakan dengan akurasi jadwal atau kepuasan pengguna.

## 2. Bukti awal dan batas kesimpulannya

Kampanye terakhir mencakup **54 observasi terkendali: 18 skenario × 3 pengulangan**, serta **16 rencana live: 12 observasi utama dan 4 diagnosis satu kali**. Sebanyak 112 package tests lulus dan satu tes live opsional dilewati. Auditor independen memeriksa kepatuhan output terhadap aturan; hasil ini belum membuktikan kepuasan pengguna atau ketepatan kondisi lapangan.

Contoh hasil yang memicu pembahasan:

| Kasus | Waktu pemrosesan client | Kunjungan taman | Pelajaran |
|---|---:|---|---|
| 3 tujuan, first-feasible, grid 15 menit | Median 8,395 detik; n=3 | 13.00–14.00 | Cepat dan lolos aturan wajib, tetapi meleset dari preferensi sore |
| 3 tujuan, first-feasible, grid 5 menit | Median 27,572 detik; n=3 | 11.40–12.40 | Grid lebih rinci tidak otomatis memperbaiki kecocokan |
| 3 tujuan, beam, grid 15 menit | 22,203 detik; n=1 | 14.45–15.45 | Konsisten dengan contoh yang dahulu diterima pengguna; belum merupakan penilaian pengguna baru |
| 5 tujuan, first-feasible, grid 15 menit | Median 9,534 detik; n=3 | 15.15–16.15 | Cocok untuk kasus tersebut; bukan bukti metode ini selalu terbaik |

Waktu tersebut dimulai setelah pilihan tempat disiapkan, mencakup pengambilan cuaca per rencana dan routing, serta tidak mencakup pencarian awal dan waktu pengguna menentukan pilihan. Kasus tiga dan lima tujuan memiliki input serta jam berangkat berbeda; jangan membandingkannya sebagai pengaruh jumlah tujuan saja.

Semua 16 rencana live lolos audit aturan keras dan tetap berstatus `candidate_with_unknown_preferences`. Sebanyak 33 kandidat lengkap dalam pengujian terkendali cocok dengan acuan optimum fixture untuk penalti cuaca dan waktu selesai. Sisa 21 observasi merupakan kontrol pemblokiran atau pemotongan pencarian; bukan 21 kegagalan akurasi manusia.

Laporan utama: Dynamic Context Simulator Results (original local evidence, omitted from this publication).

## 3. Daftar blind spot sistem

| ID | Blind spot | Kondisi yang ditemukan | Risiko atau hipotesis dampak |
|---|---|---|---|
| S01 | Pertukaran antarpreferensi belum mewakili pengguna | Skor dibandingkan secara berurutan mutlak; urutan bawaan adalah waktu pilihan, hujan, ketenangan, suhu | Jika dua kandidat dibandingkan, perbaikan satu menit pada preferensi waktu dapat mengalahkan perbaikan besar pada risiko hujan |
| S02 | Arti keinginan pengguna terlalu disederhanakan | Preferensi waktu menjadi rentang mulai kunjungan | “Taman sore” dapat berarti mulai sore, menikmati sebagian besar waktu sore, atau mengejar sunset |
| S03 | Jadwal valid tetapi rapuh | ETA dan durasi digunakan sebagai nilai tertentu untuk menyusun jadwal | Keterlambatan kecil dapat menggagalkan kunjungan berikutnya |
| S04 | Pin tempat belum tentu pintu masuk yang tepat | Konfirmasi identitas Google–Apple belum membuktikan akses lapangan | Salah sisi kompleks, waktu parkir, berjalan, atau pemeriksaan keamanan belum terhitung |
| S05 | Jam buka belum menjamin aktivitas bisa dilakukan | Sesi operasional dan durasi penuh sudah diperiksa; syarat masuk belum lengkap | Penerimaan terakhir, reservasi, tiket, dan penutupan bagian tempat dapat menggagalkan kunjungan |
| S06 | Pengaruh cuaca terlalu sempit | Skor hujan menggunakan probabilitas tertinggi per jam selama kunjungan outdoor | Intensitas, lama paparan, akses, antrean, perpindahan, dan kondisi setelah hujan belum matang |
| S07 | Urutan pengisian dapat memengaruhi rekomendasi | First-feasible mengikuti urutan percobaan; selective-orders dibatasi beberapa urutan awal | Tujuan dan preferensi sama dapat menghasilkan kualitas berbeda karena urutan menambah tempat |
| S08 | Grid waktu menghasilkan penantian buatan | Mulai kunjungan dibatasi kelipatan 5 atau 15 menit | Tiba 10.01 dapat dipaksa mulai 10.15 tanpa alasan operasional |
| S09 | Informasi tidak diketahui diberi penalti buatan | Nilai preferensi yang tidak tersedia memakai penalti tetap `10000` | Kelengkapan data dapat menentukan pemenang tanpa dasar toleransi pengguna terhadap ketidakpastian |
| S10 | Pencarian dinamis belum sama dengan rekomendasi tempat yang matang | Pengguna dapat mencari di luar katalog, tetapi masih memilih tujuan; sentimen publik lengkap belum masuk jalur live | Penyusunan tujuan pilihan belum membuktikan pemilihan tempat terbaik untuk brief terbuka |

Status S01, S02, S06–S09 didukung perilaku implementasi. Besarnya dampak terhadap pengguna masih perlu diukur. S03–S05 dan S10 terutama menunjukkan cakupan yang belum lengkap; bukan klaim bahwa semua hasil sekarang salah.

## 4. Daftar blind spot pengujian

| ID | Blind spot | Mengapa hasil sekarang belum cukup |
|---|---|---|
| P01 | Auditor membuktikan kepatuhan model, bukan kebenaran keinginan | Aturan yang salah mendefinisikan akurasi tetap bisa menghasilkan output yang lolos seluruh pemeriksaan |
| P02 | Sampel live kecil dan dipilih operator | Belum mewakili pengguna, tempat, hari, jaringan, maupun distribusi gangguan; kasus pengembangan tidak boleh terus disebut holdout |
| P03 | Waktu benchmark dimulai setelah tempat disiapkan | Tepat untuk pemrosesan rute, tetapi belum menggambarkan seluruh pengalaman dari pencarian hingga itinerary diterima |
| P04 | Rencana awal belum diuji sebagai perjalanan yang berubah | Keberhasilan menyusun jadwal belum membuktikan keberhasilan menjalankan dan memperbaruinya ketika kondisi berubah |

## 5. Usulan solusi dan pembuktiannya

### R01 — Representasikan maksud, toleransi, dan kompromi pengguna

**Menangani:** S01, S02; membantu P01.

Setiap keinginan sebaiknya memiliki bagian waktu yang dimaksud, tingkat keharusan, keluwesan, dan prioritas ketika bertabrakan. Pisahkan preferensi waktu mulai, seluruh durasi, dan sebagian durasi kunjungan. Contoh terjemahan: “sebagian besar kunjungan taman berlangsung sore; boleh sedikit lebih awal; menghindari hujan lebih penting.” Ini contoh representasi, bukan preferensi tambahan yang sudah disetujui pengguna.

Terjemahan harus terlihat dan mudah dikoreksi. Ajukan pertanyaan hanya ketika perbedaan makna dapat mengubah keputusan. Jangan membuat pengguna mengisi seluruh kemungkinan preferensi untuk setiap perjalanan.

Urutan penilaian yang diusulkan:

1. Singkirkan pelanggaran batas wajib.
2. Perlakukan kandidat di dalam toleransi yang disepakati sebagai sama-sama dapat diterima untuk aspek tersebut.
3. Bandingkan preferensi berikutnya sesuai kompromi pengguna.
4. Bila kompromi belum diketahui, tampilkan maksimal dua atau tiga alternatif yang berbeda secara berarti. Bila satu kandidat lebih baik pada semua aspek yang diketahui, cukup tampilkan kandidat itu.

Mengganti seluruh penilaian menjadi satu skor berbobot bukan solusi otomatis. Bobot masih dapat menyembunyikan asumsi tentang kesetaraan satu menit, risiko hujan, dan ketenangan. Toleransi maupun bobot perlu dibuktikan melalui pilihan pengguna, bukan ditetapkan agar kasus lama terlihat bagus.

**Uji:** pasangan jadwal yang sengaja mempertentangkan waktu, cuaca, perjalanan, dan menunggu. Minta pilihan pengguna sebelum nama metode dibuka. Catat pilihan, seri, penolakan keduanya, koreksi, dan alasannya.

**Benturan:** C01, C02, C08 pada tabel benturan.

### R02 — Pisahkan tempat, titik kedatangan, dan lokasi aktivitas

**Menangani:** S04; membantu S03, S06, P04.

Model perlu membedakan kompleks/tempat, titik turun atau parkir, pintu masuk, dan lokasi aktivitas. ETA kendaraan berakhir di titik kedatangan; waktu siap berkunjung diperoleh setelah akses menuju aktivitas diperhitungkan.

Catat sumber informasi akses, tanggal pemeriksaan, moda, dan keterbatasannya. Konfirmasi bahwa dua provider menunjuk tempat yang sama belum membuktikan gerbangnya dapat digunakan. Jika waktu akses belum diketahui, jangan otomatis mengisinya dengan nol.

Untuk PoC, mulai dari beberapa tempat kompleks dengan verifikasi manual, bukan langsung membangun basis data akses seluruh Jakarta. Contoh GBK perlu membedakan kompleks, stadion, taman, dan gerbang yang relevan dengan kegiatan.

**Uji:** ukur waktu tiba di pin sampai siap beraktivitas, akses salah gerbang, serta perbedaan mobil, berjalan, atau moda yang memang diuji. Jangan menggeneralisasikan hasil satu moda ke semua moda.

**Benturan:** C03 dan C04.

### R03 — Periksa apakah aktivitas dapat dilakukan, bukan hanya apakah tempat buka

**Menangani:** S05; membantu S03, S09.

Pisahkan jam operasional, penerimaan terakhir, reservasi/tiket, jadwal aktivitas, dan penutupan khusus. Seluruh durasi harus berada dalam sesi yang sesuai, dan syarat masuk perlu diperiksa sebelum menyatakan kunjungan terverifikasi.

Gunakan jam provider sebagai salah satu sumber dan informasi operator untuk syarat yang relevan jika tersedia. Simpan tanggal keberlakuan dan konflik antarsumber; informasi paling baru diambil belum tentu paling benar atau paling relevan untuk tanggal perjalanan.

Google `currentOpeningHours` mencakup tujuh hari termasuk hari permintaan. Tanggal di luar cakupan itu perlu dipisahkan dari tanggal yang memiliki pengecualian operasional terkini. Jam reguler tidak menjamin tidak ada pengecualian pada hari perjalanan.

Jika ketersediaan tiket wajib belum diketahui, keluarkan hasil bersyarat yang menyebut ketergantungan tersebut. Bedakan “tidak tersedia” dari “belum dapat dipastikan”.

**Uji:** penerimaan terakhir lewat meskipun tempat masih buka; sesi makan siang; tiket habis; reservasi pada jam tertentu; hari libur/penutupan khusus; tanggal di luar cakupan jam terkini; kunjungan yang mencoba melintasi sesi tutup.

**Benturan:** C04, C05, C06.

### R04 — Ukur ketahanan jadwal terhadap keterlambatan

**Menangani:** S03; membantu S04, S05, P04.

Tambahkan ukuran kelonggaran: seberapa besar keterlambatan yang masih dapat ditanggung sebelum kunjungan penting gagal. Hitung dampaknya terhadap seluruh kunjungan berikutnya, bukan hanya sisa waktu sebelum pulang.

Pisahkan cadangan waktu dari penantian yang dijadwalkan. Cadangan adalah ruang untuk menyerap gangguan; tidak seluruhnya berarti pengguna diminta duduk menunggu. Jangan mengubah definisi penantian hanya agar batas 30 menit terlihat terpenuhi.

Tahap awal dapat menggunakan skenario gangguan: satu perjalanan terlambat, semua perjalanan melambat, antrean bertambah, satu kunjungan memanjang, serta gangguan bersamaan akibat kondisi yang sama. Angka gangguan awal harus disebut asumsi eksperimen dan kemudian diperbarui dengan pengamatan lapangan.

**Uji:** pertahankan rencana awal lalu jalankan skenario gangguan yang sama untuk semua metode. Laporkan kunjungan wajib yang tetap tercapai, pelanggaran jam operasional, terlambat pulang, dan gangguan maksimum yang masih tertangani. Persentase lolos skenario buatan bukan probabilitas keberhasilan nyata sebelum model gangguannya tervalidasi.

**Benturan:** C03 dan C07.

### R05 — Nilai cuaca berdasarkan kegiatan dan seluruh bagian perjalanan

**Menangani:** S06; membantu S03, S09.

Bagi kunjungan menjadi perpindahan, akses, antrean, kegiatan utama, dan perjalanan kembali. Paparan indoor/outdoor harus mengikuti kegiatan, bukan semata kategori tempat. Museum indoor tidak menjamin antrean dan akses terlindung; kafe indoor belum tentu cocok jika kegiatan yang diinginkan adalah duduk di teras.

Jika tersedia dan relevan, pisahkan peluang presipitasi, jumlah presipitasi, suhu terasa, dan angin. Jangan menjumlahkan atau mengalikan peluang hujan beberapa jam lalu menyatakannya sebagai probabilitas terkena hujan sepanjang kunjungan tanpa model ketergantungan yang tervalidasi. Skor maksimum per jam sekarang adalah heuristik yang perlu dijelaskan, bukan jaminan cuaca.

Kondisi setelah hujan juga dapat memengaruhi aktivitas. Jika belum ada bukti genangan, kondisi jalur, atau penutupan, tandai sebagai belum dimodelkan daripada menyimpulkan aman dari prakiraan yang membaik.

**Uji:** akses terbuka versus tertutup, antrean outdoor pada tempat indoor, durasi pendek versus panjang, perubahan prakiraan, dan cuaca hilang/kedaluwarsa. Pastikan pembaruan cuaca dapat mengubah hasil hanya pada bagian yang relevan.

**Benturan:** C02, C04, C06, C07.

### R06 — Pisahkan kualitas jadwal dan kelengkapan bukti

**Menangani:** S09; membantu S05, S06, S10, P01.

Ganti satu penalti `10000` dengan kebijakan sesuai jenis informasi dan kebutuhan pengguna. Jam kunjungan wajib yang belum diketahui dapat menghalangi klaim terverifikasi. Ketenangan yang belum diketahui tidak otomatis menghalangi jadwal, tetapi ketenangan tidak boleh dijanjikan. Ketidakpastian cuaca perlu mengikuti pentingnya menghindari hujan bagi pengguna.

Setiap informasi perlu menyimpan sumber, waktu pengambilan, tanggal/cakupan berlaku, konflik, dan apakah berupa fakta, pernyataan subjektif, atau asumsi. “Baru diambil” dan “terbukti benar” merupakan dua hal berbeda.

Tampilkan kecocokan dan kelengkapan bukti secara terpisah. Hindari angka seperti “92% akurat” tanpa kalibrasi. Status kandidat, hasil bersyarat, dan hasil yang memerlukan data tambahan harus mudah dibedakan.

**Uji:** hapus satu jenis informasi dari kasus yang sama. Perubahan status dan keputusan harus mengikuti kebijakan yang dinyatakan, bukan menganggap kondisi hilang otomatis baik atau buruk. Periksa apakah tempat dengan data kurang lengkap selalu tersingkir tanpa alasan yang relevan.

**Benturan:** C04, C05, C06.

### R07 — Kurangi bias akibat urutan pengisian tujuan

**Menangani:** S07; membantu P01, P02.

Pisahkan urutan menambahkan tempat dari instruksi urutan kunjungan. Jika pengguna menyebut “museum sebelum taman”, simpan sebagai aturan eksplisit. Jika tidak, susunan pengisian tidak boleh otomatis dianggap maksud pengguna.

Bentuk kandidat awal yang beragam berdasarkan waktu tutup, waktu pilihan, dan kedekatan. Bagikan anggaran pencarian agar tidak habis pada satu keluarga urutan. Aturan pemecah seri harus konsisten agar hasil dapat direproduksi.

Mengurutkan ID hanya membuat perilaku konsisten; bukan bukti kualitas meningkat. Pencarian terbatas tetap dapat melewatkan solusi lebih baik dan perlu melaporkan pemotongannya.

**Uji:** keenam susunan input tiga tujuan dan seluruh 120 susunan lima tujuan pada data terkendali yang sama. Bandingkan kualitas dengan acuan kasus kecil. Urutan output boleh berbeda jika kualitasnya setara. Nilai pula selisih kualitas terhadap acuan, biaya ETA, dan waktu komputasi.

**Benturan:** C04 dan C09.

### R08 — Bentuk kandidat waktu dari kejadian yang relevan

**Menangani:** S08; membantu S03, S07.

Selain grid, tambahkan waktu tiba sebenarnya, jam buka, awal rentang pilihan, awal sesi/reservasi, dan batas mulai agar durasi masih selesai tepat waktu. Tiba 10.01 di tempat yang telah buka dapat menghasilkan kandidat mulai 10.01.

Grid masih dapat membantu penjelajahan waktu, terutama karena ETA berubah menurut keberangkatan. Namun tidak perlu menjadi satu-satunya sumber waktu mulai. Menunda keberangkatan juga perlu dievaluasi jika bermanfaat dan diizinkan; berangkat paling awal tidak otomatis terbaik.

Periksa ulang kandidat akhir dengan ETA pada waktu keberangkatan yang sesuai. Pergeseran waktu kunjungan dapat mengubah perjalanan berikutnya. Jangan menghapus penantian di laporan tanpa memperbaiki jadwal dan pemeriksaan waktunya.

**Uji:** tiba satu menit setelah grid, jam buka yang tidak bulat, rentang preferensi sempit, serta kasus di mana berangkat lebih lambat mengubah ETA. Ukur penantian buatan yang hilang, kualitas hasil, dan biaya tambahan. Ini hipotesis perbaikan; belum menggantikan grid di aplikasi.

**Benturan:** C04 dan C09.

### R09 — Hubungkan penemuan tempat, sentimen, dan kemungkinan jadwal

**Menangani:** S10; membantu S05, S06, S09.

Alur rekomendasi terbuka: temukan kandidat sesuai kegiatan/wilayah, periksa syarat penting, susun beberapa kombinasi, lalu perluas pencarian jika hasil awal kurang baik. Pemilihan tempat dan penyusunan jadwal perlu saling memberi masukan.

Contoh “taman sore dekat museum” perlu menilai kegiatan, akses, cuaca, waktu, dan perjalanan keseluruhan. Rating tinggi atau lima hasil pencarian pertama belum membuktikan pilihan terbaik. Batas Jakarta dan maksimal enam tujuan pada pilot tetap merupakan batas cakupan sekarang.

Pisahkan fakta dari pengalaman subjektif. Pernyataan “nyaman menjelang sore” harus membawa konteks dan sumber; sedikit ulasan tidak cukup untuk menyatakan konsensus atau pola keramaian per jam. Data tidak tersedia tidak berarti tempat sepi, ramai, atau tidak disukai.

Jika kelak LLM dipakai membaca ulasan, batasi usulan perannya pada ekstraksi pernyataan beserta sumber dan ketidakpastian. Hasil ekstraksi tetap diperiksa sebelum memengaruhi keputusan. Ini bukan keputusan untuk menambahkan LLM judge.

**Uji:** brief tanpa nama tempat, tempat di luar katalog lama, kandidat dengan informasi tidak merata, dan kebutuhan kelompok seperti orang tua. Nilai relevansi tempat, kelayakan jadwal, serta penerimaan/koreksi pengguna secara terpisah.

**Benturan:** C04, C05, C09.

### R10 — Pisahkan pengujian aturan, algoritma, manusia, dan lapangan

**Menangani:** P01, P02; memvalidasi R01–R09.

| Lapisan | Pertanyaan | Bukti yang diperlukan |
|---|---|---|
| Aturan | Apakah jadwal mematuhi durasi, sesi operasional, batas menunggu dan pulang? | Auditor independen dan kontrol output yang sengaja dirusak |
| Algoritma | Apakah pencarian melewatkan kandidat lebih baik menurut model yang sama? | Enumerasi/acuan independen untuk kasus kecil dengan data dibekukan |
| Pengguna | Apakah hasil memenuhi maksud sebenarnya? | Alternatif tersamar, urutan tampilan acak, pilihan dan alasan pengguna |
| Lapangan | Apakah jadwal dapat dijalankan? | Pengamatan akses, antrean, waktu masuk, durasi, serta perubahan kondisi |

Auditor independen tetap dapat memakai asumsi yang sama dengan planner. Karena itu, kelulusan audit tidak membuktikan asumsi tersebut cocok dengan kebutuhan pengguna.

Bekukan brief, aturan, dan ukuran keberhasilan sebelum membandingkan metode. Sediakan kasus baru yang tidak digunakan untuk tuning. Kasus evaluasi yang sudah dipakai memperbaiki algoritma menjadi kasus pengembangan/regresi, bukan holdout yang masih bersih.

Pengguna harus boleh memilih keduanya sesuai, keduanya tidak sesuai, atau menjelaskan koreksi. Jangan memaksa pemenang pada hasil yang setara. Laporkan empat lapisan secara terpisah, bukan satu angka “akurasi”.

**Uji:** jalankan lapisan aturan dan acuan pada tiap perubahan relevan; jalankan evaluasi manusia pada perubahan cara mengambil keputusan; gunakan perjalanan kecil untuk memeriksa asumsi operasional. Tambah variasi menurut alasan, bukan sekadar mengulang satu kasus berkali-kali.

**Benturan:** C10.

### R11 — Perluas benchmark kecepatan tanpa mencampur ukuran yang berbeda

**Menangani:** P02, P03; membantu pengambilan keputusan R07–R09.

Pertahankan pemrosesan rute/urutan termasuk ETA sebagai ukuran utama kecepatan. Tambahkan pencarian/persiapan tempat, waktu sampai hasil layak ditampilkan, dan waktu seluruh alur. Pisahkan waktu pengguna berpikir dari waktu sistem bekerja, dan jangan menjumlahkan tahap yang berjalan tumpang tindih dua kali.

Pisahkan kondisi pertama kali, cache masih berlaku, serta data kedaluwarsa. Masukkan kegagalan, timeout, dan hasil terpotong ke laporan; jangan hanya merata-ratakan keberhasilan. Tambah variasi hari, jam sibuk, jaringan, tempat kompleks, dan kelengkapan data.

Bandingkan metode dengan input sama dan urutan eksekusi bergantian. Lakukan perbandingan anggaran ETA sama serta anggaran waktu komputasi sama. Gunakan data beku untuk isolasi algoritma dan live berpasangan untuk biaya provider. n=3 tetap deskriptif dan diagnosis n=1 tidak disamakan dengan benchmark berulang; belum cukup untuk SLA atau ekor distribusi yang dapat diandalkan.

Sebelum mempercepat dengan paralelisme, ukur antrean, pembatasan provider, biaya, dan perilaku gagal. Jeda awal 1,2 detik pada lab adalah kebijakan lab, bukan bukti kewajiban Apple. Server tersendiri saja belum terbukti menghilangkan biaya permintaan ETA.

Jika hasil ditampilkan bertahap, bedakan hasil sementara dari kandidat yang telah lolos pemeriksaan. Kecepatan tampilan tidak boleh menyembunyikan validasi yang belum selesai.

**Uji:** laporkan sebaran waktu, status hasil, jumlah permintaan, kualitas, serta kondisi cache/jaringan bersama-sama. Jangan menambahkan biaya persiapan bersama ke setiap rencana seolah diulang dari nol.

**Benturan:** C04, C06, C09.

### R12 — Perbarui rencana secara terkendali ketika kondisi berubah

**Menangani:** P04; membantu S03–S06.

Pertahankan kunjungan selesai, keputusan yang dikunci pengguna, dan reservasi. Evaluasi ulang bagian terdampak ketika terlambat, kunjungan memanjang, tempat tutup, atau prakiraan berubah. Tidak semua perubahan membutuhkan penghitungan ulang seluruh perjalanan.

Nilai pula biaya perubahan: kebingungan, perjalanan tambahan, dan kegiatan yang sudah disepakati. Jangan mengganti itinerary karena perbaikan sangat kecil. Tetapkan ambang manfaat atau risiko pelanggaran yang membenarkan perubahan, lalu uji ambang tersebut.

Jika pembaruan gagal, simpan rencana sebelumnya dengan penanda bahwa kondisi terbaru belum terverifikasi. Hasil permintaan lama tidak boleh menimpa hasil yang lebih baru. Jalur context-planner sekarang belum dibuktikan menangani seluruh siklus ini; keberadaan eksperimen replanning lain tidak otomatis memvalidasi integrasi ini.

**Uji:** keterlambatan, penutupan, prakiraan berubah, jaringan putus, respons datang tidak berurutan, dan beberapa gangguan bersamaan. Ukur kunjungan yang terselamatkan, kegagalan, jumlah perubahan tidak perlu, serta waktu/biaya pembaruan.

**Benturan:** C06 dan C07.

## 6. Benturan antarsolusi

| ID | Benturan | Risiko | Cara menanganinya |
|---|---|---|---|
| C01 | Preferensi lengkap ↔ kemudahan penggunaan | Pengguna terbebani formulir dan pertanyaan | Klarifikasi hanya ambiguitas yang dapat mengubah hasil; tampilkan interpretasi yang dapat dikoreksi |
| C02 | Waktu pilihan ↔ cuaca | Waktu ideal dapat berisiko hujan; waktu lebih kering dapat meleset dari maksud | Gunakan toleransi dan prioritas pengguna; tawarkan alternatif bila kompromi belum diketahui |
| C03 | Cadangan, akses, dan antrean ↔ jumlah tujuan/waktu perjalanan | Jadwal realistis memuat lebih sedikit kegiatan | Bedakan wajib dan opsional; tawarkan pengurangan secara terbuka; jangan mengurangi dwell atau menambah batas menunggu diam-diam |
| C04 | Data lengkap dan pencarian teliti ↔ respons cepat/biaya API | Lebih banyak pemeriksaan dan kandidat memperlambat proses | Dahulukan informasi yang dapat menggagalkan perjalanan; perluas pencarian bertahap; nyatakan batas dan pemotongan pencarian |
| C05 | Bukti ketat ↔ cakupan serta keragaman tempat | Tempat dengan data sedikit selalu tersingkir | Pisahkan ketidakpastian dari kualitas; hasil bersyarat jika layak; batas wajib tetap tidak boleh dianggap terpenuhi tanpa bukti |
| C06 | Cache ↔ kemutakhiran | Cepat tetapi memakai kondisi lama | Bedakan kebijakan umur data menurut jenis dan penggunaan; catat waktu berlaku; perbarui informasi penting sebelum digunakan |
| C07 | Mengikuti kondisi terbaru ↔ stabilitas rencana | Jadwal sering berubah atau cadangan berlebihan menggeser kegiatan | Kunci komitmen dan kunjungan selesai; beri ambang manfaat perubahan; pertimbangkan biaya perubahan bagi pengguna |
| C08 | Toleransi/kompromi ↔ batas wajib | Pelonggaran preferensi merembet ke aturan yang tidak boleh dilanggar | Simpan keduanya terpisah; perubahan bobot atau toleransi tidak boleh menembus batas wajib |
| C09 | Urutan/waktu/kandidat lebih beragam ↔ anggaran pencarian | Kandidat tambahan menghabiskan ETA dan menyisakan sedikit anggaran validasi akhir | Alokasikan anggaran untuk eksplorasi dan penyelesaian; periksa kandidat akhir; jangan mengklaim optimum dari pencarian terpotong |
| C10 | Evaluasi manusia/lapangan ↔ kecepatan iterasi | Pengujian mahal dan lambat jika semuanya diulang | Pakai regresi otomatis untuk perubahan rutin; evaluasi manusia untuk kebijakan keputusan dan lapangan untuk asumsi operasional |

Tidak ada satu solusi yang menang pada semua aspek. Kompromi perlu terlihat dan tidak boleh diselesaikan dengan mengubah keinginan pengguna tanpa dasar.

## 7. Urutan pengerjaan yang direkomendasikan

Urutan ini merupakan rekomendasi, bukan daftar implementasi yang sudah selesai.

| Tahap | Fokus | Solusi utama | Bukti sebelum melangkah lebih jauh |
|---|---|---|---|
| 1 | Definisikan apa yang dianggap hasil baik | R01, R06, rancangan R10 | Makna preferensi, toleransi, batas wajib, status belum diketahui, dan kompromi dapat diperiksa; kasus konflik tidak diam-diam memakai asumsi operator |
| 2 | Perbaiki pencarian dengan eksperimen terkendali | R07, R08, acuan R10 | Bias susunan input dan penantian grid terukur; kualitas serta biaya dibandingkan dengan acuan kasus kecil |
| 3 | Lengkapi kelayakan dan ketahanan beberapa perjalanan | R02–R05 | Akses dan syarat masuk memiliki sumber; skenario gangguan mengungkap jadwal rapuh; cuaca dinilai sesuai kegiatan |
| 4 | Periksa kecocokan manusia dan kenyataan lapangan | R10, bagian P02/R11 | Alternatif dinilai tanpa label metode; alasan penolakan tercatat; asumsi akses dan waktu diuji dalam perjalanan kecil |
| 5 | Perluas cakupan dan optimalkan penggunaan | R09, R11, R12 | Rekomendasi terbuka, kecepatan, dan pembaruan dinilai oleh rangkaian evaluasi yang sudah mampu membedakan manfaat serta kegagalannya |

Instrumentasi dasar waktu dan kegagalan dapat diperbaiki sejak awal; tahap 5 berarti memperluas dan mengoptimalkannya setelah kualitas keputusan memiliki dasar yang lebih kuat. Pengujian lama tetap menjadi regresi dan tidak perlu diulang seluruhnya jika perubahan tidak relevan.

Prioritas pertama dalam diskusi adalah **menguji kompromi preferensi**, disertai pemeriksaan bias urutan input. Kita perlu memastikan metode yang lebih teliti memilih kompromi yang benar sebelum menambah banyak data atau kompleksitas.

## 8. Hal yang belum boleh diklaim

- Kelulusan aturan bukan persentase kecocokan pengguna.
- Optimum fixture sintetis bukan optimum kondisi Jakarta atau kualitas perjalanan nyata.
- n kecil bukan dasar SLA, p95 yang andal, atau metode terbaik untuk seluruh pengguna.
- Cuaca belum diketahui bukan cuaca baik; sumber baru diambil bukan otomatis benar.
- Tempat buka bukan jaminan tiket, akses, atau penerimaan pengunjung tersedia.
- Konfirmasi identitas bukan verifikasi pintu masuk lapangan.
- Tempat ditemukan di luar katalog bukan bukti rekomendasi terbuka telah matang.
- Hasil lama dan baru dengan tanggal, konteks, anggaran, atau kebijakan berbeda bukan pembuktian sebab-akibat algoritma saja.
- Pencarian terpotong yang tidak menemukan kandidat bukan bukti global bahwa perjalanan tidak memungkinkan.
- Solusi dalam dokumen ini belum diterapkan hanya karena sudah didokumentasikan.

## 9. Sumber dan jejak diskusi

### Artefak workspace

- Laporan kampanye Simulator 7–8 November 2026 (original local evidence, omitted from this publication).
- Protokol eksperimen (original local evidence, omitted from this publication).
- Context itinerary planner: ranking, anggaran, urutan, dan status hasil (original local evidence, omitted from this publication).
- Visit context: jam, preferensi, paparan, cuaca, dan grid (original local evidence, omitted from this publication).
- Dynamic service: pencarian, persiapan identitas, cuaca, dan perencanaan live (original local evidence, omitted from this publication).
- Kontrak input/output dinamis (original local evidence, omitted from this publication).
- Panduan Context Harness (original local evidence, omitted from this publication).

### Dokumentasi resmi yang diperiksa dalam pembahasan

- [Google Places REST resource](https://developers.google.com/maps/documentation/places/web-service/reference/rest/v1/places): cakupan current/regular hours, jam tambahan, dan pengecualian. Informasi API dapat berubah; periksa lagi ketika mengimplementasikan.
- [WeatherKit REST HourWeatherConditions](https://developer.apple.com/documentation/weatherkitrestapi/hourweatherconditions): peluang dan jumlah presipitasi, suhu terasa, dan parameter per jam. Ketersediaan data konkret tetap perlu diperiksa pada respons yang digunakan.
- [OR-Tools: Vehicle Routing Problem with Time Windows](https://developers.google.com/optimization/routing/vrptw): referensi pemodelan rentang waktu dan waktu menunggu; bukan keputusan mengganti engine atau bukti performa pada PoC ini.

### Pertanyaan pengguna yang membentuk dokumen

1. Setelah implementasi dan benchmark, pengguna meminta mencari blind spot lain pada sistem PoC.
2. Pengguna meminta solusi detail untuk seluruh blind spot sistem dan pengujian, memperbolehkan satu solusi menangani beberapa blind spot, dan meminta benturan antarsolusi ditandai dengan bahasa mudah dimengerti.
3. Pengguna meminta seluruh pembahasan tersebut dimasukkan ke `BLINDSPOT.md`.

Dokumen ini merupakan sintesis pembahasan dan sumber di atas, bukan transkrip seluruh chat atau laporan eksperimen baru.
