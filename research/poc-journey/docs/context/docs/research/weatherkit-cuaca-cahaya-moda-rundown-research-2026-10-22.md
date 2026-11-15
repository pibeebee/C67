# Riset hubungan cuaca, golden hour, moda transportasi, dan rundown

**Status konteks — 29 Oktober 2026:** Temuan sumber tetap bertanggal 22 Oktober. Arah produk diperbarui ke rekomendasi AI; metadata kreator pada sintesis lama tidak menjadi prasyarat baru. Tidak ada query WeatherKit destinasi atau riset vendor baru pada update ini. Lihat [acuan aktif](../technology/07-planning-integrations.md).

**Tanggal penelusuran:** 22 Oktober 2026, Asia/Jakarta (WIB).  
**Status:** desk research dan sintesis untuk eksplorasi produk C6; temuan sumber dipisahkan dari usulan perilaku aplikasi.  
**Konteks:** [CBL aktif](../../../source-records/CBL.md), [riset WeatherKit 21 Oktober](weatherkit-traveller-experience-research-2026-10-21.md), dan [rancangan integrasi](../technology/07-planning-integrations.md).  
**Register bukti:** [sumber, metode akses, temuan dan batas](weatherkit-cuaca-cahaya-moda-rundown-sources-2026-10-22.csv).

## 1. Kesimpulan yang paling relevan

Rundown perlu mempertimbangkan **kondisi pada saat traveller berada di spot dan berpindah**. Cuaca memengaruhi perlengkapan dan pilihan moda; pilihan moda mengubah waktu tiba; waktu tiba menentukan kondisi cuaca yang perlu diperiksa dan apakah kesempatan cahaya masih dapat dicapai. Perubahan satu bagian perlu ditinjau terhadap sisa perjalanan.

Kesimpulan ini menggabungkan bukti perubahan perilaku perjalanan, dokumentasi cuaca/cahaya, dan penalaran waktu. Ia mendukung eksplorasi fitur, belum membuktikan manfaat aplikasi bagi traveller Kota Tua atau menentukan algoritme final.

| Hubungan | Temuan / dasar | Implikasi produk yang layak diuji |
|---|---|---|
| Cuaca → moda | Studi Indonesia dan Vietnam mengaitkan hujan/cuaca buruk dengan perubahan pilihan kendaraan, termasuk motor ke mobil/taksi. | Cuaca ikut menentukan alternatif moda yang ditawarkan, bersama biaya, akses dan preferensi. |
| Moda → paparan cuaca | Kendaraan utama hanya satu bagian perjalanan; akses berjalan dan menunggu juga berada dalam rentang perjalanan. | Nilai perjalanan dari asal sampai tujuan, termasuk naik/turun kendaraan dan perpindahan. |
| Moda → waktu → cahaya | Setiap pilihan memiliki durasi berbeda; kesempatan cahaya terikat lokasi dan tanggal. | Hitung ulang waktu berangkat/tiba dan dampaknya pada target foto. |
| Cuaca → pengalaman cahaya | Fase matahari dan kondisi langit adalah informasi berbeda. | Tampilkan jendela cahaya dan prakiraan langit secara terpisah. |
| Badai/petir → pelaksanaan | Panduan resmi membedakan perlindungan dari hujan dan perlindungan dari petir. | Respons dapat berupa menunda kegiatan outdoor; pergantian moda saja belum menyelesaikan semua hambatan. |

Dasar rinci dan tautannya ada pada bagian 3–6. Implikasi di kolom kanan merupakan sintesis untuk aplikasi, bukan hasil eksperimen produk.

## 2. Batas yang berasal dari pengguna

**Given:** rundown pengalaman kreator adalah inti aplikasi; traveller memilih waktu fleksibel, mengunjungi spot dan mendokumentasikan perjalanan. Cuaca diharapkan membantu persiapan jas hujan/payung, pemilihan moda dan penyesuaian rundown. Klarifikasi terbaru menegaskan cuaca harus memengaruhi pilihan moda, termasuk menghindari motor saat hujan.

**Usulan untuk diuji:** gunakan preferensi seperti “hindari motor ketika hujan” ketika membandingkan alternatif. Bentuk kontrol, default, serta cara menerapkannya terhadap prakiraan belum ditetapkan. Preferensi tersebut berbeda dari klaim bahwa semua orang selalu berhenti menggunakan motor pada semua jenis hujan.

