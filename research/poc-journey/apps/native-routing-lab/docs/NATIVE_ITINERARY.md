# Perencana itinerary native — PoC C67

Fitur berada di layar **Rencana** dalam `poc-c67.xcodeproj`, tanpa tab tambahan. Eksperimen catatan perjalanan tetap tersedia melalui `--diary-demo` atau `--diary-ui-testing`. Fitur rombongan/lab lama tetap tersedia melalui launch argument `--legacy-poc`; argumen pengujian diary lama dipertahankan.

## Menjalankan

1. Buka proyek `poc-c67.xcodeproj`, scheme `poc-c67`, lalu jalankan melalui Xcode pada iPhone yang dipilih.
2. Layar **Rencana** dimulai kosong, memakai tanggal/jam dan zona waktu perangkat. Isi titik awal; aktifkan kembali ke awal atau isi titik akhir berbeda.
3. Tekan **Tambah tempat → Tempel daftar**, isi satu nama per baris, periksa pratinjau, lalu **Tambahkan**. Nomor dan bullet umum dibersihkan; nama/alamat dan kunjungan berulang dipertahankan. Maksimum 20 tujuan, tanpa memotong daftar diam-diam.
4. Alternatifnya, gunakan **Tambah tempat → Satu tempat** → ketik nama → **Simpan nama dulu**. Penambahan nama tidak membutuhkan jaringan. Tempat yang ditambahkan awalnya kunjungan dengan durasi default 30 menit dan paparan cuaca belum diketahui; keduanya bisa diubah di detail tujuan. Hapus tujuan melalui swipe pada barisnya.
5. Atur tanggal/jam berangkat di form; zona waktu, preferensi dan **Kota/negara pencarian** ada di **Pengaturan**. Konteks area ditambahkan ke pencarian nama pada bulk maupun detail, bukan diperlakukan sebagai koordinat. Tekan **Temukan lokasi** atau cari per tempat; hasil ambigu tetap dipilih pengguna. Titik awal/akhir dapat dicari atau disimpan namanya melalui form yang sama. Semua lokasi harus dipilih dari hasil MapKit atau pin manual sebelum perhitungan. Jam operasional dapat diisi manual di detail.

6. Tekan **Hitung itinerary**, lalu **Lihat itinerary**. Detail ruas menampilkan semua opsi yang diminta, status, ETA, waktu kunjungan, dan tombol **Periksa di Apple Maps**. Laporan dapat dibagikan sebagai teks.
7. Buka **Peta seluruh itinerary** untuk melihat jalur mobil/jalan kaki seluruh ruas kandidat, termasuk ruas pulang. Warna/nomor membedakan ruas, ikon/pola garis membedakan moda; pilih ruas untuk sorot dan zoom. Peta kandidat lain tersedia dari rincian kandidat. [Panduan dan batas peta](NATIVE_ROUTE_MAP.md).

Menu **Kelola rencana** (ikon tiga titik) menyediakan **Rencana baru** dan **Muat contoh Jepang**. Keduanya meminta konfirmasi sebelum mengganti input di layar. Contoh Jepang tetap berisi 15 tempat, 1 Desember 2026 pukul 07.00 JST, mulai/kembali Stasiun Funabashi; contoh ini tidak dimuat otomatis.

Tanpa titik/area referensi, pemilih pin dimulai dari tampilan dunia, bukan Tokyo. Ketuk area tujuan lalu geser/zoom dan konfirmasikan pin. Pemilihan manual diberi sumber tersendiri dan tidak menyatakan kecocokan nama telah diverifikasi MapKit.

Untuk membuka fitur ini tanpa bootstrap penyimpanan/lab lama, tambahkan launch argument **`--native-itinerary`** pada scheme Run. Ini tidak mengubah atau mereset data lama. Draf dan hasil belum dipulihkan otomatis setelah proses aplikasi ditutup. Snapshot input/hasil dicatat pada log lokal untuk debugging; tidak disinkronkan ke CloudKit atau backend aplikasi.

## Data dan algoritme

