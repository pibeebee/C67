# Navigasi POC 0.6 — QR, peta, rundown & routing

19 Oktober 2026 · build 8. Perapihan presentasi setelah penambahan QR v3.

| Keperluan | Lokasi tunggal pada alur utama |
|---|---|
| Membuat perjalanan dan mengundang peserta | Rombongan → Undang peserta lewat QR |
| Membuat perjalanan pengganti | Layar QR → Buat perjalanan baru; koneksi lama harus selesai |
| Bergabung ke perjalanan | Peserta → Scan QR perjalanan |
| Durasi, layar terkunci, consent | Pop-up setelah Gabung perjalanan; untuk sesi baru lewat pop-up Lanjutkan berbagi lokasi |
| Melihat status peserta/lokasi dan berhenti | Peserta |
| Membuat/edit kegiatan, waktu, lokasi dan ekspor Calendar | Rombongan → Rundown perjalanan → kegiatan |
| Melihat rundown sebagai peserta | Peserta → Rundown perjalanan (baca-saja) |
| Mengatur pin/radius meeting point | Ikon kanan atas Rombongan → Meeting point |
| Peta semua lokasi peserta, pilih detail dan geser/zoom | Rombongan → Peta rombongan |
| Mulai/berhenti lokasi TL | Rombongan → Bagikan lokasi saya ke peserta |
| Peserta melihat TL & diri sendiri | Peserta → Lihat posisi tour leader |
| Mengikuti lokasi TL/peserta | Peta peran terkait → pilih orang → Ikuti posisi |
| Rute kegiatan/meeting point | Peta → pilih kegiatan atau Meeting point → Rute |
| Eksperimen DDS 0–5 | Lab → Lab rute dinamis |
| Pemeriksaan dan tindak lanjut | Rombongan → peserta yang dipilih |
| Undangan manual, Run ID, fixture/reset pengujian | Lab → Pairing manual → pilih peran |
| Uji GPS lokal, akun iCloud dan status izin | Lab → GPS & iCloud |
| Pengukuran, failure probe, ekspor | Lab |

## Yang dibersihkan

- Form Run ID, pilihan P01–P04, instruksi undangan manual dan alat sensor dihapus dari halaman Peserta sehari-hari.
- Nomor langkah 1–2–3 tidak dipakai pada halaman Peserta. Setelah QR, tidak ada lagi langkah 3 tanpa langkah 1–2.
- Durasi/consent tidak lagi ditampilkan permanen di halaman Peserta. Pengguna hanya melihatnya ketika memilih bergabung atau melanjutkan.
- Konfirmasi QR dan melanjutkan koneksi menggunakan komponen pop-up persetujuan yang sama; persetujuan diberikan dengan tombol eksplisit, tanpa switch centang pada alur utama. Form konfirmasi disembunyikan selama pairing; setelah sesi sensor dimulai, pengguna kembali ke halaman Peserta.
- Pengaturan TL hanya berisi meeting point. Tidak ada pembuatan run fixture atau undangan manual di sana.
- Pembuatan perjalanan biasa tetap satu jalur melalui layar QR. Reset empat fixture menjadi alat pengujian di Lab dengan konfirmasi penggantian data.

## Koneksi tersimpan dan pemulihan

Saat ada owner/share tersimpan, Peserta menampilkan nama perjalanan/penerima, status, **Lanjutkan berbagi lokasi** bila sensor belum aktif, serta **Hentikan berbagi & putuskan koneksi**. Tombol scan disembunyikan sampai koneksi lama selesai. Jika app dibuka ulang, GPS tetap OFF.

Lanjutkan membuka pop-up dan memeriksa penerima privat tersimpan. Start tetap disabled sampai pemeriksaan koneksi berhasil dan consent baru diberikan. CloudKit yang gagal diperiksa tidak diperlakukan sebagai koneksi valid berdasarkan cache UI lama. Stop tersedia pada halaman Peserta, termasuk ketika pairing terputus setelah owner reference dibuat.

Mode uji GPS lokal tetap berada di Lab dan memakai pengaturan durasi untuk sensor lokal tanpa upload. Ini alat pengujian tersendiri, bukan setup berbagi kedua di alur utama.

[Penggunaan QR](QR_PAIRING_GUIDE.md) · [Verifikasi perapihan](verification/VERIFICATION_UI_CLEANUP.md).

[Panduan peta & lokasi TL 0.4](MAP_AND_LEADER_LOCATION.md). Koneksi lama perlu pairing ulang agar mendapat kanal lokasi TL; bidang baru tetap optional untuk memuat snapshot lama.

**0.4.1:** tombol Lokasi saya tersedia di kedua peta; sensor lokal peta tidak mengaktifkan upload. Meeting point default kosong; dapat disimpan/dihapus pada pengaturan TL. Angka/koordinat sensor mentah di halaman Peserta disederhanakan menjadi detail pin peta. [Verifikasi](verification/VERIFICATION_V41.md).

**0.5:** lokasi meeting point dipilih melalui pencarian/titik peta; pin kegiatan membuka detail rundown. TL dapat memilih kegiatan aktif dengan konfirmasi. Rundown dan meeting point disinkronkan melalui CloudKit, terpisah dari GPS. Calendar menyimpan salinan setelah pengguna mengonfirmasi editor native. [Panduan](ITINERARY_GUIDE.md).

**0.6:** routing memakai sumber GPS/CloudKit yang sama dengan pin peta, terpisah dari status hadir. Lab DDS 0–5 adalah eksperimen tersendiri; tahap 4–5 memakai Bonjour/TCP terenkripsi dan tidak mengubah pairing QR/CloudKit perjalanan. [Panduan routing](DYNAMIC_ROUTING.md).