**Needs validation:** siapa pengguna awal; toleransi biaya dan berjalan; kondisi hujan yang dianggap relevan; kemampuan kreator merawat metadata spot; makna “mulai”; sumber moda/ETA; aturan perubahan, skip dan penyelesaian sebagian. Desk research ini tidak menyelesaikan keputusan tersebut.

## 3. Cuaca memang berkaitan dengan pilihan moda, dengan respons yang beragam

### 3.1 Bukti Indonesia dan kota dengan penggunaan motor

[R01 — studi Tembalang, Semarang, 2019](https://scholar.undip.ac.id/en/publications/effect-of-weather-for-demand-of-online-transportation-in-tembalan/) meneliti mahasiswa dan perjalanan harian pada konteks musim hujan/kemarau. Abstrak di repositori institusi melaporkan keterkaitan hujan dengan peningkatan penggunaan layanan mobil daring. Ini bukti lokal yang relevan untuk arah hubungan; halaman yang diperiksa tidak cukup untuk mengambil ukuran sampel, ambang hujan atau besaran dampak yang dapat diterapkan pada produk.

[R02 — penelitian Ho Chi Minh City, 2020](https://doi.org/10.1007/978-981-15-0802-8_153) melaporkan survei revealed adaptation pada 400 responden dan stated adaptation pada 100 responden. Perpindahan motor ke mobil/taksi menjadi pola penting di antara perubahan moda; waktu, biaya dan karakteristik pengguna juga berhubungan dengan pilihan. Yang dapat dibaca langsung pada [repositori penulis/institusi](https://epub.vgu.edu.vn/bitstream/dlibvgu/400/1/Analysis%20of%20mode%20choice%20behavior%20under%20adverse%20weather%20conditions%20using%20RA%20and%20SA%20surveys%20-%20A%20case%20study%20from%20Ho%20Chi%20Minh%20City%20%28HCMC%29%2C%20Vietnam.pdf) adalah cuplikan dua halaman: abstrak dan awal metode, bukan keseluruhan hasil. Respons survei bukan eksperimen kausal atau observasi wisatawan aplikasi ini.

Ada bukti pembanding yang mencegah generalisasi berlebihan: [R03 — survei mahasiswa/staf di kota-kota Asia Timur, 2011](https://www.jstage.jst.go.jp/article/easts/9/0/9_0_483/_article) melaporkan moda utama relatif tidak banyak berubah pada banyak kota, sementara frekuensi perjalanan dan jadwal berubah menurut tujuan. Penulis menyebut sampel terbatas. Abstraknya menyebut sepuluh kota; jangan menyamakan angka itu dengan subset kota pada tabel analisis tertentu.

**Interpretasi:** cuaca dapat mengubah moda, jam perjalanan, tujuan, atau keputusan untuk tetap pergi. Pilihan “tunggu/ubah jam” perlu dipertimbangkan bersama pilihan “ganti moda”. Bukti belum menetapkan respons universal bagi traveller Jakarta.

### 3.2 Kenyamanan, perlindungan dan perjalanan lengkap

Untuk eksplorasi C6, bedakan motor pribadi/ojek, mobil pribadi/taksi daring, transportasi umum, dan berjalan. Penamaan “transportasi daring” saja menyatukan kendaraan terbuka dan tertutup yang memiliki pengalaman berbeda.

Usulan evaluasi alternatif perlu memerinci akses ke titik jemput/halte/stasiun, waktu menunggu, bagian dalam kendaraan, perpindahan, serta berjalan dari titik turun ke spot. Pilihan kereta dengan akses outdoor panjang dapat tetap memerlukan perlengkapan hujan. Ini konsekuensi dari penguraian perjalanan, bukan klaim bahwa seluruh jalur tersebut sudah diketahui aplikasi.

[R04 — FHWA Road Weather Management](https://ops.fhwa.dot.gov/weather/roadimpact.htm) mendokumentasikan pengaruh cuaca terhadap kecepatan dan kapasitas jalan. Temuan Amerika Serikat tidak memberi pengali ETA untuk Jakarta. Implikasinya: mengganti motor dengan mobil tidak otomatis mempertahankan waktu tiba; aplikasi memerlukan estimasi yang berlaku untuk pilihan dan waktu baru.

## 4. Hujan biasa, hujan lebat, dan badai/petir memerlukan respons berbeda

### 4.1 Peluang hujan belum menjelaskan seluruh pengalaman

[R05 — Apple precipitationChance](https://developer.apple.com/documentation/weatherkit/hourweather/precipitationchance) mendefinisikan peluang presipitasi per jam, bernilai 0–1. [R06 — penjelasan Hong Kong Observatory](https://www.weather.gov.hk/PoP) menjelaskan bahwa peluang presipitasi tidak langsung menyatakan durasi atau intensitas. Ambang ukur hujan milik HKO tidak boleh dipindahkan ke WeatherKit.

Karena itu, angka peluang hujan tidak cukup untuk menyatakan hujan lebat, petir, atau jalan banjir. Periksa konteks lain yang tersedia. Jangan merata-ratakan atau menjumlahkan peluang beberapa jam menjadi “peluang kehujanan seluruh trip” tanpa model dan definisi kejadian yang tepat.

[R07 — HourWeather](https://developer.apple.com/documentation/weatherkit/hourweather) menyediakan kondisi per jam, jumlah presipitasi, angin, jarak pandang, awan, suhu dan UV. [R08 — WeatherCondition](https://developer.apple.com/documentation/weatherkit/weathercondition) membedakan drizzle, rain, heavyRain, beberapa kategori thunderstorms dan strongStorms. Kategori tersebut merupakan deskripsi kondisi, bukan pengukuran sambaran petir di posisi pengguna.

### 4.2 Persiapan hujan berbeda dari respons terhadap petir

[R09 — CDC Lightning FAQ](https://www.cdc.gov/lightning/faq/index.html) menyebut bangunan tertutup dan kendaraan beratap keras sebagai tempat perlindungan yang relevan terhadap petir; motor, kendaraan terbuka dan struktur terbuka tidak memberi perlindungan setara. Petir juga dapat terjadi di luar area hujan. Sumber ini tidak berarti perjalanan dengan mobil selalu dapat dilanjutkan pada semua kondisi jalan.

**Usulan perilaku produk:**

| Keadaan yang diketahui | Respons yang dapat dieksplorasi | Batas pesan |
|---|---|---|
| Prakiraan hujan pada segmen outdoor | Persiapan pelindung hujan; bandingkan moda tertutup atau waktu lain. | Sebut prakiraan, interval dan bagian terdampak. |
| Prakiraan hujan lebat, angin atau visibility yang mengganggu | Tinjau ulang perpindahan, ETA dan kegiatan terbuka. | Jangan menyimpulkan banjir, penutupan jalan atau operasional kendaraan. |
| Prakiraan badai/petir atau peringatan resmi yang relevan | Tonjolkan informasi otoritas; pertimbangkan menunda segmen outdoor dan meninjau alternatif. | Jas hujan/payung dan pergantian moda tidak menjamin semua kegiatan dapat dilanjutkan. |
| Data tidak tersedia/kedaluwarsa | Jelaskan keterbatasan; pertahankan akses ke rundown dan informasi sumber. | Jangan tampilkan status “aman” karena data/alert kosong. |

Label dan ambang tindakan pada tabel belum menjadi klasifikasi meteorologi atau kebijakan produk final. Pengalaman foto wajib dalam best-case juga memerlukan rancangan pengecualian; aplikasi tidak boleh mendorong dokumentasi outdoor demi progres ketika ada hambatan cuaca.

## 5. Golden hour menghubungkan lokasi, tanggal, kondisi langit dan waktu tiba

[R10 — PhotoPills](https://www.photopills.com/articles/mastering-golden-hour-blue-hour-magic-hours-and-twilights) menggunakan fase cahaya berbasis elevasi matahari. Konvensinya menempatkan golden hour antara elevasi −4° dan +6°, dengan arah waktu berbeda pagi/sore. Ini definisi operasional produk tersebut, bukan standar tunggal yang wajib diadopsi. Durasi berubah menurut lokasi dan tanggal; bukan selalu satu jam. Panduan yang sama menjelaskan peran cuaca dan arah cahaya, termasuk cahaya menyebar saat berawan.

[R11 — SunEvents WeatherKit](https://developer.apple.com/documentation/weatherkit/sunevents) mendokumentasikan sunrise, sunset, twilight, solar noon dan solar midnight; tidak menyediakan rentang golden hour langsung. Aplikasi perlu memilih definisi dan metode perhitungan tambahan. Algoritme/library belum dipilih atau diuji melalui riset ini.

**Implikasi rancangan:**

1. Pisahkan **jendela astronomi yang dihitung**, **prakiraan kondisi langit**, dan **catatan pengalaman kreator**. Label “kesempatan golden hour” tidak menjanjikan hasil foto.
2. Gunakan koordinat spot, tanggal dan zona waktu destinasi. Jam saran kreator pada tanggal lain tidak langsung menjadi jam cahaya pengguna.
3. Tentukan target siap di spot, bukan sekadar tiba di titik turun kendaraan. Masukkan berjalan terakhir dan waktu persiapan jika memang diperlukan.
4. Catatan orientasi subjek, penghalang dan akses tempat perlu sumber lain. Cloud cover tidak mengetahui bayangan sebuah bangunan.
5. Berawan tidak otomatis berarti pengalaman fotografi gagal; relevansinya bergantung pada tujuan kreator/traveller. Jangan membuat skor kualitas foto dari persentase awan saja.

## 6. Kemampuan WeatherKit dan celah data untuk konteks Indonesia

| Kebutuhan | Dokumentasi yang diperiksa | Konsekuensi eksplorasi |
|---|---|---|
| Konteks cuaca perjalanan | [R12 — WeatherKit overview](https://developer.apple.com/weatherkit/) menyebut kondisi saat ini dan prakiraan per jam hingga 10 hari; data menit dan severe alerts hanya wilayah tertentu. | Rencana di luar horizon perlu keadaan “prakiraan belum tersedia”. Jangan mengisi dengan angka tanggal tertentu dari statistik musim. |
| Menentukan ketersediaan | [R13 — WeatherAvailability](https://developer.apple.com/documentation/weatherkit/weatheravailability) memisahkan minuteAvailability dan alertAvailability, termasuk ketidaktersediaan sementara/wilayah. | Periksa respons destinasi. Tidak ada alert dapat berarti layanan tidak tersedia. |
| Sinyal wilayah | [R14 — Apple Weather regional availability](https://support.apple.com/en-us/105038), bertanggal 5 Juni 2026, mencantumkan Jepang untuk next-hour precipitation dan severe weather; Indonesia tidak tercantum pada kedua daftar. | Ini dokumentasi aplikasi Weather, bukan hasil uji WeatherKit Kota Tua. Jangan menjanjikan “hujan berhenti dalam 12 menit” atau alert resmi Indonesia sebelum spike. |
| Waktu dan sumber data | [R15 — WeatherMetadata](https://developer.apple.com/documentation/weatherkit/weathermetadata) memisahkan waktu permintaan dan kedaluwarsa; [R16 — WeatherAlert](https://developer.apple.com/documentation/weatherkit/weatheralert) memuat sumber, severity, ringkasan dan tautan detail. | Bedakan interval prakiraan, waktu diambil dan kejadian lapangan; tampilkan sumber pesan otoritas terpisah dari saran aplikasi. |
| Peringatan dini Indonesia | [R17 — BMKG Open Data](https://data.bmkg.go.id/peringatan-dini-cuaca/) mendokumentasikan RSS/CAP, wilayah terdampak, effective/expires, polygon, serta atribusi. | Kandidat sumber pelengkap untuk diteliti. Pencocokan area/waktu, pembaruan/pembatalan, konflik sumber dan perilaku gagal belum diuji. |
| Alternatif prakiraan lokal | [R20 — prakiraan terbuka BMKG](https://data.bmkg.go.id/prakiraan-cuaca/) mendokumentasikan prakiraan 3 hari, per 3 jam, untuk kelurahan/desa, diperbarui dua kali sehari. | Kandidat sumber pembanding/pelengkap dengan horizon dan resolusi berbeda. Jangan menyajikan interval tiga jam sebagai prediksi menit mulai/berakhirnya hujan atau sebagai pengukuran di setiap ruas. |
| Moda dan ETA | [R18 — MKDirectionsTransportType](https://developer.apple.com/documentation/mapkit/mkdirectionstransporttype) mendokumentasikan walking, automobile, cycling dan transit; tidak ada tipe motor tersendiri pada inventori ini. [R19 — transit](https://developer.apple.com/documentation/mapkit/mkdirectionstransporttype/transit) menyatakan dukungannya untuk estimasi waktu tiba. | Jangan menganggap rute mobil sebagai rute motor yang tervalidasi atau ETA transit sebagai itinerary kereta/bus lengkap. Dukungan destinasi, tarif, ketersediaan dan routing motor memerlukan sumber/spike tersendiri. |

BMKG dapat melengkapi kebutuhan alert tanpa harus menggantikan seluruh sumber prakiraan. Itu opsi arsitektur untuk diperiksa, bukan keputusan menambah integrasi pada pekerjaan ini. Inventori API terkini juga bukan bukti seluruh moda tersedia pada baseline iOS 18; availability OS tiap tipe perlu diperiksa saat implementasi. Tidak ada query terautentikasi WeatherKit, pengujian CAP aktif, kompilasi SDK atau pengujian rute destinasi.

## 7. Cara menghubungkan semuanya dalam rundown

Model berikut adalah usulan untuk walkthrough, bukan planner terimplementasi:

**Rundown + waktu pengguna → estimasi kunjungan/perpindahan → cuaca pada lokasi dan interval terkait → alternatif persiapan/moda/waktu → hitung ulang waktu tiba → tinjau target cahaya dan batas kunjungan.**

Perubahan moda dapat menggeser jam kunjungan dan kondisi yang relevan; alternatif perlu dievaluasi pada jadwalnya sendiri. Menunggu sampai hujan diprakirakan berkurang juga dapat mengurangi waktu untuk spot berikutnya. Perubahan urutan memerlukan pemeriksaan ulang jam buka, akses dan perpindahan baru.

### 7.1 Informasi minimum untuk membandingkan alternatif

| Bagian | Informasi yang diperlukan | Kemungkinan asal dan ketidakpastian |
|---|---|---|
| Spot | Koordinat, durasi, indoor/outdoor/mixed, batas operasional, alasan dan prioritas kunjungan, alternatif bila tersedia. | Kreator/sumber tempat; perlu bukti bahwa isian dapat dirawat. |
| Perpindahan | Moda, durasi berjalan/menunggu/berkendara, titik naik/turun, tarif/ketersediaan jika diketahui, bagian terlindung jika diverifikasi. | Provider, catatan kreator atau pengguna; unknown tetap unknown. |
| Waktu | Tanggal, zona destinasi, basis jam mulai, waktu selesai yang diinginkan, target kesempatan cahaya. | Pilihan pengguna + hasil perhitungan berlabel. |
| Cuaca | Interval dan lokasi representatif, peluang/jumlah/kondisi hujan, angin/visibility/awan yang relevan, alert, availability dan freshness. | Provider cuaca; sampel titik bukan pengukuran setiap ruas jalan. |
| Preferensi | Menghindari motor saat hujan, biaya, batas berjalan, target yang paling penting. | Dinyatakan pengguna; jangan diasumsikan dari profil. |

Jam buka merupakan batas jika sumbernya jelas. Golden hour dapat menjadi preferensi atau target prioritas sesuai pengalaman yang dipilih; tidak otomatis menjadi kewajiban bagi semua rundown.

### 7.2 Ilustrasi pengaruh moda terhadap target kedatangan

**Seluruh angka berikut fiktif**, untuk menjelaskan logika. Bukan prakiraan, ETA, jadwal layanan atau perhitungan golden hour Kota Tua. Misalkan traveller ingin siap di spot pada 17.00 dan memiliki preferensi menghindari motor ketika hujan.

| Alternatif | Waktu kendaraan + tunggu | Akses berjalan total | Persiapan di spot | Total | Paling lambat berangkat untuk target 17.00 |
|---|---:|---:|---:|---:|---|
| Motor | 30 menit | 5 menit | 10 menit | 45 menit | 16.15 |
| Mobil/taksi | 45 menit | 5 menit | 10 menit | 60 menit | 16.00 |
| Transportasi umum | 50 menit | 15 menit | 10 menit | 75 menit | 15.45 |

Jika ada prakiraan hujan yang relevan, motor dapat tidak disarankan sesuai preferensi; mobil masih memerlukan keberangkatan lebih awal; transportasi umum mempunyai bagian berjalan yang tetap perlu ditinjau. Jika seluruh alternatif melewati batas waktu pengguna, aplikasi perlu menjelaskan target yang tidak tercapai. Jangan mempercepat durasi atau mengarang moda agar semua opsi tampak layak.

Jika informasi badai/petir relevan, pertanyaan berubah menjadi apakah kegiatan outdoor perlu ditunda. Target foto tidak membenarkan mengabaikan kondisi tersebut. Cara menandai spot tertunda atau perjalanan selesai sebagian tetap keputusan produk terbuka.

### 7.3 Evaluasi setiap alternatif pada jadwalnya sendiri

Berikut penalaran rancangan berdasarkan interval cuaca [R05, R07, R12], metadata [R15], dan ketergantungan ETA [R04, R18, R19]; bukan algoritme yang sudah diuji:

1. Bentuk jadwal awal dari asal, tanggal/zona waktu, urutan spot, lama kunjungan dan perkiraan perpindahan yang diketahui.
2. Uraikan bagian berjalan, menunggu, berkendara dan berada di spot. Periksa kondisi pada lokasi serta rentang waktu masing-masing, termasuk akses ke titik awal rundown.
3. Untuk setiap alternatif moda atau waktu berangkat, hitung jadwal alternatif terlebih dahulu, lalu cocokkan kembali cuacanya. Prakiraan yang relevan untuk motor pukul 16.00 tidak otomatis menjadi prakiraan yang relevan untuk mobil pukul 17.00.
4. Periksa kembali kesempatan cahaya, jam buka, batas akhir perjalanan dan preferensi. Alternatif hanya ditawarkan sebagai layak jika input yang penting tersedia; hasil yang belum lengkap tetap mempunyai keterangan keterbatasan.
5. Tampilkan alasan dan konsekuensi yang dapat dibandingkan: persiapan, waktu, biaya bila diketahui, bagian outdoor, serta target yang mungkin terlewat. Pilihan menunggu, menunda spot atau mengubah prioritas tetap perlu dirancang.

**Contoh granularitas, seluruh waktu ilustratif:** perpindahan 16.50–17.20 melintasi dua interval prakiraan per jam. Tinjau kedua interval yang beririsan; jangan memakai satu ikon harian atau menyimpulkan hujan pasti mulai pada 17.00. Resolusi prakiraan membatasi ketelitian pesan. Peluang pada dua jam juga tidak boleh dijumlahkan menjadi peluang seluruh perjalanan.

Tidak ada ambang seperti “peluang hujan ≥60% pasti ganti moda” yang sudah didukung riset ini. Preferensi menghindari motor saat hujan dapat menjadi input pengguna; pemicunya terhadap prakiraan, default dan hak untuk meninjau alternatif masih perlu diuji. Saran tidak perlu mengubah rencana secara otomatis.

### 7.4 Pisahkan empat jenis informasi yang ditampilkan

| Jenis | Contoh pesan ilustratif | Dasar dan batas |
|---|---|---|
| Catatan kreator | “Spot ini disarankan untuk cahaya sore; sediakan waktu berjalan dari titik turun.” | Pengalaman/catatan kreator, bukan prakiraan tanggal traveller. |
| Hasil perhitungan | “Perkiraan jendela golden hour untuk lokasi dan tanggal ini.” | Definisi fase dan perhitungan astronomi; perlu validasi metode. Tidak menjamin matahari terlihat. |
| Prakiraan / pesan otoritas | “Hujan diprakirakan pada rentang perpindahan ini.” / peringatan resmi dengan sumbernya. | Pertahankan lokasi, interval, waktu pembaruan dan atribusi. Pesan alert resmi mengikuti ketentuan sumber. |
| Saran aplikasi | “Pertimbangkan mobil; estimasi tiba lebih lambat dan target cahaya perlu ditinjau.” | Inferensi dari input yang tersedia, terpisah dari pesan otoritas dan dapat ditinjau pengguna. |

Contoh-contoh tersebut bukan kondisi aktual Kota Tua. Aplikasi sebaiknya tidak mengubah “dataset alert tidak tersedia”, “tidak ada alert aktif”, dan “prakiraan tidak menunjukkan hujan” menjadi satu label “cuaca aman”. Ketiadaan alert bukan pengesahan perjalanan outdoor [R09, R13, R14, R17].

## 8. Peluang produk dan bukti berikutnya

| Guiding Question prioritas | Aktivitas terkecil yang berguna | Bukti yang dicari |
|---|---|---|
| Bagaimana hujan terakhir benar-benar mengubah perjalanan wisata pengguna? | Wawancara berbasis kejadian nyata; telusuri pilihan moda, perlengkapan, menunggu dan pembatalan. | Keputusan beserta kendalanya, bukan persetujuan terhadap konsep app. |
| Kapan pengguna ingin menghindari motor dan apa tradeoff penggantinya? | Walkthrough beberapa alternatif berlabel ilustrasi, dengan biaya/waktu/akses berbeda. | Preferensi, alasan menolak opsi, dan informasi yang belum cukup. |
| Apakah target cahaya layak mengubah waktu berangkat atau urutan spot? | Satu rundown konkret dengan satu target foto dan satu batas jam buka; bandingkan dua jam mulai. | Pemahaman konsekuensi, prioritas dan kontrol yang diharapkan. |
| Apakah data cukup untuk Kota Tua? | Spike terpisah WeatherKit dan ETA, serta kandidat CAP BMKG bila dipilih. | Availability, horizon, field kosong, timestamp, cakupan area, routing/mode yang benar-benar didukung, dan kegagalan. |
| Bisakah kreator menyediakan metadata yang dibutuhkan? | Amati penyusunan satu rundown sampai level spot/perpindahan. | Beban input, sumber informasi dan tanggung jawab pembaruan. |
| Apakah saran per segmen lebih dipahami? | Bandingkan ringkasan harian dengan penjelasan pada perpindahan/spot terkait. | Pengguna mengenali bagian terdampak dan memahami probabilitas serta batasnya. |

Calon pemilik wawancara/walkthrough: tim produk/riset. Calon pemilik spike: engineer iOS/backend sesuai sumber yang dipilih. Penugasan dan jadwal belum ditetapkan. Studi menggunakan pengalaman lampau atau skenario simulasi, tanpa meminta peserta menghadapi cuaca berbahaya atau memberikan lokasi pribadi yang tidak diperlukan.

**Penilaian keyakinan:** hubungan umum cuaca–perjalanan dan perbedaan kesempatan astronomi–kondisi langit didukung sumber. Manfaat rekomendasi bagi traveller aplikasi ini, ambang pemilihan moda dan kelengkapan data destinasi masih tentatif. Arah paling berguna untuk tahap berikutnya adalah menguji perbandingan perjalanan lengkap beserta konsekuensi waktu, kemudian membuktikan data yang mendasarinya.

**Kesiapan:** cukup untuk walkthrough konsep dengan skenario berlabel simulasi. Belum cukup untuk menjanjikan saran moda otomatis, akurasi waktu hujan di destinasi, atau rencana yang optimal. Bukti terpenting berikutnya adalah keputusan traveller pada perjalanan nyata dan kemampuan sumber cuaca/ETA untuk satu rundown konkret.

## 9. Batas pekerjaan

- Sumber daring primer diperiksa ulang pada 22 Oktober; studi lama diberi tahun publikasi, bukan diperlakukan sebagai potret Jakarta 2026.
- Sumber penelitian mencakup abstrak institusi, abstrak penerbit dan cuplikan metode; kedalaman akses dicatat dalam register. Tidak ada klaim efek kausal, ukuran dampak untuk produk, atau temuan traveller tim.
- Dokumentasi Apple dibaca langsung melalui web dan ekstraksi Sosumi; tautan bukti mengarah ke dokumentasi resmi. Dokumentasi bukan bukti kompilasi atau respons API destinasi.
- Penguraian perjalanan, preferensi moda, model evaluasi dan contoh angka merupakan sintesis/usulan, bukan aturan produk yang sudah disetujui.
- Riset ini tidak mengubah CBL, wireframe, kode native, konfigurasi layanan, database atau deployment. Tidak menjalankan build maupun tes integrasi.
