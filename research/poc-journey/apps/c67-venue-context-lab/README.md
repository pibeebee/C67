# C67 Venue Context Lab

Context Lab v2 untuk rekomendasi tempat dan itinerary Jakarta. Folder ini memiliki paket Swift, aplikasi simulator, konfigurasi, port 8788, dan penyimpanan lokal sendiri.

## Alur

- Pencarian tempat interaktif dan konfirmasi pin memakai Apple Maps Server API. Aplikasi memakai MapKit untuk peta hasil dan garis rute. ETA backend memakai Apple Maps Server API dan penilaian cuaca memakai WeatherKit.
- Untuk rekomendasi, kandidat Apple dipadankan ke katalog independen dengan nama atau alias yang sama dan jarak maksimal 125 meter. Kandidat OSM/Overture yang sesuai area dan kategori melengkapi hasil. Lokasi yang hanya ditemukan di Apple tetap bisa dipakai sebagai titik awal. Kandidat tujuan memerlukan bukti independen sebelum bisa dijadwalkan.
- Saat data cabang diperlukan, server mengembalikan fakta yang tersedia dan mengantrekan fakta yang sudah berumur 30 hari atau belum pernah dicek. Pekerjaan latar belakang memakai Playwright untuk membaca maksimal lima halaman resmi per pekerjaan, dimulai dari URL katalog lalu mengikuti tautan cabang, lokasi, kontak, dan fasilitas yang relevan, atau Firecrawl untuk satu pencarian dan maksimal dua scrape. `luna-provider.example` membaca kutipan cabang dan mengusulkan fakta jam, akses, serta aktivitas. Server memeriksa kutipan, nama dan petunjuk cabang sebelum menerima hasil.
- Fakta yang diterima dan hasil *belum ditemukan* kedaluwarsa 30 hari setelah pemeriksaan. Satu cabang memiliki paling banyak satu pencarian aktif. HTTP atau format yang gagal dicatat sebagai kegagalan teknis dengan jeda satu jam sebelum cabang dapat diantrekan lagi. Tanggal berlaku yang lebih pendek tetap dihormati oleh planner. Jadwal reguler belum mencakup pengecualian hari libur.
- Cache menyimpan fakta independen, kutipan, URL, tanggal pemeriksaan, halaman Firecrawl yang bisa dipakai kembali, dan buku besar reservasi kredit. Respons pencarian Apple digunakan sementara untuk memilih dan mengonfirmasi lokasi. Cache fakta dan prompt pengayaan menggunakan input katalog independen. Ambang dan hasil pilot adalah bagian eksperimen.
- E5 lokal dan peringkat rekomendasi OpenRouter dari Context Lab dipakai kembali. Pengayaan menggunakan model `luna-provider.example` secara terpisah. Itinerary tetap menyaring kunjungan yang belum punya jam segar atau bukti akses publik. Jalur eksperimen sunset yang bergantung pada identitas provider lama belum dibawa ke v2.

