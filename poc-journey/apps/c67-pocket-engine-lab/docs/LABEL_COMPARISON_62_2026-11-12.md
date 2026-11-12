# Perbandingan 62 label lama dengan Pocket Engine

12 November 2026 WIB. Audit representasi dan pemetaan kode yang ada. Dokumen ini tidak mengubah engine atau menjalankan benchmark baru. Audit ini mencatat keadaan sebelum pemulihan kontrak. Lihat [hasil perubahan lanjutan](FOLLOWUP_2026-11-12.md) untuk dukungan setelah perubahan.

Daftar lama berasal dari `poc/c67-preference-lab/catalog/place-labels.json`. Pocket saat ini mempunyai 11 pilihan minat dan 8 facet kegiatan. Kategori tempat pada katalog tetap berupa string, sehingga kode penilaian dapat menerima kategori tambahan yang diberikan secara eksplisit. Dukungan lengkap memerlukan pemetaan dari sumber, penyimpanan, pilihan pengguna, aturan bukti, serta pengujian.

Jalur tersedia berarti representasi dan alur pemetaan dasarnya sudah ada. Sebagian/digabung berarti cakupannya menyempit atau maknanya belum setara. Belum dipetakan berarti belum didukung dalam alur standar pencarian/impor sampai pemilihan preferensi. Status ini tidak menyatakan ada bukti faktual yang cukup pada setiap tempat.

## 37 tipe tempat

| Label lama | Status Pocket | Penjelasan |
| --- | --- | --- |
| `cafe` | Jalur tersedia | Kategori `cafe` tersedia pada UI dan pemetaan sumber. Ketersediaan kategori tetap perlu dibedakan dari bukti syarat kegiatan. |
| `restaurant` | Jalur tersedia | Kategori `restaurant` tersedia pada UI dan pemetaan sumber. Ketersediaan kategori tetap perlu dibedakan dari bukti syarat kegiatan. |
| `bakery` | Sebagian / digabung | Adaptor Apple memasukkan bakery sebagai `cafe`. Importir OSM/Overture belum mempertahankan tipe bakery secara khusus. |
| `dessert_shop` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan kedai khusus dessert atau es krim. |
| `tea_house` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan kedai yang menjadikan teh sebagai sajian utama. |
| `food_court` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan area dengan beberapa gerai makanan dan tempat duduk bersama. |
| `street_food_area` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan sentra atau area yang menampung beberapa penjual jajanan kaki lima. |
| `park` | Jalur tersedia | Kategori `park` masuk ke minat UI `garden`. Identitas taman tetap memakai kategori sumber. |
| `botanical_garden` | Sebagian / digabung | Matcher minat garden mengenali ID ini bila ada dalam katalog. Belum ada pilihan UI dan pemetaan importir khusus yang mempertahankan pembedaan kebun botani. |
| `urban_forest` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan hutan kota yang memiliki area yang bisa dikunjungi. |
| `public_square` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan plaza atau alun-alun yang terbuka bagi publik. |
| `waterfront_walk` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan jalur publik untuk berjalan kaki di tepi sungai, danau, atau badan air. |
| `museum` | Jalur tersedia | Kategori `museum` tersedia pada UI dan pemetaan sumber. Ketersediaan kategori tetap perlu dibedakan dari bukti syarat kegiatan. |
| `art_gallery` | Jalur tersedia | Kategori `art_gallery` masuk ke minat UI `art`. Pemetaan tersedia dari OSM/Overture. |
| `cultural_center` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan pusat yang secara tetap menyelenggarakan kegiatan kebudayaan. |
| `heritage_site` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan situs yang dikenal dan dapat dikunjungi karena nilai sejarahnya. |
| `cinema` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan bioskop yang memutar film untuk penonton. |
| `performance_venue` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan tempat yang berfungsi sebagai lokasi pertunjukan seperti teater atau tari. |
| `live_music_venue` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan tempat yang rutin menyelenggarakan pertunjukan musik langsung. |
| `karaoke` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan tempat yang menyediakan layanan atau ruangan karaoke. |
| `library` | Jalur tersedia | Kategori `library` tersedia pada UI dan pemetaan sumber. Ketersediaan kategori tetap perlu dibedakan dari bukti syarat kegiatan. |
| `bookstore` | Jalur tersedia | Diganti ID menjadi `book_store`. Perlu pemetaan saat memakai kontrak lama. |
| `coworking_space` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan tempat yang menyediakan ruang kerja bersama sebagai layanan. |
| `creative_studio` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan studio yang menyediakan ruang atau peralatan untuk berkarya kreatif. |
| `workshop_venue` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan tempat yang rutin menyelenggarakan lokakarya. |
| `shopping_mall` | Jalur tersedia | Kategori `shopping_mall` tersedia pada UI dan pemetaan sumber. Ketersediaan kategori tetap perlu dibedakan dari bukti syarat kegiatan. |
| `traditional_market` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan pasar tradisional dengan beberapa pedagang atau kios. |
| `thrift_shop` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan toko yang fokus pada barang bekas atau barang vintage. |
| `record_store` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan toko yang fokus pada musik dalam format fisik, seperti piringan hitam. |
| `craft_shop` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan toko yang fokus pada produk kerajinan. |
| `sports_center` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan pusat yang menawarkan fasilitas olahraga sebagai fungsi utama. |
| `swimming_pool` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan tempat berenang yang menjadi tujuan kunjungan itu sendiri. |
| `climbing_gym` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan tempat dengan fasilitas khusus panjat atau bouldering. |
| `bowling_alley` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan arena yang menyediakan lintasan bowling. |
| `arcade` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan arena rekreasi yang menawarkan permainan arkade. |
| `playground` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan taman bermain yang menjadi tujuan utama kunjungan. |
| `cycling_track` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan lintasan yang memang disediakan untuk bersepeda. |

