# 04 — Backend dan kontrak API

## Pembaruan konteks 29 Oktober — operasi perencanaan AI

Acuan aktif: [engine AI](11-ai-planning-engine.md). Base URL dan 34 route usulan mulai bagian 1 di bawah adalah proposal 0.1; bukan API baru yang tersedia, kontrak AI final atau daftar RPC yang berjalan.

Operasi target secara konseptual: meminta kandidat tambahan, meminta rencana dari tujuan/preferensi/waktu, memperoleh hasil/status proposal, menghitung ulang dari perubahan selama trip, dan menerapkan pilihan yang diizinkan. Nama endpoint, sync/async transport, payload, error dan policy review/apply belum ditentukan.

Kontrak baru perlu membawa identitas request, account scope, versi input/preferensi, base plan revision, data/sumber/ketidakpastian dan dampak perubahan. Pengambilan data/browser/model terjadi di luar transaksi penyimpanan yang dikunci. Recheck revision dan retry identity sebelum mutasi. Jangan diam-diam mengubah arti RPC source-version lama; OpenAPI di repository C67 tetap acuan runtime sampai ada perubahan implementasi yang diuji.

[Indeks](README.md) · [Database](03-database.md) · [Upload](05-media-location.md) · [Sync](06-sync-offline.md)

## 1. Transport dan batas API

Base URL usulan:

```text
https://<project-ref>.supabase.co/functions/v1/c6-api/v1
```

Route di bawah adalah API aplikasi yang harus diimplementasikan. Supabase tidak otomatis membuat route custom ini. Supabase Auth tetap memakai SDK/endpoint Auth resmi. Read sederhana boleh memakai Data API dengan RLS; `get_trip_snapshot` dan command lintas tabel memakai RPC terkontrol. Jangan menduplikasi implementasi business rule pada dua jalur tulis.

- HTTPS; JSON UTF-8 untuk metadata, multipart untuk bytes foto.
- Timestamp RFC 3339 ber-offset/UTC; tanggal lokal `YYYY-MM-DD`; waktu template `HH:MM:SS` + offset hari + zona.
- Coordinate DTO: `{ "latitude": ..., "longitude": ... }` dengan finite number. Di PostGIS urutan konstruktor longitude-latitude.
- Header `Authorization: Bearer <user-access-token>` dan publishable API key mengikuti konfigurasi Supabase. Keduanya bukan actor ID dari body.
- `X-Request-ID` untuk korelasi; server membuat nilai sendiri bila format tidak valid.
- `Idempotency-Key` UUID wajib untuk mutasi bisnis. Nilai tetap untuk retry payload yang sama.
- API response menyertakan `api_version`, `server_time`, dan request ID; tidak menyertakan raw SQL, token, bucket admin path atau stack trace.

