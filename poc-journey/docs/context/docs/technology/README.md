# Dokumentasi teknologi C6 — AI trip planning

**Diperbarui:** 29 Oktober 2026, WIB. **Versi konteks rancangan:** 0.2. **Status:** dokumentasi target; tidak menaikkan versi aplikasi, schema atau kontrak API yang sudah diimplementasikan.

[CBL aktif](../../../source-records/CBL.md) · [Konteks produk](../product/ai-trip-planning-context-2026-10-29.md) · [Alur pengguna](../product/ai-trip-planning-user-flow-2026-10-29.md)

## Mulai dari engine baru

Pengguna memilih tujuan, preferensi, tanggal, jam berangkat dan batas selesai. AI melalui API backend memberi rekomendasi tempat tambahan yang opsional, urutan dan jadwal berbasis konteks rute/cuaca/tempat. Rekomendasi dapat dihitung ulang selama perjalanan. Keputusan mengganti atau melewati tujuan tetap milik pengguna.

Baca **[11 — Engine rekomendasi AI](11-ai-planning-engine.md)** bersama [01 — Domain](01-architecture-domain.md), [07 — Perencanaan](07-planning-integrations.md) dan [10 — Keputusan](10-decisions-sources.md). Ketiganya menggantikan asumsi aktif “tanpa LLM”, “urutan tetap saja” dan keharusan memulai dari rundown kreator pada spesifikasi 0.1.

## Daftar dan status dokumen

| Dokumen | Status setelah pembaruan |
|---|---|
| [01 — Arsitektur dan domain](01-architecture-domain.md) | Domain aktif dan batas antara keputusan produk, target teknis dan kode yang ada. |
| [02 — Aplikasi dan pembagian data](02-ios-data.md) | Tambahan data input/proposal/replanning; rincian 0.1 tetap referensi bertanggal. |
| [03 — Database](03-database.md) | Kebutuhan model AI baru dijelaskan; schema logis 0.1 bukan migrasi aktif. |
| [04 — Backend/API](04-backend-api.md) | Operasi konseptual baru dan batas compatibility; route 0.1 tetap usulan historis. |
| [05 — Media dan lokasi](05-media-location.md) | Scope foto/presence belum ditetapkan ulang; protokol 0.1 tidak dipaksakan ke engine baru. |
| [06 — Sync/offline](06-sync-offline.md) | Tambahan revision input/proposal, stale result dan pemulihan perencanaan. |
| [07 — Perencanaan/integrasi](07-planning-integrations.md) | Urutan/jadwal kontekstual serta evaluasi ulang sisa perjalanan. |
| [08 — Keamanan/operasi](08-security-operations.md) | Tambahan batas model/browser, minimisasi data dan budget provider. |
| [09 — Implementasi/pengujian](09-delivery-testing.md) | Urutan pembuktian target baru; matriks lama tetap rencana baseline 0.1. |
| [10 — Keputusan/sumber](10-decisions-sources.md) | Keputusan pengguna 29 Oktober dan pertanyaan engineering yang masih terbuka. |
| [11 — Engine AI](11-ai-planning-engine.md) | Rancangan utama orchestration, data, rekomendasi dan recalculation. |
| [12 — Sequence diagram](12-sequence-diagrams.md) | Interaksi penyusunan rencana awal serta recalculation D/C, proposal dan penerapan pilihan. |

## Arsitektur target secara konseptual

```text
iOS: tujuan + preferensi + waktu + konteks lokasi
    -> backend: orchestration + API model + browser/search + adapter data
    -> usulan urutan/jadwal + alasan/sumber + konflik/unknown
    -> perjalanan aktif dan masukan baru -> recalculation
```

Cara mengambil/mengirim data Apple, capability traffic/transit, provider/model, runtime browser, validasi dan kontrak simpan masih memerlukan keputusan serta technical spike. Tidak ada asumsi bahwa seluruh kebutuhan tersedia otomatis dari nama framework.

## Hubungan dengan implementasi C67

Repository C67 sudah mempunyai fondasi Auth, trip graph, revision, planned edits dan server jurnal/media dengan bukti masing-masing. Engine AI dan active replanning belum dibangun oleh pembaruan ini. Kontrak wire yang ada tetap acuan runtime sampai ada perubahan implementasi yang diuji.

Spesifikasi 0.1 menyebut 25 tabel logis dan 34 route usulan; angka tersebut bukan inventori API/database yang berjalan atau cakupan engine 0.2. Runtime Supabase yang dipakai tim mengikuti keputusan repository, bukan URL contoh managed di proposal lama.

## Riwayat dan pemeriksaan

[Snapshot sebelum pembaruan](../../../missing-evidence.md#missing-e4ef2b63f729) menyimpan konteks dan 11 dokumen teknologi 0.1 beserta checksum. [Audit 22 Oktober](../research/audit-kelayakan-teknologi-2026-10-22.md) tetap audit rancangan lama; hasilnya tidak membuktikan kelayakan engine baru.

Pembaruan 29 Oktober hanya menyelaraskan dokumen dan menambahkan spesifikasi target. Pemeriksaan tautan, struktur Markdown dan batas perubahan dilaporkan terpisah dari pengujian aplikasi/provider. Tidak ada build, request AI/cuaca, tes GPS, migrasi, commit, push atau deployment melalui pekerjaan ini.