- **MapKit langsung:** pencarian lokasi dan `MKDirections.calculateETA()` untuk jalan kaki/transit serta mobil jika diaktifkan. Peta menggunakan `MKDirections.calculate()` terpisah untuk geometri mobil/jalan kaki kandidat terpilih. Tidak menggunakan Google Maps, OpenRouter, model AI, atau server aplikasi.
- **Cuaca:** WeatherKit menjadi sumber utama. Jika atribusi/request gagal, prakiraan kosong, atau tanggal di luar horizon WeatherKit, sistem mencoba Open-Meteo per area. Sumber data dan penyebab fallback terlihat pada hasil/log. Tidak ada API key baru untuk PoC.
- **Core Location:** tipe koordinat dan perhitungan kedekatan. Fitur baru tidak meminta GPS atau izin lokasi; pengguna memilih titik secara eksplisit.
- Pada pilihan Baseline, kandidat dibentuk dari kedekatan geografis dan perbaikan urutan terbatas, termasuk arah kebalikannya. Kandidat akhir dibandingkan menggunakan **ETA MapKit**, bukan jarak sebagai tujuan akhir. Tidak ada klaim optimum global.
- Default **Hybrid** memeriksa baseline live, mencari kandidat dengan insertion + multi-start local search, lalu melakukan validasi/refinement terbatas sesuai budget. Hasil dibandingkan berdasarkan kelayakan dan total durasi perjalanan + menunggu + singgah. Lihat [benchmark](verification/ROUTING_TIME_AWARE_BENCHMARK_2026-11-03.md).
- Mobil pribadi memakai strategi seluruh ruas dengan mobil atau tanpa mobil. Taksi/ride-hailing boleh dipilih per ruas; waktu pesan/tunggu dan akses tetap unknown.
- Semua lokasi pilihan tetap dipertahankan. Kandidat akhir memerlukan semua tujuan dan ruas kembali; perhitungan waktu diperiksa konsistensinya.
- Setiap ruas diminta pada jam keberangkatan setelah perjalanan, singgah, dan menunggu buka sebelumnya. ETA transit yang tidak sesuai waktu permintaan tidak dipakai.
- Default singgah **30 menit**, dapat diubah per tempat. Titik transfer mendapat **0 menit kunjungan tambahan**. Waktu transfer bawaan ETA tidak ditambahkan kembali.
- Batas berjalan awal **45 menit per ruas** adalah asumsi aplikasi yang terlihat dan dapat diubah. Jika transit tidak tersedia sementara WALK melebihi batas, hasil menyatakan data transportasi belum cukup. Sistem tidak meneruskan berjalan antarkota sebagai alternatif otomatis.
- Default maksimum 96 request ETA per run (pengaturan kini dapat dinaikkan sampai 1024), pacing minimal 1,2 detik antarrequest baru, cache sementara per run, deadline permintaan arah/pencarian, dan penghentian saat MapKit melaporkan throttling. Ini kebijakan PoC, bukan batas resmi Apple.
- Hasil lama tidak boleh diterapkan setelah pembatalan/input berubah. Perhitungan dibatalkan ketika app tidak aktif atau pengguna menekan Batalkan. Membuka layar Log tetap membiarkan pekerjaan berjalan. Tidak ada pekerjaan background baru.

## Batas transit MapKit

Apple mendokumentasikan `MKDirectionsTransportType.transit` **hanya untuk estimasi waktu kedatangan**. Karena itu fitur memakai `calculateETA`, bukan `calculate` untuk mencoba memperoleh jalur kereta. Hasil tidak berisi verifikasi nama kereta, platform, timetable, detail transfer, atau polyline transit. Peta itinerary menampilkan geometri mobil/jalan kaki yang tersedia; transit tetap diberi status tanpa garis, tanpa menggambar jalur kereta yang direka. Apple Maps dapat dibuka untuk memeriksa detail perjalanan.

Ketersediaan ETA untuk daftar pengguna atau contoh Jepang tertentu **belum diuji live di perangkat pada pekerjaan ini**. Integrasi framework dan build tidak membuktikan bahwa seluruh ETA Funabashi–Kamakura–Enoshima akan tersedia.

