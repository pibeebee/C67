# Verifikasi POC 0.4.1 — lokasi sendiri, meeting point opsional, persetujuan pop-up

15 Oktober 2026 · versi 0.4.1 build 6 · iOS 18+ · Simulator iPhone 18 Pro iOS 27.

## Perubahan dan hasil

| Permintaan | Implementasi | Bukti dan batas |
|---|---|---|
| Tampilkan lokasi kita | Pin Anda / Anda · TL dan tombol Lokasi saya pada kedua peta. Sensor berbagi yang sudah aktif dipakai kembali; jika tidak ada, sensor lokal milik layar peta berjalan tanpa callback upload dan tanpa sesi background. Sensor lokal berhenti ketika peta ditutup/background. | Tes model untuk kedua peran dan lokasi invalid/run salah; UI memilih pin sendiri untuk kedua peran. API Core Location di Simulator menerima koordinat sintetis dan menampilkan posisi tanpa koneksi/sesi berbagi. Belum GPS iPhone fisik. |
| Meeting point default null | Koordinat optional; `meetingPoint` bernilai nil pada run/perjalanan baru. Pin, lingkaran dan tombol meeting point hanya muncul bila titik valid. Simpan/hapus tersedia pada pengaturan TL. | Tes default/reload/save/clear, decode JSON lama/missing/null/parsial, journey baru/join. UI default kosong → simpan → tampil pin → hapus → kosong lulus. Data lama dipertahankan; fixture Monas hanya ditetapkan eksplisit pada skenario demo. |
| Persetujuan peserta sebagai pop-up | Gabung perjalanan membuka sheet native berisi penerima, durasi, opsi layar terkunci dan Setuju & gabung. Resume memakai komponen yang sama dengan Setuju & mulai berbagi setelah koneksi dikonfirmasi. Tidak ada switch consent pada form scan/halaman utama. | UI mengubah durasi 30 → 35 menit, memeriksa teks persetujuan, batal, memastikan pairing belum dimulai, lalu membuka ulang pop-up. Resume tetap disabled jika koneksi privat gagal diperiksa. Pairing/cloud setelah konfirmasi tetap perlu uji fisik. |

## Hasil otomatis

- **58 unit/integration unik + 19 UI unik = 77 kasus unik**, hasil terbaru **77 passed, 0 failed, 0 skipped**. Ini gabungan regresi dan satu tes ulang, bukan satu run 77/77.
- Regresi final `/private/tmp/c67-v41-final-tests.xcresult` selesai dan terfinalisasi: **76 passed, 1 failed**. Kegagalan berasal dari selector tes Stepper `Increment`; hierarchy aktual memakai `participant-sharing-duration-Increment`. Selector diperbaiki tanpa mengubah kode aplikasi.
- Rerun kasus tersebut `/private/tmp/c67-v41-consent-rerun.xcresult`: **1/1 passed, TEST SUCCEEDED**. [Ringkasan hasil/provenance](test-summary-v41.json) menyimpan ringkasan resmi kedua bundle dan hasil terbaru per kasus.
- Run awal `/private/tmp/c67-v41-tests.xcresult`: 58 unit/integration lulus, 17/18 UI lulus. Satu kegagalan nyata penempatan tombol Satelit di luar area horizontal diperbaiki dengan memindahkan kontrol ke toolbar; kasus itu lulus pada regresi final.
- Build Debug iPhone signed **berhasil**, versi **0.4.1 build 6**. `codesign --verify --deep --strict --verbose=2` lulus pada produk final. Log build: `/private/tmp/c67-v41-signed-final.log`.
- Screenshot lokal, map kosong dan pop-up telah diinspeksi: [lokasi lokal](../../../../docs/missing-evidence.md#missing-8b1ceb7706c3), [meeting point kosong](../../../../docs/missing-evidence.md#missing-f92e90d8c408), [persetujuan](../../../../docs/missing-evidence.md#missing-12fd5f5f5819). Logo/legal Maps tetap terlihat; Form pada sheet dapat di-scroll.

Semua tes memakai store in-memory. Tes lokasi lokal memakai flag Debug `--ui-real-map-fixture`, izin lokasi Simulator dan koordinat sintetis dari simctl; tidak membuat share CloudKit. Skenario sintetis Simulator dihentikan setelah pengujian.

## Kompatibilitas dan batas

- Protokol QR menjadi **versi 3** karena meeting point kini boleh kosong; v1/v2 ditolak secara eksplisit. Kedua iPhone harus diperbarui untuk pairing baru. Koneksi 0.4 yang sudah lengkap dan riwayat/titik tersimpan tetap dimuat; update tidak melakukan reset otomatis.
- Welcome tetap bertanda tangan, termasuk keberadaan/isi meeting point. Null valid; titik invalid atau perubahan tanpa signature valid ditolak. Referensi cleanup dan akses privat tidak diubah.
- Menampilkan lokasi sendiri tidak mengaktifkan pengiriman. Pengiriman peserta tetap memerlukan konfirmasi pop-up dan izin iOS; pengiriman TL tetap membutuhkan consent/Start TL sendiri. Alat pairing manual di Lab mempertahankan consent switch diagnostiknya.
- Sensor lokal layar peta dibatasi dua jam per pembukaan dan tidak memiliki sesi background. Sesi berbagi yang aktif tetap memiliki durasi/Stop sendiri dan tidak dihentikan hanya karena peta ditutup.
- Meeting point peserta masih snapshot saat pairing, belum live sync. Menghapus/mengubah titik TL tidak menarik kembali snapshot peserta yang sudah terhubung.
- Pairing QR v3 tanpa meeting point pada beberapa akun iPhone fisik, izin ditolak/dicabut, lifecycle foreground/background pada perangkat fisik, baterai, skala, ACL akun lain, aksesibilitas penuh dan App Review **belum diuji pada iterasi ini**. Batas [versi 0.4](VERIFICATION_V4.md) tetap berlaku.

## Reproduksi uji lokal Simulator

Untuk tes `testRealMapShowsLocalGPSWithoutStartingSharing`, install aplikasi pada Simulator terlebih dahulu, grant location untuk `giovanchristoffel.poc-c67`, lalu set koordinat sintetis menggunakan `simctl location <device> set '-6.1754,106.8272'`. Jalankan tes scheme poc-c67 dengan `-parallel-testing-enabled NO -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO`. Setelah tes, gunakan `simctl location <device> clear`. Tes ini tidak membuktikan GPS lapangan atau koneksi CloudKit.
