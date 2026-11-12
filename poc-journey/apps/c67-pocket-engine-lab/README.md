# C67 Pocket Engine Lab

PoC terpisah untuk **engine preferensi dan itinerary di iPhone**, dengan server kecil untuk katalog bukti bersama dan proxy saran Luna Max. Bundle ID `giovanchristoffel.c67-pocket-engine-lab`; server default `127.0.0.1:8792`. Tidak memiliki dependency ke paket Context Lab, provider Google, OpenRouter, atau model embedding eksternal.

## Yang sudah diimplementasikan

- SwiftUI: tab Jelajah, Rencana, dan Pengaturan; tujuh tema Hi-Fi dengan multi-select, Next/Skip, refinements atas 62 label yang sama, serta minat terstruktur dan syarat Bebas/Disukai/Wajib/Hindari; detail sumber; pencarian lokal dengan Core Spotlight dan kata; pencarian Apple Maps; pemilihan titik awal melalui hasil peta, katalog independen, atau Core Location.
- Rekomendasi Swift di perangkat. Pencarian Apple per minat masuk ke penilaian yang sama dengan katalog independen. Pilihan wilayah Jakarta Selatan (OSM relation 5802438) atau Kemayoran (5802412) memakai polygon tersendiri; pilihan disimpan dan dipakai untuk pencarian serta filter, bukan hanya nama tampilan. Perluasan hingga sekitar 5 km dari batas meminta pilihan pengguna. Urutan mengupayakan tempat berbeda per minat yang terwakili, dengan deduplikasi nama/alias dan koordinat lintas sumber. Daftar rekomendasi muncul jika tersedia minimal tiga kandidat yang cocok dan lolos syarat. Pencarian nama di katalog tetap tersedia. Bukti kedaluwarsa dan konflik menjadi unknown. Kategori memberi skor minat. Syarat wajib membutuhkan bukti kegiatan. Syarat tanpa keanggotaan memiliki field sendiri dan memerlukan bukti eksplisit.
- Planner async lokal untuk satu hari WIB, mobil, maksimal enam tujuan. Mendukung jam berangkat tetap atau fleksibel, jam kunjungan yang diutamakan atau wajib, dan tujuan terakhir. Planner memakai ETA MapKit sesuai waktu tiap ruas dan memeriksa durasi, batas tunggu, serta perjalanan kembali jika dipilih. Pencarian terbatas pada 60 permintaan ETA dan 800 cabang secara default, dengan peringatan saat sebagian alternatif belum diperiksa. Target jumlah kunjungan terpisah dari tujuan wajib. Tujuan baru bersifat opsional, kecuali pengguna menjadikannya wajib. Jadwal di bawah target ditawarkan untuk disetujui. Waktu tunggu perlu izin pengguna. Batas awal makan malam dikonfirmasi sebelum jadwal dibuat.
  Dari jadwal yang memenuhi seluruh syarat wajib, solver mengutamakan jumlah tujuan, kedekatan dengan jam kunjungan yang diutamakan, lalu waktu selesai. Kesalahan ETA sementara yang dikenali dapat dicoba ulang sekali per ruas, dengan maksimal tiga retry per penyusunan.
- WeatherKit untuk kegiatan outdoor yang didukung bukti. Jika Hindari hujan diaktifkan, planner juga memeriksa batas jam prakiraan berikutnya dalam waktu tunggu yang diizinkan. Peluang hujan maksimal 50% selama seluruh kunjungan. Paparan unknown dan cakupan prakiraan yang kurang menahan tujuan. Angka ini adalah kebijakan PoC.
- Peta rencana dengan marker dan geometri jalan Apple yang dimuat atas permintaan. Kegagalan sebagian garis tidak mengganti jadwal dengan garis lurus atau ETA buatan.
- Foundation Models opsional, berjalan di perangkat: memilih maksimum tiga ID alasan dari deskripsi terstruktur dalam bahasa Inggris. UI menampilkan alasan Indonesia yang sudah dibuat engine; model tidak membuat fakta atau mengubah kelayakan. Tidak memerlukan PCC, entitlement PCC, model unduhan khusus, atau API key LLM.
- SwiftData untuk profil, pilihan, konteks waktu, konfirmasi pribadi, dan katalog independen. Token baca server disimpan di Keychain. Titik awal sesi, hasil pencarian Apple/TomTom, ETA, dan geometri tidak disimpan sebagai cache fakta.
- Server Python standard library + SQLite: katalog bersama, impor bukti independen yang **sudah ditinjau**, cache per field maksimal 30 hari, transaksi impor atomik, serta adaptor pembanding TomTom Places Search v3 opsional. Server tidak menerima profil, tidak meranking tempat, dan tidak menyusun itinerary.

