# Handoff riset untuk wireframe keseluruhan aplikasi

**Status konteks — 29 Oktober 2026:** Handoff ini menyimpan asumsi desain 21 Oktober. Keharusan kreator/library/merge dan pembatasan AI di dalamnya tidak menjadi batas aktif setelah instruksi pengguna 29 Oktober. Lihat [acuan aktif](ai-trip-planning-user-flow-2026-10-29.md).

**Tanggal:** 21 Oktober 2026.  
**Baca terlebih dahulu:** [CBL.md](../../../source-records/CBL.md), lalu [riset aplikasi dan Apple HIG](../research/rundown-app-design-hig-research-2026-10-21.md).  
**Status:** inventory dan rekomendasi untuk prompt wireframe berikutnya. Belum wireframe final, spesifikasi implementasi, atau keputusan baru dari pengguna.

## 1. Dasar yang sudah diberikan pengguna

- Kreator membuat rundown berbasis pengalaman: urutan spot, waktu yang disarankan, durasi, transportasi, golden hour, cuaca, dan informasi waktu.
- Pengguna memilih rundown, mengatur pelaksanaan, serta dapat menambahkan rundown kreator lain ke rencana yang sudah dimiliki.
- Konteks waktunya dapat berupa besok atau waktu yang tersedia/tersisa.
- Pin, foto, dan cerita tetap fitur map; foto/GPS mendukung travel journaling.
- GPS harus memenuhi aturan di area pin saat tombol unggah ditekan. Menyimpan riwayat kedatangan tidak otomatis membuka unggahan dari jauh.
- Peran kreator/pengguna bukan keputusan membuat akun terpisah. Cerita khusus User B belum diberikan.
- Contoh kota/area dipakai untuk penjelasan; produk akhir sampai level spot.

**Belum dipilih:** home/tab final, logika merge, pemilihan sebagian rundown, deduplikasi, penggeseran waktu otomatis, sumber data dinamis, aturan distribusi, dan ownership/sinkronisasi salinan. Semua proposal di bawah harus mempertahankan label ini.

## 2. Model pengalaman yang diusulkan

| Objek yang perlu dipahami pengguna | Isi/arti dalam UI | Pemisahan yang harus terlihat |
|---|---|---|
| Rundown kreator | Panduan sumber dengan penulis, urutan, jam saran, durasi, perpindahan, catatan. | Melihat sumber tidak sama dengan mengubah perjalanan sendiri. |
| Rundown tersimpan | Referensi yang dibookmark/disimpan untuk nanti. | Belum otomatis dijadwalkan atau tersedia sepenuhnya offline. |
| Perjalanan pribadi | Rundown yang digunakan untuk tanggal/waktu pengguna. | Jadwal pribadi dapat berbeda dari saran kreator; atribusi tetap terbaca. |
| Kegiatan/spot | Kunjungan dengan jam dan durasi. | Waktu rencana versus kejadian aktual. |
| Perpindahan | Segmen dari kegiatan satu ke berikutnya. | Moda, durasi, dan sumber estimasi; bukan kegiatan kunjungan. |
| Usulan penggabungan | Perubahan yang belum diterapkan. | Rencana awal tetap utuh sampai diterapkan; sumber/target jelas. |
| Entri jurnal | Dokumentasi pengalaman milik pengguna pada spot/perjalanan. | Lokasi terverifikasi, foto terpilih, tersimpan lokal, dan terkirim adalah keadaan berbeda. |

Ini model pemahaman desain, bukan schema backend yang sudah disepakati.

## 3. Navigasi dan entry point — Proposed

Kandidat utama untuk diuji: **Jelajah · Perjalanan · Jurnal · Karya**. Alternatif tiga tab menggabungkan akses workspace kreator dengan tombol Buat; catat tradeoff pada laporan riset. Jangan menempatkan tombol “Mulai” atau “Tambah” sebagai tab yang langsung menjalankan tindakan.

