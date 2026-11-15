# Perbaikan PoC Jakarta: tempat dan routing — build 9

**Tanggal:** 4 November 2026, WIB. **Hasil:** profil Jakarta/mobil dan pemilihan tempat sudah diterapkan. Kasus lima tujuan dari log kini menghasilkan itinerary lengkap melalui provider aktual, lalu lulus replan, apply, skip, end-only dan restore dengan fakta uji yang diskenariokan. Algoritme hybrid adaptif tetap sama.

## Perubahan yang diterapkan

- Rencana kosong baru memakai Jakarta, WIB dan satu moda mobil dengan akses taksi/ride-hailing. Walking/transit tidak menjadi ketergantungan profil ini. Budget ETA profil baru512, batas operasi replan300detik; tombol batal tetap tersedia.
- Draft lama dipulihkan tanpa perubahan otomatis. Tombol **Gunakan profil Jakarta dan mobil/taksi** meminta konfirmasi, mempertahankan tujuan/koordinat, lalu mengubah input di layar. Penyimpanan lama baru diganti melalui tindakan Simpan. Trip aktif lama tetap menyimpan fakta; perhitungan live baru memerlukan profil yang didukung.
- Pencarian dan pin manual diperiksa terhadap mask koordinat Jakarta, termasuk origin dan endpoint. Hasil luar wilayah tidak masuk daftar yang dapat dipilih pada pencarian Jakarta. Import tidak dapat melewati pemeriksaan melalui ID origin/tujuan yang bertabrakan.
- Query Jakarta kini memakai konteks kota **Jakarta**, tanpa suffix negara. Uji langsung menemukan bahwa “Kota Tua, Jakarta, Indonesia” menghasilkan kota Jakarta, sedangkan “Kota Tua, Jakarta” menghasilkan Kota Tua yang dimaksud pada sesi ini.
- Bulk lookup hanya memilih otomatis satu kandidat dengan nama/alias yang cocok dan lokasi yang sesuai. Nama berbeda, cabang ganda, atau jalan yang dikembalikan untuk pencarian suatu tempat meminta pilihan pengguna. Pin manual tetap tersedia.
- Menu **Muat kasus Jakarta · 5 tujuan** menggantikan contoh Jepang pada alur utama. Tanggal contoh besok 08.00–18.00 WIB ditampilkan sebelum dimuat; pin berasal dari log pengguna dan tetap perlu diperiksa.
- Cuaca profil Jakarta meminta Open-Meteo langsung. WeatherKit tidak dicoba pada profil ini; masalah autentikasi WeatherKit belum diperbaiki. Jalur fallback lama tetap dipertahankan untuk kompatibilitas dan tes.
- Timeout ETA boleh dicoba ulang sekali, dengan budget/pacing dan cancellation tetap berlaku. Directions unavailable tidak diperlakukan sebagai durasi0. Laporan/UI kandidat tidak lengkap kini menampilkan **durasi belum diketahui** serta konflik yang spesifik.
- Motor mempunyai pesan belum tersedia. Tidak ada konversi ETA mobil menjadi ETA motor, pengali kecepatan buatan, atau provider berbayar yang diaktifkan.
- Versi app tetap 0.6 dengan **build 9**, agar dapat dibedakan dari build 8 pada ekspor log pengguna.

Source empat komponen routing — NativeTripRoutingCore, NativeTripTimeAwarePlanner, NativeTripEngine dan NativeTripRoutingBridge — mempunyai hash yang sama dengan sebelum pekerjaan ini. Yang berubah adalah profil, input/tempat, pilihan provider cuaca, pemulihan dan penyajian hasil.

## Hasil pengujian

| Pemeriksaan | Hasil |
| --- | --- |
| XCTest lokal | **77/77 lulus**:24 planned/storage,35 trip aktif,18 profil/tempat Jakarta |
| XCTest Jakarta | **26/26 lulus** |
| Probe storage lintas proses | Tulis dan baca pada proses terpisah lulus |
| Regresi tambahan |10 input,8 kelompok cuaca,6 state peta,6 pipeline lulus |
| Build iOS | Debug iPhone18Pro/iOS27.0 Simulator berhasil, signing dimatikan; build 9 dipasang dan diluncurkan |
| Provider aktual | MapKit ETA automobile dan search; Open-Meteo forecast dipanggil dari executable macOS dengan source produksi |
| Audit independen |3 laporan,427 event;0 kesalahan aritmetika/identitas/prefix/request/provider yang diperiksa |

Bukti: [ringkasan XCTest lokal](jakarta-routing-fix-2026-11-04/local/summary.json), [Jakarta](jakarta-routing-fix-2026-11-04/jakarta/REPORT.md), [hasil live](jakarta-routing-fix-2026-11-04/live/summary.json), [audit Python](jakarta-routing-fix-2026-11-04/live/audit.json), dan [manifest source](jakarta-routing-fix-2026-11-04/manifest.json).

