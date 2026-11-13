# Riset WeatherKit untuk pengalaman traveler dan rundown kreator

**Status konteks — 29 Oktober 2026:** Temuan/sumber bertanggal dipertahankan. Sintesis produk berbasis kreator di bawah adalah konteks saat riset dibuat; integrasi target kini mendukung rekomendasi AI dan waktu kunjungan personal. Capability/terms tidak diperiksa ulang pada pembaruan ini. Lihat [acuan aktif](../technology/07-planning-integrations.md).

**Tanggal akses:** 21 Oktober 2026, Asia/Jakarta.  
**Status:** desk research kemampuan platform dan peluang produk; bahan untuk revisi wireframe.  
**Cakupan:** menemukan hubungan antara data cuaca, keputusan traveler, dan pelaksanaan rundown. Wireframe v1 dan kode aplikasi tidak diubah.  
**Bukti:** dokumentasi dan presentasi resmi Apple, WHO, National Park Service, serta dokumentasi produk komoot dan PhotoPills. [Register 36 halaman sumber primer](weatherkit-traveller-experience-sources-2026-10-21.csv). Banyak halaman berasal dari provider yang sama; jumlah halaman bukan jumlah bukti independen.

## 1. Kesimpulan yang paling berguna

Peluang terkuat adalah **memadankan kondisi pada waktu kunjungan dengan jenis pengalaman di setiap spot dan perpindahan**. Data tersebut dapat membantu pengguna memilih jam mulai, menyiapkan barang, menilai alternatif kegiatan, serta memahami perubahan rundown.

Empat arah layak diprioritaskan untuk eksplorasi desain:

1. **Pilihan jam mulai dengan dampak yang terbaca.** Bandingkan bagian perjalanan yang berpotensi terkena hujan, panas terasa, atau kehilangan kesempatan cahaya.
2. **Panduan persiapan dan perpindahan per segmen.** Kaitkan prakiraan dengan durasi berjalan dan bagian yang terbuka, termasuk perjalanan menuju landing point.
3. **Penyesuaian rundown dengan alasan.** Tawarkan pertukaran kegiatan atau alternatif yang tetap memenuhi jam buka, durasi, dan kegiatan prioritas.
4. **Menjaga kesempatan pengalaman tertentu.** Contohnya tiba sebelum sunset atau meninjau kembali kunjungan ke viewpoint ketika jarak pandang rendah.

Ini **rekomendasi riset untuk diuji**, bukan daftar fitur yang sudah diputuskan, algoritme selesai, atau bukti manfaat pada pengguna aplikasi kita. Data mentah yang tersedia tidak otomatis menghasilkan keputusan perjalanan.

## 2. Dasar produk dan pertanyaan riset

### Given — dari pengguna

- Rundown dibuat kreator berdasarkan pengalaman; jam di template adalah rekomendasi terbaik.
- Pengguna dapat memulai pada waktu berbeda. Kondisi cuaca diharapkan membantu persiapan, pemilihan moda, dan perubahan dinamis perjalanan.
- Dalam best-case Athar: berada di Agora → mencari Kota Tua melalui search/peta → memilih rundown → mengetahui landing point dan informasi perjalanan → mengikuti spot secara berurutan → foto tiap spot → album → berbagi opsional.
- Foto per spot merupakan bagian wajib dalam skenario tersebut; tidak berarti mengharuskan pengguna bertahan di lokasi saat muncul halangan cuaca.
- Penggabungan rundown tetap konteks produk, tetapi tidak sedang digambarkan dalam best-case Athar.

Sumber konteks adalah klarifikasi langsung pada percakapan ini dan [CBL.md](../../../source-records/CBL.md). Bagian CBL yang masih menyebut sumber cuaca belum dipilih belum mencatat klarifikasi WeatherKit terbaru; riset ini tidak mengubah CBL atau menetapkan detail otomatisasinya.

### Pertanyaan yang ditelusuri

