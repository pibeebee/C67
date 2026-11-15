# Alur pengguna — menyusun dan memperbarui trip personal

**Tanggal:** 29 Oktober 2026, WIB. **Status:** rancangan alur berdasarkan keputusan pengguna; belum desain layar final atau implementasi.

[Konteks](ai-trip-planning-context-2026-10-29.md) · [CBL](../../../source-records/CBL.md) · [Engine](../technology/11-ai-planning-engine.md)

## 1. Menyiapkan tujuan

Pengguna memasukkan satu atau beberapa tempat yang ingin dikunjungi. Identitas lokasi perlu jelas; nama ambigu ditinjau sebelum dipakai. Ia memberikan preferensi yang relevan serta tanggal, jam berangkat dan batas selesai. Asal perjalanan dapat menggunakan lokasi perangkat bila diizinkan atau input manual sebagai usulan fallback.

Format onboarding dan field personalisasi belum dipilih. Titik pulang, moda dan durasi kunjungan perlu dijelaskan sebagai input tambahan atau asumsi yang dapat ditinjau, bukan ditebak sebagai fakta pengguna.

## 2. Menambah kegiatan bila diinginkan

Pengguna dapat meminta kandidat tempat tambahan. AI menyajikan pilihan dan alasan relevansinya. Memilih kandidat menambahkannya ke daftar rencana; melihat rekomendasi tidak otomatis menambahkan tempat. Pengguna dapat melanjutkan dengan daftar awalnya.

## 3. Meminta rencana

Sistem mengumpulkan konteks perjalanan dan informasi tempat. UI perlu membedakan proses yang masih berjalan, hasil parsial, data tidak tersedia dan kegagalan. Tidak ada angka cuaca/ETA/jam buka rekaan untuk menutupi input yang belum tersedia.

## 4. Meninjau rekomendasi

Usulan menampilkan urutan, perkiraan tiba/berangkat, durasi kunjungan, moda/perpindahan yang didukung, perkiraan selesai, alasan penting dan asumsi. Pengguna dapat melihat sumber atau ketidakpastian yang memengaruhi keputusan.

Bila rencana tidak muat, aplikasi menjelaskan benturannya. Mengganti atau melewati tujuan tetap pilihan pengguna. Rekomendasi golden hour menjadi kesempatan pengalaman, bukan larangan mengunjungi tempat pada waktu lain.

## 5. Menjalani perjalanan

Pengguna memahami tujuan sekarang, kegiatan yang ingin dilakukan, tujuan berikutnya dan waktu yang disarankan untuk berpindah. Mode navigasi, penentuan kedatangan, penandaan selesai, serta izin background belum dipilih. GPS dekat tempat tidak otomatis membuktikan kunjungan selesai.

## 6. Meminta atau menerima hasil recalculation

Contoh pemicu: pengguna memperpanjang kunjungan D, mengubah tujuan/preferensi, atau konteks perjalanan/cuaca yang relevan berubah. Cara pendeteksian dan frekuensi pembaruan masih terbuka.

Hasil memperlihatkan rencana sebelumnya, usulan baru, alasan dan dampaknya pada C/sisa perjalanan/batas selesai. Saran yang dibuat menggunakan rencana atau preferensi lama tidak ditampilkan sebagai saran terkini. Kebijakan penerapan otomatis, review dan undo perlu ditentukan; sistem tetap menghormati keputusan destinasi pengguna.

## 7. Menutup perjalanan dan memulihkan gangguan

Alur completion, trip sebagian, statistik dan album belum ditetapkan ulang. Jangan memakai kewajiban foto pada cerita lama sebagai syarat tersembunyi untuk rekomendasi baru.

| Keadaan | Perilaku target untuk ditinjau |
|---|---|
| Model/API/browser gagal | Pertahankan daftar tujuan dan rencana terakhir; jelaskan apa yang gagal serta pilihan mencoba lagi. |
| Cuaca atau ETA tidak tersedia | Tampilkan data yang hilang dan dampaknya; saran berbasis asumsi diberi label. |
| Izin lokasi ditolak | Tinjau pilihan asal manual dan batas rekomendasi tanpa posisi aktual. |
| Pengguna mengubah input saat request berjalan | Gunakan identitas request/rencana untuk menghindari hasil lama menimpa input baru. |
| Rencana tidak muat | Pertahankan tujuan; berikan pilihan penyesuaian kepada pengguna. |

Tabel di atas adalah rancangan penerimaan, belum hasil uji atau persetujuan setiap detail UI. Wireframe HTML revisi 2 masih merepresentasikan konsep terdahulu dan tidak diubah oleh pembaruan dokumen ini.
