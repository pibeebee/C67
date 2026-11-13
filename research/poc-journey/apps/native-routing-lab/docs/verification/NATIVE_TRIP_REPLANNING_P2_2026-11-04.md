# Hasil P2A–P2B — perjalanan aktif dan replanning native

**Tanggal:** 4 November 2026, WIB. **Keputusan:** P2A dan P2B selesai untuk lingkup lokal/manual di bawah; lanjutkan P3 sebelum sesi lapangan. **G2A:** lulus alur +30 menit dari domain hingga UI. **G2:** invariant kritis yang berlaku pada lingkup ini lulus pada domain, storage dan replay; layanan live/perangkat fisik mempunyai gerbang P3 tersendiri.

Inti aplikasi sekarang dapat mencatat perjalanan aktif, memperpanjang kunjungan, melewati tujuan atas keputusan pengguna, menghitung ulang sisa perjalanan, lalu meninjau dan menerapkan atau mengabaikan proposal. Riwayat aktual dan rencana awal tetap tersimpan. Alur ini tidak memanggil model/OpenRouter/backend tim. Bukti kali ini memakai ETA beku/sintetis; build dan interaksi diamati di Simulator.

## Perilaku yang diimplementasikan

- Tindakan manual: mulai trip, tiba, mulai kunjungan, selesai/berangkat, tambah 30 menit, atur waktu keluar, ubah deadline, skip pending stop, dan konfirmasi tiba di endpoint. Tiba dan mulai kunjungan merupakan dua fakta berbeda.
- Perubahan fakta/durasi disimpan atomik sebelum dianggap berhasil. Hitung ulang adalah tindakan terpisah. Jika hitung gagal, perubahan terakhir bertahan dan rencana sebelumnya berlabel perlu diperbarui.
- Origin sisa adalah lokasi saat ini yang dikonfirmasi pengguna, atau lokasi selesai terakhir. Endpoint tetap titik akhir trip asal, termasuk bila awalnya kembali ke origin. Tanggal layanan dan deadline tetap absolut.
- Projection hanya memuat pending stop. Stop selesai, sedang dikunjungi, atau di-skip tidak dimasukkan sebagai kunjungan baru. Prefix aktual tidak dihitung ulang dengan ETA baru.
- Tambah durasi menggunakan `max(sekarang, waktu keluar lama) + 30 menit`. Ketika masih berstatus tiba, projection memperhitungkan tunggu buka dan durasi default tanpa mengarang waktu mulai aktual.
- Hybrid adaptif tetap digunakan. Urutan diterima dihitung ulang terlebih dahulu dan dipertahankan sebagai kandidat; hasil seri mempertahankan urutannya. Tidak ada klaim optimum global.
- Proposal menampilkan jadwal awal, baseline urutan yang sama pada waktu baru, hasil baru, delta, waktu tempuh/tunggu/singgah, konflik dan unknown. Apply memerlukan proposal layak, revision dan sesi yang sama, serta asumsi keberangkatan yang masih berlaku. Toleransi keterlambatan eksperimen: 60 detik sesudah departure projection; controller/domain memeriksa ulang ketika tombol ditekan.
- Aksi mempunyai receipt dan identitas. ID sama/payload sama idempoten; ID sama/payload berbeda ditolak. Request lama, pembatalan, background dan watchdog 90 detik tidak dapat mengganti state terbaru. Kegagalan save mempertahankan state sebelumnya; retry memakai identitas tindakan sama.
- Snapshot planned schema 1 tetap dibaca; mulai trip mempromosikan snapshot ke schema 2 dengan riwayat/proposal. Aplikasi versi P1 yang hanya memahami schema 1 akan menolak schema 2 dan tidak menimpanya. Proposal tersimpan setelah restart harus dihitung ulang sebelum apply.
- Trip aktif mengunci penggantian draft/itinerary. Setelah selesai, pengguna dapat memilih rencana baru. Data uji UI dipisahkan dengan launch argument `--active-ui-testing`; data rencana biasa tidak direset.

## Lingkup eksperimen yang dikunci

