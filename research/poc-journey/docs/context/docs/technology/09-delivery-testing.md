# 09 — Implementasi, pengembangan dan pengujian

## Pembaruan konteks 29 Oktober — rencana pembuktian engine

Acuan aktif: [engine AI](11-ai-planning-engine.md) dan [validasi baru](../product/ai-trip-planning-validation-plan-2026-10-29.md). Struktur, perintah dan matriks mulai bagian 1 di bawah adalah proposal baseline 0.1. Jangan menganggap seluruhnya perlu dijalankan untuk perubahan dokumen ini atau sebagai instruksi reset target bersama.

Urutan target yang diusulkan: tetapkan input/prioritas dan capability data → buktikan satu perencanaan AI berbasis sumber → periksa kelayakan waktu/fakta → buktikan kasus D/C dan stale result → desain kompatibilitas active-trip → lakukan evaluasi pengguna/lapangan. Kontrak/model/provider dan ambang penerimaan harus dipilih sebelum implementasi yang terkait.

Bedakan fixture/simulasi, request provider nyata, hasil server/native dan observasi peserta. Ukur konflik, sumber yang tidak mendukung klaim, data hilang, latensi dan biaya. Tidak ada benchmark, tes runtime/provider, migrasi atau deployment baru yang dilaporkan melalui pembaruan dokumentasi ini.

[Indeks](README.md) · [API](04-backend-api.md) · [Operasi](08-security-operations.md) · [Keputusan](10-decisions-sources.md)

## 1. Hasil yang dituju

Implementasi dianggap siap untuk pilot teknis ketika alur server+aplikasi dapat direproduksi, invariant dibuktikan dengan tes, kegagalan dapat dipulihkan, data privat tidak terbaca akun lain, dan operasi backup/deletion dapat dijalankan. Keberhasilan teknis tersebut tidak membuktikan kebutuhan pengguna, adopsi, USP atau dampak produk.

Dokumen ini bukan catatan tes yang sudah dijalankan. Semua matriks di bawah adalah rencana penerimaan implementasi.

## 2. Struktur backend usulan

```text
backend/
  supabase/
    config.toml
    migrations/           schema, constraints, functions, grants, RLS
    seed.sql              synthetic fixtures, tanpa data pribadi
    functions/
      c6-api/             versioned request routing dan handler
      job-dispatch/       lightweight jobs/scheduler adapter
      _shared/            auth, schema validation, DTO, errors, telemetry
    tests/
      database/           constraints, RPC, privileges, RLS
      integration/        Auth/API/Storage/job lifecycle
  workers/
    media/                Node + sharp image executor
  contracts/              DTO schema/API contracts ketika diimplementasikan
  scripts/                developer setup, safe fixtures, checks
```

Ini struktur target, belum folder/backend yang dibuat pada pekerjaan dokumentasi. Lokasi repository backend dapat berada di repo yang sama atau repo terpisah; pilih ownership/CI tanpa menggandakan migrasi otoritatif. API contract dan migration history hanya mempunyai satu sumber yang dipelihara.

## 3. Persiapan pengembangan lokal

Prasyarat: Xcode/toolchain yang sesuai, Supabase CLI versi dipin, container runtime untuk local services, serta Node runtime kompatibel dependency worker. Development tidak memakai credential production.

Contoh perintah hanya untuk folder backend lokal baru/terisolasi yang sudah dipilih tim:

```sh
supabase init
supabase start
supabase migration new initial_domain
supabase functions serve c6-api
```

Perintah ini adalah referensi, belum dijalankan. `migration new` hanya membuat file; SQL tetap harus ditulis dari schema reference dan diuji. Configure local Auth/Storage dan environment file yang diabaikan Git. Jangan menaruh output CLI yang berisi secret ke laporan/chat.

