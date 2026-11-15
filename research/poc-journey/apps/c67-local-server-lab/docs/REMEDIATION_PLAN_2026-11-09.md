# Rencana perbaikan setelah evaluasi user simulasi

9 November 2026, Asia/Jakarta. Dasar: [hasil user simulasi](SYNTHETIC_USER_RESULTS_2026-11-08.md). Kecepatan daftar kandidat dan kepatuhan jadwal sudah memiliki bukti teknis; peningkatan kecocokan pengguna belum terbukti. Rencana ini mempertahankan lab Mac terisolasi, E5 di device sebagai pembantu, serta LLM gratis yang wajib berhasil. Tidak ada rencana pemindahan ke homelab atau pemasangan AnyJev pada tahap ini.

## Urutan dan batas pekerjaan

| Tahap | Perbaikan konkret | Bisa dikerjakan sekarang | Data tambahan / batas |
|---|---|---|---|
| 0 | Input E5 bahasa Inggris yang dikontrol dan diberi versi | Implementasi `en-v1` dilakukan pada turn ini | Tidak mengklaim manfaat ranking sebelum perbandingan |
| 1 | Identitas tempat membedakan kompleks, tenant, cabang dan alias; tiga status cocok/perlu diperiksa/ditolak | Ubah kontrak/validator/UI serta tambah regresi tenant, alias, alamat bertentangan | Alias/relasi entitas yang dipercaya dan pintu masuk perlu sumber; jarak dekat bukan bukti |
| 1 | Alasan penghilangan terstruktur; waktu lintas hari terbaca jelas | Perbaiki status sukses `operating_hours_options` yang keliru menjadi alasan; tampilkan24 jam atau tanggal akhir | Penyebab yang tidak tercatat harus dilabeli belum diketahui, bukan direka setelah pencarian |
| 2 | Kebutuhan kegiatan per perjalanan, terpisah dari kategori onboarding | Tambah TripIntent dan pertanyaan singkat yang relevan; profil minat tetap otomatis dipakai | Arti toleransi/prioritas yang ambigu perlu jawaban pengguna |
| 2 | Bukti per kebutuhan: didukung/bertentangan/belum diketahui | Tambah DTO fakta, provenance, freshness, konflik dan tampilan status | Harga, akses, menu, ketenangan dan izin belum lengkap hanya dari kategori |
| 3 | Discovery berdasarkan kegiatan; isi kekosongan kategori sebelum judging | Query terarah dan perluasan terbatas jika suatu minat belum didukung; catat tahap kandidat gugur | Tidak menjamin semua minat mempunyai tempat yang layak pada area/waktu itu |
| 4 | Slot dari kejadian, dilengkapi grid eksplorasi | Tambah waktu tiba, jam buka, batas preferensi dan akhir sesi; validasi ulang ETA final | Tidak menjamin kecepatan meningkat; harus dibandingkan dengan anggaran sama |
| 5 | Learning berdasarkan alasan tindakan dan konteks perjalanan | Bedakan opened-for-inspection dari explicit-like/save-for-interest; konfirmasi perubahan antarminat | Manfaat learning membutuhkan pilihan berulang pengguna; klik bukan label kepuasan |
| 6 | Evaluasi perbaikan dan kontribusi LLM/AnyJev | Bekukan pembanding, instrumentasi dan metrik; baseline kategori/E5 hanya untuk eksperimen | Penilaian manusia diperlukan; persona yang sudah dipakai menjadi regresi, bukan holdout baru |

Tahap 1 memperbaiki masalah ketepatan/penjelasan yang sudah dapat direproduksi. Tahap 2 menghubungkan apa yang diinginkan dengan apa yang diketahui. Tahap 3 baru dapat menelusuri kebutuhan lebih spesifik itu. Tahap 4 meningkatkan kandidat waktu tanpa mengendurkan aturan. Tambahan judge dinilai setelah input dan bukti memadai.

## 1. Identitas: periksa cakupan entitas, bukan hanya kata bersama

Pisahkan ID tempat Google, identitas Apple, kompleks induk/tenant bila diketahui, lokasi aktivitas, serta titik kedatangan. Nama yang mengandung nama mal tidak membuktikan kesetaraan dengan mal. Alamat yang bertentangan dan jenis entitas yang berbeda menurunkan keyakinan meskipun pin dekat.

