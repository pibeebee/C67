# Kontrak HTTP lab v1

Endpoint Google konteks baru `/v1/lab/place-context/{capabilities,search,evaluate}` dijelaskan pada [setup context engine](GOOGLE_PLACES_CONTEXT_SETUP.md#6-api-lokal). Endpoint tersebut tidak menulis hasil ke job/accepted itinerary dan belum mengganti engine D/E.

Base URL default `http://127.0.0.1:8767`. Semua endpoint kecuali `/health` membutuhkan `Authorization: Bearer <token-run>`. Server dibuat dengan satu mode `replay` atau `rest`; client tidak dapat memilih fixture di server live. Respons memakai `Cache-Control: no-store`.

Tanggal di payload lab adalah **Unix seconds JSON number, double**, bukan string ISO. Nilai waktu round-trip tanpa pembulatan slot tersembunyi. Slot kunjungan tetap ditentukan engine. Raw report warisan mempertahankan encoding aslinya dan dibawa sebagai base64 Data.

## Endpoint

| Metode dan path | Hasil |
| --- | --- |
| `GET /health` | Status, nama service dan provider mode |
| `GET /v1/lab/capabilities` | Hash snapshot, schema, engine, concurrency, mode, clock, counter REST kampanye |
| `POST /v1/lab/jobs` | 202 + job baru atau job yang sama untuk idempotency key yang sama |
| `GET /v1/lab/jobs/{jobID}` | Job/progres aktual; payload result dihilangkan dari polling |
| `GET /v1/lab/jobs/{jobID}/result` | Outcome lengkap; 409 bila belum selesai/failed/cancelled |
| `POST /v1/lab/jobs/{jobID}/cancel` | Cancellation; terminal job tidak diubah lagi |
| `POST /v1/lab/proposals/{planID}/apply` | Acceptance atomik ke base revision yang cocok |

Schema Swift yang menjadi acuan: `Sources/PlannerContracts/Contracts.swift`, `LabClient.swift`, serta contracts engine. Contoh trip input lengkap terdapat dalam `artifacts/replay-final/matrix.json`; CLI/harness membuat envelope JobInput secara otomatis.

JobInput memuat `schemaVersion=1`, `clientID`, `operationID`, `runID`, `variant` (`B`/`C`), `snapshotHash`, `request`, `baseRevision` dan opsional `baseAcceptedID`. Identity nonkosong maksimal 128 byte. Key idempotency adalah `(clientID,operationID)`; input hash menormalkan urutan set preferensi. Key sama dengan payload lain menghasilkan 409. Request valid terhadap snapshot harus lolos validasi domain sebelum diproses; kesalahan domain setelah enqueue tercatat sebagai failed job.

ApplyInput memuat `clientID`, `baseRevision`, `requestHash`. Hash memakai `LabJSON.hash(plan.request)`, termasuk normalisasi set. `planID` adalah ID proposal, bukan job ID. Apply memeriksa job completed/ready, client, input hash, base revision dan accepted ID, expiry <900 detik serta keberangkatan belum lewat. Apply ulang proposal yang telah diterima mengembalikan accepted revision yang sama. Proposal lama tidak dapat menimpa accepted terbaru.

## State dan outcome

State job: queued → running → completed / failed / cancelled / timed_out. Result terlambat dibuang jika state sudah terminal. Restart menandai pekerjaan queued/running sebagai `failed: interrupted_by_restart`; tidak diam-diam mengulang request provider.

Outcome domain berbeda dari state job:

- `ready`: proposal lengkap lolos audit engine.
- `needs_places`, `needs_locations`: input/fakta/lokasi belum cukup.
- `infeasible_lower_bound`: bukti durasi wajib melebihi rentang, C saja.
- `no_feasible_candidate`: pencarian terbatas belum memperoleh jadwal layak; bukan bukti global infeasible.
- `provider_unavailable`, `incomplete_data`: data ETA tidak cukup.

Error budget, otorisasi provider atau quota menghentikan job sebagai failed dengan alasan tersimpan. Timeout job/client adalah censored, bukan itinerary cepat. Metadata provider dan raw trace tersedia di result; beberapa kegagalan alternatif tidak otomatis menggagalkan kandidat akhir yang valid.

## Batas dan respons

Worker 1, maksimum 3 outstanding job, request 64 KiB, hasil/row SQLite 5 MiB. Payload oversized →413; JSON invalid →400; token salah →401; konflik/idempotency/apply →409; kapasitas →429; job tidak ada →404. SQLite memakai WAL, prepared statements dan transaksi pendek saat apply.

Progres berupa label tahap/perkerjaan aktual, bukan persentase estimasi. Client memakai epoch task/cancellation untuk mencegah hasil terlambat menjadi hasil aktif. Penyimpanan observasi client terpisah dari store itinerary asli.

## Varian D eksperimen

JobInput kini juga menerima `variant: D`. Kontrak hasil/timer/apply tetap sama; D memakai local-prior shortlist dan maksimal3validasi provider sampai kandidat pertama layak. Tidak ada surrogate ETA dalam leg hasil. Ini perubahan kebijakan pencarian dengan trade-off kualitas, bukan klaim C-parity. Lihat [protokol D](FAST_D_PROTOCOL_2026-11-06.md).

## Varian E eksperimen

`variant: E` memakai E3: maksimal tiga validasi, dipicu ketidakpastian engineering, kalibrasi hanya untuk ranking spekulatif, dan eksplorasi satu alternatif tujuan pertama. Hasil terbaik yang sudah divalidasi dikembalikan setelah pencarian terbatas selesai; hasil layak internal pertama belum di-stream. Kontrak source/ETA/dwell/deadline/apply tetap sama. Ini bukan default atau jaminan akurasi; lihat [hasil 7 November](DECISION_SEQUENCE_RESULTS_2026-11-07.md).