| Konteks masuk | Rekomendasi tampilan | Hasil yang diharapkan |
|---|---|---|
| Pertama kali, belum punya rencana | Jelajah/Library, contoh kartu yang menjelaskan kegunaan; bantuan singkat opsional. | Bisa menemukan rundown tanpa izin lokasi terlebih dahulu. |
| Kembali sebelum hari keberangkatan | Pulihkan konteks terakhir; perjalanan terjadwal mudah dibuka. | Dapat meninjau atau mengubah waktu. |
| Punya perjalanan hari ini | Akses “Perjalanan hari ini” jelas dari bagian Perjalanan dan konteks relevan lain. | Tidak kehilangan perjalanan saat berpindah ke library. |
| Membuka undangan/tautan rundown | Detail rundown tujuan dengan jalan kembali yang jelas. | Tetap tahu sumber dan dapat memilih memakai/menyimpan. |
| Menambah dari perjalanan aktif | Jelajah dalam konteks rencana/hari yang dituju. | Memilih tambahan tidak mengganti trip tujuan atau mereset pencarian tanpa alasan. |
| Ingin membuat rundown | Karya → Buat rundown. | Bisa memulai draft tanpa mode akun permanen. |

Registrasi, penyimpanan cloud, dan publikasi mungkin memerlukan identitas; kebutuhan teknis belum diputuskan. Untuk wireframe, sediakan keadaan masuk akun bila dibutuhkan tindakan, tanpa mengasumsikan semua browse harus login.

## 4. Inventory screen family untuk tahap wireframe

**Semua baris adalah Proposed.** Screen family tidak selalu berarti halaman terpisah; filter, picker, izin, preview foto, atau konfirmasi bisa berupa sheet/komponen sistem. Pertahankan ID agar hubungan flow dan keadaan bisa diperiksa.

