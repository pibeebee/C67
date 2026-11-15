# P0–P1 native itinerary — hasil implementasi dan verifikasi

**Tanggal:** 3 November 2026, WIB. **Status:** selesai untuk audit/fondasi lokal P0–P1; replanning aktif P2 belum diimplementasikan.  
**Repository:** `<LOCAL_HOME>/Programming/software/ios/poc-c67`, branch `gi/itinerary-time-aware`.  
**Source:** working tree, base commit `712f036`; belum commit/push/deploy baru.

P0 dan P1 menghasilkan planner yang membuka jalur native tanpa bootstrap database rombongan lama, batas tiba di endpoint yang diterapkan lintas routing, serta penyimpanan draft dan itinerary pilihan secara lokal. **24 XCTest baru dan 26 XCTest Jakarta lulus**. Penyimpanan/pemulihan lintas proses dan walkthrough iPhone 18 Pro Simulator iOS 27.0 juga berhasil. Ini belum membuktikan routing offline baru, layanan provider live, atau replanning saat trip aktif.

## Yang berubah

- **Peluncuran:** default membuka planner native langsung. `--native-itinerary` tetap tersedia; flag legacy/diary dan jalur pengujian lamanya tetap diarahkan melalui bootstrap lama. Pilihan launch diuji dengan input flag terstruktur. Data legacy tidak dimigrasi atau dihapus.
- **Deadline:** `finishBy` opsional berarti sudah tiba di titik akhir, termasuk ruas pulang. Deadline harus setelah berangkat dan tidak melewati akhir hari trip. Evaluator, bridge snapshot dan screening adaptif memakai timestamp yang sama. Draft lama tanpa field tersebut mempertahankan batas akhir hari yang terlihat di UI.
- **Zona waktu:** perubahan zona trip secara eksplisit mempertahankan jam lokal mulai dan deadline; perubahan zona perangkat tidak mengubah timestamp/format zona trip. Jam operasional tetap membutuhkan pemeriksaan tanggal/zona yang sudah ada.
- **Draft dan pilihan:** tombol Simpan draft menyimpan input yang boleh masih belum lengkap. Simpan itinerary pilihan membutuhkan kandidat lengkap yang memenuhi batas diketahui dan konfirmasi penggantian. Edit/new/import tidak langsung menghapus itinerary pilihan sebelumnya.
- **Snapshot lokal:** schema version 1, ID, revision, waktu simpan, draft, dan accepted report. Report menyimpan urutan/ruas/waktu, ETA, sumber/umur cuaca, unknown/conflict, dan URL atribusi Apple Weather. Objek layanan/peta hidup tidak diserialisasi.
- **Validasi simpan/buka:** itinerary pilihan diperiksa kembali terhadap tujuan, endpoint, waktu per ruas, total durasi, deadline/jam tutup, moda dan strategi mobil pribadi. Data jam yang unknown tetap bersyarat.
- **Penulisan:** satu jalur main-actor, expected ID/revision, backup nilai terakhir yang sudah valid, lalu atomic write primary. UI mengakui sukses setelah commit; simpan gagal mempertahankan state tersimpan/revision dan memungkinkan retry.
- **Pemulihan:** launch memuat data lokal; primary rusak/hilang dapat memakai backup valid dengan pemberitahuan. Data rusak tanpa backup dan schema lebih baru memblokir overwrite; berkas tidak diganti otomatis dengan trip kosong.
- **Diagnostik:** contoh sintetis eksplisit dan kegagalan satu simpan tersedia untuk verifikasi UI. Keduanya tidak menjadi fallback provider live.

## Hasil pengujian

| Jenis bukti | Hasil | Lingkup |
| --- | --- | --- |
| XCTest P0/P1 baru | **24/24 lulus**, 0 gagal/skip | Deadline, launch, storage, restore, validasi report, failure, stale writer dan metadata |
| XCTest Jakarta | **26/26 lulus** | Regresi routing hybrid adaptif dan jadwal dengan replay yang sama |
| Probe lintas proses | **Write/read lulus** | Proses penulis berhenti, proses lain memulihkan snapshot |
| Harness routing | **18/18 lulus** | Evaluator/solver lokal |
| Harness pipeline | **6/6 lulus** | Pipeline deterministik, request, cancellation |
| Harness input | **10/10 lulus** | Kompatibilitas input/moda |
| Harness log | **9/9 lulus** | Persistensi dan failure log, termasuk lintas proses |
| Harness cuaca | **8 kelompok lulus** | Adapter/fallback dan respons URLProtocol, tanpa provider live |
| Build/launch Simulator | **Berhasil** | Xcode 27.1; iOS Simulator 27.0 arm64; signing dinonaktifkan; target minimum tetap iOS 18 |
| Native Swift format, shell syntax, diff whitespace | **Lulus** | File fitur native/test yang berubah; app entry mempertahankan style historis |