Untuk menguji pembuatan schema dari nol, gunakan database disposable dari CI/local khusus test; reset hanya environment tersebut. Jangan menjalankan reset pada workspace yang menyimpan data percobaan berharga atau remote project. Migration workflow resmi dapat berubah, sehingga versi CLI dan bantuan perintah diperiksa pada implementasi. [Database migrations](https://supabase.com/docs/guides/local-development/database-migrations).

App development menunjuk local/staging URL yang sesuai perangkat. `localhost` pada iPhone fisik adalah iPhone tersebut, bukan Mac; gunakan alamat development yang dapat dijangkau dan konfigurasi jaringan yang scoped. Tidak perlu menonaktifkan TLS/policy keamanan secara global untuk production.

## 4. Urutan migrasi dan seed

1. Buat namespace/extension dan tabel inti sesuai dependency.
2. Tambah FK gabungan, constraint status/satuan dan indeks.
3. Tambah tabel upload/idempotency/outbox dan fungsi transaksional.
4. Pasang trigger immutability, ownership dan revision.
5. Tetapkan grants, revoke EXECUTE default yang tidak diperlukan, lalu aktifkan RLS.
6. Seed akun/versi/trip sintetis melalui mekanisme yang sesuai local Auth.
7. Jalankan tes memakai anon/user/server identities yang terpisah.
8. Buktikan schema dapat dibangun ulang dan migration upgrade tidak merusak data fixture lama.

Seed minimal: kreator A/B, traveller X/Y, A-v1/A-v2/B-v1, overlap Asakusa/Shibuya, dua kemunculan place yang sama, trip hari Tokyo, active trip dengan jurnal accepted, session gagal, dan tombstone. Semua lokasi/foto test diberi label fixture/simulasi.

## 5. Tahapan implementasi

| Tahap | Deliverable | Bukti selesai |
|---|---|---|
| T0 — Fondasi | Dependency pin, environment, schema inti, Auth, role/grants/RLS, safe logging | Rebuild DB lokal; login staging; test akses silang akun. |
| T1 — Creator/discovery | Draft/publish/version, search, source metadata | Published immutable; A-v2 terpisah; discovery tidak membocorkan draft. |
| T2 — Trip | Copy, timing, landing, snapshot, revision | Copy atomik; zona benar; retry tidak duplikat; snapshot konsisten. |
| T3 — Journal/album | Draft lokal, ingress, worker, presence protocol, finalisasi dan album | File/presence failures aman; pending bukan sukses; album pemilik. DEC-04/05 harus ditetapkan untuk pilot ini. |
| T4 — Add rundown | Preview/apply manual, atribusi, benturan, plan revision | A+B dapat dipertahankan; konflik/retry/protected visits teruji. |
| T5 — Context | WeatherKit availability, ETA adapter, time rules dan saran deterministik | Source/expiry benar; unavailable tidak membuat data fiktif; saran tidak langsung memutasi. |
| T6 — Operasional | Retention, deletion, backups, restore drill, capacity test | Restore media+DB; deletion tuntas; budget/SLO terukur. |

Local read cache dan draft durability dibangun bersamaan T2/T3, bukan ditunda sampai semua fitur selesai. Group sharing/kontribusi publik/edit offline tersinkron hanya ditambahkan setelah keputusan terkait.

## 6. CI dan pemeriksaan perubahan

Ownership usulan: pengembang iOS memelihara domain/local adapters; pengembang backend memelihara kontrak/API/schema/RLS; penanggung jawab operasi memelihara environment, secret, worker dan restore; keputusan audience/completion/presence/rights ditinjau penanggung jawab produk bersama tim. Ini pembagian tanggung jawab, bukan penetapan nama atau klaim pembagian kerja yang sudah disepakati.

| Area | Pemeriksaan proporsional |
|---|---|
| Domain Swift | Unit test waktu, planner, merge, state transition dan mapping DTO. |
| Local persistence | In-memory/temp store tests, migrasi, file atomicity, relaunch/recovery. |
| TypeScript | Typecheck, schema/handler tests, auth/size/error mapping. |
| Database | Migration rebuild, constraints, RPC atomicity, RLS dan privileges dengan beberapa identity. |
| Media worker | Decoder bounds, corrupt files, metadata removal, lease/idempotency, resource usage. |
| Integration | API+DB+Storage+Auth+worker pada lingkungan terisolasi. |
| Security changes | Tes negatif terhadap direct Data API/Storage/RPC, bukan hanya jalur API normal. |
| Documentation/contracts | Link/fence/JSON check, DTO schema compatibility ketika tersedia. |

Pin runtime/dependency versions dan simpan lockfiles. Migration test memakai role biasa untuk membuktikan akses; admin hanya untuk setup. Secrets CI disimpan pada secret store runner. Deploy staging/production adalah tahap terpisah dari lint/test dan mengikuti otorisasi/target yang benar.

## 7. Matriks penerimaan domain dan database

| ID | Skenario | Hasil yang diharapkan |
|---|---|---|
| D-01 | X meminta trip/jurnal/media milik Y | Ditolak pada API serta jalur data langsung. |
| D-02 | Client mencoba mengubah owner/status/presence decision | Grant/handler menolak. |
| D-03 | Edit/delete child versi published | Ditolak; distribusi tetap bisa diubah lewat command resmi. |
| D-04 | Terbitkan A-v2 setelah trip memakai A-v1 | Trip tetap mempunyai snapshot/sumber A-v1. |
| D-05 | Stop/leg/source dari trip/version lain | FK/validasi transaksi menolak. |
| D-06 | Place sama muncul dua kali | Diperbolehkan dengan stop ID berbeda. |
| D-07 | Kegagalan setelah copy setengah stop | Seluruh copy rollback. |
| D-08 | Reorder menukar posisi | Atomik, unique order tetap valid. |
| D-09 | Dua apply memakai revision sama | Hanya satu diterima; yang lain 409. |
| D-10 | Apply mencoba menghapus documented stop | Ditolak atau diproses menurut policy eksplisit; jurnal tidak hilang. |
| D-11 | Public view/RPC mengakses row privat | Tidak membocorkan data lewat privilege pemilik function/view. |
| D-12 | Source archived/deleting | Perilaku mengikuti policy, tidak cascade ke trip tanpa aturan. |

## 8. Matriks waktu, merge dan integrasi

| ID | Skenario | Hasil yang diharapkan |
|---|---|---|
| P-01 | Perangkat Jakarta membuka jadwal Tokyo | Jam destinasi/instant tetap benar. |
| P-02 | DST missing/ambiguous time | Ditolak atau diselesaikan dengan pilihan eksplisit. |
| P-03 | Window lewat tengah malam/lintas zona | Durasi dan hari tidak salah akibat asumsi 24 jam tetap. |
| P-04 | Leg duration tidak diketahui | Tidak diperlakukan sebagai nol/feasible pasti. |
| P-05 | Merge A+B dengan overlap | Preview menampilkan keputusan; tidak deduplikasi otomatis. |
| P-06 | Preview sudah stale saat apply | Revision/hash validation menolak. |
| P-07 | Cuaca unavailable/stale/outside horizon | Tidak membuat forecast fiktif; trip tetap terbaca. |
| P-08 | Transit detail tidak didukung | Tidak melabeli ETA sebagai itinerary transit lengkap. |
| P-09 | Request provider lama selesai setelah request baru | Hasil lama tidak diterapkan. |
| P-10 | Undo setelah ada jurnal baru | Tidak menghapus fakta kunjungan; tolak/kompensasi terkontrol. |

## 9. Matriks media, presence dan crash

| ID | Skenario | Hasil yang diharapkan |
|---|---|---|
| M-01 | Sampel sebelum tap/challenge, stale, invalid, future skew | Ditolak sesuai policy. |
| M-02 | Accuracy besar/negatif/NaN atau batas radius terlintasi | Tidak dianggap pasti di dalam. |
| M-03 | Pernah tiba lalu transfer baru dari hotel | Ditolak; token kedatangan tidak berlaku. |
| M-04 | Replay nonce/user/session/media berbeda | Ditolak, tanpa efek kedua. |
| M-05 | Putus transfer/close app/lease expiry | Status dapat dipulihkan, tidak ada accepted journal palsu. |
| M-06 | Object tersimpan tetapi DB update gagal | Reconciler/cleanup menangani orphan. |
| M-07 | MIME palsu, file rusak, dimensi besar, multipart berlebih | Ditolak tanpa decode tak terbatas. |
| M-08 | Worker crash setelah output sebelum status | Retry idempotent; output tidak menggandakan entry. |
| M-09 | Media ready, final presence gagal | Tetap pending, draft dipertahankan. |
| M-10 | Final commit, response hilang | Status operation mengembalikan satu hasil diterima. |
| M-11 | Client mencoba direct Storage write/overwrite | Ditolak, termasuk media published/accepted. |
| M-12 | Simulation fixture | Label terpisah; tidak menjadi klaim presence fisik. |

## 10. Matriks lokal dan operasi

| ID | Skenario | Hasil yang diharapkan |
|---|---|---|
| L-01 | Kill setelah file draft ditulis/sebelum metadata selesai | Reconciler aman; draft lain utuh. |
| L-02 | Snapshot parsial/versi lama tiba belakangan | Snapshot valid tidak tertimpa. |
| L-03 | Logout A lalu login B | Cache/draft privat A tidak terbaca/terunggah sebagai B. |
| L-04 | Disk penuh/local DB corrupt | Kegagalan jelas; cache dapat dibangun ulang tanpa membuang draft diam-diam. |
| L-05 | Offline lalu online dari lokasi lain | Bacaan pulih; jurnal tidak auto-submit dengan presence lama. |
| O-01 | Hapus akun saat worker/upload aktif | Akses dibekukan; job/finalisasi tidak menghidupkan data lagi. |
| O-02 | Restore database tanpa objek foto | Drill mendeteksi media hilang; belum dianggap restore sukses. |
| O-03 | Restore DB+Storage lengkap | Mapping/checksum dan authorization sesuai recovery point. |
| O-04 | Retention membersihkan orphan | Tidak menghapus objek yang masih dirujuk/job ber-lease valid. |
| O-05 | Secret/log review | Tidak ada token, signed URL, raw GPS atau konten privat dalam log/repo. |

## 11. Uji perangkat dan kapasitas

Simulator membuktikan logika dan integrasi terkontrol, bukan GPS fisik. Uji iPhone nyata: izin berubah, lokasi tepat/reduced, batas radius, sinyal buruk, foto iCloud yang belum lokal, kamera, disk rendah, app interruption dan clock skew. Catat model perangkat/iOS, kondisi, policy version dan hasil, tanpa menyimpan koordinat personal yang tidak diperlukan.

Load test memakai data sintetis: tentukan jumlah concurrent user/request, distribusi read/write, trip size dan ukuran gambar. Ukur p50/p95/error, query plan, worker memory/CPU, queue lag dan egress. Beban bertingkat menguji backpressure/rate limit; jangan menembakkan load ke production tanpa scope eksplisit.

## 12. Release gate dan handoff

- Stack/dependency/config dipin; schema+seed dapat direproduksi.
- Auth/RLS/storage direct-access tests lulus untuk setiap resource privat.
- Completion, presence timing dan parameter radius/freshness dipilih serta diuji fisik sesuai scope.
- Photo worker/ingress memenuhi batas resource dan recovery; tidak ada klaim exactly-once transport.
- Deletion/source-copy policy dan revocation Apple dapat dijalankan sebelum akun nyata didistribusikan luas.
- Restore drill dan budget/SLO mempunyai bukti; attribution/provider terms ditinjau untuk integrasi yang diaktifkan.
- Deployment target/account/project diperiksa; migrasi memakai expand/contract, rollback plan dan versi client lama yang masih didukung.

Catatan rilis memuat commit/migration versions, environment, tes yang dijalankan, hasil, batas dan keputusan terbuka. Checklist ini adalah kriteria teknis rancangan, bukan bukti deployment atau persetujuan App Review.