Rujukan: [transit](https://developer.apple.com/documentation/mapkit/mkdirectionstransporttype/transit), [ETAResponse](https://developer.apple.com/documentation/mapkit/mkdirections/etaresponse), [departureDate](https://developer.apple.com/documentation/mapkit/mkdirections/request/departuredate).

## WeatherKit dan konfigurasi akun

Entitlement lokal `com.apple.developer.weatherkit` dan capability project ditambahkan. Bundle ID tetap **`giovanchristoffel.poc-c67`** dan Team ID tetap mengikuti proyek sebelumnya. Nilai entitlement iCloud/CloudKit yang sudah ada dipertahankan.

Untuk permintaan WeatherKit live:

1. Pada Apple Developer, pilih App ID yang **persis sama** dengan bundle proyek ini.
2. Aktifkan WeatherKit pada capability/app service yang sesuai.
3. Perbarui provisioning melalui signing Xcode lalu jalankan build yang ditandatangani.

Konfigurasi portal, pembaruan profile, dan autentikasi layanan **belum diverifikasi** pada pekerjaan ini. Tidak ada App ID, akun, atau container cloud yang diubah melalui portal.

WeatherKit menyediakan prakiraan sekitar **10 hari**. Cadangan Open-Meteo dapat mencakup hingga **16 hari**, bergantung data yang benar-benar tersedia. Tanggal 1 Desember masih berada di luar keduanya pada 3 November 2026; hasil tetap `outside_forecast_horizon`. Sistem tidak memakai cuaca historis atau mengarang prakiraan sebagai pengganti. Lihat [perilaku fallback, atribusi dan verifikasi](NATIVE_WEATHER_FALLBACK.md).

Paparan kunjungan diisi sebagai indoor/outdoor/mixed/unknown. Campuran memakai faktor asumsi 0,5. Bobot hujan awal 2 dan batas tambahan waktu awal 15 menit adalah parameter eksperimen, bukan hasil kalibrasi. ETA provider tidak ditambah keterlambatan akibat hujan buatan. Detail berjalan/menunggu selama TRANSIT belum tersedia; rekomendasi cuaca ditunda jika cakupan paparan belum cukup. Prakiraan kunjungan yang tersedia tetap ditampilkan bersama status dan atribusi.

Data Apple Weather menampilkan mark sesuai tema serta legal URL dari `WeatherService.attribution`. Data Open-Meteo menampilkan sumber dan tautan lisensi CC BY 4.0, termasuk pada ekspor. Prakiraan hanya dicache sementara selama run; ekspor kasus pembanding dapat memuat peluang presipitasi beserta metadata sumber.

Rujukan: [WeatherKit](https://developer.apple.com/weatherkit/), [WeatherService](https://developer.apple.com/documentation/weatherkit/weatherservice), [WeatherAttribution](https://developer.apple.com/documentation/weatherkit/weatherattribution).

## Jam operasional dan titik yang belum spesifik

Jam operasional belum diambil otomatis melalui MapKit pada fitur ini. Jika tidak diisi, kunjungan tetap diberi status belum diverifikasi. Jam yang dimasukkan berlaku sebagai input manual untuk tanggal trip, bukan hasil pencarian Apple.

Fixture mempertahankan tiga keterbatasan: toko suvenir belum ditentukan, menara jam Fujisawa masih menggunakan referensi stasiun, dan Oiwayamichi memakai titik rujukan Nakamuraya dari konteks sebelumnya. Catatan tersebut terlihat pada detail dan laporan. Jika pengguna sudah memilih tempat persisnya, nonaktifkan **Masih titik pendekatan area** pada pemilih lokasi. Tidak ada koordinat atau Place ID Google yang disalin otomatis sebagai hasil pencarian MapKit.

## Verifikasi pekerjaan ini

- Minimum iOS proyek tetap **18.0**; build memakai Xcode **27.2**.
- Build generic iOS unsigned diperiksa dengan `CODE_SIGNING_ALLOWED=NO`.
- Tidak menjalankan tes iOS, Simulator, atau aplikasi di perangkat, sesuai batasan sebelumnya.
- Keberhasilan compile tidak membuktikan ETA Jepang, autentikasi WeatherKit, kebenaran seluruh lokasi, atau kualitas urutan di lapangan.

Lihat [catatan build awal](verification/NATIVE_ITINERARY_2026-11-03.md) dan [pembaruan input bebas](NATIVE_FLEXIBLE_INPUT.md) untuk batas verifikasi tiap perubahan.

## Pembaruan pencarian tempat

Pencarian sekarang memiliki status per tempat, petunjuk area Jepang, nama alternatif, jeda/cooldown, diagnostik error, dan pemilihan pin manual. Satu timeout tidak lagi membatalkan seluruh bulk; gangguan berulang menjeda sisanya tanpa menganggap tempat tidak ada. Lihat [perbaikan pencarian dan langkah uji iPhone](NATIVE_PLACE_SEARCH_FIX.md).

## UI minimal dan log

Log native sekarang disimpan otomatis ke Application Support/NativeTripLogs, lintas sesi, dengan ekspor **Log → Ekspor log (.txt)**. Log mencakup input, pencarian, ETA, cuaca, keputusan dan error. Pengaturan rinci serta diagnostik teknis dipisahkan dari form utama. Lihat [panduan UI dan log](NATIVE_LOGGING.md) untuk retensi dan batas verifikasi.

## Pilihan algoritme dan pembandingan

**Pengaturan → Algoritme itinerary** menyediakan tujuh metode native. Metode lanjutan memakai snapshot berarah lalu memvalidasi kandidat dengan jam tiap ruas. **Bandingkan algoritme** menyediakan kasus sintetis, snapshot input pengguna, seed/pengulangan/statistik dan ekspor/impor OR-Tools Mac. Baca [panduan lengkap](NATIVE_ROUTING_LAB.md) untuk batas optimalitas, data parsial dan langkah helper.
