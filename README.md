# C67

Monorepo aplikasi iOS untuk menemukan rundown perjalanan kreator, menyesuaikannya menjadi trip pribadi, menjalankan perjalanan per spot, dan mengumpulkan foto menjadi album.

**Status 22 Oktober 2026:** struktur folder dan dokumentasi awal. Repository asal masih kosong saat di-clone. Belum ada project Xcode, Swift package, implementasi fitur, dependency, database, atau server yang dapat dijalankan.

## Pembagian pekerjaan

| Folder | Tanggung jawab | Arah awal |
|---|---|---|
| [ios-ui](ios-ui/README.md) | App entry, SwiftUI, presentasi, navigasi, wiring modul | VIPER per fitur; Entity memakai model domain bersama. |
| [ios-backend](ios-backend/README.md) | Logika dan data **di perangkat**: domain, use case, repository, network, cache/draft, adapter Apple | Lapisan Domain, Application, Data, Platform; calon local Swift package. |
| [server](server/README.md) | Identitas/otorisasi, data bersama, transaksi, API, media dan job | Usulan modular monolith; framework/provider belum dipilih. |
| [contracts](contracts/README.md) | Kontrak API, schema payload dan fixture bersama | Satu sumber kontrak lintas iOS/server; belum ada endpoint/schema executable. |
| [docs](docs/architecture.md) | Konteks produk, batas arsitektur dan catatan keputusan | Memisahkan kesepakatan, usulan dan implementasi. |

```text
C67/
├── ios-ui/          # aplikasi dan modul VIPER
├── ios-backend/     # kode non-UI yang berjalan di iPhone
├── server/          # layanan dan data remote
├── contracts/       # kontrak pertukaran data
└── docs/            # konteks dan keputusan
```

## Mulai bekerja

1. Baca [konteks produk](docs/product-context.md) dan [batas arsitektur](docs/architecture.md).
2. Baca README area pekerjaan masing-masing; direktori kosong dipertahankan dengan `.gitkeep`.
3. Saat bootstrap iOS, buat project Xcode di `ios-ui/` dan local Swift package di `ios-backend/`, lalu hubungkan melalui local package reference. Manifest dan target compiler belum dibuat pada tahap foldering ini.
4. Saat bootstrap server, pilih stack melalui [catatan usulan server](docs/decisions/0002-server-architecture.md), kemudian tambahkan runtime, lockfile, konfigurasi lokal dan pemeriksaan yang sesuai.
5. Sepakati kontrak slice pertama di `contracts/` sebelum UI dan server mengimplementasikannya secara terpisah.

Folder fitur adalah pengelompokan kode, bukan penetapan tab/layar atau komitmen membangun semua fitur pada sprint pertama. PoC terdahulu tetap berada di repository terpisah; belum diimpor.

## Kolaborasi

Perubahan kontrak dibahas lintas iOS Backend dan Server. Perubahan aturan bisnis diselaraskan dengan UI dan konteks produk; keputusan akses dan penerimaan data tetap ditegakkan server. Gunakan branch `gi/<topik>` saat mulai pengembangan. Commit/push dan deployment mengikuti tahap pekerjaan yang disepakati.

Dependency, toolchain dan konfigurasi bersama ditambahkan saat bootstrap nyata. Simpan lockfile, gunakan konfigurasi contoh tanpa rahasia, dan catat bukti build/test sesuai lapisan yang benar-benar diuji.
