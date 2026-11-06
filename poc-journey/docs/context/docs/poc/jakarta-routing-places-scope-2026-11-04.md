# Fokus PoC Jakarta: tempat dan routing

**Keputusan pengguna:** 4 November 2026, WIB. **Status terbaru:** profil Jakarta/mobil dan pemeriksaan tempat diimplementasikan pada build 9; motor belum terintegrasi. [Laporan hasil](../../../../apps/native-routing-lab/docs/verification/JAKARTA_ROUTING_FIX_2026-11-04.md).

## Lingkup yang diterima

- Jakarta menjadi wilayah uji awal. Batas pencarian dan validasi tempat perlu terlihat pada aplikasi; rincian geofence perlu ditetapkan saat implementasi, tanpa menyamakan kotak pencarian dengan batas administratif resmi.
- Mobil dan motor menjadi prioritas moda sesuai arahan pengguna. Jalan kaki dan transit dikeluarkan dari alur uji utama.
- Ketepatan tempat, pemilihan cabang/pin, ketersediaan rute, jadwal dan replanning didahulukan.
- Hybrid adaptif tetap menjadi metode pengurutan. Perubahan lingkup wilayah/moda tidak memerlukan kompetisi algoritme ulang.
- Cuaca tetap menggunakan hasil Open-Meteo yang sudah berhasil pada sesi terbaru. Audit/perbaikan WeatherKit ditunda.
- Keberhasilan alur lengkap menjadi sasaran sebelum optimasi latency/request. Cancellation dan pembatasan layanan tetap diperlukan agar proses dapat dihentikan dan tidak mengulang kegagalan tanpa akhir.
- Eksplorasi Foundation Models tetap terpisah.

## Bukti yang memicu perubahan

Pada log terbaru sesi 937B3C6C, 4 November pukul 13.17–13.24 WIB, itinerary Sudirman–Monas–Kota Tua–Glodok–Ashta–Blok M–Sudirman memakai walking/transit dengan batas berjalan45 menit. Semua request transit provider gagal, semua ruas keluar origin berjalan melampaui batas, dan mobil tidak aktif. Ini belum menguji ETA mobil atau motor pada kasus tersebut.

Cuaca berhasil melalui Open-Meteo sesudah WeatherKit gagal autentikasi. Total waktu proses sekitar129 detik, sementara solver sekitar0,03 detik. Sumber utama: file ekspor pengguna di Downloads; tidak disalin ke dokumen ini.

## Batas provider yang harus dijaga

[MapKit transport types](https://developer.apple.com/documentation/mapkit/mkdirectionstransporttype) menyediakan automobile, walking, transit dan cycling; tidak ada tipe sepeda motor khusus. Maka mode automobile dapat dipakai untuk uji mobil, tetapi tidak dilabeli sebagai ETA motor. Jangan memakai faktor pengali tetap untuk mengarang ETA motor.

Salah satu calon provider motor adalah [Google Routes TWO_WHEELER](https://developers.google.com/maps/documentation/routes/route_two_wheel), dengan [Indonesia pada cakupan yang didukung](https://developers.google.com/maps/documentation/routes/coverage-two-wheeled). Ini kandidat eksplorasi, belum keputusan mengganti provider. [Setup](https://developers.google.com/maps/documentation/routes/get-api-key) memerlukan proyek, billing dan autentikasi. Penggunaan, biaya, penyajian peta, atribusi dan penyimpanan data perlu diperiksa sebelum integrasi. Tidak ada API berbayar/key/proyek baru yang diaktifkan melalui pembaruan lingkup ini.

## Urutan perbaikan

1. **Tempat Jakarta:** konteks pencarian Jakarta, pembeda cabang/alamat/area, konfirmasi kandidat, pemeriksaan origin/tujuan/endpoint di wilayah uji, dan pin manual. Hasil luar wilayah atau ambigu tidak dipilih otomatis. Koordinat baru tidak mengganti titik tersimpan tanpa pilihan pengguna.
2. **Rute mobil:** profil satu moda yang jelas, mula-mula on-demand/ride-hailing karena jalur active-trip sudah mendukungnya. Kendaraan pribadi memerlukan aturan posisi kendaraan yang konsisten sebelum dipakai pada replanning aktif. Jangan menyamakan jenis kendaraan dengan kepemilikan kendaraan.
3. **Alur lengkap:** itinerary lima tujuan dari log, kembali ke Sudirman, pemilihan/simpan, mulai trip, +30 menit, skip, replan, apply/reject dan restore. Data aktual tidak berubah dan ruas gagal tidak dianggap0 menit.
4. **Motor:** tentukan provider dengan moda motor asli, lalu ulangi kasus sama; rute/ETA dapat berbeda dari mobil. Tidak menyatakan dukungan motor selesai hanya karena opsi UI ditambahkan.
5. **Kegagalan dan progress:** alasan transport/ruas yang gagal, retry kegagalan sementara, status durasi unknown, cancellation, waktu total yang cukup untuk complete run. Speed optimization dan WeatherKit tetap ditunda.

## Kriteria bukti berikutnya

Daftar berikut adalah kriteria awal. Pembaruan hasil build 9: J-01 lulus domain/pencarian aktual dengan batas UI; J-02 lulus provider aktual macOS; J-03 baru ETA dan state peta sintetis, belum geometry live; J-04 lulus domain/storage dengan fakta uji; J-05 motor Not run; J-06 mempunyai bukti unit kegagalan/missing ETA tetapi belum uji jaringan pada iPhone.

- J-01: nama/cabang ambigu tetap meminta pilihan; hasil di luar Jakarta tidak otomatis masuk.
- J-02: daftar lima tujuan log menghasilkan jadwal mobil lengkap dengan endpoint asal, atau alasan provider yang spesifik.
- J-03: geometry dan ETA memakai moda/provider yang benar serta metadata waktunya.
- J-04: kasus +30/skip/apply/relaunch tetap menjaga riwayat aktual pada konfigurasi Jakarta.
- J-05: motor diuji sebagai moda asli provider; hasilnya dipisahkan dari mobil.
- J-06: ETA hilang/offline/retry tidak menghasilkan jadwal lengkap palsu atau sukses simpan palsu.

Kelulusan fixture/replay lama tetap bukti domain terdahulu. Bukti provider live serta iPhone dicatat terpisah. Pembatasan Jakarta tidak berarti seluruh rute provider pasti berada di dalam batas administratif yang sama.