Tes baru meliputi default Jakarta, mask wilayah meskipun alamat mengandung kata Jakarta, endpoint luar wilayah, scope/mode tidak didukung, legacy restore/conversion, bulk lookup lama, pin tidak menimpa titik yang valid, query/cabang/jalan ambigu, provider WeatherKit yang dinonaktifkan, kegagalan Open-Meteo tetap unknown, schema round trip/end-only dan ID yang bertabrakan.

## Itinerary live lima tujuan

Kasus: Sudirman, Monas, Kota Tua, Jalan Pasar Glodok Selatan, Ashta dan Blok M Square, kembali ke Sudirman. Berangkat **5 November 2026 08.00 WIB**, deadline18.00, singgah30menit/tujuan, automobile on-demand. Jam operasional belum diisi; kelayakan hanya terhadap batas yang diketahui.

| Ruas terpilih | Berangkat | Tiba | Selesai singgah |
| --- | --- | --- | --- |
| Sudirman→Monas |08.00.00 |08.18.02 |08.48.02 |
| Monas→Glodok |08.48.02 |08.59.36 |09.29.36 |
| Glodok→Kota Tua |09.29.36 |09.36.54 |10.06.54 |
| Kota Tua→Blok M |10.06.54 |10.49.29 |11.19.29 |
| Blok M→Ashta |11.19.29 |11.29.38 |11.59.38 |
| Ashta→Sudirman |11.59.38 |12.20.10 |— |

Seluruh lima tujuan hadir tepat sekali dan endpoint benar. Total **260,17 menit**:110,17 menit perjalanan dan150menit singgah. Perhitungan awal memakai **57 request ETA**, sekitar **68,98 detik** pada run akhir. Ini satu skenario provider, bukan ukuran p90 atau jaminan waktu perjalanan.

### Replan dan pemulihan

Harness memasukkan fakta uji berdasarkan jadwal awal: Monas selesai, Glodok sedang dikunjungi. Pada09.09.36, tambahan30menit mengubah keluar Glodok dari 09.29.36 menjadi **09.59.36**. Ini **fakta uji yang diskenariokan**, bukan kehadiran pengguna/GPS atau perjalanan sungguhan.

Replan mempertahankan Monas/Glodok sebagai prefix, hanya menjadwalkan Kota Tua→Blok M→Ashta→Sudirman, dan selesai **12.55.43 WIB**. Memakai **24 request ETA**, sekitar **29,43 detik**. Selisih dari jadwal awal35menit33detik mencakup tambahan kunjungan30menit dan ETA provider pada departure yang berubah; tidak dipaksa menjadi tepat+30.

Proposal diterapkan dan snapshot dibaca ulang tanpa mengubah fakta sebelumnya. Berikutnya ketiga pending stop dikonfirmasi skip secara eksplisit, Glodok dicatat selesai pada09.59.36, lalu end-only menghitung satu ruas Glodok→Sudirman: **1 request**, tiba10.23.14. Apply, finish dan restore selesai juga lulus.

Artefak lengkap menyimpan [laporan awal](jakarta-routing-fix-2026-11-04/live/initial-report.json), [replan](jakarta-routing-fix-2026-11-04/live/replan-report.json), [end-only](jakarta-routing-fix-2026-11-04/live/end-only-report.json), [restore sesudah apply](jakarta-routing-fix-2026-11-04/live/restored-session.json) dan [snapshot selesai](jakarta-routing-fix-2026-11-04/live/completed-session.json).

Audit Python tidak memanggil validator Swift. Ia menjumlah ulang ETA/tunggu/singgah, memeriksa urutan/identitas/deadline/endpoint, prefix aktual, skip, snapshot selesai dan counter request terhadap trace. Tidak ditemukan pemanggilan WeatherKit pada run profil Jakarta. Ini tidak mengukur kebenaran traffic di jalan.

## Temuan pencarian tempat

Eksplorasi query pada API MapKit yang sama memberikan:

| Query | Hasil pada sesi ini |
| --- | --- |
| Kota Tua tanpa konteks | Kota Tua di Sumatra Utara |
| Kota Tua, Jakarta, Indonesia | Kota Jakarta |
| Kota Tua Jakarta / Kota Tua, Jakarta | Kota Tua, Jalan Kali Besar Timur No.10 |
| Monumen Nasional Jakarta | National Monument |
| Pasar Glodok Jakarta | Jalan Pasar Glodok Selatan |

