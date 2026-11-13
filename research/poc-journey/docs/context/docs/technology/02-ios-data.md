# 02 — Aplikasi iOS dan pembagian informasi

## Pembaruan konteks 29 Oktober — data engine AI

Acuan aktif: [engine AI](11-ai-planning-engine.md) dan [domain 0.2](01-architecture-domain.md). Rincian mulai bagian 1 di bawah adalah rancangan 0.1 yang dipertahankan untuk komponen yang masih relevan; nama model/library kreator tidak menjadi requirement baru.

Tambahan target yang diusulkan: input tujuan/preferensi/tanggal/mulai/batas selesai, draft perubahan durasi, identitas request, proposal beserta base revision, alasan/sumber/availability dan rencana terakhir yang dipakai. Pisahkan daftar pilihan pengguna dari kandidat tambahan AI dan bedakan proposal dari fakta perjalanan.

iOS menangani input/tampilan/konteks perangkat; model API dan browser diorkestrasi backend. Jangan menaruh rahasia provider pada aplikasi. Lokasi/preferensi yang dikirim ke backend/model memerlukan kontrak minimisasi/retensi; cara sinkronisasi preferensi belum dipilih. Respons lama tidak boleh menimpa input baru. SwiftData dan struktur folder di bawah tetap usulan, bukan implementasi baru.

[Indeks](README.md) · [Sinkronisasi](06-sync-offline.md) · [Media/lokasi](05-media-location.md)

## 1. Struktur non-UI aplikasi

```text
Domain/
  Models/              RundownVersion, Trip, Stop, Leg, Journal, TimeRule
  Rules/               TimeResolver, PlanValidator, MergePlanner, PresenceEvaluator
Application/
  Services/            RundownService, TripService, JournalService, AlbumService
  Sync/                SnapshotSync, CommandRecovery, CacheManager
Data/
  Remote/              APIClient, AuthAdapter, DTOs, ErrorMapper
  Local/               SwiftData models, LocalStore actor, migration plans
  Files/               DraftFileStore, MediaCache, FileReconciler
Platform/
  Location/            CoreLocation adapter
  Media/               Photo import, normalization, camera adapter
  Places/              MapKit search and directions adapter
  Weather/             WeatherKit adapter
Configuration/         Environment, feature flags, policy versions
```

Ini struktur usulan untuk memisahkan tanggung jawab, bukan permintaan memindahkan file PoC sekarang. Tipe domain menggunakan value types bila sesuai. Objek SwiftData tidak dikirim langsung ke network atau lintas actor; gunakan DTO/value snapshot. Repository dipakai pada batas data yang memang diperlukan, tanpa membuat lapisan generik untuk setiap tabel.

## 2. Inventori kepemilikan data