Katalog pilot membekukan 30 kandidat dari pilot sumber terbuka Jakarta Selatan. Kategori awal berfungsi untuk penemuan, dan tidak mewakili kelayakan akses. ID dan URL asal dicantumkan per kandidat. Untuk katalog alternatif, set `VENUE_CATALOG_PATH` ke JSON dengan skema yang sama. Data OpenStreetMap © kontributor OpenStreetMap (ODbL). Syarat Overture mengikuti sumber per rekaman. [Atribusi OSM](https://www.openstreetmap.org/copyright) · [Dokumentasi Overture Places](https://docs.overturemaps.org/guides/places/)

## Pengayaan dengan Playwright

Dari folder lab, jalankan `npm install --prefix Scripts` dan `npm exec --prefix Scripts -- playwright install chromium` jika Chromium yang sesuai belum tersedia. Atur `VENUE_WEB_PROVIDER=playwright`, `VENUE_ENRICHMENT_ENABLED=1`, dan kredensial `GIOVANC_API_KEY`. Mode ini memulai dari `operatorURLs` pada katalog dan menemukan tautan relevan dalam domain yang disetujui. Batas default lima halaman per cabang dapat diatur dengan `VENUE_PLAYWRIGHT_MAX_PAGES` (1–8). Gunakan halaman cabang atau direktori resmi agar nama, alamat dan fakta dapat dicek pada bagian yang sama. Status `webProvider`, `pagesRead`, `excerptsSelected` dan `extractions` tersedia dari GET `/v1/lab/evidence/status`. Dengan `VENUE_URL_DISCOVERY=none` (default), mode Playwright memakai nol kredit Firecrawl. Untuk penemuan URL lintas web, set `VENUE_URL_DISCOVERY=firecrawl` dan sediakan key Firecrawl: satu Search yang dibatasi domain resmi/rujukan pemerintah membantu memilih URL awal, lalu Playwright membaca halamannya. Hasil penemuan, termasuk hasil kosong, disimpan 30 hari per cabang dan memakai buku besar batas kredit yang sama. Mode opsional ini tidak dijalankan dalam uji Playwright 30 tempat.

Untuk membandingkan dua kolektor pada roster yang sama, gunakan folder `LAB_DATA_DIR` baru untuk setiap percobaan. Pemakaian sehari-hari menggunakan cache fakta yang sama selama 30 hari.

## Pengayaan dengan Firecrawl

Gunakan salinan privat `.env.local` dari `.env.example`. Simpan kunci provider di server. Aplikasi hanya memerlukan URL server lokal dan token lab pada `ContextHarness/RunConfig.json` yang dapat dibuat dari berkas contoh. Untuk Simulator gunakan loopback. Untuk perangkat fisik gunakan alamat lokal Mac dan atur `LAB_HOST` untuk menerima koneksi LAN. Pengaturan proyek memakai XcodeGen.

1. Periksa di dashboard Firecrawl bahwa pay-as-you-go nonaktif. Isi `FIRECRAWL_API_KEY` dan `GIOVANC_API_KEY` di konfigurasi server privat. Kutip nilai `GIOVANC_MODEL` jika konfigurasi dimuat lewat shell.
2. Verifikasi koneksi dengan `swift run venue-context-server check-firecrawl`. Perintah ini memanggil endpoint pembacaan saldo, tanpa Search, Scrape, atau ekstraksi. Lanjutkan setelah autentikasi dan respons saldo berhasil. [Endpoint pembacaan saldo](https://docs.firecrawl.dev/api-reference/endpoint/credit-usage)
3. Jalankan `swift test`. Setelah lulus, isi kredensial Apple Maps Server API, WeatherKit dan OpenRouter yang diperlukan Context Lab. Atur `VENUE_WEB_PROVIDER=firecrawl` dan `VENUE_ENRICHMENT_ENABLED=1`, pertahankan `VENUE_FIRECRAWL_CREDIT_CAP=150`, lalu jalankan `swift run venue-context-server` dari folder ini. Jika memakai `.env.local`, ekspor variabel yang diperlukan sebelum menjalankan perintah.
4. Ambil kondisi awal dengan GET `/v1/lab/evidence/pilot`. Kirim POST `/v1/lab/evidence/pilot` dengan token lab untuk mengantrekan maksimal 30 tempat. Pantau GET `/v1/lab/evidence/status`. Nilai `pending=0` menandakan antrean kosong. Periksa juga `suspended` dan `lastError` sebelum menafsirkan hasil.
5. Ambil hasil akhir dan audit kutipan per cabang. POST `/v1/lab/evidence/pilot/apple` memeriksa padanan Apple pada 30 kandidat yang sama. Hitung fakta yang benar-benar terverifikasi dan kandidat dengan padanan Apple, jam dan akses pada hari yang diuji. Ulangi enqueue pada cache segar dan periksa bahwa reservasi kredit tidak bertambah. Untuk uji aplikasi, jalankan `xcodegen generate` dari `ContextHarness`, buka skema `C67VenueContextLab`, lalu coba pencarian, konfirmasi pin, rekomendasi, dan itinerary dari sumber yang sudah diperiksa. Catat apakah tujuan yang bukti jam atau aksesnya kurang tertahan dengan status yang benar.

Batas 150 kredit disimpan lintas restart pada folder data yang sama. Server memeriksa saldo sebelum setiap pekerjaan dan mencatat reservasi sebelum setiap Search atau Scrape. Batas adalah perkiraan konservatif untuk operasi yang digunakan, dan dashboard Firecrawl tetap menjadi sumber tagihan aktual. Biaya `luna-provider.example` terpisah. [Tarif Firecrawl](https://www.firecrawl.dev/pricing)

## Diagnosis dan uji yang dapat diulang

GET `/v1/lab/evidence/diagnostics` (dengan token lab) mengembalikan laporan per cabang: URL yang ditemukan, setiap percobaan halaman beserta status dan durasi, jumlah halaman cache, percobaan ekstraksi, klaim model, dan alasan penerimaan/penolakan per field. Laporan dan halaman sumber disimpan pada `venue-evidence-v1.json`; kredensial tidak disimpan di dalamnya. Laporan terbaru per cabang tetap tersedia setelah server restart.

Pembaca mempertahankan JSON-LD, blok cabang pada DOM, artikel SSR Jakarta Smart City, dan objek respons JSON publik dari domain resmi yang dipakai situs. Jadwal schema.org hanya diterima setelah nama dan alamat cabang cocok. Jadwal bertanggal khusus, jam ambigu, serta periode yang bertumpuk ditahan. Teks dan kutipan tidak ditambahi nama hasil pencarian. HTML dinamis hanya diberi waktu tunggu terbatas; pembacaan halaman dan ekstraksi tidak menjamin fakta akan ditemukan.

Gangguan jaringan dan HTTP sementara dicoba ulang secara terbatas. HTTP 403/429 memberi jeda satu jam pada domain sumber, termasuk untuk cabang lain dan setelah restart, dengan halaman cache tetap boleh dipakai. Penemuan tautan generik pada situs rujukan dibatasi agar crawler tidak masuk ke direktori cabang yang tidak berkaitan. Ekstraksi memakai model luna-provider.example yang sama hingga tiga percobaan untuk gangguan sementara atau format tidak valid; tidak berganti model/provider. Batas waktu ekstraksi default 90 detik per percobaan dapat diatur dengan `GIOVANC_TIMEOUT_SECONDS` (15–180); potongan sumber identik tidak dikirim berulang. Bila tetap gagal, fakta yang belum berhasil tidak diubah menjadi hasil unknown selama 30 hari: cabang masuk jeda kegagalan teknis satu jam. Fakta yang sudah didapat dari metadata tetap tersimpan bila ekstraksi field lain gagal.

Dari folder lab:

```sh
swift test --disable-sandbox
node --test Scripts/collector.test.cjs
python3 Scripts/benchmark-enrichment.py --output .local/enrichment-pilot
```

Harness benchmark memakai roster pilot yang sama, port loopback sementara, dan folder data terpisah yang dipertahankan. Harness hanya mengambil konfigurasi Apple untuk inisialisasi server; tidak menjalankan pencarian Apple, rekomendasi, itinerary, Google Places, ataupun Firecrawl. Kredensial Google dan Firecrawl tidak diteruskan. `result.json`, `run-config.json`, `progress.json`, dan log server tersedia dalam folder hasil; konfigurasi hasil tidak memuat kunci API. `NODE_PATH` atau argumen `--node-path` dapat menunjuk instalasi Playwright 1.61.1 yang sudah ada.

Untuk menguji ulang parsing dengan halaman yang sama tanpa mengunjungi situs:

```sh
python3 Scripts/benchmark-enrichment.py --output .local/enrichment-replay --offline-source .local/enrichment-pilot
python3 Scripts/benchmark-enrichment.py --output .local/enrichment-replay --verify-cache
```

Replay mempertahankan URL halaman per cabang dari manifest hasil awal dan tidak memanggil browser atau Firecrawl; ekstraksi tetap memanggil model yang sama. Ini eksperimen terpisah: cache pemakaian normal tidak dihapus atau diperbarui sebelum 30 hari. `--verify-cache` menolak menjalankan pekerjaan baru bila ada cabang yang sudah layak diambil ulang; hasil pemeriksaan setelah restart disimpan terpisah pada `cache-verification.json`. Untuk mengulang ekstraksi yang gagal secara teknis dalam eksperimen replay, tambahkan `--retry-extraction-errors` bersama `--offline-source`; fakta yang telah tersimpan dipertahankan dan hasil percobaan tambahan masuk `retry-result.json`. Catat tambahan percobaan ini saat membandingkan hasil.

Ulang enqueue dengan hasil nol perlu dibaca bersama laporan: fakta segar menggunakan cache 30 hari, sedangkan kegagalan teknis bisa tertahan oleh jeda satu jam. Ini dua alasan yang berbeda. Membandingkan dengan hasil historis pada roster yang sama menunjukkan perubahan hasil, tetapi tidak mengisolasi pengaruh setiap perubahan karena halaman live dan respons model bisa berubah.
