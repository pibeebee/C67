# Matriks pengujian PoC itinerary native dan replanning

**Tanggal:** 3 November 2026, WIB. **Status:** spesifikasi pengujian seluruh rangkaian; sebagian P0–P1 sudah mempunyai bukti pada [laporan implementasi](../../../../apps/native-routing-lab/docs/verification/NATIVE_LOCAL_P0_P1_2026-11-03.md). Kasus trip aktif/proposal kini mempunyai bukti domain/storage/replay dan walkthrough Simulator; layanan live/pengguna belum dijalankan.  
Rencana induk: [masterplan](native-trip-replanning-masterplan-2026-11-03.md). Hasil dicatat memakai [template laporan](native-trip-replanning-report-template.md).

**Pembaruan hasil 4 November:** [laporan P2](../../../../apps/native-routing-lab/docs/verification/NATIVE_TRIP_REPLANNING_P2_2026-11-04.md) memetakan L-01…L-05, R-01…R-12, E-01…E-17, S-06/S-07 dan V-01 ke bukti serta batasnya. 35 XCTest P2, 24 regresi lokal, 26 Jakarta, 144 run berpasangan; tidak ada error/failure akhir. E-14 dipersempit dengan penolakan private car/transit aktif; E-16 stress UI belum dijalankan; restart UI saat proposal pending dan kill tepat di tengah request live belum diamati. P3/P4 tetap Not run kecuali bagian UI utama V-01 yang tercatat. Kolom hasil yang direncanakan di bawah tetap spesifikasi, bukan klaim semua Passed.

**Kemajuan provider Jakarta build 9:** [laporan perbaikan](../../../../apps/native-routing-lab/docs/verification/JAKARTA_ROUTING_FIX_2026-11-04.md) memuat103 XCTest lulus serta tiga jadwal dari MapKit/Open-Meteo aktual yang lolos auditor independen pada macOS. Kunjungan adalah fakta uji yang diskenariokan. Ini tidak menutup kasus N-01…N-11 yang mensyaratkan iPhone/permission/jaringan dan tidak menandai walkthrough UI lengkap Passed. Rincian J-01…J-06 ada pada [lingkup Jakarta](jakarta-routing-places-scope-2026-11-04.md).

## 1. Cara menggunakan matriks

- **Kritis (K):** pelanggaran dapat membuat rencana/fakta salah, data hilang, atau perubahan tidak sesuai pilihan pengguna. Semua kasus K yang berlaku pada suatu gerbang harus lulus sebelum gerbang ditutup.
- **Utama (U):** perilaku inti/ketahanan yang dibutuhkan untuk penggunaan tahap tersebut. Kegagalan wajib mempunyai keputusan revisi dan dampak yang terlihat.
- **Observasi (O):** pengukuran atau bukti pengguna; tidak dipaksa menjadi unit test biner.
- Status per kasus: `Not run`, `Passed`, `Failed`, `Blocked`, atau `Inconclusive`. Perubahan lingkup yang membuat kasus tidak berlaku ditulis dengan alasannya; tidak dihitung sebagai Passed.
- Kolom oracle menjelaskan sumber pembanding. Jangan memakai angka keluaran fungsi yang sedang diuji sebagai satu-satunya bukti kebenarannya.

## 2. Invariant yang selalu diperiksa

| ID | Aturan |
| --- | --- |
| I-01 | Tujuan selesai dan timestamp aktual tidak diubah oleh replanning/apply |
| I-02 | Setiap tujuan pending yang tidak di-skip hadir tepat sekali; tujuan saat ini tidak dimasukkan kembali sebagai kunjungan baru |
| I-03 | Asal sisa, endpoint trip asal, tanggal layanan dan deadline tetap benar |
| I-04 | Untuk ruas tersedia: tiba = berangkat + ETA; mulai = max(tiba, buka yang diketahui); keluar = mulai + sisa durasi yang sah |
| I-05 | Deadline dan jam tutup yang diketahui dipenuhi untuk kandidat yang dapat diterapkan; konflik/unknown tidak disembunyikan |
| I-06 | Fakta/perubahan yang sudah dikonfirmasi hanya diakui berhasil setelah tersimpan; proposal belum mengganti rencana diterima |
| I-07 | Hasil lama, action berulang, pembatalan dan kegagalan simpan tidak menghasilkan penerapan ganda/salah revision |
| I-08 | ETA/forecast yang tidak ada tetap unknown; nilai nol hanya sah jika datanya memang menyatakan nol |
| I-09 | Request/evaluasi/waktu dibatasi; perhitungan prefix aktual tidak memakai ETA baru |
| I-10 | Trip dapat dipulihkan tanpa server tim/model; metadata sumber dan umur rencana tetap terlihat |

