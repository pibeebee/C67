# Google Places context engine — setup dan penggunaan

Implementasi 7 November 2026. Engine berada di lab terpisah, menggunakan **Places API (New)** REST pada Mac. API key tidak masuk aplikasi iPhone, bundle, query URL, hasil JSON, atau log. Belum ada panggilan Google live pada verifikasi awal karena key belum diisi.

## 1. Mendapatkan API key

1. Buka [Google Cloud Console](https://console.cloud.google.com/), pilih/buat project khusus PoC dan hubungkan billing.
2. Pada **APIs & Services → Library**, aktifkan **Places API (New)** (`places.googleapis.com`). Tidak perlu mengaktifkan Maps SDK for iOS atau Routes API untuk engine ini.
3. Buka **Google Maps Platform → Keys & Credentials** atau **APIs & Services → Credentials**, pilih **Create credentials → API key**.
4. Pada **API restrictions**, batasi key ke **Places API (New)**. Untuk REST dari Mac/server, gunakan **IP addresses** pada Application restrictions dengan IP publik keluar yang dilihat Google; bukan IP Wi-Fi lokal atau pembatasan bundle iOS. Perubahan jaringan/VPN/IP memerlukan penyesuaian.
5. Atur quota pengujian pada project. Engine juga membatasi panggilan per proses, tetapi batas ini bukan batas tagihan seluruh project.

[Panduan resmi key dan aktivasi](https://developers.google.com/maps/documentation/places/web-service/get-api-key), [panduan pembatasan key](https://developers.google.com/maps/api-security-best-practices).

## 2. Tempat mengisi key

File privat sudah disiapkan, permission `600`, diabaikan Git. Nilai Apple yang sudah ada dipertahankan:

```text
<original-workspace>/poc/c67-local-server-lab/.env.local
```

Isi baris ini secara lokal; jangan mengirim nilai key ke chat:

```dotenv
GOOGLE_PLACES_API_KEY=ISI_API_KEY_ANDA
GOOGLE_PLACES_MAX_REQUESTS=20
```

Wrapper membaca hanya dua variabel Google tersebut, tanpa mengeksekusi isi file sebagai shell. Variabel shell yang sudah terisi memiliki prioritas; nilai shell kosong tidak menutupi key dalam file. `MAX_REQUESTS` menghitung semua percobaan, termasuk yang gagal, dan reset saat proses baru dimulai. Server memakai satu client/counter sepanjang proses. Respons 401/403/429/5xx tidak diulang otomatis.

## 3. Coba engine

Jalankan dari folder `poc/c67-local-server-lab`:

```sh
python3 scripts/places-context.py status
python3 scripts/places-context.py demo
```

`status` tidak menghubungi Google; sesudah key diisi, `configured` menjadi `true`. `demo` selalu sintetis: HTTP mock berbentuk respons Google → normalisasi → penilaian slot → pencarian urutan dengan travel sintetis 15 menit. Tidak memerlukan key dan tidak membuktikan mutu rekomendasi tempat nyata.

Untuk panggilan live pertama:

```sh
python3 scripts/places-context.py search "Museum Nasional Jakarta"
```

Ini satu Text Search; maksimal lima kandidat, dengan batas wilayah Jakarta. Engine tidak memilih otomatis cabang/nama yang ambigu. Periksa identitas, alamat dan ID hasil sebelum details.

Salin [contoh request](../fixtures/google-context-request.example.json) ke `.local/my-place-context.json`. Ganti `placeID`, tanggal yang masih relevan, durasi dan preferensi; `identityConfirmed=true` menyatakan pemilihan identitas tersebut. Kemudian:

```sh
python3 scripts/places-context.py evaluate .local/my-place-context.json
```

Ini satu Place Details. Default `includeReviews=false`. Untuk eksperimen indikasi waktu dari ulasan, ubah `includeReviews=true` dan `request.seeksQuiet=true` secara eksplisit. Ulasan maksimal lima dan bukan sampel representatif seluruh pengunjung. Request jam operasional memakai field Enterprise; meminta reviews/outdoorSeating menaikkan tingkat field ke Enterprise + Atmosphere. Gunakan [daftar field/SKU resmi](https://developers.google.com/maps/documentation/places/web-service/place-details) untuk biaya yang berlaku; engine tidak memakai wildcard `*`.

Semua live response hanya diproses sementara; tidak disimpan ke catalogue, SQLite jobs, corpus embeddings atau training. Jangan mengalihkan stdout live ke arsip bersama. ID tempat boleh dipelihara secara terpisah sesuai ketentuan provider. Expiry internal 15 menit adalah penjagaan kesegaran, bukan klaim hak menyimpan konten Google.

## 4. Input dan output penilaian

- `availableStart`/`availableEnd`: menit sejak tengah malam WIB. Durasi 15–360 menit, kelipatan 15.
- `preferredTime`: rentang **mulai** kunjungan, bukan seluruh durasi. `required=true` menjadi batas wajib; `false` menjadi preferensi.
- `priorities`: urutan eksplisit `preferredTime`, `lowerRain`, `quiet`, `comfortableTemperature`. Komponen dibandingkan secara leksikografis; tidak ada bobot personal universal atau persentase akurasi.
- `exposure`: `unknown` default. `outdoorSeating` dari Google tidak otomatis menjadikan aktivitas outdoor. Klasifikasi membutuhkan `exposureEvidence`, misalnya pernyataan pengguna atau pengamatan area bersumber.
- `weather`: opsional, konteks dari adapter/caller dengan `source`, `fetchedAt`, `expiresAt`, `hours`. Tanggal berupa Unix seconds. Engine memeriksa cakupan seluruh kunjungan; ini tidak mengautentikasi klaim caller sebagai WeatherKit. Endpoint Google tidak mengambil forecast otomatis.
- Quietness: ekstraksi aturan konservatif id/en dari klausa dengan konteks waktu eksplisit; menangani beberapa negasi, konflik, kedaluwarsa dan hari kerja/akhir pekan. Tidak menyimpulkan waktu dari publishTime, visitDate atau rating. Umur maksimum hint 180 hari adalah kebijakan eksperimen, bukan jaminan kesegaran pengalaman.
- Band aplikasi pagi 06–11, sore 15–18, malam 18–22 adalah interpretasi kata, bukan pengukuran keramaian per jam. Tidak ada endpoint popular-times atau klaim jam terbaik universal.

Status mencakup `needs_identity_confirmation`, `needs_hours`, `closed`, `no_feasible_visit_window`, `operating_hours_options`, `context_options`, `options_with_unknowns`. Semua opsi menjaga full-stay dalam satu sesi; jeda, overnight, current exceptions, timezone dan snapshot kedaluwarsa diperiksa. Regular hours di luar cakupan current hours tetap diberi peringatan pengecualian tanggal belum dikonfirmasi. Last-entry, reservasi dan kapasitas belum dilengkapi Google secara universal; kandidat tetap bersyarat.

Attribution Google, provider, author ulasan dan tautan asal ikut hasil. Tidak ada UI baru pada tahap ini; consumer wajib menampilkan attribution yang berlaku dan tidak menganggap data display sebagai izin penyimpanan permanen.

## 5. Engine urutan dan batas integrasi

Library `PlaceContextEngine` menyediakan `ContextItineraryPlanner.plan`. Ia menerima snapshot tempat, preferensi per aktivitas, forecast opsional, dan adapter `ContextTravelProvider`. Planner menjalankan bounded beam search atas **urutan dan slot**; semua stop, durasi, deadline dan return dipertahankan. Ada batas beam dan travel calls; cutoff atau ETA unavailable tidak disebut bukti global infeasible. Travel harus membawa departure persis sama, durasi nonnegatif dan provenance; tidak ada penggantian unknown menjadi nol.

Adapter travel memakai ID milik aplikasi, tanpa import MapKit atau meneruskan koordinat Google ke MapKit. Adapter Apple/identitas lintas-provider belum dipasang ke planner baru. Demo memakai travel sintetis. D/E, katalog, UI dan storage aplikasi acuan tidak diganti; library baru belum menjadi default aplikasi produksi.

Hasil memisahkan `travelSeconds`, `waitingSeconds`, `dwellSeconds` dan `elapsedSeconds`. Preferensi waktu dapat menghasilkan waktu menunggu panjang; angka ini tidak disembunyikan sebagai keuntungan kualitas. Cuaca dinilai sepanjang aktivitas kunjungan, belum seluruh perpindahan/menunggu. Jika kandidat penghindar hujan harus menunggu, status menjadi `candidate_with_unknown_preferences` karena paparan saat menunggu belum diketahui.

## 6. API lokal

Endpoint pada `planner-server`, memakai token lab yang sama, response `Cache-Control: no-store`:

| Endpoint | Fungsi |
| --- | --- |
| `GET /v1/lab/place-context/capabilities` | Status key/counter; tidak menghubungi Google |
| `POST /v1/lab/place-context/search` | Body `{"query":"Museum Nasional Jakarta","limit":5}` |
| `POST /v1/lab/place-context/evaluate` | Body sesuai file contoh |

Panggilan live membutuhkan server `--mode rest` dan env Google. Mode replay menolak pemanggilan Google dengan 409; tanpa key, 503. Ini mencegah replay tiba-tiba menjadi panggilan berbayar. CLI Google dapat digunakan sendiri tanpa konfigurasi Apple; server REST yang lama tetap membutuhkan konfigurasi Apple-nya.

Untuk server, source file privat sebelum lifecycle helper agar variabel Google diteruskan ke child process. Token lab dihasilkan helper di `.local`, bukan API key Google. Tidak ada instance server yang dibiarkan berjalan oleh proses verifikasi.

## 7. Verifikasi dan asumsi penggunaan

**Update live 7 November:** satu Place Details Museum Nasional berhasil, termasuk jam dan lima ulasan; 16 skenario slot lokal diperiksa. [Hasil live dan batasnya](GOOGLE_PLACES_CONTEXT_LIVE_2026-11-07.md). Command `python3 scripts/places-context.py verify-live CONFIRMED_PLACE_ID` menjalankan satu request details dengan reviews lalu perbandingan lokal tanpa menyimpan teks ulasan.

Lihat [laporan verifikasi](GOOGLE_PLACES_CONTEXT_VERIFICATION_2026-11-07.md). Build, synthetic HTTP, aturan jadwal, perubahan preferensi dan regression diuji. Belum ada verifikasi credentials, cakupan/response Google Jakarta atau penilaian manusia; ini dilakukan setelah key tersedia.

User memilih penggunaan Google sebagai data pendukung keputusan. Implementasi mencatat asumsi tersebut, tidak menetapkan bahwa kasus Google → optimizer → hasil bersama MapKit telah disetujui Google. Batas penggunaan, attribution, penyimpanan dan derived content tetap perlu dinilai terhadap ketentuan akun yang berlaku. Tidak ada scraping UI, pemanenan ulasan massal, training, deployment atau integrasi MapKit baru pada tahap ini.
