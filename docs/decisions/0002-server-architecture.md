# ADR-0002 — Usulan arsitektur Server

**Tanggal:** 22 Oktober 2026. **Status:** usulan untuk ditinjau; framework, provider dan runtime belum diputuskan.

## Usulan

Gunakan modular monolith: satu codebase server dengan modul berdasarkan kemampuan produk. Di dalam tiap modul, pisahkan handler, logika application/domain dan adapter data secukupnya. Awali dari accounts, discovery, rundowns, trips, journals dan media. Database mempunyai satu riwayat migrasi; kerja media berat memiliki batas worker tersendiri.

Alasannya: data trip, copy versi, jurnal dan atribusi berkaitan erat dan membutuhkan konsistensi. Tim dapat membangun serta meninjau satu slice tanpa langsung mengelola banyak layanan. Ini rekomendasi engineering untuk C67, belum hasil pengukuran kapasitas.

## Pilihan implementasi yang masih terbuka

| Kandidat | Pekerjaan yang perlu dibuktikan |
|---|---|
| Supabase managed + PostgreSQL/PostGIS + functions/RPC | Auth native, akses/data isolation, transaksi, migrasi, protokol media dan host worker; kandidat dari spesifikasi workspace. |
| API custom + database/object storage yang dipilih | Framework/bahasa, Auth, hosting, operasi, transaksi dan integrasi media perlu dipilih serta dirawat tim. |

Struktur folder mendukung pengelompokan fitur pada kedua arah. Jika memilih functions/RPC, sesuaikan entrypoint dan lokasi migrasi dengan tooling provider; jangan memaksakan satu executable atau menggandakan migrasi. Worker tambahan tidak berarti semua modul harus menjadi microservice.

## Sebelum memilih dan bootstrap

Pertimbangkan pengalaman anggota Server, waktu delivery, lifecycle Auth, biaya/operasi dan satu uji copy trip beserta akses dua akun. Untuk slice jurnal, putuskan presence dan buktikan jalur foto termasuk worker tertunda/retry. Hasil keputusan berikutnya harus memperbarui ADR ini dan konfigurasi nyata bersama-sama.

Folder kosong yang dibuat sekarang menyediakan tempat kerja. Tidak ada dependency, provisioning layanan, schema produksi atau endpoint yang aktif.