| Informasi | iPhone | Server C6 | Acuan / lifecycle |
|---|---|---|---|
| Lokasi sesaat | Memori | Sampel minimum saat command memerlukan presence | Perangkat mengukur; server mengevaluasi. Tidak ada logging jejak kontinu. |
| Permission lokasi/kamera | Status OS | Tidak menjadi salinan otoritatif | Baca status saat diperlukan; perubahan OS harus ditangani. |
| Draft foto/cerita | Durable local file + SwiftData | Belum ada sampai intent/upload dimulai | Draft belum terkirim tidak boleh terhapus sebagai cache. |
| Draft perubahan rencana | SwiftData, base revision dan command payload | Hanya hasil yang diterima | Edit offline tersinkron belum baseline. |
| Keadaan proses lokal | Memori/SwiftData | Status operasi server tersedia terpisah | Timeout client bukan bukti gagal server. |
| Preferensi perangkat | Penyimpanan preferensi lokal | Tidak wajib | Satuan/unduhan lokal; preferensi lintas perangkat menjadi scope tambahan. |
| Sesi pengguna | Secure credential storage | Sesi dan identitas Auth | Sesi tidak disimpan di file JSON atau log. |
| Profil | Cache profil yang dibutuhkan | Profil tersimpan | Server; data auth internal tidak masuk cache profil. |
| Rundown versi terbit | Cache versi yang dibuka/diunduh | Isi versi dan distribusi | Server; cache dipatok ke version ID. |
| Places/stop/leg | Snapshot terkait trip/rundown | Data sumber dan snapshot | Perubahan place pusat tidak menggeser pin snapshot diam-diam. |
| Trip/jadwal/atribusi | Snapshot trip milik akun | Aggregate tersimpan | Server revision. |
| Progres terkonfirmasi | Cache | State diterima | Server; spot yang sedang dilihat hanya keadaan lokal. |
| Jurnal diterima | Cache pemilik | Entry dan relasi | Server; pending tetap diberi state berbeda. |
| Foto diterima | Thumbnail/cache atau download eksplisit | Bytes Storage + metadata DB | Tidak perlu mengunduh seluruh foto semua pengguna. |
| Album | Proyeksi lokal dari jurnal/media | Proyeksi terotorisasi | Data yang sama, bukan tabel album duplikat. |
| Cuaca/ETA | Cache berumur terbatas | Opsional, hanya jika dibutuhkan | Provider + interval/waktu fetch; bukan kebenaran permanen. |
| Audit/presence lengkap | Hasil terbatas bila dibutuhkan | Privat server | Retensi minimal; tidak disinkronkan sebagai library. |
| Idempotency ledger | Hanya command ID/payload lokal | Ledger penuh | Server memutuskan apakah efek bisnis sudah diterapkan. |
| Secrets/policy akses | Publishable config dan subset policy untuk validasi awal | Rahasia dan implementasi otoritatif | Keputusan akhir di server. |

## 3. Jenis penyimpanan lokal

| Tempat | Isi | Dapat dibersihkan otomatis? |
|---|---|---|
| SwiftData | Snapshot terstruktur, metadata draft, command recovery, download manifest | Cache terkonfirmasi boleh dievikt; draft/command belum selesai dilindungi. |
| Application Support | Foto draft yang disalin ke ruang app, payload belum selesai dan arsip migrasi | Tidak selama masih diperlukan untuk recovery. |
| Caches | Thumbnail/foto hasil download yang dapat diperoleh kembali | Ya, sesuai kuota lokal. |
| Keychain/secure credential storage | Material sesi pengguna | Hanya mengikuti lifecycle sesi/akun. |
| Memori | Sampel lokasi, hasil sementara, tugas aktif | Ya; kehilangan memori tidak boleh merusak draft durable. |
| Preferensi lokal | Konfigurasi perangkat yang tidak sensitif | Ya sesuai reset preferensi. |

