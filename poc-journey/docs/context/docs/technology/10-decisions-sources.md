# 10 — Keputusan, pertanyaan terbuka dan sumber konteks

**Diperbarui:** 29 Oktober 2026, WIB. **Status:** register rancangan 0.2; bukan bukti implementasi.

[Indeks](README.md) · [CBL](../../../source-records/CBL.md) · [Engine AI](11-ai-planning-engine.md)

## 1. Keputusan produk yang dikonfirmasi

| ID | Keputusan | Status |
|---|---|---|
| AI-01 | AI menjadi penghasil rekomendasi; ketergantungan pada rundown orang yang pernah berkunjung dilepas | Dikonfirmasi pengguna 29 Oktober. |
| AI-02 | Tujuan awal dan preferensi berasal dari pengguna; tambahan AI dipilih pengguna | Dikonfirmasi. |
| AI-03 | Pengguna menentukan tanggal, jam berangkat dan batas selesai | Dikonfirmasi. Semantik titik akhir/pulang masih terbuka. |
| AI-04 | Pengurutan mempertimbangkan waktu, cuaca, rute dan konteks tempat | Dikonfirmasi sebagai arah. Skor/bobot belum dipilih. |
| AI-05 | Recalculation dapat berlangsung selama trip, termasuk kunjungan yang diperpanjang | Dikonfirmasi. Pemicu/apply belum dipilih. |
| AI-06 | Keputusan mengganti/melewati tujuan tetap milik pengguna | Dikonfirmasi. |
| AI-07 | Fokus framework MapKit, Core Location, WeatherKit | Dikonfirmasi. Capability/coverage perlu spike. |
| AI-08 | Model melalui API backend; tidak self-hosting | Dikonfirmasi. Provider/model belum ditetapkan. |
| AI-09 | Backend mempunyai kemampuan browser untuk mencari informasi tempat | Dikonfirmasi sebagai rancangan. Runtime/tools/sumber belum dipilih. |

## 2. Keputusan engineering yang masih diperlukan

| ID | Topik | Yang perlu ditetapkan/dibuktikan |
|---|---|---|
| OPEN-01 | Model/API | Provider, model/version, routing, data policy, budget, timeout dan fallback. |
| OPEN-02 | Browser/search | Runtime, tool boundaries, strategi pencarian, sumber, freshness dan konten yang saling bertentangan. |
| OPEN-03 | Personalisasi | Field, onboarding, consent, scope penyimpanan dan cara pengguna mengubah prioritas. |
| OPEN-04 | “Urutan terbaik” | Tujuan penilaian, batas wajib vs preferensi, bobot, tradeoff dan metode pencarian kandidat. |
| OPEN-05 | Waktu | Durasi tiap stop, waktu tunggu, zona, titik akhir/pulang dan makna batas selesai. |
| OPEN-06 | Integrasi wilayah/moda | Place identity, ETA, traffic, transit, data cuaca/solar dan availability aktual. |
| OPEN-07 | Recalculation | Pemicu, cadence, active-trip state, review/apply, undo dan perlindungan fakta kunjungan. |
| OPEN-08 | Kontrak/database | Jalur trip dari tujuan sendiri, proposal/revision, provenance dan kompatibilitas source-version lama. |
| OPEN-09 | Data/provider | Ketentuan cache/atribusi/transfer ke model, retensi koordinat/preferensi dan log minimum. |
| OPEN-10 | Offline/recovery | Draft input, rencana terakhir, proposal stale, retry dan kegagalan provider. |
| OPEN-11 | Scope lanjutan | Foto/album/presence, completion/skip/partial, merge dan kontribusi publik. |
| OPEN-12 | Mutu/biaya | Fixture, evaluasi fakta/kelayakan, latensi, jumlah tool call, biaya dan bukti pengguna. |

Detail rancangan pada bab 11 adalah usulan untuk ditinjau, bukan jawaban final atas tabel ini. Tidak ada angka default produksi atau provider dipilih melalui pembaruan dokumen.

## 3. Hubungan dengan keputusan 0.1 dan implementasi

DEC-01–DEC-12 dan parameter kandidat 22 Oktober tersimpan dalam [snapshot teknologi 0.1](../../../missing-evidence.md#missing-e4ef2b63f729). Itu register proposal saat itu, bukan status implementasi terbaru. Keputusan runtime yang kemudian diterapkan—misalnya Supabase self-hosted, Auth, jurnal privat dan planned-only edits—mengikuti ADR dan bukti di repository C67.

AI-01–AI-09 memperbarui arah rekomendasi produk. Keputusan ini tidak merombak migration history, source manifest historis, wire payload lama atau guard data yang sudah berjalan. Rancangan compatibility dan penerimaan diperlukan sebelum implementasi baru.

## 4. Sumber konteks dan batas bukti

| Sumber | Pemakaian dan batas |
|---|---|
| Percakapan pengguna 29 Oktober | Keputusan produk di bagian 1; bukan persetujuan seluruh detail engineering atau bukti hasil lapangan. |
| [CBL](../../../source-records/CBL.md) | Ringkasan aktif dan riwayat. |
| [Konteks produk](../product/ai-trip-planning-context-2026-10-29.md) | Cerita Johan dan fixture A/B/C/D dari pengguna. |
| [Alur pengguna](../product/ai-trip-planning-user-flow-2026-10-29.md) | Rancangan pengalaman, belum layar berjalan. |
| [Rencana validasi](../product/ai-trip-planning-validation-plan-2026-10-29.md) | Skenario penerimaan, belum hasil uji. |
| [Riset WeatherKit](../research/weatherkit-traveller-experience-research-2026-10-21.md) | Sumber bertanggal 21 Oktober, belum verifikasi API destinasi baru. |
| [Riset cahaya/cuaca/moda](../research/keterkaitan-cahaya-cuaca-moda-rundown-2026-10-22.md) | Temuan sumber dipertahankan; sintesis kreator lama diberi konteks historis. |
| [Audit 22 Oktober](../research/audit-kelayakan-teknologi-2026-10-22.md) | Evaluasi rancangan lama, bukan persetujuan kelayakan engine AI. |
| [Indeks chat](../../../missing-evidence.md#missing-cf164b146107) | Pointer ke diskusi yang mendasari konteks. |

Tidak ada sumber vendor daring yang diperiksa ulang atau API provider yang dipanggil pada pekerjaan dokumentasi ini. Fakta capability/terms yang akan dipakai implementasi perlu diverifikasi pada sumber resmi dan respons aktual yang relevan.
