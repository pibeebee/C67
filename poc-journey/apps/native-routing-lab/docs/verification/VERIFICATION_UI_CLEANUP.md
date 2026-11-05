# Verifikasi perapihan UI — 0.3.1 build 4

15 Oktober 2026 · Asia/Jakarta. Pengguna meminta redundansi menu v3 dibersihkan. [Navigasi terbaru](../UI_NAVIGATION.md).

## Perubahan

- Peserta sebelum bergabung hanya menyediakan alur scan QR. Run ID, fixture, undangan manual dan alat sensor dipindah ke Lab.
- Koneksi tersimpan menampilkan identitas/status, Lanjutkan dan Stop. Consent tidak tampil permanen dan tidak ada nomor langkah 3 tanpa 1–2.
- Form durasi/background/consent dipakai ulang untuk konfirmasi QR atau resume, satu konteks pada satu waktu. Form QR disembunyikan selama pairing; setelah sensor mulai, layar kembali ke Peserta.
- Resume memeriksa penerima lagi dan Start disabled sampai koneksi terkonfirmasi serta consent baru diberikan. Label sensor dimulai tidak membuktikan sampel GPS sudah diterima.
- Pengaturan TL hanya mengatur meeting point. Pembuatan/penggantian perjalanan melalui layar QR. Reset fixture hanya di Lab dengan konfirmasi.
- Alat manual disembunyikan bila run sedang memakai QR; incoming invitation tetap dapat ditinjau. Reset fixture tetap ditolak saat koneksi masih tersimpan.
- State completed pairing dibersihkan saat sesi UI ditutup agar formulir untuk scan berikutnya tidak tertahan oleh completion lama.

## Hasil verifikasi

| Pemeriksaan | Hasil |
|---|---|
| Build + launch Simulator | Berhasil, tanpa warning compiler pada build final |
| Unit/integration | 40 tes lulus |
| UI | 12 tes unik lulus |
| Hasil terakhir per kasus | **52 lulus, 0 gagal, 0 skipped**; [ringkasan dan provenance](test-summary-ui-cleanup.json) |
| Build iPhone Debug signed | Berhasil, 0.3.1 build 4 |
| Signature | `codesign --verify --deep --strict --verbose=2` lulus; valid on disk / Designated Requirement |
| Inspeksi visual | [Peserta sebelum join](../../../../docs/missing-evidence.md#missing-7767e4f83ac4), [koneksi tersimpan](../../../../docs/missing-evidence.md#missing-0acae47148f8), [resume consent](../../../../docs/missing-evidence.md#missing-4b3ca7eef8e9) |

Full regression `/private/tmp/c67-ui-cleanup-tests.xcresult`: 51 lulus dan 1 gagal pada assertion tombol reset fixture yang berada di luar area render Form. Tombol diberi identifier stabil, lalu tes memakai helper scroll. Setelah guard UI final ditambahkan, `/private/tmp/c67-ui-cleanup-final.xcresult` mengulang seluruh 40 tes unit/integrasi dan 3 tes UI terkait; 43/43 lulus. Angka 52 adalah hasil terakhir per kasus dari kedua run, bukan klaim satu full run final tanpa kegagalan. Tidak ada failure yang diabaikan atau skipped dihitung lulus.

Tes UI baru mengonfirmasi: manual ada di Lab, pengaturan TL tidak menyediakan Run ID/reset, Peserta sebelum join tidak mempunyai form lama atau tombol Start, koneksi tersimpan tetap mempunyai Stop, dan consent hanya muncul setelah memilih Lanjutkan. Tes QR, pemeriksaan, follow-up, closure/reset dan ukuran teks aksesibilitas juga tetap dijalankan.

Screenshot koneksi tersimpan menggunakan fixture `--ui-resume-fixture`, hanya pada build DEBUG dengan store in-memory ketika argumen UI testing digunakan. Label mode Perangkat nyata pada fixture tersebut **bukan bukti koneksi/GPS fisik**. Resume di Simulator menampilkan penolakan CloudKit yang diharapkan dan Start tetap disabled. Tidak ada bypass izin atau simulasi keberhasilan provider. Scheme normal tidak menambahkan argumen fixture.

CloudLocationChannel, LocationService, SessionStore, DomainModels dan konfigurasi CloudKit/Info.plist tidak berubah pada iterasi ini. Data tersimpan tidak direset otomatis. Build/test tidak mengulang pairing antar-akun, GPS background, ACL server atau baterai fisik; batas uji fisik v3 tetap berlaku.

Log signed final: `/private/tmp/c67-ui-cleanup-signed-final.log`. Result bundles di atas dan output build di tmp dapat dibersihkan OS. Ringkasan/screenshot disimpan di proyek. [Panduan QR](../QR_PAIRING_GUIDE.md).
