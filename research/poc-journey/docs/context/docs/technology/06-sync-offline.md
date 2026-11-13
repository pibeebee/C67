# 06 — Sinkronisasi, offline dan recovery

## Pembaruan konteks 29 Oktober — proposal dan recalculation

Acuan aktif: [engine AI](11-ai-planning-engine.md). Rincian mulai bagian 1 di bawah adalah referensi 0.1. Publikasi/copy/merge kreator tidak menjadi prasyarat alur AI.

Tambahan target: simpan draft input serta rencana terakhir sesuai policy yang dipilih; kaitkan proposal dengan versi input/preferensi dan base revision; tandai hasil stale saat tujuan/waktu berubah. Request client yang dibatalkan tidak otomatis membatalkan proses backend. Pemulihan harus membedakan request belum selesai, proposal tersedia dan perubahan yang sudah tersimpan.

Offline tidak berarti tersedia AI, browser, ETA atau forecast terkini. Antrean retry tidak boleh menerapkan hasil untuk konteks lama. Perubahan rencana aktif harus menjaga kejadian/dokumentasi yang telah diterima; persistensi, cadence, auto-apply dan undo masih memerlukan kontrak baru.

[Indeks](README.md) · [iOS/data](02-ios-data.md) · [API](04-backend-api.md) · [Media](05-media-location.md)

## 1. Model konsistensi

Server menjadi acuan data bersama yang sudah diterima. iPhone menyimpan snapshot, draft dan status operasi lokal. Tidak ada dua database yang dianggap selalu identik. SwiftData adalah local persistence; protocol C6 yang menentukan kapan data Supabase diambil dan ditulis.

Baseline awal menggunakan **snapshot per aggregate + optimistic concurrency**. Realtime bukan kebutuhan awal; invalidation event kelak hanya memicu refresh, bukan menggantikan pemeriksaan revision atau hak akses.

## 2. Field sinkronisasi

| Field | Fungsi |
|---|---|
| `server_id` | Identitas domain yang stabil. |
| `server_revision` | Revision aggregate terakhir yang diterima lokal. |
| `snapshot_schema_version` | Versi bentuk snapshot untuk decode/migrasi. |
| `last_synced_at` | Waktu receipt lokal; bukan penentu pemenang konflik. |
| `access_checked_at` | Waktu akses terakhir diverifikasi. |
| `sync_state` | synced/local_draft/submitting/awaiting_confirmation/conflict/failed. |
| `base_revision` | Revision saat draft perubahan dimulai. |
| `command_id` | Kunci recovery/idempotency operasi bisnis. |

Waktu `updated_at` hanya membantu daftar/diagnostik. Jangan memakai last-write-wins berbasis jam iPhone untuk menyelesaikan perubahan jadwal.

## 3. Fetch snapshot konsisten

1. Client mengirim known revision dari local store.
2. Server memverifikasi account dan akses resource.
3. Jika sama, server memberi hasil unchanged tanpa graph duplikat; jika berbeda, baca root+children pada satu snapshot transaksi.
4. Client memvalidasi schema version dan completeness lalu menulis seluruh snapshot secara atomik.
5. Local revision tidak boleh turun; respons lama yang tiba belakangan dibuang.
6. Draft lokal tetap terpisah dan tidak ditimpa snapshot.

Untuk versi rundown terbit gunakan version ID + content hash; distribution/access metadata tetap diperbarui. Immutable content tidak berarti aksesnya berlaku permanen.

Daftar trip memakai pagination stabil, kemudian fetch aggregate yang diperlukan. Baseline tidak mengandalkan query `updated_at > last_sync` sebagai protokol delta karena dapat kehilangan delete, tie timestamp atau perubahan akses.

## 4. Download package

Manifest download menyebut snapshot version/revision, daftar metadata wajib dan media opsional. State:

```text
not_downloaded -> downloading -> metadata_ready -> media_partial -> available
                        |              |
                        +----------> failed/retryable
```

Trip dapat readable ketika metadata lengkap walau foto opsional belum selesai. Label internal package harus membedakan metadata_ready dan all_requested_media_ready. Peta dasar, search, cuaca segar dan routing bukan bagian yang otomatis tersedia dari download package.

Download snapshot yang sedang diperbarui server diselesaikan pada revision tertentu. Refresh berikutnya dapat mengganti package secara atomik tanpa menghapus draft atau file yang masih dipakai upload.

## 5. Write online dan konflik

Client membuat draft perubahan dari base revision, menghitung proposal, lalu mengirim command dengan expected revision dan request ID. Server tidak menerima perubahan jika revision berbeda.

Saat 409:

- pertahankan draft/pilihan lokal;
- fetch snapshot terbaru;
- hitung ulang proposal terhadap state terbaru;
- tampilkan/serahkan perbedaan sebagai domain conflict yang memerlukan keputusan;
- command hasil revisi memakai request ID baru karena payload bisnis berubah.

Rebase otomatis hanya boleh untuk operasi yang telah dibuktikan aman dan tidak mengubah maksud pengguna. Reorder/schedule/merge tidak otomatis di-rebase pada baseline.

