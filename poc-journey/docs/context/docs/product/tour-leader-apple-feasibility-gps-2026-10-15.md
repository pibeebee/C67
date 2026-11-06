# Apple feasibility dan batas GPS — Tour Leader

15 Oktober 2026 · Pemeriksaan dokumentasi resmi Apple/App Review · Belum technical spike, build, pengukuran perangkat, atau persetujuan App Review.

Rujukan scope: [Feature Specification](tour-leader-feature-specification-2026-10-15.md), F01–F08. MVP saat ini satu perangkat TL dengan pemeriksaan manual. Tracking peserta tidak termasuk scope itu; kajian berikut mengevaluasi opsi tambahan tanpa mengubah keputusan scope.

## Kesimpulan

MVP inti secara arsitektur dapat dibangun dengan framework publik Apple. Fitur GPS juga didukung, termasuk penggunaan background yang sesuai, tetapi sistem tidak menyediakan jaminan posisi terus-menerus atau pembuktian kehadiran. Yang perlu dibedakan: kapabilitas framework, pembatasan OS/izin, akurasi lingkungan, transmisi antarperangkat, dan aturan distribusi.

| Kebutuhan | Jalur implementasi | Penilaian |
|---|---|---|
| Trip, roster, sesi, filter, follow-up, review | SwiftUI dan logika aplikasi | Tidak menemukan kebutuhan API privat dalam scope |
| Penyimpanan lokal, riwayat, koreksi | SwiftData atau Core Data; transaksi/event dirancang aplikasi | Didukung; atomicity dan recovery tetap perlu diuji |
| Meeting point dengan pin | MapKit | Dapat ditampilkan; tidak otomatis memperoleh posisi peserta |
| Lokasi perangkat yang menjalankan aplikasi | Core Location | Didukung dengan otorisasi pengguna |
| Lokasi semua peserta pada iPhone TL | Pengambilan di perangkat peserta + kanal pengiriman + MapKit | Perlu arsitektur multi-perangkat; satu izin di ponsel TL tidak cukup |
| Lokasi background | Core Location background configuration/session | Bersyarat OS/izin/lifecycle; bukan loop tanpa batas |
| Alert masuk/keluar area tetap | Condition/region monitoring | Didukung dengan batas; bukan presensi otomatis |
| Deteksi berada di dalam bus | GPS saja | Tidak dapat dijamin oleh akurasi GPS |
| Membaca daftar People Find My | Tidak ada API publik terverifikasi pada penelusuran ini | Jangan dijadikan dependency |