Toleransi aritmetika fixture: maksimum satu detik, dengan perbandingan himpunan ID dan status secara tepat. Untuk prefix, bandingkan nilai field faktual secara kanonis, bukan urutan key JSON.

## 3. Dataset dan oracle

### Fixture pertama: `RPL-04-EXTEND`

Gunakan **lokasi A/B/C/D sintetis** agar jam dan hasil yang diharapkan dapat dihitung tepat. Zona Asia/Jakarta, tanggal contoh tetap, endpoint O, satu moda, ETA berarah statis terlebih dahulu. Waktu contoh adalah data simulasi.

- Mulai O 08.00; A dan B masing-masing direncanakan 30 menit.
- O → A 10 menit; A dikunjungi aktual 08.10–08.40.
- A → B 10 menit; B mulai dikunjungi aktual 08.50; sekarang 09.00.
- Waktu keluar B saat ini 09.20; Tambah 30 menit menghasilkan 09.50.
- B → C 10, C → D 10, D → O 20 menit; C/D masing-masing 30 menit.
- Tanpa perubahan urutan dan tanpa menunggu, baseline baru selesai 11.30: B keluar 09.50 → C 10.00–10.30 → D 10.40–11.10 → O 11.30.
- Jadwal semula tanpa perpanjangan selesai 11.00. Delta keterlambatan adalah +30 menit pada fixture dasar.
- Isi reverse arcs secara eksplisit. Jika ingin hasil dasar tidak di-reorder, atur B → D, D → C dan C → O lebih mahal; simpan nilainya pada fixture. Jangan mengasumsikan simetri.
- Varian deadline 11.45 layak; deadline 11.20 tidak layak pada urutan itu dan perlu diperiksa terhadap seluruh alternatif yang disediakan oracle.
- Varian D buka 11.00 menghasilkan waktu tunggu; hasil dihitung ulang secara independen, tidak menyalin angka dasar 11.30.

Fixture ini menguji aritmetika dan state. Fixture Jakarta ETA rekaman dipakai terpisah sebagai regresi/provenance; tidak mengeklaim jam sintetis A/B/C/D sebagai jam tempat Jakarta nyata.

### Paket replay lanjutan

Rancang setidaknya 16 kasus pengembangan yang mencakup 2/4/6 tujuan, statis/dinamis, jam ketat/longgar, end-only, urutan lama yang masih baik, dan rencana yang mustahil. Untuk perbandingan mutu gunakan tiga seed dan dua arm: **urutan sisa diterima yang divalidasi ulang** versus **replanner hybrid adaptif dengan baseline tersebut**. Itu 96 evaluasi replan, bukan 96 perjalanan independen; perencanaan awal merupakan tahap setup terpisah.

Kedua arm menerima state/asOf/deadline/oracle yang sama, cache awal yang setara dan plafon sama. Ganti urutan eksekusi. Seluruh kandidat lengkap diaudit dengan implementasi penghitung terpisah. Pada ukuran kecil yang memungkinkan, enumerasi menjadi acuan pada model fixture.

Bekukan setidaknya delapan kasus tambahan sebelum penyetelan berikutnya, dengan geometri/jam yang berbeda dan manifest tersendiri. Jika kasus tambahan dipakai memperbaiki kebijakan, labeli sebagai kasus pengembangan sejak saat itu dan tambahkan kasus yang belum digunakan lagi. Jangan mengeklaim holdout tetap independen setelah dipakai menyetel implementasi.