| ID | Surface / tujuan | Isi dan tindakan utama | Masuk → keluar |
|---|---|---|---|
| E01 | First use / bantuan singkat | Penjelasan pakai rundown kreator; Lewati/Lihat contoh bila perlu. | Launch → L01; bukan carousel wajib. |
| L01 | Jelajah / library | Search rundown, tujuan, kartu dengan kreator/durasi/rentang waktu. | Tab/tautan dari T/A → L02/L03. |
| L02 | Hasil pencarian dan filter | Query, filter aktif, hasil, hapus filter; scope jelas. | L01 → L03; batal mempertahankan konteks. |
| L03 | Detail rundown sumber | Kreator, ringkasan, timeline, transportasi, preview map; Simpan/Pakai/Tambahkan. | L01/L02/tautan → T01 atau M01. |
| L04 | Detail spot sumber | Foto/cerita, waktu saran, lama tinggal, catatan kondisi, sumber data. | L03 → kembali ke pilihan sama. |
| L05 | Profil kreator | Identitas dan daftar karya yang relevan; tanpa mengarang metrik sosial. | L03 → karya lain/detail. |
| L06 | Rundown tersimpan | Referensi yang disimpan; belum dijadwalkan. | Perjalanan/Jelajah → L03/T01. |
| T01 | Gunakan rundown / jadwalkan | Tanggal, jam mulai, zona waktu destinasi; akhir/waktu tersedia jika dipakai. | L03 → T02 atau batal. |
| T02 | Tinjau rencana pribadi | Timeline tanggal sendiri, estimasi, info belum pasti, sumber kreator. | T01 → simpan T03; kembali edit. |
| T03 | Daftar perjalanan | Hari ini, mendatang, selesai/draft sesuai kebutuhan; akses tersimpan. | Tab → T04/A01/J01. |
| T04 | Detail perjalanan pribadi | Tanggal, sumber, kegiatan, transportasi, akses map, edit, tambah rundown. | T03 → T05/M01/A01. |
| T05 | Edit waktu dan urutan | Ubah kegiatan/perpindahan; tanda perubahan; Simpan/Batal. | T04 → T04; draft tidak hilang. |
| T06 | Map perjalanan | Pin bernomor dan jalur sesuai data; baris terpilih tersinkron. | T04/A01 → detail kegiatan/kembali. |
| T07 | Detail perpindahan | Moda, asal/tujuan, waktu berangkat/tiba bila tersedia, durasi, sumber. | Timeline → kembali; buka navigasi eksternal jika dipilih. |
| M01 | Tambah rundown: pilih tujuan | Perjalanan/hari tujuan, rundown sumber; konfirmasi konteks. | L03 atau T04/A01 → M02. |
| M02 | Tinjau isi yang akan ditambahkan | Kegiatan asal dan yang sudah ada; opsi sebagian hanya bila dinyatakan asumsi. | M01 → M03/M04; batal tanpa perubahan. |
| M03 | Konflik/duplikasi | Tempat sama, jam bertabrakan, durasi/perpindahan belum diketahui; alasan dan pilihan. | M02 → M04 atau kembali. |
| M04 | Pratinjau hasil gabungan | Sebelum/sesudah, perubahan jam/akhir, sumber tiap tambahan; Terapkan/Batal. | M02/M03 → T04/A01. |
| A01 | Perjalanan hari ini | Kegiatan saat ini/berikutnya, waktu, transportasi; buka rundown, tambah kegiatan, jurnal. | T03/T04 → A02/T06/M01/J02. |
| A02 | Kegiatan di lapangan | Detail singkat, posisi/jarak, rencana versus aktual; navigasi dan tambah jurnal. | A01/T06 → T07/J02. |
| A03 | Perubahan saat pelaksanaan | Terlambat, ingin melewati/mengubah urutan; dampak waktu ditinjau. | A01/A02 → T05/M04; otomatisasi belum dipilih. |
| A04 | Penutupan perjalanan | Selesai/lanjut nanti, kegiatan yang tercatat, akses jurnal. | A01 → J01/T03; bukan kewajiban menyelesaikan misi. |
| J01 | Jurnal perjalanan | Pilih perjalanan dan lihat entri berdasarkan tempat/waktu aktual. | Tab/perjalanan selesai → J03/J02. |
| J02 | Tambah foto/cerita | Picker/kamera sistem, preview, tempat tujuan, status lokasi, Unggah. | A02/J01 → J03; gagal tetap simpan draft foto. |
| J03 | Detail entri jurnal | Foto, cerita, waktu, tempat, status penyimpanan/pengiriman; edit bila diizinkan. | J01/J02 → kembali. |
| C01 | Karya kreator | Rundown draft/tersedia; Buat, lanjutkan edit, pratinjau. | Tab Karya → C02/C03. |
| C02 | Identitas rundown | Judul, area/destinasi, ringkasan, cover opsional. | C01 → C03; simpan draft. |
| C03 | Editor rundown | Urutan spot, jam saran, durasi, segmen transportasi, indikator data kosong. | C02 → C04/C05/C06. |
| C04 | Cari/tentukan spot | Search lokasi, list/map, pemilihan/koreksi pin. | C03 → C05. |
| C05 | Editor spot/perpindahan | Waktu, durasi, transportasi, foto/cerita; catatan golden hour/cuaca dengan sumber. | C03/C04 → C03. |
| C06 | Preview dan review kelengkapan | Perspektif pembaca, masalah jadwal/input, cakupan akses/distribusi. | C03 → C07 atau edit. |
| C07 | Simpan/publikasikan/bagikan | Status draft/tersedia; pilihan distribusi sesuai keputusan; Share Sheet bila cocok. | C06 → C01/L03; gagal bisa dicoba lagi. |
| P01 | Profil dan pengaturan | Identitas, izin, akses data, preferensi waktu, bantuan. | Toolbar → kembali ke konteks. |
| P02 | Identitas/akun bila diperlukan | Masuk/lanjut, batal dan kembali tanpa kehilangan pekerjaan. | Tindakan yang memerlukan identitas → pemanggil. |

