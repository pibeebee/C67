# Batas arsitektur monorepo

**22 Oktober 2026.** Dokumen ini menjelaskan struktur awal. Kesepakatan pengguna: iOS UI, iOS Backend dan Server berada di satu repository. VIPER adalah arah awal aplikasi iOS. Pemilihan framework/backend tetap terbuka.

## Tanggung jawab dan arah dependency

```text
ios-ui: View → Presenter → Interactor
                     └──→ Router
                               (wiring melalui Assembly/CompositionRoot)

Interactor → ios-backend: Application / Domain protocols
Data + Platform ────────→ Application / Domain protocols
CompositionRoot ───────→ implementasi Data + Platform

Data/Remote ⇄ API server     [kontrak di contracts/]
Server → database / object storage / worker
```

Diagram menunjukkan hubungan kode dan pertukaran data yang dituju; folder belum menjadi target compiler atau layanan yang berjalan. Domain tidak mengimpor UI atau SDK vendor. Composition root adalah tempat menghubungkan implementasi konkret.

| Bagian VIPER | Lokasi |
|---|---|
| View, Presenter, Router | `ios-ui/Features/<Feature>/` |
| Interactor | Fitur yang sama; menjalankan use case melalui protocol domain/aplikasi. |
| Entity | `ios-backend/Sources/Domain/Entities/`, dibagi lintas fitur bila identitasnya sama. |
| Factory/wiring tambahan | Assembly fitur dan App/CompositionRoot. |

Interactor yang sederhana tidak wajib mendelegasikan ke wrapper UseCase identik. Pisahkan layanan application bila alur dipakai bersama atau perlu koordinasi di luar satu fitur. Aturan domain hanya memiliki satu implementasi client yang dipakai bersama; server tetap menegakkan otorisasinya sendiri terhadap request yang tidak dipercaya.

## Bentuk server yang disarankan

Mulai dengan modul accounts, discovery, rundowns, trips, journals dan media di satu codebase. Pilih runtime/API entrypoint setelah stack disepakati. Batas worker media disediakan karena beban pemrosesan berbeda; belum menjadi keputusan host atau jumlah deployment. Detail dan konsekuensinya ada pada [usulan server](decisions/0002-server-architecture.md).

Satu monorepo tidak mengharuskan satu bahasa atau satu proses deploy. Pemilihan runtime, dependency manager, provider dan CI menunggu bootstrap implementasi. Kontrak API dan migrasi masing-masing memiliki satu sumber yang dipelihara.

## Aturan produk yang memengaruhi semua bagian

- Rundown/versi kreator berbeda dari salinan trip traveller; terbitnya versi baru tidak menimpa trip lama.
- Jam saran kreator, jadwal pengguna, forecast dan kejadian aktual dipisahkan.
- Draft foto, bytes terkirim, jurnal diterima, stop selesai dan trip selesai adalah keadaan berbeda.
- GPS saat tindakan unggah tetap diperlukan; policy transfer/finalisasi belum final. Jangan membuat izin unggah permanen berdasarkan arrival lama.
- Merge, otomatisasi cuaca, audience foto, skip/partial completion dan hak salinan tidak diaktifkan dari asumsi scaffold.

## Slice berikutnya yang disarankan

Setelah bootstrap dan pemilihan stack, mulai dengan katalog rundown terkurasi → detail → copy ke trip pribadi melalui satu kontrak. Berikutnya buktikan satu stop + satu foto sampai penerimaan server, termasuk draft recovery dan keputusan presence. Baru perluas fitur. Ini urutan usulan, belum otorisasi implementasi atau hasil tes.

Dasar pemisahan VIPER: [artikel penulis VIPER](https://www.objc.io/issues/13-architecture/viper/). Pemisahan folder, adaptasi Interactor/use case, dan bentuk server di atas adalah pilihan proyek, bukan aturan framework tersebut.
