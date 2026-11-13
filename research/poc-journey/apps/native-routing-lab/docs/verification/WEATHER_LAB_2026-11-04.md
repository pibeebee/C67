# Weather Lab C67 — implementasi dan hasil pengujian

Tanggal: **4 November 2026, WIB**. Aplikasi: **0.6 build 10**, working tree pada branch `gi/itinerary-time-aware`, base commit `712f036b222839173d7ea82bb736dd57aaeed6f5`.

Layar eksperimen cuaca sudah diimplementasikan dan menjadi layar awal aplikasi. Tab **Rencana** tetap membuka perencana Jakarta yang sudah ada. **126 XCTest lulus**, build iOS Simulator berhasil, dan alur live menunjukkan fallback serta cache bekerja. WeatherKit masih gagal pada layanan autentikasi Simulator; laporan ini tidak menyatakan autentikasi Apple atau provisioning iPhone sudah diperbaiki.

## Perubahan yang diterapkan

| Bagian | Perilaku build 10 |
| --- | --- |
| Diagnosis satu titik | Meminta hourly WeatherKit untuk satu titik perwakilan pertama, tanpa cache, retry, atau fallback. Boleh dicoba kembali walaupun pemutus autentikasi sedang aktif. |
| Pengelompokan | Koordinat diurutkan secara deterministik, kemudian tiap titik dimasukkan ke perwakilan terdekat dalam radius 3 km. Semua anggota dibatasi jaraknya terhadap perwakilan; kedekatan A–B–C tidak menyatukan C yang terlalu jauh dari A. Tidak ada pencarian MapKit atau akses GPS tambahan. |
| Rentang waktu | Hanya hourly untuk rentang pilihan, dibulatkan keluar ke batas jam. Maksimal 24 jam dan 22 titik berkoordinat pada cakupan operasional Jakarta. Data harus mencakup seluruh interval yang diminta. |
| Cache | Di memori, dipisahkan menurut provider dan koordinat perwakilan. Data dapat digunakan ulang bila mencakup seluruh rentang baru dan belum kedaluwarsa. Maksimal 15 menit sejak pengambilan, atau expiration WeatherKit yang lebih awal; maksimal 128 entri. Mengubah urutan input tidak mengubah kelompok. Mengubah anggota dapat mengubah perwakilan. |
| Batas waktu | 8 detik per provider, termasuk maksimal satu retry untuk `networkConnectionLost`/`timedOut`. Tidak ada retry otomatis untuk autentikasi, offline, atau diagnosis satu titik. Angka ini bukan batas waktu seluruh run. Satu kelompok dapat mencoba WeatherKit lalu Open-Meteo; kelompok lain dapat menunggu giliran. |
| Pembatasan kerja | Kelompok pertama diselesaikan sebelum memulai kelompok berikutnya untuk mendeteksi kegagalan autentikasi; sesudah itu maksimal dua kelompok diproses bersamaan. |
| Pemutus autentikasi | `WeatherError.permissionDenied` serta dua domain/kode layanan autentikasi yang benar-benar teramati menghentikan request WeatherKit berikutnya selama sesi. Reset eksplisit atau diagnosis baru yang berhasil membuka kembali pemutusnya. Kesalahan proxy tidak mengidentifikasi konfigurasi Apple mana yang salah. |
| Cadangan | Mode otomatis memakai Open-Meteo ketika WeatherKit gagal. Bila keduanya gagal, data tetap **belum diketahui**, tidak diberi peluang hujan 0%. Mode provider tunggal tersedia untuk pembanding. |
| Pembatalan | Tombol batal, meninggalkan layar dan aplikasi masuk background membatalkan pekerjaan aktif. Pembatalan tidak memulai fallback. Respons setelah timeout/pembatalan tidak dapat mengisi hasil atau cache. API provider mungkin masih menyelesaikan pekerjaan internal setelah pembatalan; aplikasi tidak menjanjikan penghentian jaringan internal secara instan. |
| Rincian dan atribusi | Sumber, waktu pengambilan, metadata provider bila tersedia, expiry, status cache dan penyebab fallback ditampilkan. Apple Weather tidak dipublikasikan tanpa atribusi; Open-Meteo memiliki kredit dan tautan lisensi. Waktu kunjungan tiap tempat dapat diubah untuk membaca interval jam yang sesuai dari prakiraan perwakilan. |
| Data trip | Tombol salin titik membaca rencana tersimpan tanpa menulisnya. Penyalinan ditolak bila ada titik tanpa koordinat; tempat tidak dihilangkan diam-diam. Hasil Weather Lab tidak otomatis dimasukkan ke optimizer atau trip aktif. |
| Bukti pengujian | Log, hitungan request/cache, durasi, kelompok, mode, rentang waktu dan hasil provider dapat diekspor sebagai JSON. Berkas ekspor berada di direktori sementara khusus Weather Lab; cache hilang setelah aplikasi ditutup. |