Untuk perangkat compact, editor panjang atau merge multilangkah perlu ruang penuh dengan navigasi yang jelas. Sheet cocok untuk tugas singkat. Detail pin di atas map dapat memakai sheet nonmodal bila map memang harus tetap interaktif. Jangan menumpuk sheet berlapis untuk seluruh perjalanan pengguna.

## 5. Flow yang harus tersambung

| Flow | Jalur representatif | Kondisi berhasil |
|---|---|---|
| Pilih A untuk besok | E01 → L01 → L03 → T01 → T02 → T04 | Ada perjalanan pribadi bertanggal dengan sumber A jelas. |
| Tambah B pada pagi pelaksanaan | A01 → L01/L02 dalam konteks → L03 → M01–M04 → A01 | Pengguna paham perubahan dan dapat membatalkan sebelum apply. |
| Jalankan rundown | T03 → A01 → A02/T07/T06 → A01 | Kegiatan berikutnya dan cara berpindah dapat ditemukan. |
| Jurnal di spot | A02 → J02 → picker/kamera → validasi GPS saat unggah → J03 | Hasil sesuai lapisan simpan/kirim yang tersedia, tanpa sukses palsu. |
| Buat rundown kreator | C01 → C02 → C03 → C04/C05 → C06 → C07 | Draft dapat dilanjutkan dan konten yang akan dibagikan dapat ditinjau. |
| Edit/perbaiki rencana | T04 → T05 atau A03 → tinjau → T04 | Perubahan jelas dan pengguna dapat kembali tanpa kehilangan data. |
| Pulih dari interupsi | Tutup modal/pindah tab/app kembali | Query, trip/hari tujuan, seleksi, dan draft tetap konsisten. |

## 6. Matriks keadaan yang perlu digambar

| Area | Varian penting | Jalan pemulihan |
|---|---|---|
| Library | Memuat, isi, kosong, tidak ada hasil, offline, gagal. | Coba lagi, ubah query/filter, buka yang tersimpan jika tersedia. |
| Detail sumber | Memuat, rundown dihapus/tidak dapat diakses, sumber berubah. | Kembali atau gunakan salinan yang tersedia dengan penjelasan; jangan menganggap akses tetap. |
| Konfigurasi | Belum pilih tanggal, nilai valid/tidak valid, melewati tengah malam, zona waktu. | Kesalahan di dekat field; pertahankan input. |
| Merge | Tidak ada konflik, tujuan sama, jam bentrok, transfer unknown, hasil berakhir lewat hari, gagal apply. | Tinjau pilihan, kembali edit/batal; tidak ubah rencana diam-diam. |
| Pelaksanaan | Sebelum mulai, sedang kegiatan, berpindah, terlambat, selesai, offline. | Tetap akses rundown dan kontrol pengguna; jangan auto-skip berdasar GPS saja. |
| Data kondisi | Cuaca tersedia/tidak tersedia/di luar horizon; transit diperbarui/stale. | Teks status/sumber dan waktu pembaruan bila tersedia; hindari angka palsu. |
| Lokasi | Belum diminta, ditolak, perkiraan, mencari, jauh, di radius, keluar sebelum unggah. | Browse tetap jalan; arahan pengaturan/coba lagi sesuai konteks. |
| Foto | Belum pilih, picker dibatalkan, foto gagal dimuat, preview, validasi, gagal tulis/kirim, sukses lokal/kirim. | Draft dipertahankan; status lokal bukan terkirim. |
| Creator | Draft kosong, sebagian, lengkap, validasi gagal, tersimpan, publikasi gagal. | Lanjutkan draft dan perbaiki field, tanpa kehilangan isi. |
| Empty state | Belum ada trip, jurnal, atau karya. | Jelaskan dan arahkan ke aksi relevan; jangan hilangkan tab. |
| Unsaved/destructive | Batal edit, hapus kegiatan/trip/draft. | Jalan keluar jelas; konfirmasi atau undo sesuai dampak. |
| Akun | Tidak masuk, memerlukan identitas, login gagal/dibatalkan. | Kembali ke tindakan/draft yang memanggilnya. |

