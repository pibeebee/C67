# ADR-0001 — Tiga area kerja dalam satu monorepo

**Tanggal:** 22 Oktober 2026. **Status:** kesepakatan monorepo pengguna; pembagian folder awal diterapkan.

## Konteks

Tim membagi pekerjaan menjadi iOS UI, iOS Backend dan Server, dan sepakat memakai repository `pibeebee/C67`. Aplikasi iOS diarahkan memakai VIPER. Stack backend belum diputuskan.

## Keputusan struktur

`ios-ui/` menampung app dan modul VIPER. `ios-backend/` menampung domain/data/use case dan adapter yang berjalan di perangkat. `server/` menampung backend remote. `contracts/` menjadi sumber kontrak bersama; `docs/` mencatat konteks dan keputusan.

Interactor berada pada fitur VIPER; Entity dibagikan melalui Domain iOS Backend. Logika bersama dipisahkan dari presentasi. Ini penataan awal yang dapat direvisi tim, bukan persetujuan semua rincian pola implementasi.

## Konsekuensi

Tim dapat meninjau perubahan lintas UI/client/server dalam satu PR. Akses repository dan proses review perlu mencakup perubahan kontrak bersama. Tiap runtime mempunyai manifest, dependency dan proses build sendiri ketika diinisialisasi; monorepo belum membutuhkan orchestrator tambahan.

Tahap ini hanya membuat folder dan panduan. Project Xcode, local Swift package, server, database, CI serta migrasi PoC belum diinisialisasi. Detail batas ada di [arsitektur](../architecture.md).