Ada **50 XCTest**; jumlah tersebut tidak digabung dengan kelompok harness, build atau tindakan UI menjadi satu angka tes. Build mempunyai satu warning tooling `Metadata extraction skipped, no AppIntents.framework dependency found`; tidak ada error kompilasi.

[Manifest source/lingkungan](native-local-p0-p1-2026-11-03/manifest.json), [ringkasan 24 tes](native-local-p0-p1-2026-11-03/P1-local/summary.json), [JUnit lokal](native-local-p0-p1-2026-11-03/P1-local/junit.xml), [log lokal](native-local-p0-p1-2026-11-03/P1-local/test.log), [probe lintas proses](native-local-p0-p1-2026-11-03/P1-local/cross-process.log), dan [laporan Jakarta](native-local-p0-p1-2026-11-03/jakarta/REPORT.md).

SwiftPM tidak selalu menulis xUnit untuk XCTest pada host ini. Runner lokal membangun JUnit/ringkasan dari event console aktual jika perlu, lalu memeriksa jumlah kasus/failure terhadap suite summary. Ini konversi bukti run, bukan hasil tes yang diisi manual. Hash source manifest lokal/Jakarta diperiksa terhadap checkout final.

## Walkthrough UI yang diamati

1. Membuka planner, memeriksa kontrol deadline eksplisit dan menyimpan draft. Deadline 12.00 WIB pada contoh berikut juga dipulihkan dari data tersimpan.
2. Memilih menu **Kelola rencana → Muat simulasi penyimpanan**, lalu mengonfirmasi. Input sintetis empat tujuan tidak otomatis mengganti file tersimpan.
3. **Simpan itinerary pilihan → konfirmasi** menghasilkan tautan Itinerary tersimpan dan waktu simpan.
4. Membuka Itinerary tersimpan menampilkan 50 menit perjalanan + 120 menit singgah = **170 menit**, mulai 07.00, selesai 09.50, deadline 12.00 WIB; semua lokasi dan ETA diberi label sintetis dan request ETA nol.
5. **Uji penyimpanan lokal → Gagalkan satu simpan berikutnya → Simpan draft** menampilkan kegagalan, tanpa mengganti waktu simpan lama. Retry berhasil dan memperbarui waktu simpan.
6. Stop/launch app dan build/launch ulang memulihkan itinerary pilihan serta waktu simpan. Peluncuran default tanpa argumen khusus juga membuka planner dan hasil tersimpan.
7. **Rencana baru → konfirmasi** mengubah input menjadi kosong dengan status belum disimpan, sementara tautan itinerary pilihan lama tetap tersedia. Relaunch memulihkan draft yang terakhir benar-benar disimpan.

[Bukti semantic snapshot UI](native-local-p0-p1-2026-11-03/ui/observations.json), [tampilan itinerary sintetis](native-local-p0-p1-2026-11-03/ui/saved-itinerary.jpg), [tampilan kegagalan simpan](native-local-p0-p1-2026-11-03/ui/save-failure.jpg), dan [log build](native-local-p0-p1-2026-11-03/checks/ios-build.log).

Snapshot yang belum settle pada salah satu tap diambil ulang sebelum tindakan berikutnya; status tap saja tidak dijadikan bukti perubahan UI. Tidak membuka peta untuk meminta geometri atau menjalankan provider live pada walkthrough ini.

## Hasil P0: dependensi dan batas kemandirian

| Area | Temuan |
| --- | --- |
| Jalur native | Tidak membutuhkan auth/OpenRouter/API backend tim untuk input, perhitungan native dan penyimpanan lokal |
| Root app historis | Sebelumnya bootstrap controller/database rombongan sebelum planner; sekarang jalur native melewatinya |
| Storage/log | Application Support lokal; dapat digunakan tanpa server tim; uninstall menghapus data app |
| ETA/pencarian/geometri | Tetap bergantung MapKit/network saat mengambil data baru |
| Cuaca | Tetap WeatherKit dengan cadangan Open-Meteo; unknown dipertahankan jika gagal |
| Legacy CloudKit | Tetap milik fitur historis; tidak menjadi bootstrap wajib planner native |
| Sistem/provider | Signing, OS, entitlement, atribusi, kuota dan ketersediaan provider tetap dependensi distribusi |

P0 menggabungkan audit call path dengan tes domain/storage tanpa transport dan UI sintetis. **Tidak ada pemblokiran host backend pada jaringan iPhone fisik atau acceptance provider live dalam pekerjaan ini.** Pengujian runtime host-blocking dengan provider nyata tetap dibedakan dari bukti kemandirian kode lokal. Tidak mematikan server bersama dan tidak memakai key model.

