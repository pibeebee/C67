# Hasil eksperimen D — cari lokal, validasi finalis

Implementasi dan benchmark: **6 November 2026 malam, WIB**. Laporan/handoff diselesaikan **7 November 2026**. Source lab terpisah dari aplikasi acuan; belum diintegrasikan ke produk.

## Hasil utama

**Target eksploratif lima tujuan di bawah10 detik tercapai pada simulator:** median D **7,05 detik**, dibanding C **35,85 detik** dalam pasangan kontemporer dengan input sama. Median rasio berpasangan memberi pengurangan sekitar**80,3%** terhadap C.

Seluruh **34 observasi live** selesai,17kasus×2varian. **28 itinerary layak** dan **6 outcome non-ready sesuai kasus**;34/34 lolos auditor independen. Empat belas pasangan itinerary layak mempunyai elapsed trip dan paparan hujan terhitung yang sama. Ini hasil pada katalog/matriks terbatas, **bukan jaminan kualitas sama untuk lokasi/kondisi yang belum diuji**.

| Tujuan | C: batch hybrid (detik) | D: finalis (detik) | Pengurangan paired D/C | Median ETA calls C→D |
| --- | ---: | ---: | ---: | ---: |
| 1 | 2,43 | 2,37 | 3,6% | 2 → 2 |
| 3 | 20,31 | 4,75 | 76,6% | 17 → 4 |
| 4 | 31,18 | 5,89 | 81,1% | 26 → 5 |
| 5 | 35,85 | 7,05 | 80,3% | 30 → 6 |

Tiga pengulangan fresh per keluarga, urutan bergantian CD/DC. Request ETA D=jumlah ruas final:2/4/5/6. Sel ETA D sama dengan call karena tidak perlu matriks; C memakai2/23/39/52cells untuk N1/N3/N4/N5. Pacing1,2detik dan concurrency1 dipertahankan pada keduanya. Percepatan berasal terutama dari **mengurangi jumlah observasi provider yang diperlukan untuk memperoleh kandidat pertama**, bukan menambah resource server.

Pada lima tujuan,120urutan dinilai lokal; satu finalis lolos pada ketiga pengulangan. Tidak ada snapshot ETA penuh pada D. Seluruh14 hasil ready D live memakai satu validasi; jalur repair diuji dengan fault/adversarial lokal, belum terpicu pada matriks live ini.

## Apa yang diimplementasikan

Varian D terdaftar pada kontrak/worker lab. `LabFastPlanner.swift` menghitung semua permutasi sampai6tujuan(≤720urutan), memakai prior jarak/time sederhana dan aturan jam/slot/fullstay. Ranking perkiraan mempertimbangkan feasibility, elapsed+paparan hujan, travel dan tie-break. Tidak ada LLM atau model jalan terlatih.

D lalu meminta ETA Apple secara berurutan pada departure setelah kunjungan sebelumnya; **NativeTripEngine.evaluate dan audit akhir tetap digunakan**. Estimasi lokal tidak masuk cache provider, leg hasil atau label ETA aktual. Jika jadwal gagal, observasi edge mengkalibrasi ranking spekulatif dan urutan lain dipilih; maksimal3validasi. Provider unavailable menghentikan pencarian tanpa mengisi nol atau memberi sertifikat infeasible. Hasil layak pertama dikembalikan.

C tetap engine hybrid/batch yang diuji sebelumnya, dengan precomputed passage E5 yang sama seperti D. Tidak ada cache ETA lintasjob. D tidak belajar dari hasil C pada benchmark; prior tetap dibekukan sebelum run. Private key tetap di Mac.

Ini implementasi inti ide pertama. Prefetch selama form diisi, model traffic terlatih, dan optimasi lanjutan di background dengan tawaran perubahan **belum diimplementasikan**. Tidak ada proposal yang otomatis menimpa accepted baseline.

## Kualitas dan trade-off yang benar-benar diuji

Semua ready mempertahankan tujuan, durasi utuh, sumber jam/session/entry pause, slot15menit, semua ETA final dan deadline kembali. Auditor menghubungkan setiap leg dengan request exact departure/koordinat serta memeriksa cuaca. REV5 memakai accepted baseline varian sendiri dan hanya menambah30menit pada kunjungan terakhir.

Pada14pasangan ready live:

- Selisih elapsed trip D−C **0detik** untuk semuanya; tidak ada quality flag>5menit atau>5%.
- N4: D mempunyai travel sekitar**3,30menit lebih pendek**, diimbangi waiting lebih panjang; finish sama.
- MIX5: D mempunyai travel sekitar**1,72menit lebih panjang**, diimbangi waiting lebih pendek; finish sama.
- Paparan hujan terhitung sama pada setiap pasangan. Ini tidak membuktikan kondisi cuaca aktual di venue.

**Uji adversarial juga membuktikan batasnya:** ketika prior salah tetapi kandidat pertama masih layak, D dapat berhenti pada itinerary dengan elapsed lebih buruk daripada urutan lain. Test ini sengaja diluluskan hanya bila keterbatasan tersebut teramati dan tidak ada klaim optimum. Tidak ada kebijakan yang dapat menjamin kualitas C dari enam panggilan tanpa asumsi tambahan tentang edge yang belum diamati.

Repair diuji dengan edge pertama jauh lebih lambat dari perkiraan sehingga kandidat pertama melewati deadline; D memilih urutan lain dan memvalidasinya. Tes lainnya memeriksa semua ETA unavailable, semua jadwal gagal, batas3validasi, penolakan full-stay, tidak membocorkan prior ke hasil provider, departure aktual, dan720urutan unik.