Rekap kategori ini — 8 jalur tersedia, 2 sebagian/digabung, 27 belum dipetakan.

## 12 subtipe

| Label lama | Status Pocket | Penjelasan |
| --- | --- | --- |
| `specialty_coffee` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan kopi spesialti merupakan fokus utama kafe. |
| `brunch_cafe` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan brunch merupakan fokus kafe atau alasan utama orang berkunjung. |
| `dessert_cafe` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan dessert merupakan fokus kafe atau alasan utama orang berkunjung. |
| `indonesian_cuisine` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan masakan Indonesia merupakan fokus restoran. |
| `japanese_cuisine` | Jalur tersedia | Menjadi minat UI tersendiri. Sumbernya tag cuisine OSM atau kategori/taksonomi Overture. Kueri Apple sendiri belum membuktikan masakan Jepang. |
| `korean_cuisine` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan masakan Korea merupakan fokus restoran. |
| `art_museum` | Sebagian / digabung | Dapat diimpor dari kategori Overture dan cocok untuk minat art/museum. UI belum menyediakan subtipe museum seni secara terpisah. |
| `history_museum` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan sejarah merupakan fokus utama museum. |
| `science_museum` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan sains atau teknologi merupakan fokus utama museum. |
| `used_books` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan buku bekas merupakan fokus utama toko buku. |
| `comics` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan komik merupakan fokus utama toko buku. |
| `childrens_books` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan buku anak merupakan fokus utama toko buku. |

Rekap kategori ini — 1 jalur tersedia, 1 sebagian/digabung, 10 belum dipetakan.

## 13 fitur

| Label lama | Status Pocket | Penjelasan |
| --- | --- | --- |
| `indoor` | Sebagian / digabung | Tidak mempunyai field indoor sendiri. Planner memakai outdoor=contradicted untuk paparan kegiatan indoor. Tempat dengan area indoor sekaligus outdoor belum termodelkan setara dengan dua label independen. |
| `outdoor` | Jalur tersedia | Facet `outdoor` dapat dipilih Bebas/Disukai/Wajib/Hindari. Definisi UI berfokus pada kegiatan di luar ruang. Label lama menyatakan area pengunjung outdoor, sehingga konteks kutipan tetap perlu diperiksa. |
| `semi_outdoor` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan ada area pengunjung beratap dengan sisi terbuka. |
| `rooftop` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan pengunjung bisa menggunakan area di atap bangunan. |
| `garden_seating` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan ada tempat duduk pengunjung di kebun atau taman tempat ini. |
| `nature` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan kebun, pepohonan, atau pemandangan alam merupakan bagian utama pengalaman. |
| `heritage` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan sejarah atau warisan budaya menjadi daya tarik tempat ini. |
| `architecture` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan desain bangunan atau arsitektur merupakan daya tarik tempat ini. |
| `city_view` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan tempat menawarkan pemandangan kota sebagai daya tarik. |
| `public_art` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan karya seni yang bisa dilihat publik merupakan daya tarik di tempat ini. |
| `local_cuisine` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan hidangan khas daerah setempat merupakan daya tarik utama. |
| `walking_path` | Belum dipetakan | Belum ada pemetaan dan pilihan khusus yang mempertahankan makna label ini dalam alur standar Pocket. Definisi lama menyatakan ada jalur berjalan kaki yang disediakan bagi pengunjung. |
| `children_play_area` | Sebagian / digabung | Facet children menyatakan kegiatan untuk anak. Bukti kegiatan anak belum otomatis membuktikan tersedianya area bermain. |

