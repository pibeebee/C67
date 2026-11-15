# Pocket Engine — laporan pengujian 11 November 2026

## Hasil yang diamati

| Pengujian | Hasil | Batas |
| --- | --- | --- |
| Swift XCTest di Mac | 4/4 lulus: katalog dan syarat, bukti kedaluwarsa, itinerary satu tujuan dengan ETA sintetis dan pulang, serta penolakan akses unknown | ETA dan cuaca sintetis; bukan ketepatan perjalanan nyata atau pengujian di iPhone |
| Server `/health` | HTTP 200 | Database terisolasi `.local/validation-2026-11-11/db` |
| Katalog | Token baca: HTTP 200, 30 tempat; tanpa token: 401 | Tidak menguji sinkronisasi dari aplikasi |
| Pemisahan hak | Token baca untuk impor: HTTP 401 | Bukan audit keamanan menyeluruh |
| Impor dan cache | Fakta sintetis diterima 1; pengulangan melewati 1 fakta yang masih segar; batch dengan ID tidak dikenal: 422 | Satu cabang, satu field; tidak membuktikan semua kondisi cache atau rollback |
| TomTom melalui server | HTTP 200, 5 hasil untuk pencarian museum Jakarta; diulang setelah konfigurasi sertifikat permanen, HTTP 200 dan 5 hasil | Dua panggilan Discover pada kampanye ini; tidak diaudit satu per satu untuk akurasi, jam, atau kecocokan cabang |
| Simulator iPhone 18 Pro Max, iOS 27.2 | Aplikasi terpasang, proses diluncurkan dan layar Jelajah menampilkan 30 kandidat | Hanya tampilan awal yang diamati; interaksi, pencarian, perencanaan, sync dan persistensi belum diuji di UI |

Katalog awal tidak berisi jam atau akses yang terverifikasi. Data sintetis pengujian hanya masuk database khusus pengujian; tidak diimpor ke katalog aplikasi maupun database biasa. Cuaca, Apple Maps ETA, Foundation Models, kinerja dan baterai belum diuji live. Keberhasilan compile sebelumnya untuk perangkat iPhone tidak membuktikan signing, entitlement, atau perilaku di perangkat fisik.

## Masalah dan perubahan

Python 3.14 pada mesin ini tidak menemukan CA bundle default. TomTom berhasil ketika Python memakai `SSL_CERT_FILE=/etc/ssl/cert.pem`; nilai tersebut telah ditambahkan ke `Server/.env`. Pengujian kedua melalui server tanpa override environment pada perintah menghasilkan HTTP 200. TLS tetap diverifikasi. Lokasi CA bundle perlu disesuaikan jika server dipindahkan ke mesin lain.

Server kini mencatat timestamp, method, endpoint yang dikenal dan status HTTP; endpoint lain dicatat sebagai `other`. Tidak mencatat token, isi body, kueri atau respons provider. Log terakhir yang menunjukkan request berhasil berasal dari versi logger sebelum pembatasan nama endpoint lain; perubahan akhir tersebut hanya diperiksa kompilasinya.

## Artefak diagnostik

- `.local/validation-2026-11-11/swift-tests.log`: output XCTest.
- `.local/validation-2026-11-11/integration.log`: status dan hitungan request, tanpa key.
- `.local/validation-2026-11-11/server-final.log`: log HTTP server.
- `.local/validation-2026-11-11/app-runtime.log`: log sistem Simulator untuk proses aplikasi. Log sistem dapat memuat metadata perangkat dan sebaiknya diperiksa sebelum dibagikan.
- `.local/validation-2026-11-11/settled.png`: layar awal Simulator.

Server pengujian dihentikan setelah kampanye; aplikasi Simulator tidak dihapus. XCTest ditambahkan ke `Tests/PocketEngineTests` agar dapat dijalankan kembali. Hasil ini belum membuktikan bahwa PoC siap TestFlight atau bahwa rekomendasi sudah akurat.
