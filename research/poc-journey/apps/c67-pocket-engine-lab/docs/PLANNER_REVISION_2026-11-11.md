# Pocket Engine · revisi rekomendasi dan planner

## Perubahan

- Jelajah menampilkan rekomendasi jika ada minimal tiga kandidat cocok yang lolos syarat. Pencarian katalog eksplisit tetap bisa mengembalikan satu atau dua hasil. Ini adalah ambang daftar rekomendasi. Pengguna tetap dapat menyusun itinerary dari jumlah tujuan yang mereka pilih.
- Rencana menerima keberangkatan tetap atau jendela fleksibel, jam kunjungan wajib atau diutamakan, serta tujuan yang harus terakhir. Perjalanan kembali tetap masuk batas pulang. Pemilihan jam diutamakan dilakukan dalam batas tunggu yang dikonfigurasi. Solver mengutamakan jumlah tujuan, kedekatan ke jam preferensi, lalu waktu selesai.
- Kandidat yang tutup lebih awal diprioritaskan di antara tujuan dengan tingkat kewajiban yang sama. Pencarian tetap beranggaran. Setelah jadwal lengkap dengan penalti preferensi nol ditemukan, planner membatasi pencarian tambahan. Perjalanan pulang hanya diminta untuk kandidat yang masih dapat memperbaiki hasil.
- Saat menghindari hujan, planner memeriksa batas jam prakiraan berikutnya dalam interval yang masih dapat ditunggu. Prakiraan harus mencakup kunjungan penuh. Prakiraan yang tidak lengkap dilaporkan terpisah dari peluang hujan di atas ambang.
- Kesalahan ETA yang ditandai sementara dapat dicoba ulang sekali pada ruas dan waktu yang sama, dengan maksimum tiga retry per penyusunan. Adaptor iOS memetakan kegagalan server MapKit serta beberapa kesalahan jaringan yang dapat pulih. Throttling menghentikan permintaan dalam penyusunan itu. ETA yang tetap tidak tersedia membuat ruas dilewati, tanpa durasi rekaan.

## Sebelum dan sesudah

Fixture yang sama seperti [benchmark awal](ACCEPTANCE_BENCHMARK_2026-11-11.md) dipakai kembali. Harness versi baru meneruskan jendela keberangkatan, jumlah minimum untuk brief, jam kunjungan, tujuan terakhir, dan jenis kegagalan sementara ke kontrak planner baru. Jumlah minimum tujuan untuk benchmark adalah permintaan skenario; ambang rekomendasi diuji lewat XCTest terpisah.

**11/18 → 18/18** pada lima pengulangan terukur per skenario, ditambah satu pemanasan. ETA dan prakiraan sintetis. Seluruh jadwal keluaran melewati pemeriksaan independen terhadap aturan fixture.

| Kasus | Sebelum | Sesudah |
| --- | --- | --- |
| Makan malam sebagai tujuan terakhir | Makan pukul 17.00 di urutan pertama | Makan pukul 18.00–18.50 di tujuan ketiga dan terakhir; kembali 18.55 |
| Berangkat fleksibel | Berangkat tetap 08.00, gagal | Memilih 17.40 dan kembali 18.50 dalam skenario waktu diutamakan |
| MACAN tepat pukul 14.00 | Mulai 12.40 | Mulai 14.00 |
| Lima tempat dengan MACAN sekitar 14.00 | MACAN 12.40, 60 permintaan ETA | MACAN 14.00, 18 permintaan ETA |
| Enam tempat dengan tujuan tutup awal | Tidak ada jadwal setelah 60 permintaan | Mengunjungi tujuan yang tutup awal pukul 09.10, seluruh tujuan masuk, 19 permintaan ETA |
| Hujan reda setelah tiba | Tidak ada jadwal | Menunggu 20 menit dalam batas fixture, kunjungan mulai 11.00 |
| ETA gagal sekali | Tidak ada jadwal | Memakai satu retry dan ETA yang berhasil. Kegagalan permanen tetap ditahan. |

Pencarian fleksibel memilih dari sejumlah jam yang disampel, dengan anggaran bersama antarkandidat keberangkatan. Pencarian jadwal menguji waktu tertentu yang tersedia dalam jam buka dan batas tunggu. Sebagian alternatif dapat terpotong. Angka di atas bukan ukuran latensi Apple atau jaminan hasil optimal. Ketersediaan tiket, kelengkapan katalog, dan perilaku runtime iPhone tidak diuji. Tidak ada panggilan Google, MapKit, atau WeatherKit live pada replay ini.

Log mentah, hasil audit, build dan tes versi ini berada di `.local/acceptance-verified-2026-11-11/`. Manifest tersimpan di `.local/acceptance-2026-11-11/fixtures.json`.