| Pertanyaan | Jawaban ringkas | Status bukti |
|---|---|---|
| Data apa yang tersedia dan pada granularitas apa? | Kondisi saat ini, prakiraan per jam/hari, presipitasi per menit bersyarat, solar/lunar events, alert bersyarat, statistik dan ringkasan historis. | Didukung dokumentasi; respons destinasi belum diuji. |
| Keputusan apa yang mungkin terbantu? | Jam mulai, perlengkapan, perpindahan, prioritas spot, kesempatan cahaya, dan alternatif kegiatan. | Interpretasi produk; perlu uji pengguna. |
| Apa yang masih harus diketahui di luar cuaca? | ETA, lama kunjungan, indoor/outdoor, jam buka, keterlindungan perpindahan, prioritas pengguna/kreator, dan alternatif yang valid. | Kebutuhan turunan; sumber dan beban input belum ditetapkan. |
| Apakah semua kemampuan berlaku di Kota Tua? | Belum terbukti. Presipitasi per menit dan alert memiliki batas wilayah. | Perlu pemeriksaan API pada koordinat target. |
| Apa nilai lebih dari membuka aplikasi Weather? | Menghubungkan prakiraan dengan rundown yang sedang dipilih/dijalankan. | Hipotesis nilai; bukan USP tervalidasi. |

## 3. Inventori data → peluang pengalaman

Kolom pengalaman adalah **usulan aplikasi kita**. Apple menyediakan data yang disebutkan, bukan rekomendasi atau perhitungan rute dalam kolom tersebut.

