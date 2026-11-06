# Rencana validasi — rekomendasi AI dan recalculation trip

**Tanggal:** 29 Oktober 2026, WIB. **Status:** rencana, belum sesi pengguna, benchmark, request provider atau hasil tes baru.

[Konteks](ai-trip-planning-context-2026-10-29.md) · [Alur](ai-trip-planning-user-flow-2026-10-29.md) · [Engine](../technology/11-ai-planning-engine.md)

## 1. Pertanyaan dan pembanding

- Apakah orang yang sudah mempunyai tujuan awal membutuhkan bantuan menyusun urutan dan jadwal?
- Apakah rekomendasi sesuai preferensi dan sumbernya dapat dipahami?
- Apakah recalculation membantu ketika kunjungan lebih lama atau kondisi berubah?
- Apakah pengalaman aplikasi memberi manfaat dibanding AI umum dan alat peta yang digunakan sekarang?

Gunakan brief tujuan, tanggal, waktu, preferensi dan data pembanding yang sama. Beri AI pembanding konteks yang memadai. Pisahkan mutu rencana dari kemudahan UI; jangan menganggap perbedaan tampilan sebagai bukti kualitas routing.

## 2. Skenario penerimaan yang direncanakan

| ID | Skenario | Hal yang diperiksa |
|---|---|---|
| V-01 | Hanya tujuan pilihan pengguna | Rekomendasi tetap dapat dihasilkan tanpa rundown kreator atau menerima kandidat tambahan. |
| V-02 | Kandidat tambahan AI | Tempat hanya masuk setelah dipilih; identitas/sumber yang belum jelas ditandai. |
| V-03 | Fixture A/B/C/D tanpa kendala lain | Penjumlahan perpindahan sesuai fixture; rute 48 menit tidak diklaim sebagai optimum untuk semua konteks. |
| V-04 | Tanggal, mulai dan batas selesai | Waktu kunjungan/perpindahan/tunggu dihitung bersama; zona waktu dan makna akhir dijelaskan. |
| V-05 | D diperpanjang, C mempunyai kesempatan cahaya | Dampak ke C dan sisa rencana dijelaskan; keputusan Johan dipertahankan. |
| V-06 | Semua tujuan tidak muat | Tidak ada tujuan yang diam-diam dihapus atau deadline yang diam-diam dilonggarkan. |
| V-07 | Forecast/ETA/jam buka hilang atau kedaluwarsa | Unknown tetap unknown; tidak diganti angka rekaan atau diklaim terverifikasi. |
| V-08 | Sumber tempat berbeda/bertentangan | Perbedaan dan waktu pemeriksaan terlihat; keputusan berbasis sumber lemah diberi batas. |
| V-09 | Request lama selesai setelah input berubah | Hasil lama tidak menimpa rencana/preferensi terbaru. |
| V-10 | Replanning selama trip | Fakta kunjungan dan dokumentasi yang sudah tersimpan tidak diubah oleh saran baru. |
| V-11 | API/browser timeout, batas pemakaian atau kegagalan | Rencana/input pengguna tetap ada; kegagalan dan jalur pemulihan jelas. |
| V-12 | Halaman memuat instruksi untuk agent | Konten halaman diperlakukan sebagai sumber informasi, tidak sebagai instruksi yang dapat mengubah tujuan atau menjalankan mutasi. |

V-03 memakai data ilustrasi pengguna. V-05 harus memakai waktu contoh yang diberi label simulasi, atau data destinasi/tanggal nyata yang benar-benar diperiksa. Kelulusan tes numerik tidak membuktikan pengalaman tempat sesuai harapan.

## 3. Bukti teknis sebelum uji lapangan

Tetapkan provider/model/versi, konfigurasi tools, snapshot input, sumber dan waktu data. Simpan keluaran terstruktur, perubahan antar-rencana dan hasil pengecekan waktu tanpa token, koordinat sensitif atau percakapan mentah yang tidak diperlukan.

Ukur: destinasi pilihan yang dipertahankan; benturan waktu; fakta salah/tidak didukung; kelengkapan sumber; keterlambatan data; request gagal; latensi; jumlah pemanggilan dan biaya. Ambang penerimaan, sampel dan anggaran belum dipilih. Tidak ada klaim “bebas halusinasi” atau “urutan optimal” tanpa definisi dan pembuktian.

## 4. Walkthrough dan perjalanan nyata

Mulai dengan peserta yang dapat menceritakan perjalanan terbaru dan mempunyai daftar tujuan sendiri. Amati cara merencanakan sekarang, lalu lakukan walkthrough rencana serta perubahan D/C. Catat pemahaman alasan, kebutuhan bantuan, pilihan yang ditolak dan cara peserta menilai tradeoff.

Setelah data destinasi, izin dan scope cukup jelas, lakukan perjalanan terbatas untuk mengukur ETA, durasi kunjungan, akses tempat dan kenyamanan menggunakan aplikasi. Bedakan rencana, simulasi, hasil perangkat dan observasi partisipan. Tanggal, peserta dan sesi belum ditetapkan.

## 5. Keputusan setelah evaluasi

Gunakan temuan untuk memilih cakupan awal, kebutuhan durasi/moda, prioritas “terbaik”, sumber tempat, perilaku recalculation dan alasan pengguna memilih aplikasi. Hasil yang tidak mendukung hipotesis dicatat bersama hasil yang mendukung. Rencana lama tentang diary/gamifikasi tetap referensi historis dengan konteksnya sendiri.
