# Server

Area layanan remote: otorisasi, data bersama, API, transaksi, penyimpanan media dan pemrosesan job. Belum ada runtime, framework, database atau deployment yang aktif.

**Usulan awal:** modular monolith dengan modul berdasarkan fitur. Ini rekomendasi struktur, belum keputusan stack; lihat [ADR-0002](../docs/decisions/0002-server-architecture.md).

```text
server/
├── src/
│   ├── modules/
│   │   ├── accounts/
│   │   ├── discovery/
│   │   ├── rundowns/
│   │   ├── trips/
│   │   ├── journals/
│   │   └── media/
│   └── shared/
│       ├── auth/
│       ├── config/
│       ├── errors/
│       └── observability/
├── database/
│   ├── migrations/
│   ├── seeds/
│   └── tests/
├── workers/media/
├── tests/integration/
└── deploy/
```

Saat modul mulai dibangun, susun entry API/handler, application service, domain rule dan infrastructure adapter **di dalam modul terkait** sesuai kebutuhan. Hindari menambah empat lapisan kosong untuk setiap operasi sederhana. Shared hanya memuat kebutuhan lintas modul; aturan trip tetap di modul trip. Album awal dapat berupa query/proyeksi jurnal/media satu trip.

`database/migrations/` adalah slot riwayat migrasi tunggal. Jika tool yang dipilih mengharuskan lokasi lain, pindahkan satu kali dan perbarui referensi/tooling; jangan memelihara dua salinan migrasi. `workers/media/` menyediakan batas eksekusi pekerjaan berat; host/runtime dan cara dispatch belum dipilih.

## Aturan implementasi berikutnya

Identitas terverifikasi menentukan pemilik dan hak akses. Server menegakkan transaksi copy/merge, versi terbit stabil, revision check, idempotency dan penerimaan jurnal; pemeriksaan client hanya bantuan awal. Payload/response didefinisikan bersama di [contracts](../contracts/README.md), bukan lewat bentuk row database langsung.

Supabase Auth, PostgreSQL/PostGIS, Storage, Edge Functions/SQL RPC dan worker media merupakan kandidat dari spesifikasi workspace. Tidak ada SDK, konfigurasi Supabase atau container yang diinisialisasi pada tahap ini. Bila kandidat itu dipilih, sesuaikan entrypoint dengan runtime vendor sambil mempertahankan batas fitur; struktur `src` bukan klaim bahwa satu executable server sudah tersedia.

Selesaikan kebijakan presence dan audit model landing → stop pertama sebelum slice terkait. Data seed harus sintetis. Rahasia ditempatkan pada environment/secret store, dengan template yang aman untuk Git saat konfigurasi nyata ditambahkan.