### Dataset layanan dan pengguna

- Live: tiga brief 2/4/6 tujuan, lima pasangan awal/revisi per brief; total 15 pasangan atau 30 operasi planning yang terukur. Skenario fault injection dilaporkan terpisah.
- Field: 2–3 perjalanan terbatas dengan input tujuan dan jam yang diperiksa sebelum berangkat.
- User: usulan 5–8 peserta; brief sama untuk pembanding, urutan penggunaan dibalik, data dianonimkan.

## 4. P0/P1 — basis, deadline, dan penyimpanan

| ID | Prioritas | Kasus/tindakan | Hasil yang harus diperiksa | Tingkat/oracle |
| --- | --- | --- | --- | --- |
| B-01 | K | Jalankan alur native dengan host backend tim dan OpenRouter ditolak | Alur inti tidak mempunyai request wajib ke host tersebut; provider langsung tetap dapat dipakai | Audit konfigurasi + transport terkontrol + UI |
| B-02 | U | Jalankan regresi routing sebelum perubahan | Source/config/hasil basis tercatat; kegagalan lama tidak diklaim akibat perubahan baru | Runner lama + manifest |
| D-01 | K | Deadline 17.00; kandidat selesai 17.10 tetapi masih hari sama | Kandidat tidak bisa diterapkan; evaluator dan optimizer mengenali deadline yang sama | Domain + pipeline + auditor |
| D-02 | K | Deadline sebelum mulai atau melewati hari layanan | Input ditolak dengan pesan yang tepat; deadline tidak diperbaiki diam-diam | Domain |
| D-03 | K | Draft lama tanpa deadline/adaptive field | Dapat dibaca; batas akhir hari lama dan status default terlihat; mobil tidak diaktifkan otomatis | Fixture kompatibilitas |
| D-04 | K | Zona perangkat berubah sementara zona trip tetap | Timestamp/deadline/tanggal operasional tidak bergeser | Clock/calendar test + UI |
| D-05 | K | Endpoint sama dengan origin, lalu endpoint berbeda | Batas akhir mencakup ruas ke endpoint yang benar | Domain + audit ruas |
| S-01 | K | Simpan draft/rencana, hentikan proses, baca dari proses baru | Field rencana, deadline, metadata sumber dan ID tetap sama | Storage lintas proses |
| S-02 | K | Gagalkan simpan fakta/perubahan | UI tidak mengaku berhasil; state tersimpan lama tetap; retry dapat dilakukan | Injected repository failure |
| S-03 | K | Gagalkan simpan apply | Rencana diterima/revision/receipt tidak berubah sebagian; proposal tetap bisa ditinjau | Storage + domain |
| S-04 | K | Primary snapshot rusak; backup valid ada/tidak ada | Pulihkan hanya data valid dengan pemberitahuan atau tampilkan recovery; tidak mengganti diam-diam dengan trip kosong | Storage fixture |
| S-05 | K | Schema version lebih baru daripada yang dipahami | Tidak ditulis ulang/dihapus; error kompatibilitas terlihat | Storage fixture |
| S-06 | K | Buat trip baru ketika satu trip aktif tersimpan | Ada keputusan eksplisit untuk menangani trip aktif; tidak tertimpa diam-diam | UI + storage |
| S-07 | K | Restart ketika proposal belum diterapkan | Accepted plan/fakta dipulihkan; proposal lama tidak auto-apply; ketersediaan proposal diberi status perlu validasi ulang | Storage + UI |

## 5. P2A — lifecycle dan perpanjangan kunjungan

