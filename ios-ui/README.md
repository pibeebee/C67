# iOS UI

Area aplikasi iOS dan presentasi SwiftUI. Arah awal tim adalah VIPER per fitur. Folder saat ini belum terdaftar pada project Xcode dan belum berisi kode aplikasi.

```text
ios-ui/
├── App/
│   ├── CompositionRoot/     # membuat dan menghubungkan dependency konkret
│   └── Navigation/          # state navigasi tingkat app
├── Features/
│   ├── Discovery/
│   ├── Rundown/
│   ├── Trip/
│   ├── Journal/
│   ├── Album/
│   ├── Creator/
│   └── Account/
├── Shared/
│   ├── Components/
│   └── DesignSystem/
├── Resources/
├── Templates/VIPER/         # slot struktur untuk fitur baru
└── Tests/
    ├── Unit/
    └── UI/
```

## Struktur satu fitur

Gunakan struktur pada `Templates/VIPER/` ketika fitur mulai dibangun:

| Bagian | Tanggung jawab |
|---|---|
| `View/` | SwiftUI View; menampilkan state dan meneruskan aksi. |
| `Interactor/` | Mengimplementasikan alur use case fitur melalui protocol; menggunakan domain/repository dan layanan bersama dari iOS Backend. |
| `Presenter/` | State presentasi dan pemetaan hasil ke tampilan; perubahan state UI terisolasi pada main actor. |
| `Router/` | Tujuan dan aksi navigasi; tidak menjalankan networking atau aturan domain. |
| `Assembly/` | Factory/wiring modul; menerima dependency dari composition root. |

**Entity** pada VIPER berasal dari `ios-backend/Sources/Domain/Entities/`; tidak dibuat salinan entity berbeda untuk setiap layar. View state boleh memiliki tipe presentasi sendiri. Assembly adalah tambahan untuk wiring, bukan huruf baru pada VIPER.

Interactor tetap menjadi bagian VIPER suatu fitur. `Application/UseCases` di iOS Backend menampung logika yang perlu digunakan lintas fitur; jangan menyalin aturan bisnis atau mewajibkan dua wrapper identik untuk satu operasi sederhana. Batas ini merupakan adaptasi proyek terhadap [pembagian tanggung jawab VIPER](https://www.objc.io/issues/13-architecture/viper/).

UI bergantung pada protocol/use case/domain, bukan DTO API, objek SwiftData atau SDK provider secara langsung. Composition root dapat mengenal implementasi Data/Platform untuk dependency injection. Router fitur tidak mengimpor View fitur lain untuk membentuk dependency melingkar; gunakan factory atau route tingkat app.

Simpan fixture tampilan dengan label simulasi. Pemilih foto dan permintaan izin dipicu oleh tindakan yang relevan; aturan penerimaan jurnal/presence tidak boleh diputuskan hanya dari state UI. Saat bootstrap, hubungkan local package `../ios-backend`; target dan versi toolchain ditentukan pada pekerjaan tersebut.
