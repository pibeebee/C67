# iOS Backend

Kode non-UI yang **berjalan di iPhone**, terpisah dari server remote. Struktur ini disiapkan sebagai calon local Swift package; `Package.swift`, target dan dependency belum dibuat.

```text
ios-backend/
├── Sources/
│   ├── Domain/
│   │   ├── Entities/
│   │   ├── Rules/
│   │   └── Repositories/   # protocol kebutuhan data domain
│   ├── Application/
│   │   ├── UseCases/       # alur/logika yang dipakai lintas fitur
│   │   └── Sync/           # recovery, snapshot dan koordinasi cache
│   ├── Data/
│   │   ├── Repositories/   # implementasi protocol domain
│   │   ├── Remote/         # client API, DTO dan mapping error
│   │   ├── Local/          # persistensi lokal dan mapping model
│   │   └── Files/          # draft foto dan cache media
│   ├── Platform/
│   │   ├── Location/
│   │   ├── Media/
│   │   ├── Places/
│   │   ├── Weather/
│   │   └── Authentication/
│   └── Configuration/
└── Tests/{Domain,Application,Data,Platform}/
```

## Batas dependency

- Domain tidak mengenal UI, storage, DTO atau provider. Simpan Entity dan aturan bisnis yang berlaku bersama di sini.
- Application memakai Domain serta protocol yang diperlukan; tidak mengimpor implementasi Data/Platform. Protocol kemampuan perangkat dapat diletakkan di Application dekat use case pemakainya.
- Data dan Platform mengimplementasikan protocol dari lapisan dalam; UI composition root menghubungkannya.
- Interactor VIPER memakai batas tersebut; tidak mengulang aturan waktu, merge atau presence di Presenter/View.

Direktori belum menjadi modul compiler yang menegakkan arah import. Saat membuat local package, wujudkan batas yang diperlukan sebagai target, dengan dependency mengarah ke Domain/Application. Jangan membuat satu package atau repository generik untuk setiap tabel. [Manifest Swift Package](https://docs.swift.org/package-manager/PackageDescription/PackageDescription.html) akan menentukan target yang benar-benar ada.

## Batas data

Cache server, draft lokal, command yang belum pasti hasilnya dan data yang telah diterima server memiliki status berbeda. SwiftData masih kandidat penyimpanan; sinkronisasi memerlukan implementasi tersendiri. Tidak ada upload otomatis dari lokasi lain hanya karena pengguna pernah tiba di pin.

Jaga scope akun, draft/file yang belum terkirim, identitas request dan pembatalan. Simpan sesi dengan secure credential storage; rahasia server tidak pernah masuk bundle aplikasi. Angka GPS, TTL dan policy final belum ditetapkan oleh scaffold.