Radius 3 km adalah **asumsi eksperimen**, bukan wilayah resmi WeatherKit atau jaminan cuaca seragam. Label kota di aplikasi Weather tidak membuktikan semua koordinat Jakarta mempunyai prakiraan sama.

## Isolasi perubahan

Empat file baru berada di `poc-c67/Features/WeatherLab`: core/engine, adapter provider, model dan UI. Dari 79 berkas source/project yang diambil hash-nya sebelum implementasi, hanya app entry dan nomor build pada project yang berubah. Semua source perencana, algoritme hybrid adaptif, pencarian tempat, replanning, penyimpanan lokal dan jalur cuaca Jakarta tetap identik dengan baseline sebelum pekerjaan ini. Jalur Jakarta di tab Rencana tetap memakai Open-Meteo langsung.

Peluncuran biasa membuka Weather Lab dan menyediakan tab Rencana. Argumen `--native-itinerary`, `--jakarta-ui-testing` dan `--active-ui-testing` tetap membuka perencana secara langsung. Jalur legacy/diary tidak diganti. Fixture `--weather-lab-ui-testing` hanya tersedia pada Debug dan ditandai **SIMULASI** di UI serta ekspor; pengukuran live di bawah tidak memakai fixture tersebut.

## Hasil pengujian

| Pemeriksaan | Hasil dan batas bukti |
| --- | --- |
| XCTest lokal | **100/100 lulus**, 0 gagal/dilewati: 77 regresi yang sudah ada dan **23 tes Weather Lab**. Menggunakan source produksi dengan provider fixture yang diinjeksi, tanpa jaringan. |
| XCTest Jakarta | **26/26 lulus**, menggunakan ETA replay; source routing tidak berubah. |
| Penyimpanan lintas proses | Write/read pada direktori uji terpisah lulus. |
| Build | `poc-c67`, Debug, iPhone 18 Pro, iOS 27 Simulator, `CODE_SIGNING_ALLOWED=NO`; berhasil. Peringatan metadata AppIntents tanpa dependensi tidak memblokir build. |
| UI live | Peluncuran, mode otomatis, diagnosis satu titik, pengulangan cache, tab Rencana, kembali ke Weather Lab, rincian sumber/expiry/interval kunjungan dan share sheet JSON diamati. |
| Data rencana Simulator | Dua berkas rencana tersimpan identik byte-per-byte sebelum diagnosis/cache dan sesudah membuka Rencana. Baseline pemeriksaan ini diambil setelah run otomatis pertama. Penyalinan dari storage juga diuji dengan byte comparison pada fixture tersimpan di XCTest. |

Tes Weather Lab mencakup kelompok stabil/radius/tidak berantai, input tidak valid, keberhasilan Apple dengan kredit, reuse cache untuk input terbalik/rentang lebih kecil, perbedaan provider/tanggal, TTL dan expiry lebih awal, pemutus autentikasi/reset/pemulihan, diagnosis tanpa fallback, jam tidak lengkap/atribusi hilang/respons kedaluwarsa, kedua provider gagal, refresh/clear, concurrency, retry terbatas, provider yang mengabaikan pembatalan, cancel/restart, JSON/provenance, pemisahan launch dan penyalinan storage tanpa perubahan atau tempat hilang.

### Pengukuran live pada Simulator

Enam titik publik: Sudirman, Monas, Kota Tua, Glodok, Ashta dan Blok M. Dengan radius 3 km terbentuk **empat kelompok**: Blok M–Ashta (terjauh 1,80 km), Sudirman, Monas, dan Glodok–Kota Tua (0,99 km). Sudirman dan Monas tidak dipaksakan masuk satu kelompok ketika melebihi radius.

| Run | Request WeatherKit | Request Open-Meteo | Cache hit | Durasi yang dicatat engine | Hasil |
| --- | ---: | ---: | ---: | ---: | --- |
| Otomatis, cache kosong | 1 | 4 | 0 | 2,291 detik | 4/4 kelompok melalui Open-Meteo; pemutus autentikasi aktif |
| Diagnosis satu titik sesudahnya | 1 | 0 | 0 | 0,006 detik | 0/1; kegagalan WeatherKit terlihat, tanpa cadangan |
| Otomatis diulang dalam sesi | 0 | 0 | 4 | 0,013 detik | 4/4 dari cache yang belum kedaluwarsa |

Kegagalan aktual: `WeatherDaemon.WDSJWTAuthenticatorServiceProxy.Errors`, kode `0`. Classifier awal hanya mengenali error listener dari log terdahulu; temuan live ini diperbaiki dan dicakup regresi. Aplikasi tidak menganggap sembarang error 0/2 sebagai kegagalan autentikasi.

