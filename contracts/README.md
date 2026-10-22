# Kontrak bersama

Satu tempat untuk menyepakati pertukaran data antara iOS Backend dan Server.

| Folder | Isi ketika slice mulai diimplementasikan |
|---|---|
| `api/` | Spesifikasi API, misalnya OpenAPI setelah format dipilih. |
| `schemas/` | Schema request/response, error dan versi payload. |
| `fixtures/` | Contoh sintetis yang mengikuti kontrak; bukan data pengguna. |

Belum ada kontrak executable, generator atau endpoint yang berjalan. Keberadaan folder tidak mengesahkan 34 route usulan pada spesifikasi workspace.

Untuk setiap operasi yang dibangun, sepakati input/output, satuan dan zona waktu, optional/null, identitas/revision, error, retry/idempotency dan batas akses. Kontrak tidak mengirim rahasia, objek SwiftData atau detail internal database kepada client.

Pada satu slice, tetapkan satu definisi otoritatif dan periksa adapter Swift/server terhadapnya. Jika nanti ada code generation, catat sumber dan perintah regenerasinya; jangan mengedit hasil generator menjadi sumber kedua.