SwiftData menyediakan persistensi model; adapter C6 tetap membuat fetch/save ke Supabase secara eksplisit. Jangan mengaktifkan sinkronisasi CloudKit untuk model trip yang sama sambil menganggap dua backend memiliki otoritas setara. [Persistensi SwiftData](https://developer.apple.com/documentation/swiftdata/preserving-your-apps-model-data-across-launches).

## 4. Model lokal minimum

| Model lokal | Field khusus lokal |
|---|---|
| `CachedRundownVersion` | `account_scope`, `server_id`, `content_hash`, `cached_at`, `access_checked_at` |
| `CachedTrip` | `account_id`, `server_id`, `server_revision`, `snapshot_schema_version`, `last_synced_at` |
| `DraftJournal` | `local_id`, `account_id`, `trip_stop_id`, `base_revision`, `story`, `local_media_paths`, `state` |
| `PendingCommand` | `command_id`, `account_id`, `operation`, `payload_hash`, `payload`, `state`, `attempt_count`, `next_attempt_at` |
| `LocalMedia` | `local_id`, `server_media_id?`, `file_path`, `sha256`, `byte_size`, `kind`, `upload_state` |
| `DownloadManifest` | `trip_id/version_id`, `required_objects`, `optional_media`, `download_state`, `last_verified_at` |

Gunakan relative path terhadap direktori app; jangan menyimpan absolute sandbox path yang bisa berubah. Simpan object path cloud dan media ID, bukan signed URL sebagai identitas permanen. URL sementara diterbitkan ulang saat diperlukan.

Scope akun wajib pada setiap data privat. Pengguna B yang login pada iPhone bekas sesi A tidak dapat membaca cache A melalui query yang kurang filter. Draft milik akun A tidak boleh diunggah menggunakan sesi B.

## 5. File durability

Alur import foto: baca hanya item yang dipilih → normalisasi orientasi/ukuran → tulis ke file sementara → atomic rename ke direktori draft → simpan metadata draft → hapus temporary yang tidak dipakai. Jika save metadata gagal, pertahankan atau tandai file untuk rekonsiliasi; jangan menghapus file milik draft lain.

Pada launch, rekonsiliasi metadata dan file: missing file menjadi error yang dapat dipulihkan, orphan temporary diberi grace period, cache dapat diunduh ulang. Sukses pemilihan foto bukan sukses upload. Ruang disk rendah harus menghasilkan kegagalan eksplisit sebelum draft lama disentuh.

Set file protection dan backup eligibility sesuai klasifikasi: cache unduhan dapat dikecualikan dari backup; draft yang belum terkirim memerlukan keputusan backup/privasi tersendiri. Jangan menganggap sandbox lokal sama dengan backup yang dapat dipulihkan.

## 6. Concurrency dan pembatalan

- Pisahkan operasi IO dan pemrosesan foto dari main actor.
- Local store memiliki isolasi actor/context yang konsisten; perubahan batch snapshot disimpan atomik.
- Satu command bisnis mempunyai satu ID tetap. Pembatalan task client tidak membatalkan transaksi server yang sudah commit.
- Refresh snapshot yang lebih tua tidak boleh menimpa revision lebih baru.
- Location/ETA/weather request mempunyai request identity. Hasil request yang dibatalkan atau superseded dibuang.
- Hentikan pengambilan lokasi yang tidak diperlukan; tidak ada background tracking kontinu pada baseline.
- Saat app kembali aktif, pulihkan sesi, cek pending command, dan ambil pembaruan trip yang relevan.

## 7. Auth adapter

Sign in with Apple native menghasilkan credential yang ditukar melalui Supabase Auth. Terapkan nonce/state sesuai alur SDK yang dipilih; jangan membuat verifier token sendiri berdasarkan decode payload tanpa validasi. Nama dapat hanya tersedia pada otorisasi awal, sehingga profil harus dapat dilengkapi tanpa menganggap nama selalu ada di ID token. [Login Apple di Supabase](https://supabase.com/docs/guides/auth/social-login/auth-apple).

API client melakukan refresh sesi secara terkoordinasi; beberapa request yang menerima expired token tidak memulai refresh paralel tanpa batas. Satu retry setelah refresh diperbolehkan untuk request yang aman/idempotent; kegagalan autentikasi permanen mengakhiri retry otomatis.

## 8. Migrasi dari PoC lokal

PoC yang tercatat menyimpan JSON dan foto lokal, bukan data Supabase. Import ke model baru tidak boleh membuat jurnal lama seolah mendapat verifikasi server.

1. Baca versi arsip dan backup file sumber tanpa mengubahnya.
2. Validasi record/file; import ke namespace `legacy_local`.
3. Pertahankan identitas pin, cerita, waktu dan label simulasi dari data asal.
4. Tandai `verification_origin = legacy_local_unverified`; tidak membuat accepted presence attempt palsu.
5. Verifikasi jumlah record/checksum dan pemulihan sebelum menjadikan model baru aktif.
6. Upload data lama hanya melalui alur yang diizinkan; aturan GPS jurnal tidak dilewati untuk migrasi diam-diam.

Belum ada migrator dalam pekerjaan dokumentasi ini. Kode eksperimen lama tetap dipertahankan sesuai konteks CBL.