Angka di atas berasal dari satu rangkaian run dengan rentang enam jam, **bukan benchmark lintas kondisi**, jaminan latency, atau bukti kecepatan WeatherKit yang sehat. Kegagalan diagnosis yang sangat cepat dapat berasal dari layanan lokal Simulator. Penghitung WeatherKit mencatat pemanggilan hourly oleh aplikasi, termasuk retry; tidak mengukur jumlah request internal daemon. Attribution merupakan operasi tambahan bila belum tersedia, dan tidak tercapai pada kegagalan autentikasi ini.

## Cara mencoba di aplikasi

1. Jalankan build 10; layar awal adalah **Weather Lab**. Tidak ada request cuaca otomatis saat peluncuran.
2. Periksa titik serta tanggal/jam WIB. Enam titik contoh sudah disediakan; atau salin koordinat rencana tersimpan, lalu periksa tanggalnya.
3. Pilih **Diagnosis satu titik WeatherKit** untuk memisahkan masalah WeatherKit dari fallback. Bila gagal, buka panduan autentikasi dan bagikan JSON.
4. Pilih **WeatherKit + cadangan**, kemudian **Uji semua kelompok**. Buka hasil kelompok untuk melihat sumber, expiry dan prakiraan per jam serta mengubah waktu kunjungan contoh.
5. Ulangi run untuk memeriksa cache. **Ambil ulang tanpa cache** tetap menghormati pemutus autentikasi. Diagnosis satu titik atau reset pemutus diperlukan untuk mencoba kembali Apple setelah konfigurasi diperbaiki.
6. **Bagikan laporan JSON** membuka berkas yang dapat disimpan melalui share sheet. Run berikutnya mengganti laporan terakhir pada sesi tersebut; ekspor laporan yang ingin dibandingkan sebelum menjalankan lagi.
7. Buka tab **Rencana** untuk memakai itinerary/replanning sebelumnya.

Runner tanpa provider live:

```sh
bash scripts/test-weather-lab.sh /tmp/c67-weather-results-baru
bash scripts/test-native-trip-jakarta.sh /tmp/c67-jakarta-results-baru
```

Gunakan direktori hasil baru. Runner Weather Lab menjalankan 100 tes, termasuk regresi lokal, bukan hanya 23 tes barunya.

## Bukti dan pekerjaan berikutnya

Artefak: [XCTest lokal](weather-lab-2026-11-04/local/summary.json), [log lokal](weather-lab-2026-11-04/local/test.log), [Jakarta](weather-lab-2026-11-04/jakarta/REPORT.md), [run otomatis](weather-lab-2026-11-04/ui/automatic-live.json), [diagnosis](weather-lab-2026-11-04/ui/probe-live.json), [cache](weather-lab-2026-11-04/ui/cache-live.json), [snapshot UI](weather-lab-2026-11-04/ui/snapshots.json), [isolasi source](weather-lab-2026-11-04/source-isolation.json), dan [log build](weather-lab-2026-11-04/build.log).

Tangkapan layar: [awal](weather-lab-2026-11-04/ui/initial.jpg), [hasil/fallback](weather-lab-2026-11-04/ui/automatic-live.jpg), [cache](weather-lab-2026-11-04/ui/cache-results.jpg), [rincian](weather-lab-2026-11-04/ui/forecast-detail.jpg), [Rencana lama](weather-lab-2026-11-04/ui/planner-preserved.jpg), [ekspor](weather-lab-2026-11-04/ui/export-sheet.jpg).

Berikutnya: jalankan diagnosis satu titik pada **iPhone dengan signing yang sesuai**, periksa WeatherKit di App Capabilities dan App Services beserta provisioning/embedded entitlement, lalu uji mode otomatis dan cache pada perangkat tersebut. Entitlement WeatherKit sudah dideklarasikan dalam repo; percobaan ini tidak mengubah akun Developer, capability di portal atau provisioning. Keberhasilan WeatherKit aktual, logo/atribusi Apple dengan respons nyata, keadaan background perangkat dan manfaat radius 3 km di lapangan belum tervalidasi. Penanganan timeout/cancel diuji memakai provider fixture; jaringan internal Apple setelah cancel tidak diobservasi.

Dasar API: [hourly dengan rentang waktu](https://developer.apple.com/documentation/weatherkit/weatherquery/hourly(startdate:enddate:)), [metadata dan expiration](https://developer.apple.com/documentation/weatherkit/weathermetadata), [atribusi Apple Weather](https://developer.apple.com/documentation/weatherkit/weatherattribution), serta [konfigurasi WeatherKit Apple Developer](https://developer.apple.com/help/account/services/weatherkit/).
