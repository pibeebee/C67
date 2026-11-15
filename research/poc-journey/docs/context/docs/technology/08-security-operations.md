# 08 — Keamanan, privasi dan operasi

## Pembaruan konteks 29 Oktober — API model dan browser backend

Acuan aktif: [engine AI](11-ai-planning-engine.md). Rincian mulai bagian 1 di bawah adalah referensi operasi 0.1; provider AI/browser belum dikonfigurasi oleh dokumen ini.

Rancangan tambahan perlu menetapkan provider/model/versi/routing, data policy, minimisasi koordinat/preferensi, retensi, redaksi log dan rahasia server. Tentukan batas request/token/tool call, timeout, rate limit, retry, budget dan fallback; belum ada angka final atau pengukuran biaya/latensi.

Browser mengumpulkan informasi untuk perencanaan. Isi halaman diperlakukan sebagai data tidak tepercaya, tidak diberi hak mengubah tujuan atau menjalankan mutasi. Pisahkan tools baca dari command penyimpanan; cek kepemilikan/revision di backend. Ketentuan provider untuk cache/atribusi/transfer data ke model perlu diperiksa sebelum integrasi. Runbook, backup dan bukti deploy yang sudah ada tetap mengikuti scope implementasinya.

[Indeks](README.md) · [Database](03-database.md) · [Media](05-media-location.md) · [Delivery](09-delivery-testing.md)

## 1. Trust boundary

| Batas | Ancaman | Kontrol rancangan |
|---|---|---|
| iPhone → API | Actor/pin/status/media palsu | Identitas terverifikasi, schema allowlist, lookup owner/pin server. |
| User A → data B | IDOR, nested resource salah owner | Root authorization, FK aggregate, RLS dan tes silang akun. |
| API → database | Mutasi parsial, injection, bypass function | Parameter binding, RPC terbatas, transaksi dan grants eksplisit. |
| API/worker → storage | Path injection, overwrite, file palsu | Path server-generated, quarantine status, byte/hash/decode validation. |
| Public read → privat | View/URL bocor | DTO/column grants, invoker-aware read, bucket privat, URL TTL. |
| External provider → planner | Data usang/kurang dipakai seolah pasti | Provenance, availability/expiry, deterministic validation. |
| Admin/runtime → secrets | Kebocoran credential melalui log/repo | Secret store, redaction, pemisahan environment dan rotasi. |

Kompromi perangkat tetap dapat memalsukan lokasi yang dilaporkan. App Attest/integrity signal dapat diteliti sebagai defense-in-depth, tetapi tidak diaktifkan atau diklaim sebagai bukti lokasi pada baseline.

## 2. Autentikasi dan otorisasi

Gunakan Sign in with Apple native melalui Supabase Auth. API tidak menerima user ID sebagai bukti login. Token diverifikasi memakai SDK/JWKS/metode yang didukung konfigurasi project; algoritme/issuer/audience harus dipatok. Jangan membiarkan perubahan jenis API key membuat function seolah authenticated tanpa pemeriksaan user JWT.