## Temuan yang diperbaiki

- Regresi Jakarta awal: 25/26 lulus; satu tes memeriksa pesan konflik akhir hari lama. Semantik constraint benar tetapi teks kompatibilitas berubah. Pesan lama dipertahankan untuk `finishBy == nil`, lalu 26/26 lulus. [Bukti run awal](native-local-p0-p1-2026-11-03/initial-jakarta-failure/test.log).
- Pemeriksaan log baseline pertama gagal di sandbox karena plugin macro Observation tidak dapat berjalan. Run dengan akses build yang sesuai lulus; ini dicatat terpisah dari kegagalan source. [Baseline](../../../../docs/missing-evidence.md#missing-d7accb313e91).
- Status sukses lama dibersihkan ketika draft diganti atau simpan gagal, agar UI tidak memberikan dua pesan yang bertentangan.
- Komentar recovery diperbaiki agar lulus aturan formatter; perubahan ini tidak mengubah kebijakan recovery.

## Hubungan dengan masterplan

- **G0/P0:** audit/basis selesai, source awal disimpan beserta daftar perubahan yang sudah ada. Tidak mengulang kompetisi algoritma.
- **G1/P1:** selesai untuk planned draft/accepted itinerary, deadline, simpan/pulih dan failure yang relevan.
- Kasus S-06 diuji sebagai perlindungan **rencana tersimpan** ketika input baru dimuat. Perjalanan yang benar-benar berstatus aktif belum ada pada fitur ini.
- S-07 untuk proposal belum diterapkan, lifecycle kunjungan, perpanjangan, skip, revision/apply proposal dan 68 kasus keseluruhan tetap milik P2 dan seterusnya. Tidak dilaporkan Passed pada tahap ini.
- Tidak ada perubahan/deployment ke repo C67 terpisah, backend bersama atau eksplorasi Foundation Models.

## Batas yang tersisa

Penyimpanan bersifat eksplisit melalui tombol, satu dokumen lokal dengan satu backup. Bukan sinkronisasi, multi-process transactional store, atau backup cloud. Draft yang diubah tetapi belum disimpan dapat hilang ketika proses dihentikan; UI menampilkan statusnya. Backup dapat lebih lama daripada primary. File yang tidak dapat dipulihkan dilindungi; belum ada UI untuk mengekspor/mereset file corrupt secara selektif.

Layanan live, iPhone fisik, pengukuran latensi/trafik/kuota provider, VoiceOver menyeluruh, dan pengguna/lapangan belum diuji. Membaca ulang ETA rekaman tidak menjadikannya kondisi terbaru. Penyimpanan atribusi diuji dengan data fixture, bukan acceptance WeatherKit live.

Algoritma tetap hybrid adaptif. Penambahan deadline tidak menjadi klaim optimum global. Pengujian replay lama tetap relevan sebagai regresi, sementara manfaat replanning dan ketepatan perjalanan aktual belum dibuktikan.

## Cara mencoba dan reproduksi

Buka proyek PoC dan Run. Planner native sekarang merupakan jalur default. Untuk uji tanpa provider: **Kelola rencana → Muat simulasi penyimpanan → konfirmasi → Simpan itinerary pilihan → konfirmasi**. Tutup/buka app dan pilih Itinerary tersimpan. Jangan tekan Hitung itinerary/Peta untuk menganggap itu uji tanpa jaringan; tindakan tersebut dapat meminta provider nyata.

Dari root repo, gunakan direktori output baru:

```sh
bash scripts/test-native-trip-local.sh /tmp/c67-local-new
bash scripts/test-native-trip-jakarta.sh /tmp/c67-jakarta-new
bash scripts/check-native-trip-routing.sh
bash scripts/check-native-trip-pipeline.sh
bash scripts/check-native-trip-input.sh
bash scripts/check-native-trip-logs.sh
bash scripts/check-native-trip-weather.sh
```

Runner memakai Swift/Xcode lokal; plugin macro memerlukan izin proses build yang sesuai. Raw data sintetis, manifest dan log disimpan bersama laporan. Source belum di-commit; pekerjaan berikutnya adalah P2A sesuai masterplan, bukan bagian terselesaikan oleh laporan ini.

## Pemeriksaan limit

Pemakaian 5H diperiksa pada checkpoint: 9%, 18%, 25%, 27%, 32%, 40% dan 47% terpakai. Karena pekerjaan selesai sebelum mendekati batas, tidak dibuat timer/scheduler kelanjutan dan tidak memakai kredit reset. Angka berlaku pada akun saat checkpoint, bukan pengukuran biaya satu fitur.