| Data / dataset | Yang disediakan | Peluang untuk traveler | Batas interpretasi utama |
|---|---|---|---|
| Peluang presipitasi per jam | precipitationChance, nilai 0–1. | Mengetahui spot atau perpindahan yang berpotensi bertepatan dengan hujan. | Peluang 80% tidak berarti hujan selama 80% waktu. [S04](https://developer.apple.com/documentation/weatherkit/hourweather/precipitationchance) |
| Jenis dan jumlah presipitasi | Jenis hujan/salju/dll.; precipitationAmount per jam berupa ekuivalen cair. | Persiapan perlengkapan dan evaluasi kegiatan outdoor berdasarkan konteks selain probabilitas. | Jumlah presipitasi tidak menyatakan genangan, kondisi jalan, atau pembatalan transportasi. [S05](https://developer.apple.com/documentation/weatherkit/hourweather/precipitationamount), [S03](https://developer.apple.com/documentation/weatherkit/hourweather) |
| Presipitasi per menit | Jenis, peluang, dan intensitas untuk prakiraan dekat. | Mempertimbangkan kapan melakukan perpindahan singkat atau menunggu di tempat yang sesuai. | Hanya jika tersedia; waktu mulai/berakhir tetap prakiraan. [S06](https://developer.apple.com/documentation/weatherkit/minuteweather) |
| Suhu dan suhu terasa | temperature dan apparentTemperature. | Menilai kenyamanan segmen berjalan; mempertimbangkan jam lebih sejuk atau jeda indoor. | Kenyamanan subjektif; bukan prediksi kelelahan, heatstroke, atau durasi aman individu. [S07](https://developer.apple.com/documentation/weatherkit/hourweather/apparenttemperature) |
| Kelembapan dan dew point | Konteks kelembapan udara. | Penjelasan tambahan untuk kondisi gerah/lembap bila relevan. | Jangan menjumlahkannya sembarang dengan suhu terasa menjadi skor kesehatan; dew point saja tidak memastikan kabut. [S03](https://developer.apple.com/documentation/weatherkit/hourweather) |
| UV Index | Nilai dan kategori paparan. | Pengingat perlindungan matahari pada kegiatan outdoor dan pilihan waktu kunjungan. | Nilai UV dan suhu menyampaikan hal berbeda. [S08](https://developer.apple.com/documentation/weatherkit/uvindex) |
| Angin dan gust | Kecepatan berkelanjutan, arah asal angin, gust opsional. | Meninjau kegiatan di area terbuka, viewpoint, tepi air, atau bersepeda bila konteks tersebut ada. | Tidak mengetahui apakah tempat terlindung atau moda tertentu beroperasi. [S10](https://developer.apple.com/documentation/weatherkit/wind) |
| Visibility | Estimasi jarak pandang. | Mengelola ekspektasi kunjungan skyline, panorama, atau landmark yang dilihat dari jauh. | Tidak menjamin objek spesifik terlihat; bukan indikator AQI. [S11](https://developer.apple.com/documentation/weatherkit/hourweather/visibility) |
| Cloud cover dan lapisan awan | Tutupan total dan, pada iOS 18+, awan rendah/menengah/tinggi. | Konteks cahaya, panorama, atau langit; informasi lebih rinci jika pengguna membutuhkannya. | Persentase awan tidak cukup untuk memastikan kualitas sunset/foto. [S13](https://developer.apple.com/documentation/weatherkit/cloudcoverbyaltitude), [S14](https://developer.apple.com/documentation/weatherkit/hourweather/cloudcoverbyaltitude) |
| Solar events dan daylight | Sunrise, sunset, civil/nautical/astronomical twilight, solar noon, isDaylight. | Mengatur kesempatan foto dan transisi siang–malam; menghitung kapan perlu tiba. | Rentang golden/blue hour dan arah cahaya membutuhkan perhitungan tambahan. [S12](https://developer.apple.com/documentation/weatherkit/sunevents) |
| Weather alerts | Sumber otoritas, ringkasan, tingkat severity, wilayah dan tautan detail. | Mengetahui bagian perjalanan yang perlu ditinjau atau ditunda. | Bersyarat wilayah/provider; tidak adanya alert tidak berarti kondisi aman. [S17](https://developer.apple.com/documentation/weatherkit/weatheralert) |
| Prakiraan harian dan day parts | Ringkasan hari, siang, malam, dan sisa hari; beberapa detail tersedia sejak iOS 18. | Ringkasan persiapan sebelum berangkat dan perbedaan kebutuhan siang–malam. | Gunakan data per jam untuk waktu kunjungan yang spesifik. [S15](https://developer.apple.com/documentation/weatherkit/dayweather), [S16](https://developer.apple.com/documentation/weatherkit/daypartforecast) |
| WeatherChanges | Arah perubahan suhu serta presipitasi siang/malam dibanding kondisi sebelumnya. | Menonjolkan perubahan relevan menjelang hari perjalanan. | Bukan webhook perubahan prakiraan atau notifikasi otomatis. [S21](https://developer.apple.com/documentation/weatherkit/weatherchanges), [S22](https://developer.apple.com/documentation/weatherkit/weatherchange) |
| HistoricalComparisons | Kondisi sekarang dibanding baseline historis, diurutkan menurut signifikansi penyimpangannya. | Menjelaskan bahwa hari perjalanan berbeda dari kondisi lazim. | Tidak meramalkan tanggal masa depan. [S23](https://developer.apple.com/documentation/weatherkit/historicalcomparisons) |
| Statistik bulan/hari/jam | Baseline statistik suhu dan presipitasi; rincian bergantung query. | Konteks musim dan persiapan untuk rencana yang masih jauh. | Statistik klimatologis bukan prakiraan tanggal tertentu. [S24](https://developer.apple.com/documentation/weatherkit/weatherservice/monthlystatistics(for:including:)), [S25](https://developer.apple.com/documentation/weatherkit/monthprecipitationstatistics), [S26](https://developer.apple.com/documentation/weatherkit/monthtemperaturestatistics) |
| Daily summaries historis | Ringkasan suhu dan presipitasi harian untuk lokasi dan interval. | Konteks tambahan album atau pengalaman kreator yang memiliki tanggal perjalanan. | Tidak membuktikan cuaca pada menit foto; data ini tidak menyediakan arsip lengkap semua field cuaca. [S27](https://developer.apple.com/documentation/weatherkit/weatherservice/dailysummary(for:fordaysin:including:)), [S28](https://developer.apple.com/documentation/weatherkit/dailyweathersummaryquery) |
| Lunar events | Moonrise, moonset, fase bulan. | Peluang opsional untuk rundown fotografi malam atau astronomi. | Prioritas rendah untuk city walk; bukan prakiraan aurora, pasang surut, atau polusi cahaya. [S30](https://developer.apple.com/documentation/weatherkit/moonevents) |
| Tekanan udara dan tren | pressure dan pressureTrend. | Detail bagi pengguna yang memahami meteorologi. | Tidak cukup untuk menyimpulkan sendiri badai akan terjadi; nilai langsung untuk best-case Athar tampak rendah. [S03](https://developer.apple.com/documentation/weatherkit/hourweather) |

**Sumber konteks UV:** WHO merekomendasikan perlindungan matahari mulai UV Index 3 dan menjelaskan bahwa paparan UV tetap dapat tinggi ketika berawan. Maka menilai kebutuhan perlindungan hanya dari suhu atau ikon awan akan menghilangkan informasi yang relevan. Ini panduan umum, bukan personalisasi medis. [S09](https://www.who.int/news-room/fact-sheets/detail/ultraviolet-radiation)

## 4. Peluang yang paling dapat meningkatkan pengalaman

Urutan berikut adalah prioritas desain sementara berdasarkan kedekatan dengan rundown dan best-case Athar. Belum ada pengukuran preferensi traveler atau perkiraan dampak kuantitatif.

### A. Memilih jam mulai sambil memahami konsekuensinya — prioritas utama

**Pertanyaan pengguna:** “Kalau saya mulai sekarang, bagian mana yang waktunya kurang cocok?”

Padankan prakiraan per jam dengan rentang berada di setiap spot dan perpindahan, lalu bandingkan beberapa jam mulai yang masih memenuhi batas rundown. Tampilkan alasan seperti “perpindahan kedua bertepatan dengan prakiraan hujan” atau “kedatangan melewati sunset”.

Tambahan yang diperlukan: lama kunjungan, ETA, jam buka, kegiatan prioritas, dan batas akhir perjalanan. Hasil sebaiknya menunjukkan tradeoff; klaim “jam paling optimal” memerlukan definisi tujuan dan validasi. Jangan menggabungkan peluang hujan antarjam dengan rumus independensi tanpa dasar.

### B. Persiapan yang mengikuti rencana sebenarnya — prioritas utama

**Pertanyaan pengguna:** “Apa yang perlu saya bawa untuk perjalanan ini?”

Ambil konteks keseluruhan waktu perjalanan: kebutuhan perlindungan matahari saat outdoor, perlengkapan hujan saat perpindahan, atau lapisan pakaian bila aktivitas berlanjut ke malam yang lebih dingin. Susun alasan yang terkait segmen, bukan daftar barang generik setiap hari.

Konteks pengguna seperti bepergian bersama anak, sensitivitas panas, atau kebutuhan mobilitas belum diteliti. Jangan menyimpulkannya dari profil atau menetapkan batas paparan individu.

### C. Menilai perpindahan dengan lebih baik — prioritas utama

**Pertanyaan pengguna:** “Bagian jalan kaki mana yang perlu saya pertimbangkan lagi?”

Kombinasikan suhu terasa, UV, hujan, dan angin dengan durasi berjalan serta keterlindungan jalur. Perjalanan Agora → landing point perlu ikut dinilai; dimulainya rundown di Kota Tua tidak menghapus perjalanan menuju titik tersebut.

WeatherKit tidak menyediakan pilihan moda, tarif, keterlindungan jalur, atau status operasional. Jalur yang menggunakan kereta juga dapat memiliki akses berjalan yang panjang. Perubahan moda memerlukan data rute dan preferensi pengguna; hujan saja tidak menentukan satu moda sebagai pilihan terbaik.

### D. Mengubah rundown sambil mempertahankan tujuan kreator — prioritas utama

**Pertanyaan pengguna:** “Masih bisa mendapatkan pengalaman yang saya pilih kalau cuaca berubah?”

Pertukaran spot outdoor dengan kegiatan indoor atau memilih alternatif kreator dapat menjadi respons yang masuk akal jika jam buka, durasi, perpindahan, dan spot prioritas tetap terpenuhi. Tampilkan bagian yang berubah beserta dampaknya terhadap waktu selesai.

Kondisi “berawan” tidak otomatis membuat kegiatan buruk; hujan juga tidak memberi alasan untuk mengarang tempat pengganti. Tingkat otomatisasi, persetujuan pengguna, dan sumber alternatif belum diputuskan. Saran dengan penjelasan merupakan kandidat awal untuk diuji, bukan aturan final.

### E. Menjaga kesempatan cahaya dan panorama — prioritas utama bila rundown memuatnya

**Pertanyaan pengguna:** “Apa yang perlu saya prioritaskan supaya kesempatan ini tidak lewat?”

Waktu sunset atau cahaya tertentu menjadi anchor; aplikasi bisa menghitung mundur dari target kedatangan menggunakan lama perpindahan dan buffer persiapan. Cloud cover dan visibility menambah konteks untuk ekspektasi, tanpa menjanjikan hasil foto.

Golden hour bukan properti langsung WeatherKit dan bukan selalu tepat satu jam sebelum sunset. Definisi fase cahaya perlu dipilih dan dihitung berdasarkan posisi matahari, tanggal, dan lokasi. Bangunan, horizon, arah pandang, dan medan juga perlu informasi lain. PhotoPills memberi referensi perencanaan fase cahaya berbasis tanggal/lokasi, sedangkan NPS menjelaskan bahwa cahaya berawan pun dapat berguna untuk jenis foto tertentu. [S35](https://www.photopills.com/articles/mastering-golden-hour-blue-hour-magic-hours-and-twilights), [S36](https://www.nps.gov/grca/planyourvisit/photography.htm)

### F. Memprioritaskan viewpoint berdasarkan jarak pandang — prioritas lanjutan

**Pertanyaan pengguna:** “Apakah waktu ini sesuai untuk menikmati pemandangannya?”

Visibility lebih relevan untuk panorama daripada kunjungan interior. Dengan informasi jenis pengalaman pada spot, aplikasi dapat menjelaskan keterbatasan pemandangan dan memperlihatkan waktu lain yang mungkin lebih sesuai. Tetap perlu lokasi objek, jarak dan arah pandang; visibility umum tidak memverifikasi pandangan dari bangunan tertentu.

### G. Persiapan musim untuk perjalanan yang masih jauh — prioritas lanjutan

**Pertanyaan pengguna:** “Bagaimana biasanya kondisi pada bulan saya bepergian?”

Statistik bulanan dapat mendukung catatan musim pada rundown kreator dan persiapan awal. Ketika tanggal masuk jangkauan forecast, tampilkan prakiraan untuk tanggal tersebut secara terpisah. HistoricalComparisons dapat memberi konteks saat kondisi sekarang berbeda dari pola lazim.

Perbandingan sumber mendukung kelayakan teknis arah ini: [statistik bulanan](https://developer.apple.com/documentation/weatherkit/weatherservice/monthlystatistics(for:including:)) dan [historical comparisons](https://developer.apple.com/documentation/weatherkit/historicalcomparisons). Kesukaan pengguna terhadap informasi musim belum diuji.

### H. Memberi konteks pada album dan konten kreator — opsional

Tanggal perjalanan kreator dapat membantu pembaca memahami bahwa rekomendasi berasal dari musim atau kondisi tertentu. Untuk album pengguna, ringkasan cuaca area pada hari perjalanan dapat menjadi detail opsional.

Pisahkan “prakiraan yang ditampilkan saat perjalanan” dari “ringkasan cuaca harian yang diperoleh kemudian”. Hujan yang tercatat pada satu hari di area tersebut tidak membuktikan bahwa foto diambil ketika hujan. Jangan membuat narasi pengalaman pengguna secara otomatis berdasarkan cuaca saja. [S27](https://developer.apple.com/documentation/weatherkit/weatherservice/dailysummary(for:fordaysin:including:)), [S29](https://developer.apple.com/documentation/weatherkit/dayprecipitationsummary)

## 5. Menghubungkan waktu fleksibel dengan template kreator

Model berikut adalah usulan untuk eksplorasi:

| Jenis informasi | Contoh | Cara memperlakukannya |
|---|---|---|
| Jam rekomendasi | Kreator menyarankan mulai pukul 09.00. | Titik acuan; dapat berbeda dari jam pengguna. |
| Durasi | Menetap 45 menit, lalu berpindah. | Menjadi dasar menghitung rentang waktu; variasinya perlu diuji. |
| Batas yang harus dipenuhi | Jam operasional atau reservasi yang diketahui. | Penyesuaian tidak boleh mengabaikannya. |
| Kesempatan berbatas waktu | Sunset, pertunjukan, atau momen cahaya. | Tinjau apakah masih dapat dicapai dari jam mulai pengguna. |
| Kondisi yang memengaruhi pengalaman | Outdoor, panorama jauh, atau sensitif hujan. | Hubungkan dengan data cuaca yang relevan. |
| Alternatif | Kegiatan indoor pilihan kreator. | Gunakan hanya jika alternatif ada dan sesuai, bukan asumsi otomatis. |

Untuk setiap kandidat jadwal, periksa tiga jenis interval: **menuju landing point, berada di spot, dan berpindah antarspot**. Gunakan waktu lokal destinasi dan bedakan jam mulai perjalanan dari jam tiba di spot pertama.

Penggeseran jadwal tidak cukup dengan menambah offset ke semua jam. Perubahan harus meninjau kembali batas kegiatan, kesempatan cahaya, prakiraan pada waktu baru, serta dampaknya terhadap kegiatan setelahnya. Bagian yang sudah dijalankan tetap menjadi catatan aktual.

Sinyal baru tidak selalu memerlukan perubahan. Penilaian perlu mempertimbangkan kegiatan yang terdampak, besarnya perubahan, kebaruan data, dan preferensi pengguna. Aturan ini perlu diuji; hindari jadwal yang terus berubah pada setiap pembaruan kecil.

## 6. Horizon, wilayah, dan ketidakpastian

### Horizon yang sesuai dengan keputusan

| Waktu keputusan | Data yang dapat dipertimbangkan | Janji yang perlu dibatasi |
|---|---|---|
| Perjalanan masih di luar forecast | Statistik iklim untuk persiapan; perhitungan astronomi terpisah bila diperlukan. | Jangan menyebut rata-rata musim sebagai prakiraan pada tanggal pilihan. |
| Dalam jangkauan forecast | Prakiraan per jam/hari, dipadankan dengan tanggal dan ETA. | Apple menyebut forecast per jam hingga 10 hari; tetap periksa rentang yang benar-benar diterima. |
| Perpindahan dalam waktu dekat | Per jam; presipitasi per menit untuk satu jam ke depan jika tersedia. | Jangan menjanjikan waktu hujan presisi bila dataset menit tidak tersedia. |
| Sedang berjalan | Kondisi sekarang, forecast mendatang, dan alert jika didukung. | Data cuaca bukan sensor keadaan di setiap pintu bangunan atau trotoar. |
| Setelah perjalanan | Data yang disimpan dengan provenance atau daily summaries historis. | Jangan mengubah prediksi lama menjadi klaim observasi aktual. |

[S01 — Cakupan forecast](https://developer.apple.com/weatherkit/), [S24 — Statistik jangka panjang](https://developer.apple.com/documentation/weatherkit/weatherservice/monthlystatistics(for:including:)), [S31 — Metadata](https://developer.apple.com/documentation/weatherkit/weathermetadata).

### Indonesia dan Jepang

Apple Support mencantumkan Jepang untuk next-hour precipitation serta severe weather information. Indonesia tidak tercantum dalam kedua daftar tersebut pada halaman yang diperiksa. Halaman itu menjelaskan **aplikasi Weather**, sehingga merupakan sinyal untuk perencanaan, bukan bukti hasil WeatherKit di koordinat Kota Tua. [S20](https://support.apple.com/en-us/105038)

Implikasi: pengalaman Kota Tua perlu tetap berguna dengan prakiraan per jam. Notifikasi seperti “hujan mulai dalam 12 menit” tidak boleh menjadi ketergantungan desain. Ketika implementasi dimulai, periksa **minuteAvailability** dan **alertAvailability** pada koordinat target, termasuk keadaan available, unsupported, temporarilyUnavailable, dan unknown. Belum ada query live pada riset ini. [S18](https://developer.apple.com/documentation/weatherkit/weatheravailability), [S19](https://developer.apple.com/documentation/weatherkit/weatheravailability/availabilitykind)

### Waktu data dan kepercayaan pengguna

Pisahkan waktu permintaan, waktu berlakunya forecast, dan waktu kedaluwarsa. **WeatherMetadata.date** adalah waktu permintaan data; **HourWeather.date** adalah awal jam yang dijelaskan; **expirationDate** menunjukkan kedaluwarsa. Label “diamati pukul ...” tidak tepat jika yang diketahui hanya waktu request. [S31](https://developer.apple.com/documentation/weatherkit/weathermetadata), [S03](https://developer.apple.com/documentation/weatherkit/hourweather)

Gunakan keterangan “diperkirakan”, “data belum tersedia”, dan “pembaruan terakhir diambil ...” sesuai lapisannya. Jangan membuat persentase “kecocokan rute” atau skor kualitas foto sebelum definisi, bobot, dan kalibrasinya diuji.

## 7. Kemampuan yang masih memerlukan data atau logika lain

- **Penyesuaian urutan dan moda:** perlu routing, jam buka, preferensi, durasi, dan metadata tempat.
- **Golden/blue hour presisi dan arah cahaya:** perlu model astronomi serta definisi fase; occlusion bangunan/medan membutuhkan data tambahan.
- **Ketersediaan tempat indoor atau jalur terlindung:** tidak disediakan oleh field cuaca.
- **Kondisi banjir jalan, genangan, permukaan licin, penutupan tempat dan gangguan transportasi:** tidak dapat ditetapkan dari jumlah hujan saja.
- **AQI, polen, pasang surut, aurora dan kejadian petir spesifik:** tidak ditemukan sebagai dataset tersendiri pada inventori API yang diperiksa. WeatherCondition yang menyebut haze/smoke/thunderstorms tidak menggantikan pengukuran atau dataset tersebut.
- **Notifikasi di background:** query WeatherKit bukan langganan push perubahan cuaca. Penjadwalan, izin, pembaruan data dan pengiriman perlu dirancang terpisah.
- **Keamanan atau kesehatan personal:** tidak ada dasar untuk menyatakan moda/jalur “aman” atau menghitung paparan aman individu dari fitur ini.

Dasar batas inventori: [WeatherKit](https://developer.apple.com/documentation/weatherkit), [WeatherChange](https://developer.apple.com/documentation/weatherkit/weatherchange), [SunEvents](https://developer.apple.com/documentation/weatherkit/sunevents), [WeatherAlert](https://developer.apple.com/documentation/weatherkit/weatheralert).

Untuk alert resmi, tampilkan sumber otoritas dan tautan detail; Apple mensyaratkan teks severe weather alert dipertahankan. Rekomendasi aplikasi perlu terlihat terpisah dari pesan otoritas. Sisakan atribusi Apple Weather dan tautan sumber pada rancangan. [S01 — Attribution](https://developer.apple.com/weatherkit/)

## 8. Referensi pengalaman yang sudah ada

**komoot** mendokumentasikan cuaca sepanjang rute, termasuk konteks panas, hujan, angin dan waktu gelap. Ini mendukung eksplorasi informasi cuaca pada segmen yang relevan, tetapi tidak membuktikan efektivitasnya untuk pengguna kita atau penggunaan WeatherKit oleh komoot. [S34](https://www.komoot.com/premium/weather)

**PhotoPills** menghubungkan lokasi, tanggal dan fase cahaya dalam perencanaan foto. Referensi ini membantu membedakan kesempatan astronomi dari kondisi langit pada hari pelaksanaan. [S35](https://www.photopills.com/articles/mastering-golden-hour-blue-hour-magic-hours-and-twilights)

Keduanya diperiksa melalui dokumentasi publik; tidak dilakukan pengujian native, registrasi, pembelian, atau studi usability. Cuaca pada rute dan perencanaan golden hour sudah muncul pada produk lain, sehingga keduanya tidak cukup menjadi bukti kebaruan aplikasi kita.

## 9. Handoff untuk revisi wireframe

Ini daftar implikasi rancangan, bukan perubahan layar yang sudah dilakukan.

| Konteks dalam flow | Informasi yang layak ditampilkan | Tindakan/hasil yang perlu dipahami |
|---|---|---|
| Search/peta → hasil Kota Tua | Kecocokan pengalaman dan ringkasan cuaca untuk waktu yang dipilih; tanpa kepastian palsu jika tanggal belum ditentukan. | Memilih rundown dengan alasan yang relevan. |
| Detail rundown | Rekomendasi asli kreator, durasi, kondisi yang memengaruhi pengalaman, dan kesempatan berbatas waktu. | Memahami mengapa urutan/jam disarankan. |
| Jam mulai fleksibel | Dampak beberapa jam mulai terhadap kegiatan dan perpindahan. | Memilih dengan tradeoff yang jelas. |
| Sebelum berangkat | Persiapan yang relevan dengan keseluruhan rentang perjalanan dan akses ke landing point. | Mengetahui hal yang perlu disiapkan. |
| Menuju/tiba/berada di spot | Ringkasan yang memengaruhi spot sekarang atau perpindahan berikutnya. | Tetap fokus pada pengalaman di lapangan. |
| Cuaca berubah | Alasan peninjauan, bagian yang terdampak, opsi perubahan, dan akibat waktunya. | Menilai perubahan tanpa kehilangan tujuan perjalanan. |
| Album | Konteks cuaca opsional dengan tanggal, lokasi area, dan jenis sumber yang jelas. | Menambah konteks tanpa mengarang cerita pengguna. |

Utamakan ringkasan yang membantu keputusan, dengan detail tersedia ketika dibuka. Sebagai contoh, “perpindahan berikutnya bertepatan dengan prakiraan hujan” lebih langsung terkait tugas daripada menaruh seluruh tabel meteorologi pada setiap spot.

Notifikasi sebaiknya ringkas dan bernilai pada waktunya, serta tidak berulang untuk kejadian yang sama, sesuai [S33 — Apple HIG Notifications](https://developer.apple.com/design/human-interface-guidelines/notifications). Warna/ikon cuaca perlu teks penjelas; saran perubahan perlu menyebut alasan dan dampaknya.

Hubungan foto wajib dengan halangan cuaca tetap pertanyaan produk: jangan merancang progres yang mendorong pengguna bertahan di spot berisiko demi menyelesaikan dokumentasi. Keadaan tersebut berada di luar best-case Athar dan belum ditentukan pada riset ini.

## 10. Bukti berikutnya yang perlu dikumpulkan

| Pertanyaan prioritas | Metode terkecil yang berguna | Bukti / sinyal yang dicari |
|---|---|---|
| Informasi mana yang benar-benar mengubah keputusan city traveler? | Wawancara berbasis perjalanan terakhir dan walkthrough tiga kondisi: hujan, panas/UV, serta target sunset. | Keputusan nyata, informasi yang dicari, dan alasan memilih/menolak perubahan. |
| Apakah ringkasan per segmen lebih mudah dipahami? | Bandingkan contoh rundown dengan ringkasan harian versus kondisi pada spot/perpindahan. | Pemahaman bagian terdampak, waktu yang diperlukan untuk memutuskan, dan salah tafsir probabilitas. |
| Apakah jam mulai fleksibel tetap menjaga maksud kreator? | Gunakan satu rundown konkret, dua jam mulai, satu anchor sunset dan satu jam buka. | Batas yang terlewat, tradeoff yang dipahami, serta kontrol yang diharapkan. |
| Data apa yang sanggup diisi kreator? | Amati penyusunan satu rundown dengan penandaan indoor/outdoor, prioritas dan alternatif. | Beban input dan konsistensi informasi; jangan mengasumsikan metadata lengkap tersedia. |
| Apa yang benar-benar tersedia di lokasi target? | Technical spike terpisah pada Kota Tua, landing point, dan satu lokasi pembanding di Jepang. | Availability, interval forecast, timestamp, field kosong, serta perilaku gagal. |
| Bagaimana respons pada prakiraan berubah? | Walkthrough pembaruan yang memengaruhi satu segmen, lalu pembaruan kecil yang tidak relevan. | Apakah pengguna memahami alasan, kehilangan konteks, atau merasa terlalu sering diinterupsi. |

Tim produk/riset menjadi calon pemilik studi pengguna; engineer iOS menjadi calon pemilik spike. Penugasan, jumlah peserta dan jadwal belum disepakati. Gunakan contoh ilustratif dengan label yang jelas; jangan mengajak peserta menghadapi cuaca berbahaya atau merekam lokasi pribadi yang tidak diperlukan.

**Kesiapan handoff:** cukup untuk memilih peluang yang akan dieksplorasi dalam wireframe. Ketersediaan data destinasi, aturan perubahan jadwal, manfaat yang dirasakan traveler, dan beban kreator masih memerlukan bukti. Fitur dasar WeatherKit didokumentasikan sejak iOS 16; sejumlah detail/statistik yang relevan sejak iOS 18. Kompilasi SDK dan integrasi proyek belum diperiksa pada pekerjaan riset ini.

## 11. Batas pekerjaan dan jejak sumber

- Menginspeksi dokumen primer secara langsung melalui web dan dokumentasi Apple yang diambil melalui Sosumi; tautan mengarah ke sumber asli.
- Tidak menguji respons WeatherKit terautentikasi, akurasi lapangan, konsumsi daya, background delivery, atau perilaku native produk referensi.
- Tidak ada wawancara atau uji traveler pada pekerjaan ini. Potensi manfaat dan prioritas merupakan hipotesis desain.
- Wireframe v1, CBL.md, dan kode Swift tidak diubah. Dokumen ini beserta register sumber merupakan hasil riset baru.
- Contoh kalimat/perubahan rute adalah ilustrasi, bukan prakiraan aktual Agora/Kota Tua.
- Rincian tiap sumber, observasi terdokumentasi dan batasnya tersedia dalam [register sumber](weatherkit-traveller-experience-sources-2026-10-21.csv).