Nama alias menjadi bukti yang memiliki sumber, bukan kamus bebas untuk memaksa semua pasangan lolos. Kasus perpustakaan berlabel gabungan HB Jassin/Jakarta Provincial Library perlu pemeriksaan entitas; jangan otomatis mengesahkannya dari alamat saja. Jika bukti memungkinkan tetapi belum cukup, tampilkan alasan status “perlu diperiksa” dan kandidat pembanding. Konfirmasi tidak boleh menjadi tombol bypass terhadap padanan yang jelas berbeda.

Uji bersama: Monas/Fatahillah, TOMORO/Kompormie, mal/tenant, perpustakaan/alias, stasiun/nama kota, nama sama di cabang berbeda, serta alamat berbeda. Catat salah terima, salah tolak dan yang memang belum dapat diputuskan. Jangan memilih radius baru hanya agar kasus lama lolos.

## 2. Kegiatan dan syarat per perjalanan

Onboarding kategori+ritme tetap menjadi profil awal yang dipakai ulang. Tambahkan rincian perjalanan hanya jika menentukan keputusan. Contoh setelah memilih Membaca: “membaca di tempat atau mencari buku?”; setelah menyebut vegetarian: simpan sebagai kebutuhan makanan, bukan minat restoran umum.

Representasi TripIntent menyimpan kegiatan, durasi, tujuan wajib/opsional, syarat wajib, preferensi, toleransi, waktu yang dimaksud (mulai/sebagian/seluruh kunjungan), serta prioritas kompromi yang sudah dikonfirmasi. Area/tanggal/waktu tetap diminta sebelum rekomendasi. Jangan memaksa pengguna mengonfirmasi minat lama setiap perjalanan.

LLM dapat membantu menyusun teks bebas menjadi struktur, tetapi hasil terjemahannya diperlihatkan untuk dikoreksi. LLM tidak boleh mengubah “sore” menjadi batas wajib15.00 tanpa dasar. Untuk kontrol terstruktur sederhana, gunakan pemetaan deterministik agar tidak menambah request AI.

## 3. Syarat dan bukti harus bertemu

Setiap syarat menyimpan status didukung/bertentangan/belum diketahui, sumber, tanggal pengambilan dan cakupan berlaku. Kandidat bersyarat tetap dapat ditampilkan sesuai keputusan pengguna sebelumnya. Status “terverifikasi memenuhi kebutuhan” hanya diberikan ketika syarat wajib mempunyai dukungan yang cukup; unknown tidak dikonversi menjadi benar atau salah dan tujuan wajib tidak dihilangkan diam-diam.