| ID | Prioritas | Kasus/tindakan | Hasil yang harus diperiksa | Tingkat/oracle |
| --- | --- | --- | --- | --- |
| L-01 | K | Mulai trip, tiba, mulai kunjungan, selesai | Transisi sah; maksimal satu current visit; timestamp berurutan; setiap aksi tersimpan | Domain + storage |
| L-02 | K | Tandai mulai stop berikutnya ketika stop saat ini belum diselesaikan | Tidak menghasilkan dua kunjungan aktif; pengguna diberi tindakan yang jelas | Domain + UI |
| L-03 | K | Tiba sebelum jam buka yang diketahui | Actual arrival tersimpan; actual visit start masa depan tidak direka; waktu tunggu tampak | Domain + manual timeline |
| L-04 | K | Laporan aktual berada di luar jam diketahui | Fakta pengguna tidak digeser; konflik/asal laporan terlihat | Domain |
| L-05 | K | Clock mundur atau waktu selesai sebelum mulai | Tidak ada durasi negatif/fakta rusak; input/perubahan waktu perlu diperiksa | Injected clock |
| R-01 | K | Fixture `RPL-04-EXTEND`, Tambah 30 menit pada 09.00 | Keluar B 09.50; baseline selesai 11.30; prefix A tetap; C/D tepat sekali | Auditor independen |
| R-02 | K | Waktu keluar lama sudah lewat ketika tombol +30 ditekan | Tambahan dihitung dari max(now, waktu keluar lama), lalu 30 menit; waktu baru ditunjukkan | Injected clock |
| R-03 | K | Input Keluar pukul lebih awal dari sekarang | Ditolak; waktu yang sudah dijalani tidak dikurangi | Domain + UI |
| R-04 | K | Replan menggunakan origin=current B dan return-to-origin asli O | Ruas akhir kembali ke O; tidak kembali ke B akibat flag origin | Projection + auditor |
| R-05 | K | Prefix selesai mencakup rute dan timestamp aktual | Proposal/apply tidak mengubah field aktual atau meminta ETA untuk menggantinya | Spy provider + snapshot compare |
| R-06 | K | Baseline urutan diterima lebih baik daripada alternatif optimizer | Baseline yang sudah divalidasi dipertahankan pada kandidat dan pemilihan | Replay + auditor |
| R-07 | U | Baseline dan alternatif sama nilainya | Urutan diterima dipertahankan; tidak ada reorder tanpa manfaat pada seri | Replay |
| R-08 | K | Waktu baru menembus jam tutup/deadline | Konflik eksplisit; candidate tidak dapat diterapkan sebagai layak | Replay + UI |
| R-09 | K | Tidak ada pending stop; endpoint berbeda dari lokasi sekarang | Hanya ruas endpoint dievaluasi; tidak membuat kunjungan palsu | Domain + end-only oracle |
| R-10 | K | Tidak ada pending stop dan sudah di endpoint | Dapat menyelesaikan trip dengan aksi pengguna; tidak meminta ETA nol yang tidak perlu | Domain + UI |
| R-11 | K | Perpanjangan disimpan, lalu replan gagal | Pilihan durasi/fakta tetap tersimpan; accepted plan lama tersedia dengan status perlu hitung ulang | Pipeline failure + restore |
| R-12 | K | Review lalu Abaikan proposal | Tidak mengganti accepted plan; fakta/perubahan terbaru tetap ada; label stale sesuai keadaan | Domain + UI |

## 6. P2B — skip, apply, request lama, dan data hilang