## Katalog awal dan informasi yang belum tersedia

Resource `Sources/PocketEngine/Resources/catalog.json` menyalin **30 identitas** dari snapshot pilot sumber terbuka yang sudah ada. Nama, koordinat, ID sumber, kategori, alias, URL sumber, dan operator dipertahankan. **Tidak ada jam, akses, atau karakter tempat baru yang diklaim terverifikasi.** Ini tidak menyalin cache/provider credentials ataupun kode dari PoC sebelumnya.

Jika jam atau akses belum lengkap, pengguna dapat memberikan interval kunjungan dan konfirmasi akses **untuk tanggal perjalanan tersebut saja** pada tab Rencana. Ini ditandai sebagai informasi pribadi, bukan bukti publik. Konfirmasi tidak memenuhi syarat lain, seperti membaca atau akses kursi roda. Konfirmasi tanggal lain tidak berlaku.

Katalog dari server hanya memuat identitas independen dan fakta yang telah diimpor dengan persetujuan peninjau. Tidak ada crawling yang otomatis berjalan. Pekerjaan akuisisi/pengayaan di chat lain dapat memasok kontrak [Server/CONTRACT.md](Server/CONTRACT.md). Server memeriksa bentuk data, sumber yang dikenal, nama cabang, dan masa berlaku; ia **tidak** membuktikan isi kutipan dengan mengunjungi ulang situs. Peninjau bertanggung jawab memeriksa sumber sebelum impor.

## Build saja

Persyaratan: Xcode 26+ dengan SDK iOS 26+, Swift 6.2+, XcodeGen. Build yang tercatat memakai Xcode 27.2 / Swift 6.4.2 dan deployment target iOS 26.0. Tidak ada package eksternal yang perlu diunduh.

```sh
cd poc/c67-pocket-engine-lab
swift build --disable-sandbox
cd App
xcodegen generate
cd ..
xcodebuild -project App/C67PocketEngineLab.xcodeproj \
  -scheme C67PocketEngineLab -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .local/DerivedData CODE_SIGNING_ALLOWED=NO build
python3 -m py_compile Server/server.py
```

Rencana dan keputusan perilaku tersimpan di [rencana implementasi](docs/RECOMMENDATION_AND_ITINERARY_IMPLEMENTATION_PLAN.md). Pengujian saat ini dibatasi iPhone Simulator sesuai instruksi pengguna. [Laporan acceptance 12 November](docs/SIMULATOR_ACCEPTANCE_2026-11-12.md) memuat hasil live, replay, diagnosis perjalanan, dan hambatan data. [Laporan lanjutan 12 November](docs/FOLLOWUP_2026-11-12.md) memuat pemulihan label, pengaruh bukti, pengukuran routing, dan status percobaan model.

Lihat [docs/BUILD_STATUS.md](docs/BUILD_STATUS.md) untuk checkpoint build awal dan [laporan benchmark planner](docs/PLANNER_REVISION_2026-11-11.md) untuk pengujian revisi. Build tidak memasang atau membuka aplikasi.

## Konfigurasi untuk menjalankan nanti

Bagian ini petunjuk penggunaan, **belum dijalankan** dalam implementasi awal.