JWT harus diverifikasi, termasuk issuer/audience/expiry sesuai proyek dan konfigurasi SDK. Decode payload tanpa validasi tidak cukup. Verifikasi identitas gateway tidak menggantikan pemeriksaan kepemilikan di handler/database. [Securing Edge Functions](https://supabase.com/docs/guides/functions/auth).

## 2. Format hasil

```json
{
  "data": {
    "trip_id": "20000000-0000-4000-8000-000000000001",
    "revision": 1,
    "status": "planned"
  },
  "meta": {
    "api_version": "1",
    "request_id": "90000000-0000-4000-8000-000000000001",
    "server_time": "2026-10-22T03:00:00Z"
  }
}
```

```json
{
  "error": {
    "code": "REVISION_CONFLICT",
    "message": "Trip telah berubah sejak data terakhir yang digunakan.",
    "retryable": false,
    "details": { "expected_revision": 4, "current_revision": 5 }
  },
  "meta": {
    "api_version": "1",
    "request_id": "90000000-0000-4000-8000-000000000002",
    "server_time": "2026-10-22T03:01:00Z"
  }
}
```

Resource privat yang tidak dapat diakses dapat menggunakan 404 seragam untuk mengurangi enumerasi. 409 current revision hanya diberikan setelah caller terbukti mempunyai akses.

## 3. Discovery, profil dan konten kreator

| Method dan route | Input utama | Hasil/otorisasi |
|---|---|---|
| `GET /rundowns` | `query?`, bbox?, cursor?, limit | Card DTO versi yang boleh dibaca; limit dibatasi. Guest browse menunggu DEC-01. |
| `GET /rundowns/{id}/versions/{version_id}` | ID identitas+versi | Snapshot konten versi, source metadata dan hash; tidak mengembalikan draft orang lain. |
| `GET /profiles/{id}` | ID | Profile display DTO, tanpa data Auth/internal. |
| `PATCH /me/profile` | Field tampilan yang diizinkan, expected_revision | Profil baru; owner diambil dari sesi. |
| `POST /rundowns` | Judul/default timezone awal | Identitas + draft versi 1 milik actor. |
| `POST /rundowns/{id}/draft-versions` | Source version?, expected rundown revision | Draft baru; konten published tidak diubah di tempat. |
| `PUT /rundown-drafts/{version_id}` | Draft graph, expected_revision | Save atomik stop/leg/rule; field yang tidak diizinkan ditolak. |
| `POST /rundown-drafts/{version_id}/publish` | expected_revision | Published version dan content hash setelah validasi. |
| `POST /rundowns/{id}/distribution` | listed/withdrawn/archived sesuai scope, expected_revision | Perubahan distribusi dengan audit, tanpa perubahan isi versi. |
| `POST /creator-media-sessions` | Draft stop ID, file declaration | Upload konten kreator tanpa presence; tetap owner-scoped dan file-validated. |

Draft graph mempunyai ID stop yang stabil selama penyuntingan. Hapus/reorder draft harus mempertahankan referensi yang masih valid atau menolak seluruh save. Creator upload memakai session/path yang diotorisasi; tidak boleh mengubah media versi published. Bila memakai signed upload untuk kreator, hak ini tidak berlaku pada jurnal ber-presence.

## 4. Trip

| Method dan route | Input utama | Hasil |
|---|---|---|
| `POST /trips` | version ID, timing, optional origin, request ID | Trip dengan copy source dan revision 1. |
| `GET /trips` | cursor/limit/status | Daftar trip milik actor. |
| `GET /trips/{id}` | known_revision? | Snapshot root+children konsisten; `unchanged` bila revision sama. |
| `POST /trips/{id}/plan-preview` | Proposed operations, base revision | Kandidat plan, warnings, input hash; tidak menyimpan rencana. |
| `POST /trips/{id}/add-rundown-preview` | Source version, selections, base revision | Kandidat merge dengan attribution dan unresolved choices. |
| `POST /trips/{id}/apply-plan` | expected_revision, input hash, source IDs, explicit decisions | Plan/revision baru, atomik. |
| `POST /trips/{id}/start` | expected_revision | Active trip; bukan klaim sudah tiba. |
| `POST /trips/{id}/stops/{stop_id}/arrival-observations` | Timestamp/source, expected_revision | Observation berlabel sumber; tidak membuat izin upload. |
| `POST /trips/{id}/stops/{stop_id}/complete` | expected_revision | Completed stop jika dokumentasi/policy memenuhi. |
| `POST /trips/{id}/complete` | expected_revision | Completed trip sesuai completion policy. |
| `POST /trips/{id}/archive` | expected_revision | Archived tanpa memalsukan completion. |
| `DELETE /trips/{id}` | expected_revision | Tombstone + deletion job scope trip. |
| `GET /trips/{id}/album` | cursor? | Journal accepted + media ready, milik actor. |

### Contoh create trip

```json
{
  "rundown_version_id": "10000000-0000-4000-8000-000000000001",
  "timing": {
    "local_date": "2026-10-23",
    "timezone": "Asia/Jakarta",
    "start_time_basis": "departure_origin",
    "requested_start_at": "2026-10-23T08:00:00+07:00",
    "available_until_at": "2026-10-23T18:00:00+07:00"
  },
  "origin": null
}
```

`origin=null` berarti tidak disimpan/belum diketahui; planner tidak membuat ETA akses fiktif. Start-time basis pada contoh adalah pilihan input eksplisit, bukan default produk yang sudah disetujui. Metadata yang belum cukup menghasilkan warnings, bukan angka jadwal hasil karangan.

### Contoh apply perubahan rencana

```json
{
  "expected_revision": 4,
  "preview_input_hash": "sha256:example-input-hash",
  "source_version_ids": [
    "10000000-0000-4000-8000-000000000001",
    "10000000-0000-4000-8000-000000000002"
  ],
  "operations": [
    {
      "type": "append_source_stops",
      "source_version_id": "10000000-0000-4000-8000-000000000002",
      "source_stop_ids": ["11000000-0000-4000-8000-000000000004"]
    }
  ]
}
```

Hash contoh bukan hash valid. Server menghitung ulang input dan memeriksa semua relasi. Allowlist operation awal: set_timing, append_source_stops, reorder_unvisited_stops, update_unvisited_duration, replace_unvisited_leg. Gabung/deduplikasi stop hanya ketika keputusan merge eksplisit diberikan dan fitur diaktifkan. Client tidak boleh mengirim SQL/field patch arbitrer.

## 5. Jurnal, media dan lifecycle akun

| Method dan route | Perilaku |
|---|---|
| `POST /journal-upload-sessions` | Membuat pending entry/session untuk satu foto, terikat trip stop dan content hash. |
| `POST /journal-upload-sessions/{id}/challenges` | Nonce sekali pakai untuk transfer atau finalisasi; tidak memberi hak upload tanpa batas. |
| `PUT /journal-upload-sessions/{id}/content` | Multipart metadata+bytes melalui ingress terverifikasi; presence baru wajib per percobaan. |
| `GET /journal-upload-sessions/{id}` | Status session/media, error aman dan langkah protokol berikutnya; tanpa raw presence log. |
| `POST /journal-upload-sessions/{id}/finalize` | Presence final sesuai policy usulan, expected trip revision dan media validated; commit jurnal. |
| `DELETE /journal-upload-sessions/{id}` | Cancel belum finalized; buat cleanup event. |
| `POST /media/{id}/download-access` | Periksa akses lalu beri download yang berotorisasi/URL berumur terbatas. |
| `DELETE /journal-entries/{id}` | Tombstone dan cleanup terkontrol; tidak langsung memalsukan ulang riwayat trip. |
| `GET /operations/{operation}/{request_id}` | Status command yang dimiliki actor untuk recovery. |
| `POST /me/deletion-requests` | Autentikasi ulang sesuai policy, bekukan account, buat deletion job. |
| `GET /me/deletion-requests/{id}` | Status job yang aman bagi pemilik selama akses pemulihan masih valid. |

Protokol presence, metadata multipart dan batas finalisasi dirinci pada [media/lokasi](05-media-location.md). Pembagian `begin/finalize` di proposal lama dipertegas menjadi session+challenge+transfer+validasi+finalize. Foto berada di quarantine privat sampai diterima; audience kontribusi tidak diaktifkan oleh endpoint ini.

## 6. Tipe snapshot

Trip snapshot memuat `trip`, `days`, `sources`, `stops`, `stop_sources`, `legs`, `time_rules`, ringkasan progres/jurnal, `revision`, `snapshot_schema_version`, `server_time`. Foto bytes dan audit presence tidak ditanam dalam JSON snapshot. Snapshot yang sama tidak boleh mencampur child revision berbeda.

Rundown snapshot memuat identity, version ID, content hash, creator display attribution, landing, stops, legs, time rules, media descriptors dan distribution metadata. Signed URL bila diberikan tetap bersifat sementara; media ID/object descriptor tetap identitasnya.

Pagination menggunakan cursor opaque yang terikat filter/sort dan tie-breaker. Cursor bukan otorisasi; setiap halaman memeriksa akses lagi. Input limit default kandidat 20, maksimum kandidat 100; nilai final ditetapkan setelah query/load test.

## 7. Error yang stabil

| HTTP | Kode | Tindakan client |
|---|---|---|
| 400 | `INVALID_ARGUMENT` | Perbaiki payload; jangan retry otomatis. |
| 401 | `SESSION_EXPIRED` | Refresh sesi sekali; retry command dengan ID sama bila masih valid. |
| 403/404 | `ACCESS_DENIED` / `NOT_FOUND` | Hentikan penggunaan resource; bersihkan akses/cache sesuai scope. |
| 409 | `REVISION_CONFLICT` | Fetch ulang, hitung ulang proposal, command ID baru untuk payload baru. |
| 409 | `IDEMPOTENCY_KEY_REUSED` | Payload bisnis berbeda memakai key sama; jangan retry. |
| 409 | `OPERATION_IN_PROGRESS` | Poll status/backoff; jangan membuat command duplikat. |
| 410 | `UPLOAD_SESSION_EXPIRED` | Buat percobaan/session sesuai status, presence baru. |
| 413 | `MEDIA_TOO_LARGE` | Buat file lebih kecil; perubahan bytes berarti deklarasi/hash baru. |
| 415 | `UNSUPPORTED_MEDIA_TYPE` | Pilih format yang didukung. |
| 422 | `PRESENCE_REJECTED` / `PRESENCE_UNCERTAIN` | Pertahankan draft; sampel baru pada tindakan ulang. |
| 422 | `CONTENT_NOT_READY` / `PLAN_CONSTRAINT_FAILED` | Periksa status/masalah terstruktur. |
| 429 | `RATE_LIMITED` | Patuhi Retry-After dan jitter. |
| 503 | `DEPENDENCY_UNAVAILABLE` / `FEATURE_NOT_CONFIGURED` | Fallback bacaan/draft; retry hanya bila aman. |

Business error tidak diubah menjadi success 200 dengan payload kosong. Error provider dipetakan ke kode aplikasi dan safe diagnostics; jangan membocorkan respons kredensial/provider mentah.

## 8. Algoritme command transaksional

```text
verify session and current account status
validate size/schema/allowlist
derive actor from verified session
BEGIN
  claim (actor, operation, request_id) with payload hash
  if applied: re-check current access; return recorded result
  if same key + different payload: reject
  lock aggregate root
  compare expected_revision
  verify ownership, source access and all invariants
  apply all business changes
  increment aggregate revision once
  append audit/outbox as needed
  record applied result
COMMIT
return committed result
```

Klaim idempotency dan efek command DB berada dalam transaksi sama. Uniqueness conflict harus ditangani dengan savepoint/`ON CONFLICT` yang benar; jangan melanjutkan transaksi PostgreSQL yang sudah aborted. Jika transaksi rollback, tidak ada efek bisnis parsial atau ledger applied palsu.

Payload hash mencakup isi bisnis yang sudah dikanonisasi; urutan array bermakna dipertahankan. Header trace, JWT dan retry timestamp tidak masuk hash. New presence attempt mempunyai nonce/attempt ID sendiri; jangan menganggap sampel baru identik dengan sampel lama. Untuk operasi yang sudah applied, retry hanya mengambil hasil, tidak melakukan upload/jurnal baru.

Jaminan replay berlaku dalam recovery/retention window yang dikonfigurasi dan dikembalikan pada metadata operasi. Setelah receipt kedaluwarsa, client harus merekonsiliasi resource lebih dahulu; API tidak menjanjikan idempotency tanpa batas waktu. Unique submission operation pada jurnal tetap menjaga identitas submission selama record bisnis dipertahankan. Menghapus ledger sensitif dapat menyisakan receipt/tombstone minimum sesuai kebijakan yang dipilih.

## 9. Pekerjaan lintas layanan

Media dan deletion memakai state machine tahan crash. Jangan menahan transaksi SQL selama transfer file atau request provider. Buat state pendek → lakukan IO → finalisasi dengan compare-and-set/lease. Lease kadaluwarsa dapat diklaim worker lain; operasi eksternal harus idempotent atau direkonsiliasi.

Job awal: validate_media, generate_thumbnail, cleanup_orphan_upload, purge_deleted_resource, process_account_deletion, reconcile_storage. Masukkan event ke outbox dalam transaksi bisnis; jangan mengandalkan fire-and-forget pada response handler.

Executor dapat memproses job ringan dalam Edge Functions dengan batas batch. Decode/re-encode gambar dan beban berat memerlukan spike/runtime yang sesuai. Edge Functions mempunyai batas CPU/memori; pekerjaan dokumentasi ini belum membuktikan pemrosesan foto memenuhi batas tersebut. [Limits](https://supabase.com/docs/guides/functions/limits).

Kontrak internal worker tidak dapat dipanggil user JWT atau Data API client:

| Fungsi internal | Input/hasil dan guard |
|---|---|
| `server_claim_outbox_batch` | Allowlist job type, worker ID, batas batch; pilih job tersedia, beri lease dan fencing token atomik. |
| `server_extend_job_lease` | Job ID + token yang masih dimiliki; jangan memperpanjang job milik executor lain. |
| `server_complete_media_job` | Job/session generation, token, output descriptor/hash; compare-and-set state dan canonical pointer. |
| `server_fail_job` | Token, safe error code, transient/permanent; backoff atau dead-letter. |

Claim batch dapat menggunakan row locking yang melewati job terkunci. Lease tidak menjamin proses lama langsung berhenti; fencing token dan output path unik mencegah stale executor mengubah hasil baru. Worker tidak mengambil actor ID dari payload app untuk menaikkan privilege. Admin retry dead-letter harus memvalidasi ulang account/resource yang mungkin sudah dihapus.

## 10. Batas dan konfigurasi

Semua batas payload, jumlah stop, jangka challenge, ukuran file, dan rate limit ada di [register parameter](10-decisions-sources.md). Nilai kandidat bukan janji kapasitas produksi. Handler wajib enforce batas sebelum query/IO mahal dan tetap membatasi bytes aktual ketika `Content-Length` tidak ada atau tidak dapat dipercaya.