| ID | Prioritas | Kasus/tindakan | Hasil yang harus diperiksa | Tingkat/oracle |
| --- | --- | --- | --- | --- |
| E-01 | K | Pengguna mengonfirmasi skip satu pending stop | Event/status skip tersimpan; stop lain tetap wajib; tidak dihitung sebagai selesai dikunjungi | Domain + UI |
| E-02 | K | Proposal menyarankan skip tetapi pengguna belum menyetujui | Himpunan tujuan belum berubah | Domain |
| E-03 | K | Semua pending stop di-skip secara eksplisit | Jalur end-only berlaku; tujuan selesai tetap utuh | Projection + UI |
| E-04 | K | Ubah deadline saat trip aktif | Revision bertambah setelah save; proposal memakai deadline baru; rencana lama ditandai perlu diperbarui | Domain + replay |
| E-05 | K | Terlambat memulai dari origin | Sisa dihitung dari waktu aktual dengan semua tujuan; deadline absolut tidak ikut mundur | Clock + auditor |
| E-06 | K | Tidak ada urutan yang layak pada oracle lengkap | Konflik tampak; pilihan perubahan ditawarkan; tidak ada tujuan/deadline berubah otomatis | Enumerasi kecil + UI |
| E-07 | K | ETA satu ruas wajib hilang | Candidate incomplete; ETA tidak dianggap nol; tidak bisa apply sebagai jadwal baru yang lengkap | Provider stub + auditor |
| E-08 | K | Jam buka/tutup salah tanggal/zona atau hanya satu batas diketahui | Data yang berubah meminta pemeriksaan; sisi unknown tetap unknown | Domain + compatibility fixture |
| E-09 | K | A lambat, input berubah, B selesai dahulu, A selesai terakhir | A dibuang; accepted state dan B tidak ditimpa | Controlled async provider |
| E-10 | K | Proposal sesuai revision tetapi asumsi waktu keberangkatan sudah lewat | Apply meminta refresh sesuai toleransi; tidak menerapkan jadwal yang berangkat di masa lalu | Injected clock |
| E-11 | K | Apply dua kali action ID sama; ID sama payload berbeda | Yang pertama idempoten; yang kedua ditolak; tidak ada event/revision ganda | Domain + storage |
| E-12 | K | Batalkan request atau app masuk background lalu hasil datang | Hasil tidak diterapkan; fakta dan accepted plan tetap | Pipeline + UI lifecycle |
| E-13 | K | Request/evaluasi/budget waktu kecil atau habis | Batas dipatuhi; kandidat valid yang sudah ada dipertahankan; hasil partial tidak dipalsukan lengkap | Replay + counters |
| E-14 | K | Private car tidak berada pada anchor saat ini | Pemakaian tidak diasumsikan tersedia; scope/mode dikonfirmasi sebelum hitung | State validation |
| E-15 | K | Forecast seluruhnya/sebagian unknown | Routing waktu tetap dapat bersyarat; risiko hujan tidak dianggap nol | Weather stub + replay |
| E-16 | U | Rapid tap/perubahan beruntun saat calculating/apply | Hanya aksi valid yang tersimpan; tombol/status tidak menipu atau macet | UI + event trace |
| E-17 | K | Force-quit setelah fakta berhasil disimpan, sebelum hasil tersedia | Restore mempertahankan fakta; request lama berhenti; accepted plan berstatus sesuai | iPhone/Simulator restart + storage |

## 7. P3 — UI, provider, dan iPhone

| ID | Prioritas | Kasus/tindakan | Hasil yang harus diperiksa | Tingkat/oracle |
| --- | --- | --- | --- | --- |
| V-01 | K | Alur empat tujuan +30 menit melalui kontrol UI | Sebelum/sesudah, konflik, Terapkan/Abaikan sesuai state domain | UI Simulator + trace |
| V-02 | U | Dynamic Type ukuran aksesibilitas dan VoiceOver | Tindakan inti dapat ditemukan/dipakai; informasi utama tidak hilang; status tidak hanya warna | Manual UI |
| V-03 | U | Geometri satu ruas peta gagal | Jadwal tersimpan tetap tersedia; ruas lain tetap; retry terbatas | Map adapter + UI |
| N-01 | K | Backend tim ditolak saat awal/replan di iPhone | Alur core live tetap berjalan dengan provider langsung; tidak ada login server wajib | Device + daftar host request |
| N-02 | U | WeatherKit live sukses | Provider, waktu, atribusi dan forecast yang relevan tercatat | Live provider evidence |
| N-03 | U | WeatherKit gagal terkontrol lalu Open-Meteo live | Alasan fallback dan sumber tercatat; cancellation tidak memulai fallback baru | Injection + live request |
| N-04 | K | Kedua provider cuaca gagal | Unknown terlihat; tidak mengisi peluang nol; waktu rencana tidak dibatalkan tanpa alasan | Injection + UI |
| N-05 | K | Offline saat replan | Accepted plan dan fakta dapat dibaca; fakta disimpan lokal; ETA baru tidak direka | Device/network failure |
| N-06 | K | Jaringan pulih, retry, kemudian respons request lama masuk | Hanya request yang sesuai revision berlaku; tidak ada rollback state | Device + controlled response |
| N-07 | K | Izin lokasi ditolak/dicabut atau posisi tidak segar | Pin/konfirmasi lokasi tersedia; tidak memakai posisi lama sebagai fakta sekarang | Device + permission cases |
| N-08 | U | Perangkat/scene background–foreground, kill–relaunch | Tidak ada klaim continuous tracking; state tersimpan kembali; pekerjaan lama tidak apply | Device lifecycle |
| N-09 | O | 15 pasangan awal/replan live sesuai dataset | Semua sukses/gagal, latency, request, cache dan provider tercatat; p90 diberi ukuran sampel | Metrics per operation |
| N-10 | K | Batas operasi total habis | Operasi dihentikan; UI keluar loading; state lama tetap; retry manual mungkin | Slow provider + wall budget |
| N-11 | U | Ekspor ringkas hasil sesi peserta | Field sensitif diminimalkan; sumber/umur data dan kegagalan tetap terlihat | Export inspection |