Karena itu area dan pemeriksaan identitas diperlukan bersamaan. Perbaikan final menghasilkan Kota Tua yang benar untuk input Kota Tua. Input Monas menghasilkan National Monument tetapi tetap meminta pilihan karena namanya berbeda. Query Kota Tua Padang dapat menghasilkan kandidat lain di Jakarta; kandidat itu **tidak dipilih otomatis**. Pengguna tetap perlu memeriksa nama, alamat dan cabang; wilayah saja tidak membuktikan identitas tempat.

Lihat [varian query](jakarta-routing-fix-2026-11-04/search-variants.json) dan [hasil pencarian final](jakarta-routing-fix-2026-11-04/live/search-results.json). Ini pengamatan bertanggal, bukan janji hasil pencarian selalu sama.

## Batas verifikasi dan data

- Mask Jakarta adalah data geoBoundaries/OSM yang dibekukan, disederhanakan, vintage 2017. Ia dipakai sebagai cakupan operasional PoC, bukan batas hukum/survei terbaru. Pin dekat batas/pulau kecil perlu pemeriksaan. Pembatasan endpoint tidak menjamin semua segmen jalan berada dalam wilayah yang sama. [Data, lisensi ODbL dan provenance](../data/jakarta-boundary/README.md).
- ETA aktual berasal dari panggilan framework MapKit pada host macOS; model traffic/cache internal provider tidak diaudit. Ini tidak membuktikan perilaku, permission, signing atau latency iPhone fisik.
- Build iOS dan layar awal Jakarta diamati pada Simulator. Kontrol UI melalui Device Hub/CUA gagal dengan noWindowsAvailable; refresh dan satu retry tetap gagal. Karena itu klik menu, pencarian, apply dan relaunch melalui UI lengkap **belum diverifikasi pada sesi ini**. Fungsionalitas domain/provider/storage diperiksa melalui harness dan XCTest; hasil itu tidak dilabeli sebagai walkthrough UI.
- Jam operasional, akses masuk/parkir, waktu menunggu taksi, harga, motor dan kendaraan pribadi yang ditinggal belum divalidasi. Prediksi cuaca tetap prakiraan, bukan kondisi pasti.
- Report tidak mengklaim seluruh gate P3/perangkat atau P4/pengguna selesai. Motor memerlukan provider dengan moda motor asli serta keputusan integrasi tersendiri.

## Kegagalan selama pengerjaan

Percobaan awal harness gagal kompilasi karena membandingkan tipe non-Equatable dan try yang belum lengkap; diperbaiki pada harness. Satu tes lama juga gagal sesudah default berubah menjadi Jakarta karena tes menulis nilai Jakarta yang sama lalu mengharapkan dirty state. Fixture diubah menjadi Jakarta Selatan agar benar-benar menguji perubahan yang gagal disimpan. Log percobaan tetap disimpan;77+26 tes akhir lulus.

Python HTTPS awal gagal menggunakan certificate store-nya; unduhan data publik berhasil menggunakan system curl dengan validasi TLS tetap aktif. Build iOS hanya melaporkan warning metadata App Intents dilewati karena tidak ada dependency framework itu; tidak ada error build.

## Cara mencoba dan reproduksi

Pada aplikasi:

1. Untuk data lama, pilih **Gunakan profil Jakarta dan mobil/taksi**, lalu konfirmasi dan periksa pin.
2. Atau buka menu **Kelola rencana→Muat kasus Jakarta ·5 tujuan**, konfirmasi, lalu **Hitung itinerary**.
3. Periksa tanggal, waktu dan deadline. Contoh memakai besok; untuk memulai trip aktif nyata, pilih tanggal hari ini dan rentang waktu yang sesuai sebelum menghitung/menyimpan.
4. Simpan itinerary pilihan, lalu mulai perjalanan. Tidak ada overwrite otomatis terhadap trip aktif atau data lama.

Runner dari checkout aktual:

~~~sh
bash scripts/test-native-trip-local.sh /tmp/c67-jakarta-local-new
bash scripts/test-native-trip-jakarta.sh /tmp/c67-jakarta-regression-new
bash scripts/test-native-trip-jakarta-live.sh /tmp/c67-jakarta-live-new
python3 scripts/audit-native-trip-jakarta-live.py /tmp/c67-jakarta-live-new
~~~

Runner live memanggil provider sungguhan pada titik publik tersebut dan memakai tanggal besok; hasil/timing dapat berubah. Gunakan output baru. Package/binary/module cache sementara dibersihkan oleh runner; artefak JSON/log tetap ada. Launch argument **--jakarta-ui-testing** memisahkan data Simulator dari NativeTripPlans biasa.

Checkout: <LOCAL_HOME>/Programming/software/ios/poc-c67, branch gi/itinerary-time-aware, base 712f036b222839173d7ea82bb736dd57aaeed6f5. Source awal sudah dirty dan dipertahankan. Tidak ada commit, push, deployment, perubahan akun Apple, atau aktivasi Google API/billing baru.