Account state diperiksa untuk command dan read privat. Suspension/deletion dapat memerlukan penolakan segera meskipun JWT belum expired; RLS/helper dan handler harus memakai state server. Session refresh dan revocation mengikuti layanan Auth, bukan hanya menghapus token lokal. [Sessions](https://supabase.com/docs/guides/auth/sessions).

Satu akun dapat menjadi kreator/traveller tanpa role eksklusif. Admin adalah claim/assignment yang hanya bisa dikelola server; user-editable profile metadata bukan sumber admin privilege.

## 3. Secret dan konfigurasi

| Material | Lokasi |
|---|---|
| Supabase URL/publishable key | Konfigurasi aplikasi per environment; bukan admin credential. |
| User session material | Secure storage perangkat sesuai lifecycle SDK/Keychain. |
| Backend secret key / DB privileged connection | Secret store server, tidak didistribusikan dalam app. |
| Worker credential | Secret store executor, akses dibatasi dan diaudit. |
| Apple signing/revocation material | Secret store server sesuai kebutuhan integrasi; bukan profil publik. |
| WeatherKit native entitlement/config | Project Apple yang sesuai environment. |
| WeatherKit REST signing key bila dipakai | Server secret store. |

Publishable key mengidentifikasi aplikasi/project; user JWT dan RLS membatasi akses. Secret key melewati RLS dan tidak boleh dikirim ke client. Gunakan nomenklatur publishable/secret yang direkomendasikan saat provisioning, bukan menyalin legacy key dari contoh lama. [API keys](https://supabase.com/docs/guides/getting-started/api-keys).

Tidak ada credential nyata dalam dokumentasi. Jangan mencatat header Authorization, nonce, signed URL, foto, cerita privat atau raw coordinate pada log umum. Dukungan debug memakai safe identifiers dan error code.

## 4. Akses database dan storage

Aktifkan RLS pada tabel yang diakses client, batasi column grants, dan cabut INSERT/UPDATE/DELETE langsung pada field/domain server-managed. Test RLS lewat request nyata dengan user tokens; koneksi admin yang bypass RLS tidak membuktikan policy benar.

Private schema tidak diekspos Data API. Server-only RPC mencabut EXECUTE untuk PUBLIC/anon/authenticated. Function definer memerlukan owner terbatas, empty search path dan explicit authorization. RLS metadata aplikasi tidak otomatis melindungi file; storage.objects mempunyai kebijakan sendiri. [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [Storage access control](https://supabase.com/docs/guides/storage/security/access-control).

Buckets usulan: `journal-media`, `creator-media`, `profile-avatars`, semuanya privat pada baseline. Jurnal tidak memberi direct client write. Creator/avatar upload boleh memakai jalur terotorisasi khusus; path owner dan parent diperiksa. Read creator content mengikuti distribusi; read jurnal mengikuti owner sampai audience contribution dipilih.

## 5. Retensi dan minimisasi

Angka berikut **kandidat operasional untuk review**, belum keputusan retensi produksi atau penilaian hukum. Tetapkan sebelum menyimpan data nyata.

| Data | Kandidat baseline | Catatan |
|---|---|---|
| Raw sampel GPS pengguna | Hanya memori request | Tidak merekam continuous trace. |
| Hasil presence minimum | 7 hari | Distance/accuracy/policy/reason; perpanjangan memerlukan tujuan jelas. |
| Upload belum accepted | Session maksimum 24 jam; cleanup setelah lease/grace aman | Tidak membersihkan job/transfer yang masih memiliki lease valid. |
| Raw input sesudah canonical tervalidasi | Hapus lewat job dalam 24 jam | Canonical output sesuai kebijakan konten pengguna. |
| General diagnostic/audit logs | 30 hari | Tanpa isi privat/credential. |
| Receipt idempotency | Minimum recovery window, kandidat 90 hari | Key expiry harus selaras kebijakan retry; client lama tidak replay tanpa rekonsiliasi. |
| Trip/jurnal accepted | Sampai dihapus/policy akun | Hak salinan, audience dan export perlu keputusan. |
| Cuaca/ETA cache | Sesuai validitas dan ketentuan provider | TTL final bukan angka universal. |
| Backup | Jadwal/retensi paket + kebijakan tim | Penghapusan pada backup mengikuti siklus dan kontrol akses. |

Retention job mencatat counts/safe outcome; jangan mereplikasi data yang dihapus ke audit tanpa alasan. Device cache mempunyai quota dan eviksi; draft belum terkirim terlindungi dari eviksi cache.

## 6. Penghapusan akun dan konten

Penghapusan bukan sekadar `DELETE auth.users`. Alur server:

1. Verifikasi actor dan autentikasi ulang yang sesuai, terima request idempotent.
2. Tandai account deleting; hentikan mutasi baru dan penerbitan download baru.
3. Buat deletion job yang dapat dilanjutkan dari checkpoint.
4. Batalkan upload/jobs yang belum final dan bersihkan objek sesuai lease.
5. Hapus trip/jurnal/media pribadi serta avatar; proses source content/attribution sesuai policy yang disepakati.
6. Lakukan revocation provider Apple yang berlaku dan hapus material credential yang tak lagi diperlukan.
7. Hapus identitas Auth ketika storage/business dependencies telah ditangani; verifikasi hasil.
8. Bersihkan cache lokal pada client yang terhubung; simpan receipt minimum yang memang diperlukan.

Integrasi native ID-token login tidak boleh diasumsikan otomatis menyediakan seluruh material revokasi Apple kepada backend. Spike harus menetapkan pemilik penukaran authorization code/token, penyimpanan privat dan cara revoke. Jika token tidak tersedia, ikuti mekanisme yang didukung Apple sambil tetap memenuhi permintaan penghapusan; jangan menahan penghapusan tanpa batas. [Apple TN3194](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple), [Supabase user management](https://supabase.com/docs/guides/auth/managing-user-data).

Hak salinan source saat kreator menghapus akun adalah DEC-06. Publikasi untuk pengguna nyata belum boleh diluncurkan sebelum policy source/copy/deletion dapat dijalankan. Snapshot tidak dijadikan alasan menyimpan nama/konten pribadi tanpa batas. Kebijakan yang dipilih dapat memakai redaction lineage atau purge sumber terkontrol sambil menjaga konsistensi trip.

## 7. Environment dan konfigurasi operasional

Pisahkan development lokal, staging dan production: Supabase project, bucket, Apple identifiers/config, secrets, logs dan synthetic accounts. Tidak ada data production di seed/fixture. Client build menyebut environment secara deterministik; project URL bukan dipilih dari input pengguna.

Konfigurasi server versioned: API version, presence/completion policy, upload limits, rate limits, retention, job lease, cache expiry dan feature gates. Simpan nomor versi policy pada event penting. Perubahan policy harus dapat diaudit dan memiliki rollback yang tidak membuat accepted history menjadi palsu.

Region dipilih dari pengguna awal, latency, kebutuhan data dan availability layanan; belum ditetapkan. Pilihan paket/vendor diperiksa saat provisioning. Backup/restore dan egress budget tetap tanggung jawab tim meskipun backend terkelola.

## 8. Observability dan SLO kandidat

| Sinyal | Dimensi aman |
|---|---|
| API latency/error | Route, status/error code, environment, request ID |
| Command conflict/retry | Operation, outcome, jumlah attempt; tanpa payload privat |
| Media pipeline | Bytes, queue age, lease expiry, validation failure code |
| Presence | Decision/reason agregat, policy version; tanpa raw GPS |
| Sync | Snapshot size, outdated response count, conflict count |
| Provider | Availability/error/rate-limit, request count |
| Deletion | Job age, checkpoint, safe remaining counts |

Target awal untuk diuji, bukan SLA vendor: metadata API p95 < 1 detik pada beban pilot yang didefinisikan; job media normal p95 < 30 detik; RPO data tersimpan <= 24 jam dan RTO <= 8 jam. Batas upload dipantau terpisah dari latency metadata. Jika hasil load/restore test tidak memenuhi, revisi target/arsitektur sebelum menjanjikannya.

Alert pada lonjakan 5xx, queue age/failed jobs, cleanup tertinggal, deletion job macet, biaya/egress melampaui budget, auth failures dan provider quota. Jadwal/threshold alert dipilih ketika pilot mempunyai trafik; jangan membuat notifikasi per request normal.

## 9. Backup dan restore

Backup database **tidak mencakup bytes object Storage**, hanya metadata terkait. Rencana recovery wajib mencakup objek media dan mapping-nya secara terpisah. [Supabase backups](https://supabase.com/docs/guides/platform/backups).

Runbook restore:

1. Tentukan recovery point dan scope insiden; hentikan penulis hanya bila diperlukan.
2. Restore database ke lingkungan terisolasi, bukan langsung menimpa production.
3. Restore/verifikasi objek media dari backup/inventori terpisah dengan path+checksum.
4. Terapkan grant, secret configuration dan runtime version yang cocok.
5. Rekonsiliasi pending upload, outbox, tombstone dan deletion job agar pekerjaan lama tidak diputar ulang tanpa validasi.
6. Uji login, akses silang akun, trip snapshot, album dan media sebelum cutover.
7. Catat recovery time dan data gap nyata; RPO/RTO dinilai dari bukti tersebut.

Backup terenkripsi dan aksesnya terbatas. Export credential/token bukan bagian backup dokumen biasa. Restore tidak dianggap sukses hanya karena SQL import selesai.

## 10. Incident handling

| Insiden | Respons awal |
|---|---|
| Secret bocor | Cabut/rotasi secret, hentikan akses terkait, audit pemakaian dan deploy konfigurasi baru. |
| Akses privat bocor | Batasi route/policy, hentikan penerbitan URL, identifikasi objek terdampak dan TTL akses lama. |
| Queue media macet | Pause intake bila perlu, periksa lease/poison job, retry terbatas; jangan mark ready tanpa validasi. |
| Data trip salah | Hentikan command penyebab, identifikasi revisions/event, buat repair transaksional yang dapat ditinjau. |
| Storage orphan membesar | Jalankan reconcile dalam dry-run/inventori dahulu, lalu cleanup yang hanya menyentuh orphan terkonfirmasi. |
| Provider down | Nonaktifkan saran yang bergantung data baru, pertahankan trip/draft, backoff terukur. |

Runbook produksi baru dieksekusi dalam scope yang diotorisasi. Dokumen ini tidak melakukan perubahan akun, provisioning atau deployment.

## 11. Kapasitas dan biaya

Modelkan biaya dari MAU, database compute/storage, retained image volume, thumbnail, egress/download ulang, invocation, worker runtime dan request provider. Bukan hanya jumlah row.

Contoh asumsi untuk perhitungan, bukan proyeksi adopsi: 1.000 trip/bulan × 4 foto × 1 MB canonical ≈ 4 GB foto baru/bulan, belum thumbnail/input sementara/backup. Jika setiap foto dibaca 5 kali, transfer canonical saja ≈ 20 GB/bulan sebelum cache. Gunakan satuan decimal secara konsisten atau nyatakan GiB bila memakai binary.

Batasi ukuran file/jumlah stop/page size, cache thumbnail, hitung ulang ETA/cuaca hanya saat input relevan berubah, dan ukur read amplification. Harga, kuota gratis, disk region dan biaya container host belum dihitung; gunakan harga resmi saat keputusan provisioning dibuat.