Status offline queue foto belum diputuskan; **jangan menggambar unggah otomatis setelah keluar lokasi sebagai perilaku pasti**. Pisahkan ketersediaan teks/pin lokal, basemap, perhitungan rute, dan pengiriman foto.

## 7. Asumsi untuk prototipe yang dapat ditinjau

Saat prompt berikutnya meminta wireframe, keputusan yang belum final dapat dibuat sebagai **usulan eksplisit yang dapat diubah**, bukan alasan menghentikan seluruh pekerjaan:

1. Entry baru dari Jelajah; perjalanan hari ini mudah diakses tanpa mengubah tab secara mendadak.
2. Gunakan pratinjau sebelum penggabungan, dengan rencana awal tidak berubah sampai Terapkan.
3. Jika memerlukan jalur contoh konflik, gambarkan pengguna meninjau dan memilih hasil secara eksplisit. Jangan mengklaim auto-deduplikasi/auto-reschedule sudah diputuskan.
4. Simpan identitas kreator pada sumber tambahan; cara sinkronisasi sumber kemudian masih terbuka.
5. Posisi/waktu aktual tidak otomatis menyatakan kegiatan selesai; ini usulan kontrol manual untuk prototipe.
6. Gunakan label kota/area pada data cerita yang sudah diberikan, lalu satu contoh spot berlabel ilustrasi untuk menguji kepadatan UI; jangan menganggap keputusan spot final.

**Data cerita:** A = Chiyoda pagi–siang, Asakusa siang–sore, Shibuya sore–malam. B = Asakusa dan Shibuya dengan timeline kurang lebih sama, lalu Shinjuku. Tujuan User A adalah menambah aktivitas malam. Semua jam, moda spesifik, durasi transfer, forecast, dan golden hour numerik yang kelak ditampilkan harus ditandai sebagai data contoh kecuali sudah diverifikasi; riset ini tidak menghitung perjalanan Tokyo aktual.

## 8. Checklist kualitas wireframe

- Orang baru dapat menjelaskan beda Simpan rundown, Pakai untuk perjalanan, dan Tambahkan ke perjalanan.
- Ringkasan kartu/detail menjawab ke mana, berapa lama, dan kapan cocok dijalankan.
- Timeline menunjukkan kegiatan serta perpindahan; map bukan satu-satunya representasi.
- Flow merge memperlihatkan target, tambahan, masalah, hasil, apply, dan batal.
- Hari perjalanan dan query pencarian tetap terbaca saat mencari tambahan.
- Waktu saran kreator, jadwal pribadi, dan kejadian aktual tidak tercampur.
- Creator dan traveller sama-sama punya alur lengkap; peran tidak mengunci akun.
- Jurnal terhubung ke perjalanan; foto/GPS tidak menggeser rundown sebagai fungsi utama.
- Setiap alur punya exit/recovery; tidak hanya happy path.
- Dynamic Type, list alternatif map, label VoiceOver yang direncanakan, teks+ikon untuk status, serta alternatif reorder ditandai.
- Kebutuhan iPad dicatat terpisah; wireframe iPhone bukan bukti adaptasi iPad selesai.
- Tidak memperluas scope menjadi booking, budget, feed sosial, gamifikasi, atau AI tanpa permintaan.

**Pertanyaan uji paling bernilai:** tanpa dijelaskan moderator, bisakah seseorang memilih A untuk besok lalu menambahkan B untuk malam, sambil menjelaskan apa yang akan terjadi pada Asakusa/Shibuya yang sama? Jika tidak, perbaiki model penggabungan dan bahasa tindakan sebelum memperhalus tampilan.
