# POC v2 — panduan demo

**Riwayat v2:** untuk onboarding QR dan roster dinamis terbaru, gunakan [panduan v3](QR_PAIRING_GUIDE.md). Alur manual di bawah tetap fallback.

15 Oktober 2026. Fokus iterasi ini adalah **tampilan dan demo**, sesuai pilihan pengguna. Dukungan GPS tetap satu peserta ke satu TL; roster empat orang merupakan fixture.

## Apa yang berubah

- Tab **Rombongan**: ringkasan progres, peserta belum diperiksa, kasus terbuka dan pengecualian terlihat lebih dahulu. Aksi **Review pemeriksaan** tetap mudah dijangkau di bawah layar.
- Daftar peserta punya pencarian dan filter Semua / Belum diperiksa / Tindak lanjut / Diperiksa / Tidak ikut. Filter tidak mengubah ringkasan global.
- Detail peserta menyediakan aksi pemeriksaan utama. Koreksi, pengecualian dan tindak lanjut membuka form catatan khusus agar input hanya muncul saat dibutuhkan.
- Tombol **Demo** membuka empat skenario sintetis. Setiap pemuatan meminta konfirmasi mengganti run/riwayat lokal. Jika GPS, share atau undangan masih aktif, pemuatan diblokir; cleanup terlebih dahulu.
- Ikon kanan atas Rombongan membuka **Meeting point**. Run ID, pairing manual dan reset fixture kini berada di **Lab → Pairing manual**; undangan masuk membuka review manual.
- **Peta rombongan** membuka peta, umur data dan kualitas; koordinat/sequence ada dalam Detail pengukuran. Dashboard tetap menampilkan umur sampel tanpa harus membuka peta.
- Tab **Peserta** sekarang berfokus pada scan QR, status koneksi dan Stop. Durasi/consent tampil ketika bergabung atau memilih Lanjutkan berbagi. Tab **Lab** menampung alat manual dan diagnostik.

## Demo 3 menit, cukup satu iPhone atau Simulator

1. Buka **Rombongan → Demo → Satu peserta belum kembali → Muat skenario demo**. Dialog menjelaskan penggantian data; batalkan bila run saat ini ingin dipertahankan. Jangan hapus aplikasi untuk upgrade ini.
2. Tunjukkan ringkasan **2 dari 3 diperiksa**, **1 belum diperiksa**, **1 tindak lanjut**, **1 tidak ikut**. Empat orang tetap ada dalam roster. Ini kasus yang disiapkan secara sintetis, bukan insiden pengguna.
3. Pakai filter **Tindak lanjut**. Buka **Ayu · P01**: ia belum diperiksa, kasus belum selesai, dan lokasi hanya petunjuk. Buka **Lokasi tambahan** untuk melihat umur dan kualitas jika diperlukan. Peta rombongan kini memuat seluruh sampel demo sekaligus; tab Peserta mempunyai demo posisi TL.
4. Tekan **Tandai diperiksa** setelah menjelaskan bahwa ini mensimulasikan pemeriksaan TL. Kasus tidak otomatis selesai. Pilih **Selesaikan dengan hasil**, tulis hasil dan simpan.
5. Kembali ke dashboard → **Review pemeriksaan**. Periksa catatan Citra yang tidak ikut, lalu **Tutup pemeriksaan normal**. Penutupan bukan perintah kendaraan berangkat atau klaim semua aman.
6. **Mulai sesi berikutnya**: semua pemeriksaan mulai baru. Riwayat lama dapat dibuka lewat **Riwayat pemeriksaan**.

Alternatif: muat **Lokasi tidak lagi baru** untuk memperlihatkan label Kedaluwarsa; atau **Pemeriksaan lengkap** untuk langsung mencoba review. **Mulai pemeriksaan** memulai demo dari empat orang yang belum diperiksa.

## Lanjut uji dua atau lebih iPhone

Gunakan [panduan QR terbaru](QR_PAIRING_GUIDE.md). Fallback manual dan uji GPS lokal sekarang berada di Lab; lihat [peta navigasi 0.3.1](UI_NAVIGATION.md).

## Bukti dan batas

Pengguna melaporkan alur POC dua iPhone sebelumnya berhasil. Ini laporan pengguna, bukan hasil pengukuran ulang oleh agen. Iterasi UI ini tidak mengubah schema CloudKit maupun menambah pelacakan multi-peserta. Setelah update, ulangi pairing/Start/Stop pada dua perangkat sebelum menilai regresi jalur nyata.

Pemrosesan lokasi, expiry, izin, antrean upload, dan kontrol baca CloudKit dipertahankan. Format payload RunState/SwiftData tetap sama; update aplikasi tidak mereset run yang tersimpan otomatis. Demo secara sengaja mengganti run hanya setelah konfirmasi dan setelah pengecekan tidak ada share/sensor aktif.

Mode sintetis selalu berlabel **DEMO · SIMULASI** dan laporan tidak menganggapnya bukti GPS/background. Lulus demo tidak membuktikan manfaat operasional, akurasi GPS di bus, skala rombongan, atau kelulusan App Review.

Untuk screenshot tanpa menimpa data lokal, developer dapat memakai launch argument `--demo-preview`. Ini membuat store in-memory dan skenario regroup; tidak ditambahkan pada scheme Run normal. `--large-text` memberi ukuran teks accessibility3 untuk pemeriksaan, bukan pengganti VoiceOver manual.

## Demo tambahan 0.5

Muat skenario Satu peserta belum kembali, lalu Rombongan → Rundown perjalanan. Pilih Kembali ke bus → Lihat pada peta; pin kegiatan berbeda dari pin peserta. Kembali ke detail → Jadikan titik berkumpul aktif → konfirmasi. Ekspor Calendar membuka editor Apple; batalkan untuk demo tanpa menambah jadwal. Kunjungan museum memiliki pin lain dan Waktu bebas tidak mempunyai lokasi. [Panduan](ITINERARY_GUIDE.md).