Google Places menyediakan field `servesVegetarianFood`, `priceRange`, `accessibilityOptions`, serta relasi `containingPlaces`/`subDestinations`. Field tersebut dapat menjadi bukti awal bila tersedia, tetapi cakupannya perlu dihormati: akses kursi roda pada pintu masuk belum membuktikan seluruh perjalanan stroller; rentang harga belum menjadi total biaya; vegetarian belum memverifikasi setiap menu. Perluas DTO dan field mask secara selektif, karena field mask memengaruhi data dan billing. Sumber diperiksa 9 November 2026: [Place resource](https://developers.google.com/maps/documentation/places/web-service/reference/rest/v1/places), [Place Details](https://developers.google.com/maps/documentation/places/web-service/place-details#fieldmask).

Ketenangan, boleh membaca 90 menit, izin fotografi, produk lokal dan antrean masih memerlukan sumber operator, bukti kontekstual atau konfirmasi manusia. Jika memakai ulasan, pisahkan pengalaman subjektif dari fakta operasional dan jangan menganggap ketiadaan ulasan sebagai ketiadaan fasilitas. Tahap ini tidak mengunduh review corpus baru.

## 4. Waktu berbasis kejadian dan alasan keputusan

Bentuk kandidat mulai dari jam tiba sebenarnya, jam buka, batas rentang pilihan, awal sesi dan batas terakhir mulai yang masih mempertahankan durasi penuh. Grid tetap membantu eksplorasi, tetapi bukan satu-satunya sumber waktu mulai. Setiap perubahan waktu divalidasi dengan ETA pada keberangkatan yang benar, menggunakan cache dan anggaran per-job yang sama untuk seluruh subset.

Alasan penghilangan harus berasal dari peristiwa yang dicatat selama evaluasi: bukti wajib kurang, durasi tidak muat dalam sesi, kombinasi melampaui tunggu/deadline, bukti perjalanan tidak tersedia, kalah menurut preferensi yang dinyatakan, atau pencarian/budget terpotong. Jika penyebab belum dapat dibuktikan, beri alasan terbatas yang jujur. Status sukses konteks jam bukan alasan kegagalan.

Kontrol grid yang ditemukan dipertahankan. Bandingkan grid 15/grid 5/slot-kejadian pada input sama dan anggaran ETA sama; laporkan jumlah kegiatan, tunggu, pelanggaran, call, pemotongan dan latency. Perbandingan ini tetap diperlukan karena grid 5 pada kontrol memerlukan 20 evaluasi dibanding 5 pada grid 15.

## 5. E5 bahasa Inggris: perubahan yang dilakukan sekarang

Jalur personal kini memakai `PersonalEmbeddingText` versi `en-v1`. Query mengubah enum minat menjadi frasa Inggris, misalnya `books and reading`, bukan label UI Indonesia. Passage dibuat dari kategori provider yang diizinkan dan kategori minat; `book store` tetap berbeda dari `library`. Tidak ada inferensi tentang tempat duduk, ketenangan atau harga.

Nama tempat, alamat, deskripsi bebas dan teks provider yang tidak dikenal tidak masuk ke E5. Identitas dan teks tampilan tetap disimpan untuk UI/konfirmasi; tidak diterjemahkan secara spekulatif. UI dan pencarian Google lokal tidak dipaksa menjadi bahasa Inggris. Runtime menambahkan prefix `query:`/`passage:` seperti sebelumnya; helper tidak menambahkannya dua kali. Cache menggunakan isi teks, sehingga representasi baru memiliki key baru tanpa menghapus profil pengguna.

Model tetap `intfloat/multilingual-e5-small`, revision dan bobot tetap. Instruksi menggunakan bahasa Inggris adalah kebijakan input; bukan migrasi ke checkpoint E5 lain. Metadata pengujian memakai suffix `_en_v1` agar hasil lama tidak tercampur. Perubahan tidak menggantikan LLM, tidak menyediakan fakta yang hilang dan belum membuktikan peningkatan akurasi.

Pembanding kualitas E5 selanjutnya memakai fakta, kandidat, brief dan budget yang sama: input lama versus English v1; E5 aktif versus sinyal semantik tidak diberikan. Model LLM dan urutan run dikendalikan, semua kegagalan dicatat, serta hasil dinilai tanpa membuka nama metode. Nama/kode tempat tetap berada pada jalur identitas, sehingga normalisasi bahasa tidak merusak pencarian GBK atau konfirmasi entitas.

## 6. Kriteria selesai

- Kasus identitas salah tidak lolos otomatis; alias yang belum jelas dapat diperiksa tanpa mengesahkan tenant sebagai kompleks.
- Setiap syarat penting mempunyai representasi dan status bukti; tidak ada janji vegetarian/tenang/akses hanya dari kategori.
- Kekosongan kandidat dilaporkan sebelum LLM; perluasan pencarian dibatasi waktu/call.
- Durasi, tujuan wajib, total tunggu, waktu pulang dan identitas kembali tidak dikorbankan untuk kecepatan.
- Slot-kejadian diuji dengan oracle kecil dan ETA final; tidak ada klaim optimum dari pencarian terpotong.
- Penilaian pengguna nyata, persona sintetis, kepatuhan aturan dan pengamatan lapangan dilaporkan terpisah.

Selain normalisasi input E5, butir-butir perbaikan di dokumen ini masih rencana; belum diterapkan pada turn penulisan ini.

## Verifikasi perubahan English v1

Tiga tes input lulus: urutan minat tidak mengubah query, library/book store tetap dibedakan, dan nama/deskripsi/facet tak dikenal tidak bocor ke teks embedding. Satu tes UI simulator dengan tempat/jam sintetis menjalankan E5 aktual serta LLM gratis dan lulus. Auditor memeriksa ID, alasan, bukti, biaya nol serta versi model/input. Waktu satu observasi daftar 2,583 detik, E5 0,818 detik; ini pemeriksaan fungsional, bukan benchmark perbaikan akurasi atau kecepatan. Artefak: `artifacts/e5-english-2026-11-09/verification.json` dan `english-fixture.xcresult`.