Rekap kategori ini — 1 jalur tersedia, 2 sebagian/digabung, 10 belum dipetakan.

## Rekap

| Status | Jumlah dari 62 |
| --- | --- |
| Jalur tersedia | 10 |
| Sebagian / digabung | 5 |
| Belum dipetakan | 47 |

Pengurangan cakupan ini terjadi pada implementasi PoC Pocket. Perbandingan kualitas dengan sistem lama perlu menyamakan kontrak label dan bukti terlebih dahulu. Mengganti sumber data dapat tetap memakai taksonomi 62 label yang sama. Daftar label itu dapat dipakai kembali dengan data independen baru.

## Tambahan dan pengelompokan Pocket

- `sushi` menjadi minat khusus di bawah cakupan makanan Jepang.
- `animal` menggabungkan kategori sumber zoo dan aquarium. Kedua kategori ini tidak terdapat dalam 62 label lama.
- `art` mengelompokkan art_gallery dan art_museum. `garden` mengelompokkan taman dan kebun. Pengelompokan ini memerlukan pemeliharaan subtipe agar pembedaan lama tetap tersedia.
- Facet publicAccess, reading, coffee, quiet, wheelchair, dan noMembership menambah syarat operasional/kegiatan yang tidak berdiri sebagai label tersendiri dalam daftar 62.
- Facet children perlu dibedakan dari label fasilitas children_play_area.

## Lokasi pemrosesan sumber terbuka

Pengambilan dan penyiapan ekstrak OSM/Overture berlangsung di komputer pengelola atau server. `Scripts/import-open-data.py` mengubah data menjadi katalog independen. Server Python/SQLite menyimpan dan mendistribusikan katalog, menerima impor bukti ditinjau, serta memeriksa masa berlaku per field.

Aplikasi mengunduh katalog melalui `GET /v1/catalog` dan menyimpannya dengan SwiftData. Penyaringan area, pemadanan kandidat, perankingan preferensi, serta penyusunan urutan itinerary dijalankan di iPhone. Permintaan Apple Maps untuk pencarian dan ETA tetap menuju layanan Apple.

Benchmark Simulator terakhir menyalin file katalog terbekukan berisi 14.832 identitas langsung ke sandbox aplikasi. Pengujian itu menjalankan penggabungan dan penilaian lokal dengan data yang sudah disiapkan. Sinkronisasi server produksi dan pembaruan akuisisi sumber secara otomatis belum dibuktikan oleh run tersebut.

## Pekerjaan berikutnya yang dicatat

1. Bandingkan luna-provider.example dengan Foundation Models pada tugas yang sama. Saat ini Foundation Models hanya memilih alasan rekomendasi, sedangkan planner Pocket memakai solver Swift. Perbandingan pemilihan jam kunjungan memerlukan adaptor tugas yang setara untuk kedua model. Bekukan kandidat, bukti sumber, batas perjalanan, format output dan validator deterministik yang sama. Catat model aktual dari provider, kualitas saran, pelanggaran syarat, kepatuhan format, latensi, dan pemakaian resource. Dugaan bahwa luna-provider.example lebih pintar menjadi hipotesis pengujian.
2. Implementasikan pengukuran waktu pada pekerjaan berikutnya sesuai arahan pengguna. Catat waktu sampai jadwal pertama, waktu pencarian selesai, setiap panggilan ETA beserta retry/cache, total waktu menunggu layanan, serta pemuatan garis rute. Ukur durasi end-to-end secara langsung agar panggilan paralel tidak terhitung ganda.

Rujukan kode — [taksonomi lama](../../c67-preference-lab/catalog/place-labels.json), [minat dan matcher](../Sources/PocketEngine/Discovery.swift), [facet dan aturan penilaian](../Sources/PocketEngine/Domain.swift), [adaptor Apple](../App/Sources/AppleServices.swift), [importir sumber terbuka](../Scripts/import-open-data.py).