Replay bersama **34/34** outcome lolos;14pasangan ready mempunyai objective identik dalam1detik. Oracle replay berbasis jarak/time serupa prior D, jadi equality ini mudah dipenuhi dan **tidak dipakai sebagai bukti generalisasi**. Adversarial dan hasil live dilaporkan berdampingan.

## Kasus tambahan

| Kasus | C detik | D detik | Outcome D |
| --- | ---: | ---: | --- |
| REV5 | 35,85 | 7,02 | ready |
| MIX5 | 34,68 | 7,11 | ready |
| TIGHT5 | 0,19 | 0,19 | infeasible_lower_bound |
| SIX | 0,18 | 0,19 | needs_places |
| UNKNOWN | 0,19 | 0,16 | needs_places |

REV5 danMIX5 ready pada kedua varian. TIGHT5 di keduanya ditolak dengan proof450>360menit sebelum ETA. SIX/UNKNOWN memerlukan koreksi fakta/katalog; waktunya bukan waktu itinerary enam tujuan. Semua non-ready tetap masuk denominator34. Accepted baseline C/D tetap N5-R3 revision3 setelah proposal tambahan, bukan otomatis diganti.

## Kesebandingan dan batas bukti

Eksperimen dijalankan pada iPhone18ProMax simulator/iOS27.2 dan server Mac yang sama, konfigurasi Debug, HTTP loopback, E5 aktual, WeatherKit dan Apple Maps REST aktual, tanpa fallback. Satu worker, satu runtime E5, satu provider request aktif. Kedua varian menerima keenam pin nyata yang sama dengan benchmark sebelumnya; tujuan dan koordinat cocok dengan iPhone baseline. Trip7November2026/WIB dan constraint dipertahankan.

Timer client dari create/revise sampai result lengkap diterima dan dipersist. Build/precompute/acceptance dikeluarkan. **Discovery lokasi tidak termasuk timer**; unresolved REST origin/GBK dari eksperimen sebelumnya belum diperbaiki dengan D. Kesimpulan berlaku untuk perencanaan setelah identitas lokasi tersedia.

C menyelesaikan bounded search yang lebih luas; D menyelesaikan validasi finalis layak pertama. Pengurangan latency ditukar dengan cakupan observasi provider yang lebih sempit. Perbandingan ini memang menguji perubahan kebijakan tersebut, bukan speedup untuk jumlah pekerjaan identik.

Provider dapat drift antarrequest. Tidak ada regresi kualitas pada pasangan yang teramati bukan bukti regret nol secara kausal atau optimum global. Tiga pengulangan/katalog lima tempat tidak mendukung p95/SLA/seluruh Jakarta. Tidak ada pengujian perjalanan lapangan atau iPhone fisik pada tahap ini.

## Verifikasi, resource dan penutupan

- **69 tes lokal** lulus:34XCTest(incl7adversarial D)+35Swift Testing warisan.
- Replay34/34, live34/34, enam negative controls auditor ditolak.
- Runtime source tidak berubah setelah manifest live dibekukan; perubahan postprocessing dicatat terpisah.
- Seluruh66hash source/input asli identik. OriginalIntegrationModel masih byte-identik.
- 500panggilan HTTP provider/514ETAcells untuk kampanye live ini, di bawah batas1500/2000;347di antaranya merupakan ETA calls. Ini tidak sama dengan jumlah logical evaluations dan tidak mencakup traffic internal framework.
- Interval sampling maksimum5,08detik, RSS server maksimum326,81MiB. Host dijaga aktif sementara; tidak ada host sleep gap seperti run sebelumnya. Ini bukan kapasitas produksi/energi/RAM iPhone.
- Semua job terminal; accepted baseline terlindungi; server ditutup, token sementara dicabut, pencegah idle sleep dilepas, app simulator asli dipasang dan diluncurkan tanpa uninstall.
- Pemeriksaan layar melalui CUA terhalang Mac terkunci. Tidak ada unlock/bypass dicoba. Kompilasi, eksekusi simulator, status/results lengkap dan audit numerik terverifikasi; **tidak diklaim ada verifikasi visual/interaksi manual untuk build D**.
- Tidak ada homelab, cloud deployment, perubahan source produksi, commit/push atau publikasi.

## Artefak dan reproduksi

- [Kebijakan dan protokol](FAST_D_PROTOCOL_2026-11-06.md)
- [Source planner D](../Sources/PlannerEngine/LabFastPlanner.swift)
- Ringkasan live (original local evidence, omitted from this publication)
- CSV semua observasi (original local evidence, omitted from this publication)
- CSV kualitas per pasangan (original local evidence, omitted from this publication)
- Audit live (original local evidence, omitted from this publication), negative controls (original local evidence, omitted from this publication)
- Manifest sebelum live (original local evidence, omitted from this publication), source manifest (original local evidence, omitted from this publication)
- Verifikasi final (original local evidence, omitted from this publication), log tes (original local evidence, omitted from this publication)
- Audit replay C/D (original local evidence, omitted from this publication)
- [Tes estimasi salah dan keterbatasan kualitas](../Tests/PlannerLabTests/FastPlannerTests.swift)
- [Benchmark A/B/C terdahulu](LIVE_SIMULATOR_BENCHMARK_2026-11-06.md)

`planner-bench fast-replay <folder-baru>` memakai server replay untuk34observasi C/D. `audit.py <folder> --fast` memeriksa replay; `--live --fast` memeriksa hasil aktual, lalu `report-fast.py <folder>` menghasilkan kualitas/latensi pasangan. Setup key/mode server tetap mengikuti SETUP.md; live helper memerlukan manifest baru dengan `comparison: CD`. Jangan mengubah tanggal sumber/fixture untuk membuat data lama tampak baru.