1. Buka `App/C67PocketEngineLab.xcodeproj`, pilih scheme `C67PocketEngineLab`. Untuk perangkat fisik, pilih team sendiri dan pastikan kemampuan Maps/WeatherKit serta provisioning tersedia. Simulator tidak membuktikan entitlement perangkat.
2. Aplikasi sudah memiliki katalog identitas bawaan. Mesin lokal dapat dipakai tanpa server katalog; pencarian Apple, ETA dan cuaca tetap memerlukan koneksi ke layanan Apple. Saran jadwal Luna aktif secara default dan memerlukan server serta koneksi provider. Pengguna dapat menonaktifkannya secara eksplisit untuk memakai planner Swift. Penjelasan AI Apple opsional bergantung pada Apple Intelligence.
3. Untuk server, salin `Server/.env.example` menjadi `Server/.env`. Isi `POCKET_READ_TOKEN` dan `POCKET_WRITE_TOKEN` dengan dua nilai acak berbeda, minimal 24 karakter. Contoh pembuatan satu nilai: `python3 -c 'import secrets; print(secrets.token_urlsafe(32))'`. Kredensial Luna dapat dirujuk secara eksplisit melalui POCKET_LLM_ENV_FILE; kunci provider tetap di server, bukan di app. Untuk salinan publik ini, set juga POCKET_LLM_BASE_URL ke base HTTPS provider (termasuk /v1) pada konfigurasi privat.
4. Jalankan `python3 Server/server.py` saat sudah siap. Default hanya loopback. iPhone fisik membutuhkan alamat LAN Mac dan `POCKET_HOST` yang sesuai, atau reverse proxy HTTPS untuk server yang di-host. HTTP hanya diizinkan aplikasi untuk localhost/private LAN; gunakan HTTPS untuk akses di luar LAN.

   Bila Python macOS tidak menemukan sertifikat CA, atur `SSL_CERT_FILE=/etc/ssl/cert.pem` pada `.env`; validasi TLS tetap aktif. Server mencatat waktu, metode, endpoint dan status HTTP tanpa token, kueri, isi request, atau respons provider. Redirect output server ke file privat jika log perlu disimpan.
5. Pada Pengaturan, isi URL dan **token baca**, simpan, kemudian pilih Unduh katalog terbaru. Token tulis tidak perlu dan tidak boleh dimasukkan ke aplikasi.
6. Opsional: isi `TOMTOM_API_KEY` di server untuk tab sumber TomTom. Setiap pencarian eksplisit mereservasi satu request, termasuk kegagalan, dibatasi 20/hari UTC secara default. Respons TomTom hanya sesi, tidak digabung menjadi bukti atau disimpan 30 hari. Tidak ada panggilan otomatis, fallback provider, atau pemeriksaan API key pada build.

## Struktur dan batas

| Folder | Tanggung jawab |
| --- | --- |
| `Sources/PocketEngine` | Kontrak data, kesegaran bukti, aturan rekomendasi, solver itinerary; paket tanpa dependency eksternal |
| `App/Sources` | SwiftUI, SwiftData, Keychain, MapKit, Core Location, Core Spotlight, WeatherKit, Foundation Models |
| `Server` | Distribusi katalog independen, impor bukti ditinjau, SQLite, proxy Luna Max, dan TomTom opsional |
| `.local` | Log build dan artefak build lokal; diabaikan Git |

Jam mingguan tidak membuktikan pengecualian hari libur, tiket, reservasi atau slot layanan. Jadwal memiliki keterbatasan ETA dan pencarian. Katalog dapat diperluas memakai `Scripts/import-open-data.py` dan `--import-identities` pada server. Jalur ini menambah identitas dan kategori sumber, sementara fakta syarat wajib tetap memerlukan pengayaan yang ditinjau. Cakupan katalog mengikuti ekstrak sumber yang dimuat. Ambang padanan cabang adalah nama/alias yang sama dan jarak maksimal 125 meter, tepat satu padanan; ambiguitas tidak digabung. Ambang ini belum divalidasi lapangan. Bukti pengujian harus dibaca bersama lingkup sumber, jenis fixture, runtime, dan versi kode yang dicatat per laporan.

Perubahan preferensi, pilihan, waktu, titik awal, atau katalog membatalkan rencana yang tampil. Setelah aplikasi dibuka ulang, pilihan dipulihkan tetapi titik awal dan rencana perlu dihitung kembali. Indeks Spotlight hanya pembantu pencarian; penilaian syarat selalu membaca katalog aktual.

Cache 30 hari berlaku pada fakta independen yang izin penggunaannya memungkinkan, bukan data Apple Maps atau TomTom secara umum. Waktu diperiksa tidak sama dengan tanggal perubahan nyata tempat. Lisensi OSM adalah ODbL; lisensi Overture mengikuti sumber per record. Pertahankan atribusi dan periksa izin penggunaan data sebelum menambah sumber.

Rujukan: [MapKit](https://developer.apple.com/documentation/mapkit), [Core Spotlight](https://developer.apple.com/documentation/corespotlight/building-a-search-interface-for-your-app), [Foundation Models](https://developer.apple.com/documentation/foundationmodels), [WeatherKit](https://developer.apple.com/documentation/weatherkit), [TomTom Discover v3](https://docs.tomtom.com/places-search-api/documentation/places-search/discover).

Penyambungan Hi-Fi, wilayah pilihan, dan saran Luna: [laporan implementasi 12 November 2026](docs/HIFI_LUNA_IMPLEMENTATION_2026-11-12.md).