## 6. Offline capability matrix

| Operasi | Baseline offline |
|---|---|
| Baca trip/rundown terunduh | Ya, sesuai manifest yang sudah tersedia. |
| Baca foto terunduh | Ya; tidak menjamin semua foto tersedia. |
| Mengukur lokasi/jarak terhadap pin cache | Dapat dilakukan perangkat; hasil belum menjadi keputusan server. |
| Membuat foto/cerita draft | Ya, bila file berhasil disimpan. |
| Mencatat tampilan stop aktif secara lokal | Ya; bukan progres server terkonfirmasi. |
| Simpan perubahan rencana sebagai draft | Ya, tanpa janji auto-apply ketika online. |
| Publish rundown/copy/merge tersimpan | Memerlukan server. |
| Terima jurnal ber-presence | Memerlukan koneksi dan pemeriksaan baru. |
| Konfirmasi completion server | Memerlukan server pada baseline. |
| Cuaca/ETA terbaru | Memerlukan provider; cache diberi timestamp/stale state. |
| Search tempat/routing/peta dasar | Bergantung layanan/platform, bukan jaminan C6 offline. |

Jika edit offline tersinkron dipilih kelak, tambahkan outbox lokal dengan semantic operation/base revision, penghapusan/tombstone dan protokol konflik. PendingCommand baseline digunakan untuk recovery request online yang hasilnya belum diketahui; bukan izin menjalankan semua operasi otomatis dari lokasi berbeda.

## 7. Recovery request dan retry

```text
prepared -> sent -> awaiting_confirmation -> applied
                      |           |
                      |           -> conflict / rejected
                      -> retryable_unknown
```

Request timeout berarti hasil belum diketahui. Cari status operasi atau kirim ulang request ID/payload sama. Jangan langsung membuat resource ID/command ID baru. `applied` hanya ditetapkan setelah receipt server atau status terverifikasi.

Retry network/read dapat memakai exponential backoff dan jitter, berhenti pada batas percobaan/waktu. 429 mengikuti Retry-After. 401 hanya memicu refresh sesi terkoordinasi; 403/404 dan validation errors tidak diulang membabi buta. Jurnal presence tidak diretry dengan sampel/challenge lama; recovery hasil yang sudah finalized diperbolehkan.

## 8. Lifecycle app dan akun

Saat foreground/launch: pulihkan sesi → identifikasi account scope → load draft lokal → rekonsiliasi file/command → refresh trip aktif → hapus akses/cache yang dicabut. Snapshot tidak menghalangi pembacaan draft yang sah bagi akun sama.

Saat background: simpan draft durable dan checkpoint upload; hentikan lokasi yang tidak diperlukan. Baseline tidak memulai finalisasi jurnal dengan presence lama dari background task. OS dapat menghentikan app; correctness tidak bergantung pada background callback pasti dijalankan.

Saat logout/account switch: hentikan task akun lama, lepas subscription, hapus material sesi yang sesuai, dan hilangkan akses cache privat dari akun baru. Penghapusan draft belum terkirim harus mengikuti kebijakan eksplisit; dapat ditahan dalam namespace akun lama yang tidak terbaca akun baru. Tidak pernah mengirim draft A dengan token B.

## 9. Penghapusan, pencabutan akses dan stale cache

Server memakai tombstone untuk resource privat yang dihapus; daftar/snapshot tidak menyajikan konten aktifnya. Client membuang snapshot dan media cache terkait setelah menerima deletion/access result. Draft yang merujuk resource terhapus menjadi orphan draft berlabel, bukan diterapkan ke stop baru yang kebetulan mirip.

Perangkat yang benar-benar offline belum mengetahui pencabutan hak. Dokumentasi produk harus mengakui batas ini. Tentukan access revalidation interval/lease bila distribusi membutuhkan batas offline; policy belum final pada DEC-06. Signed URL dan file lokal yang sudah diperoleh bukan mekanisme revocation instan.

## 10. Protokol delta lanjutan

Jika snapshot menjadi mahal, rancang change feed berdasarkan commit-safe cursor, tombstone dan filter hak akses. Jangan memakai sequence biasa seolah urutan allocation selalu sama dengan urutan commit: transaksi yang commit terlambat dapat terlewat. Feed memerlukan desain/tes concurrency, token expiry dan full-resync path. Fitur ini belum baseline.

## 11. Migrasi lokal dan verifikasi

Versikan schema SwiftData dan snapshot DTO secara terpisah. Migrasi lokal menjaga draft/command belum selesai. Jika cache rusak, cache dapat dibangun ulang; draft tidak otomatis dihapus untuk memperbaiki cache. Simpan backup migrasi yang tidak berisi rahasia dan uji rollback/restore pada fixture.

Kriteria tes: respons lama tidak menurunkan revision, snapshot parsial tidak menggantikan graph valid, draft selamat setelah kill/relaunch, timeout setelah commit tidak menggandakan objek, akun berbeda tidak melihat cache lama, dan koneksi pulih tidak mengunggah jurnal memakai presence kedatangan lama.