[SwiftData](https://developer.apple.com/documentation/swiftdata) menyediakan persistence model dan [Core Location](https://developer.apple.com/documentation/corelocation) menyediakan lokasi perangkat. Pemetaan ini adalah kesimpulan arsitektur, bukan hasil uji app.

## 1. Background location: diperbolehkan dengan desain yang sesuai

Apple mendokumentasikan background location melalui konfigurasi Location updates dan API sesi. Pemilihan API mengikuti deployment target. `CLBackgroundActivitySession`/`CLServiceSession` adalah opsi pada OS yang mendukungnya; jangan menyalin konfigurasi tanpa memeriksa availability. [Handling location updates in the background](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background).

**When In Use tidak selalu berarti langsung berhenti saat layar terkunci.** Dalam konfigurasi yang tepat, sesi location aktif dapat berlanjut di background. **Always** mempunyai cakupan lebih luas dan dapat memungkinkan peluncuran ulang untuk jenis event tertentu; bukan jaminan proses hidup terus. Apple juga menjelaskan perbedaan peluncuran ulang berdasarkan service. Pengguna dapat mengubah izin kapan pun. [Requesting authorization](https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services).

Untuk produk ini, usulan awal adalah sesi berbagi yang dimulai peserta secara eksplisit dan berakhir saat stop/akhir tur. Mulai dari akses minimum; minta Always hanya jika perilaku yang benar-benar dibutuhkan tidak cukup dengan alur sesi aktif. Purpose string harus menggambarkan perilaku yang benar-benar dilakukan. Ini rekomendasi desain, bukan pernyataan bahwa semua skenario cukup dengan satu tingkat izin.

Jangan menjanjikan update setiap detik, operasi setelah force-quit/reboot, atau kelanjutan tanpa koneksi. Lock screen, suspension, system termination, force-quit dan reboot perlu fixture berbeda; hasil bergantung layanan/OS. Ponsel mati tidak menyediakan koordinat baru. Akurasi tinggi dan pembaruan lebih sering mempunyai biaya energi. [Energy guidance](https://developer.apple.com/documentation/xcode/accessing-the-device-s-location-efficiently).

## 2. Presisi dan geofence

Pengguna dapat memberikan reduced accuracy. Pada `CLLocationManager`, Apple menyatakan menaikkan `desiredAccuracy` tidak mengatasi reduced authorization; region monitoring dan beacon ranging tidak tersedia dalam kondisi itu. Jangan memperlakukan Precise Location sebagai hak aplikasi atau menjanjikan akurasi tertentu hanya karena sudah diizinkan. [accuracyAuthorization](https://developer.apple.com/documentation/corelocation/cllocationmanager/accuracyauthorization).

Bahkan dengan full accuracy, layanan hanya berusaha mencapai `desiredAccuracy` dan aplikasi harus menangani hasil yang kurang akurat. Karena itu, inferensi produk adalah: radius kecil di sekitar bus tidak dapat membedakan dengan pasti peserta di kabin, trotoar, atau kendaraan lain. Contoh jarak adalah ilustrasi, bukan hasil pengukuran lapangan. [desiredAccuracy](https://developer.apple.com/documentation/corelocation/cllocationmanager/desiredaccuracy).

Geofence mendeteksi perubahan kondisi terhadap **area geografis**; pusat area tetap tidak otomatis mengikuti TL yang berjalan. Untuk jarak dari TL yang bergerak, diperlukan posisi kedua pihak dan logika perhitungan/pembaruan sendiri. Geofence juga tidak membuktikan orang sudah mendengar instruksi atau siap berangkat.

Apple membatasi 20 kondisi yang dipantau bersamaan per app pada perangkat. Ini **bukan batas 20 peserta**: 40 ponsel peserta masing-masing dapat memantau meeting point yang sama; iPhone TL dapat menampilkan data peserta yang diterima. Jangan membuat satu monitored region per peserta dan menganggap sistem memantau orang itu dari jarak jauh. [Condition monitoring](https://developer.apple.com/documentation/corelocation/monitoring-the-user-s-proximity-to-geographic-regions).

## 3. Lokasi peserta memerlukan sumber dan pengiriman

Alur konseptual yang dibutuhkan bila dipilih:

`Perangkat peserta → izin + sesi berbagi → Core Location → kanal pertukaran data → aplikasi TL → peta + umur data + indikasi kualitas`

Core Location memberi lokasi perangkat setempat; MapKit menampilkan peta, bukan jaringan pelacak anggota tour. Seluler/Wi-Fi dapat membawa data antarperangkat berjauhan; komunikasi lokal memiliki cakupan dan lifecycle berbeda. Tanpa kanal aktif, TL hanya dapat melihat data terakhir yang diterima, tidak posisi live baru.

Backend/CloudKit atau layanan lain perlu evaluasi identitas, akses, ketersediaan, biaya dan platform. Tidak dipilih atau dibangun dalam kajian ini. Satu perangkat TL tidak dapat mendeteksi posisi setiap orang hanya dari daftar nama. Peserta tanpa perangkat/sumber lokasi tetap membutuhkan pemeriksaan manual. Browser link bukan substitusi yang diasumsikan setara untuk native background tracking.

Penelusuran Find My menemukan program aksesori untuk barang, bukan API People yang dapat diandalkan untuk roster tour. Kesimpulan terbatasnya adalah tidak ada API publik People yang berhasil diverifikasi, bukan pembuktian universal tentang seluruh integrasi Apple. [Apple Accessories](https://developer.apple.com/accessories/).

## 4. Aturan App Review yang relevan

[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) mensyaratkan penggunaan background sesuai tujuan (2.5.4), lokasi relevan dan disertai pemberitahuan/persetujuan (5.1.5), serta privasi, minimisasi, kontrol izin dan sharing yang jelas (5.1.1–2). Bagian 5.1.5 juga membatasi penggunaan location APIs untuk emergency services. Rekomendasi: posisikan produk sebagai koordinasi tur, jangan menjanjikan layanan penyelamatan berbasis GPS. Penjelasan produk harus sesuai perilaku nyata; pergantian istilah tidak memperbaiki fungsi yang melanggar. Ini bukan jaminan diterima.

Contoh risiko implementasi yang diturunkan dari aturan tersebut: tracking diam-diam/berlanjut setelah sesi; kebutuhan background yang tidak dijelaskan; roster manual diblokir saat izin lokasi ditolak; atau klaim kehadiran/keselamatan yang tidak didukung. Izin iOS peserta dan persetujuan mengirim lokasi ke TL adalah dua kebutuhan desain berbeda. Persetujuan TL tidak menggantikan kontrol peserta.

Jika posisi dikirim/disimpan di luar perangkat, sesuaikan App Privacy Details dengan alur data nyata, termasuk SDK. Privacy label bukan pengganti prompt izin atau consent sharing. [App privacy details](https://developer.apple.com/app-store/app-privacy-details/). Kajian ini membahas aturan Apple, bukan legal review lintas negara.

## 5. Rekomendasi scope dan syarat uji

**Tahap inti:** pertahankan F01–F08 tanpa lokasi wajib. **Opsi lokasi awal:** meeting point manual dan lokasi diri opsional. **Jika tracking peserta dipilih:** lakukan spike beberapa perangkat sebelum memasukkannya sebagai release requirement; memperluas scope bukan otomatis disetujui oleh dokumen ini.

Tambahan acceptance criteria GPS yang disarankan jika fitur itu diadopsi:

| ID | Perilaku yang harus diverifikasi |
|---|---|
| GPS01 | Deny/revoke lokasi tidak memblokir roster, pemeriksaan atau follow-up manual |
| GPS02 | Berbagi memerlukan aksi eksplisit; peserta mengetahui penerima/durasi dan dapat berhenti |
| GPS03 | Setelah stop/akhir sesi, akuisisi/pengiriman sesi itu dihentikan; queued upload tidak dikirim ulang tanpa otorisasi sesi yang masih berlaku |
| GPS04 | Koordinat menampilkan waktu pengukuran dan terakhir diterima; ambang stale ditetapkan dan diuji, tidak ditampilkan seolah live |
| GPS05 | Reduced accuracy, error atau data stale tidak mengubah status kehadiran; kualitas/ketidakpastian terlihat |
| GPS06 | Masuk/keluar radius hanya indikator untuk ditinjau; tidak otomatis menjadi Diperiksa TL atau hilang |
| GPS07 | Fixture lock, background, offline, pencabutan izin, force-quit, relaunch dan reboot dijalankan pada perangkat/OS sasaran; perilaku kehilangan update terlihat |
| GPS08 | Akses data dipisahkan antartrip; akses tur yang berakhir dicabut sesuai policy; stop peserta tidak dapat di-override TL |

Uji outdoor/indoor/keramaian, perangkat dan mode izin berbeda; ukur umur data yang terlihat TL, false proximity/exit, gap update, dan penggunaan baterai. Tetapkan target berdasarkan kebutuhan aktual TL; tidak ada angka akurasi atau frekuensi yang dinyatakan lulus pada kajian ini.

**Hasil saat ini:** supported menurut dokumentasi untuk MVP dan lokasi opsional; tracking peserta bersyarat; GPS sebagai verifikasi kehadiran andal tidak didukung oleh bukti ini; penerimaan App Store tetap belum diuji.