Sukses N-03 tidak menggantikan N-02. Jika autentikasi WeatherKit terhalang, catat N-02 Blocked beserta sebab; jangan menyatakan rantai fallback lengkap sudah tervalidasi.

## 8. P4 — manfaat dan penggunaan nyata

| ID | Prioritas | Tugas | Observasi yang dicatat | Keputusan |
| --- | --- | --- | --- | --- |
| U-01 | O | Peserta menyusun brief tujuan sendiri melalui cara biasa dan PoC | Waktu, bantuan, koreksi, alat lain yang dipakai | Apakah penyusunan jadwal mengurangi pekerjaan peserta? |
| U-02 | O | Durasi kunjungan bertambah 30 menit pada kedua cara | Kemampuan memperbarui, tujuan/deadline yang terlewat, waktu keputusan | Apakah replanning membantu pada perubahan yang sama? |
| U-03 | O | Peserta menjelaskan proposal dengan kata sendiri | Pemahaman delta selesai, konflik dan unknown | Apakah informasi cukup untuk memilih? |
| U-04 | O | Peserta boleh menerima/menolak/menyesuaikan proposal | Pilihan aktual dan alasan; catat terpisah dari interpretasi tim | Prioritas apa yang belum dimodelkan? |
| U-05 | K | Sesi/perjalanan menemukan konflik atau data hilang | Tidak ada perubahan otomatis atau informasi keterbatasan disembunyikan | Perbaiki sebelum memperluas sesi jika invariant dilanggar |
| U-06 | O | 2–3 perjalanan terbatas | ETA vs actual, akses, stop duration, replans, kebutuhan membuka alat lain | Lanjut, revisi atau persempit scope |

## 9. Gerbang dan format ringkasan hasil

| Gerbang | Kasus minimum | Ketentuan |
| --- | --- | --- |
| G0 | B-01 audit, B-02, keputusan waktu/storage | Inventaris lengkap; celah lifecycle yang memang baru menjadi task P1 |
| G1 | D-01…D-05; S-01…S-07 | Semua K lulus pada domain/storage yang berlaku; UI restore diperiksa |
| G2A | L-01…L-05; R-01…R-12; V-01 | Alur lengkap sampai apply/restore; bukan hanya unit test projection |
| G2 | E-01…E-17 dan regresi lama yang relevan | Semua K lulus; setiap U gagal memiliki keputusan dan dampak yang jelas |
| G3 | V-02/V-03; N-01…N-11 | Invariant K lulus; cakupan provider/device dan latency dilaporkan; blocker provider tidak disamarkan |
| G4 | U-01…U-06 | Bukti observasi dan keputusan dicatat; K tidak boleh gagal; target 80% dianalisis bersama jumlah peserta |

Untuk setiap run, tulis `ID kasus → input/state/asOf → aksi → hasil harapan → hasil aktual → status → tautan bukti → keputusan`. Laporkan jumlah kasus dan jumlah pengulangan secara terpisah. Tes yang sama pada tiga seed bukan tiga hipotesis yang berbeda.