Satu hari, satu trip lokal, maksimal 20 tujuan input; satu moda jalan kaki **atau** automobile dengan kebijakan on-demand/taksi. Private car dan transit pada trip aktif ditolak dengan pesan karena posisi kendaraan dan jadwal transit belum dimodelkan. Perhitungan dari tengah perjalanan, GPS otomatis, background tracking, sinkronisasi multi-perangkat, multi-day dan optimasi geometri peta sisa tidak termasuk P2.

Kedatangan/keberangkatan adalah laporan pengguna, bukan bukti keberadaan. Fakta di luar jam diketahui tetap disimpan dengan peringatan; konflik waktu pada sisa rencana mencegah apply sebagai hasil layak. Jam operasional dan cuaca yang tidak diketahui tetap unknown.

## Hasil pengujian

| Lapisan | Hasil teramati | Bukti |
| --- | --- | --- |
| XCTest lokal | **59/59 lulus**, 0 gagal/skip: 24 regresi P0–P1 + 35 P2 | [Ringkasan](native-trip-replanning-2026-11-04/local/summary.json), [log](native-trip-replanning-2026-11-04/local/test.log), [JUnit](native-trip-replanning-2026-11-04/local/junit.xml) |
| Storage lintas proses | Proses tulis berhenti; proses baca memulihkan snapshot | [Log probe](native-trip-replanning-2026-11-04/local/cross-process.log) |
| XCTest Jakarta | **26/26 lulus**, 0 gagal/skip; hash seluruh source yang dikompilasi cocok dengan versi akhir | [Laporan](native-trip-replanning-2026-11-04/jakarta/REPORT.md) |
| Replay berpasangan | **24 kasus × 3 seed × 2 alur = 144 run**, 72 pasangan; 0 error auditor | [Ringkasan](native-trip-replanning-2026-11-04/paired-replay/summary.json), [run lengkap](native-trip-replanning-2026-11-04/paired-replay/runs.jsonl) |
| Pemeriksaan regresi | 18 routing, 6 pipeline, 10 input, 9 log, 8 kelompok cuaca lulus | [Log pemeriksaan](../../../../docs/missing-evidence.md#missing-398b05b6c52c) |
| iOS Simulator | Build akhir berhasil; +30, apply, relaunch, skip C/D, end-only, reject, selesai dan restore diamati | [Catatan UI](native-trip-replanning-2026-11-04/UI.md), [observasi tool](native-trip-replanning-2026-11-04/tool-observations.json) |

Suite P2 mencakup lifecycle/clock, window/deadline, endpoint, prefix tetap, ETA hilang, end-only, mode, revision/freshness/sesi, idempotensi, reject, failure/retry, schema, request A/B terbalik, cancellation dan watchdog. Review menambahkan pemeriksaan ruas aktual harus cocok dengan fakta kunjungan serta anchor terakhir ketika timestamp beberapa kunjungan sama. Lima pemeriksaan lama/regresi berbeda dari XCTest; jumlahnya tidak digabung sebagai satu jumlah tes.

### Fixture empat tujuan: `RPL-04-EXTEND`

Semua tanggal/jam/ETA berikut sintetis, 5 November 2026, Asia/Jakarta. Awal O 08.00; A tiba/mulai 08.10, selesai 08.40; B tiba/mulai 08.50. Jam simulasi 09.00, B awalnya keluar 09.20. Tambah 30 menit menghasilkan **keluar B 09.50**. C dan D masing-masing 30 menit, ruas B→C dan C→D 10 menit, D→O 20 menit. Baseline awal selesai **11.00**; urutan sama setelah perpanjangan dan proposal baru selesai **11.30**. Batas tiba **12.00**.

UI menampilkan perjalanan sisa 40 menit, singgah pending 60 menit, dan total sisa dari 09.00 sebesar 150 menit (termasuk 50 menit tersisa di B). Apply lalu relaunch mempertahankan hasil 11.30, A 08.10–08.40 dan B mulai 08.50. [Screenshot proposal](native-trip-replanning-2026-11-04/screenshots/proposal-1130.jpg).

Sesudah C dan D dikonfirmasi skip, proposal hanya B→O; arc ini sengaja 60 menit pada oracle contoh, sehingga selesai 10.50. Tidak ada stop palsu. Proposal ini diabaikan lewat UI; rencana terakhir 11.30 tetap tersimpan dengan label perlu diperbarui. B kemudian selesai aktual 09.50, tiba endpoint dikonfirmasi 10.50. Restart/build ulang memulihkan A/B completed dan C/D skipped. [Screenshot end-only](native-trip-replanning-2026-11-04/screenshots/end-only.jpg), [hasil akhir](native-trip-replanning-2026-11-04/screenshots/finished-restored.jpg), [snapshot sintetis](native-trip-replanning-2026-11-04/ui-final-session.json).

### Perbandingan baseline dengan adaptif

Baseline berarti **urutan tersisa yang sudah diterima, dihitung ulang pada departure/deadline baru**. Ini berbeda dari jadwal awal yang belum terkena perubahan. Setiap pasangan memakai state, seed, oracle dan budget sama; urutan eksekusi kedua alur bergantian.

| Metrik | Baseline | Adaptif |
| --- | ---: | ---: |
| Run layak / 72 | 66 | 66 |
| Tidak layak pada kedua alur | 6 | 6 |
| Total request ETA simulasi | 234 | 1.269 |
| Request tertinggi per run | 5 | 43 |

Di antara 66 pasangan yang sama-sama layak, **18 lebih singkat, 48 seri, 0 lebih lama**. Pada 18 perbaikan itu, penghematan 0,52–13,10 menit, median 6,20 menit. Keberhasilan menemukan jadwal layak belum meningkat pada dataset ini. Request tambahan menghasilkan tradeoff nyata; data ini tidak membuktikan efisiensi biaya atau kecepatan UI/provider live.

Dataset berisi 16 kasus utama dan 8 tambahan, ukuran awal 2/4/6 tujuan dengan dua kunjungan sudah berjalan, ETA asimetris statis/dinamis, deadline ketat, skip dan end-only. Semua memakai automobile on-demand; mode jalan kaki divalidasi pada domain tetapi manfaat rutenya belum diukur berpasangan di sini. Seed solver 11/67/101. Budget per replan 96 request, 12.000 evaluasi dan 3 detik solver; budget awal menyusun itinerary tidak dicampur ke biaya sisa. Cuaca dinonaktifkan/unknown pada replay.

Auditor Python terpisah dari validator Swift memeriksa setiap candidate lengkap: identitas/himpunan stop, endpoint, ETA sesuai waktu ruas, aritmetika jadwal, window/deadline, prefix aktual tetap, budget, dan baseline tervalidasi tidak hilang. Enumerasi urutan sisa kecil menyediakan acuan tambahan. Tes tidak mengasumsikan semua candidate harus layak; 6 pasangan sama-sama tidak layak tetap dilaporkan. Kasus tambahan bukan studi blind atau validasi lapangan.

## Pemetaan matriks dan batas kelulusan

| Kasus masterplan | Status/bukti pada P2 |
| --- | --- |
| L-01…L-05 | Passed domain/storage: lifecycle, tiba sebelum buka, laporan di luar jam, clock mundur; L-01 diamati UI |
| R-01…R-12 | Passed pada domain/replay; R-01/09/12 juga diamati UI. Prefix tidak berubah, endpoint tetap, baseline/tie, konflik dan end-only diperiksa |
| E-01…E-13 | Passed pada domain/storage/replay: explicit skip, deadline, late start, infeasible/missing ETA, stale date/request/apply, receipt, cancel dan budget. E-02 dipenuhi dengan tidak adanya skip otomatis/fitur saran skip |
| E-14 | Kasus private car dipersempit: ditolak sebelum start/projection; tidak dihitung sebagai bukti kendaraan sudah dimodelkan |
| E-15 | Unknown tetap unknown pada replay aktif dan suite cuaca lama lulus; forecast aktif live/parsial tetap P3 |
| E-16 | Transisi/receipt beruntun diuji domain; stress rapid-tap UI belum dijalankan, **Not run** untuk lapisan UI tersebut |
| E-17 | Restore fakta/accepted plan lulus storage dan stop/relaunch UI; force-quit tepat di tengah request terkontrol diuji melalui cancellation/failure harness, bukan kill saat request live |
| S-06 | Passed: perubahan rencana diblokir selama trip aktif; root UI teramati terkunci |
| S-07 | Passed domain/storage: runtime baru menolak apply proposal lama; UI mempunyai pesan perlu hitung ulang. Restart UI sesi ini dilakukan setelah apply/reject, bukan saat proposal pending |
| V-01 | Alur utama +30/apply dan reject sesudah skip diamati pada Simulator; UI konflik lengkap/aksesibilitas terarah tetap P3 |

Tidak ada klaim seluruh kasus rangkaian PoC sudah dijalankan. G2 lokal ini tidak menggantikan V-02…V-03, N-01…N-11 atau evaluasi pengguna P4. Bukti storage/async tidak disamakan dengan uji jaringan atau iPhone fisik.

## Source, kegagalan dan reproduksi

Checkout: `<LOCAL_HOME>/Programming/software/ios/poc-c67`, branch `gi/itinerary-time-aware`, base `712f036b222839173d7ea82bb736dd57aaeed6f5`. Working tree sudah dirty saat mulai; perubahan lama dipertahankan. Tidak ada commit, push, deploy, perubahan server bersama, atau integrasi Foundation Models. [Manifest awal](native-trip-replanning-2026-11-04/baseline-manifest.json) dan [manifest akhir](native-trip-replanning-2026-11-04/manifest.json) memisahkan bukti ini dari snapshot lama.

Kode utama: `NativeTripActiveTrip`, `NativeTripActivePlanner`, `NativeTripActiveController`, `NativeTripActiveView`; integrasi pada model/view planner, storage dan jalur retained-order pada time-aware planner. Tidak ada perubahan dependency/project build untuk menarik layanan baru.

Host macOS 27.0.1 arm64, Swift 6.4.2; XCTest melalui SwiftPM, mode bahasa Swift 5. Build Debug Simulator iPhone 18 Pro, iOS 27.0, signing dimatikan. Build akhir berhasil; log mentah mempunyai warning metadata App Intents dilewati karena tidak ada dependency framework itu. Tidak ada error build. Awal implementasi sempat gagal kompilasi akibat shadowing `error` dan import WeatherKit pada controller; diperbaiki dan log gagal tetap disimpan di folder `attempts`.

Manifest lokal merekam semua file planner, meskipun hanya daftar tertentu dikompilasi ke harness. Sesudah 59 XCTest lulus, satu perubahan teks status trip selesai pada `NativeTripActiveView.swift` dilakukan; file UI itu tidak dikompilasi oleh harness. Build dan observasi UI akhir memverifikasi perubahan tersebut. Manifest asli hasil tes dipertahankan, dan catatan perbedaan/hash akhir tersedia pada `verification.json`. Manifest replay/Jakarta cocok dengan seluruh source yang mereka kompilasi. Perubahan terakhir runner Python hanya mencegah bytecode cache; log replay berasal dari algoritme/auditor sama.

Jalankan dari checkout, selalu dengan direktori output baru:

```sh
bash scripts/test-native-trip-local.sh /tmp/c67-p2-local-new
bash scripts/test-native-trip-jakarta.sh /tmp/c67-p2-jakarta-new
python3 scripts/benchmark-active-trip.py . /tmp/c67-p2-replay-new
```

Untuk walkthrough, buka menu **Kelola rencana → Muat simulasi trip aktif**, simpan itinerary pilihan, lalu **Mulai / lihat perjalanan**. Pada data biasa, selesaikan trip yang sedang aktif sebelum mengganti itinerary. Gunakan launch argument `--active-ui-testing` bila ingin menyimpan sesi uji secara terpisah. Simulasi diberi label jelas dan tidak meminta provider.

## Langkah berikutnya

P3: jalankan di iPhone fisik dengan MapKit/WeatherKit langsung, backend tim/OpenRouter diblokir, dan catat host/request, latency total, failure, umur ETA, atribusi serta cancellation/fallback. Bandingkan biaya baseline/adaptif pada 15 pasangan awal/replan live yang direncanakan; uji offline/retry, relaunch saat request, UI konflik, Dynamic Type dan VoiceOver. Setelah bukti perangkat layak, lanjutkan P4 untuk menilai pemahaman serta manfaat keputusan pengguna. Eksplorasi Foundation Models tetap jalur teman dan tidak menghalangi langkah ini.
