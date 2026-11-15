# Konteks kerja C6 — AI trip planning

**Diperbarui:** 29 Oktober 2026, WIB. Audiens: anggota tim dan AI agent yang melanjutkan pekerjaan.

Pengguna mempunyai tujuan awal dan preferensi, menentukan tanggal/jam berangkat/batas selesai, lalu memperoleh rekomendasi AI mengenai tambahan opsional, urutan dan jadwal. Aplikasi dapat menghitung ulang selama trip. Pengguna tetap menentukan perubahan destinasi.

Pengalaman dasar perjalanan berkesinambungan dengan konsep sebelumnya. Engine penyusunnya kini mengandalkan AI dengan konteks rute/cuaca/tempat, tanpa ketergantungan pada rundown orang yang pernah ke sana. Fokus framework adalah MapKit, Core Location dan WeatherKit; API model dan browser berada pada rancangan backend. Provider/model dan runtime belum dipilih.

## Urutan baca

1. [CBL aktif](../../source-records/CBL.md): keputusan, riwayat, batas scope dan status implementasi.
2. [Konteks produk](product/ai-trip-planning-context-2026-10-29.md): Johan, daftar tujuan dan fixture.
3. [Alur pengguna](product/ai-trip-planning-user-flow-2026-10-29.md): sebelum dan selama perjalanan.
4. [Engine AI](technology/11-ai-planning-engine.md) serta [keputusan terbuka](technology/10-decisions-sources.md): rancangan, bukan kontrak berjalan.
5. [Validasi](product/ai-trip-planning-validation-plan-2026-10-29.md) dan [indeks chat](../../missing-evidence.md#missing-cf164b146107).

## Melanjutkan pekerjaan dengan benar

- Klarifikasi eksplisit terbaru pengguna mengungguli dokumen lama.
- Bedakan keputusan produk, usulan engineering, implementasi dan hasil uji.
- Recalculation D/C perlu menjaga pilihan pengguna dan menjelaskan dampak ke waktu/experience; keputusan mengganti atau melewati tempat tidak diambil diam-diam.
- Cakupan foto/album, completion, merge, kontribusi publik dan framework tambahan belum ditetapkan ulang.
- Periksa repository C67 dan bukti bertanggal sebelum menyatakan fitur berjalan. Engine AI dan active replanning belum dibangun oleh pembaruan dokumen ini.
- [Wireframe revisi 2](../../missing-evidence.md#missing-06b84a4df0de) dan snapshot teknologi 0.1 adalah baseline sebelumnya, belum desain target baru.

## Riwayat

Aviation/pilot-rest, koordinasi tour leader, diary dan rundown kreator adalah perjalanan investigasi sebelumnya. [Snapshot sebelum pembaruan](../../missing-evidence.md#missing-e4ef2b63f729) menyimpan konteks lama. Arsip riset, sumber interview dan bukti PoC tetap sumber sesuai tanggal/cakupannya, bukan hasil penelitian baru untuk AI trip planning.
