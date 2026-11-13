# Matriks aksi layar untuk revisi wireframe rundown

**Status konteks — 29 Oktober 2026:** Matriks ini adalah baseline layar konsep kreator. Untuk target baru, gunakan alur input tujuan/preferensi/waktu, kandidat tambahan opsional, proposal dan recalculation. ID layar di bawah belum diperbarui atau diimplementasikan ulang. Lihat [acuan aktif](ai-trip-planning-user-flow-2026-10-29.md).

**Tanggal:** 21 Oktober 2026, Asia/Jakarta.  
**Status:** Proposed — spesifikasi perilaku untuk review desain, belum diimplementasikan.  
**Dasar:** [riset HIG dan UX travel](../research/travel-ux-screen-actions-hig-2026-10-21.md), [riset WeatherKit](../research/weatherkit-traveller-experience-research-2026-10-21.md), cerita Athar, serta sumber [wireframe v1](../../../missing-evidence.md#missing-83197e886c26).  
**Batas:** nama dan label di bawah adalah kandidat. Surface dapat berupa halaman, panel, sheet, atau varian state; jumlah baris bukan jumlah halaman baru.

## 1. Kontrak aksi

Setiap surface perlu menjelaskan tujuan, informasi minimum sebelum bertindak, aksi dominan, hasil tindakan, dan jalan kembali. Pertahankan konteks pengguna saat berpindah, menutup panel atau kembali dari sistem.

Penekanan satu aksi dominan adalah pilihan desain untuk flow kita. HIG Buttons menyarankan satu atau dua tombol menonjol per view; kontrol tambahan yang relevan tetap dapat tersedia. [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons), [Designing for iOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ios)

Pisahkan jenis tindakan:

| Jenis | Contoh | Efek yang perlu dipahami |
|---|---|---|
| Membuka informasi | Lihat rundown, lihat detail cuaca. | Belum mengubah rencana. |
| Menyimpan referensi | Simpan rundown. | Belum memulai atau menjadwalkan perjalanan. |
| Memilih pelaksanaan | Gunakan rundown, atur waktu. | Membentuk konteks perjalanan pengguna. |
| Memulai perpindahan | Menuju titik awal, ke spot berikutnya. | Tujuan perpindahan berubah secara eksplisit. |
| Menyimpan/mengirim konten | Simpan foto atau unggah foto. | Label dan status sesuai tindakan nyata dan audience. |
| Menerapkan perubahan | Terapkan perubahan. | Rencana berubah setelah dampaknya ditinjau. |
| Berbagi keluar aplikasi | Bagikan album. | Membuka pratinjau/Share Sheet; membatalkannya tidak menghapus album. |

## 2. Alur utama Athar

Tiga belas surface berikut menguraikan cerita 14 langkah dan tambahan waktu fleksibel. UX05 berasal dari klarifikasi waktu, bukan dari klaim bahwa tim telah menggambar langkah konfigurasi tersebut di papan.

| ID / padanan v1 | Tujuan pengguna | Aksi utama; tambahan | Informasi minimum | Hasil tindakan dan jalan kembali |
|---|---|---|---|---|
| UX01 · L01 | Menentukan area yang ingin dijelajahi. | Cari tujuan atau jelajahi peta; Lokasi saya. | Peta, search yang terlihat, area pencarian dan akses perjalanan aktif jika ada. | Masuk UX02/UX03; lokasi diminta ketika diperlukan, pencarian manual tetap tersedia. |
| UX02 · L02 varian input | Menyampaikan maksud “Kota Tua”. | Pilih saran tujuan / tampilkan hasil; Hapus, Batal. | Query, scope rundown, saran yang relevan. | UX03 menampilkan rundown untuk tujuan tersebut; Batal mengembalikan peta dan konteks sebelumnya. |
| UX03 · L02 varian hasil | Membandingkan beberapa rundown. | Pilih rundown; Filter, peta/daftar. | Judul, kreator, karakter pengalaman, landing point, jumlah spot, durasi dan informasi waktu yang relevan. | UX04 untuk rundown terpilih; kembali mempertahankan query, filter, area, posisi daftar dan seleksi. |
| UX04 · L03/L04 | Menilai apakah rundown cocok. | Gunakan rundown; Simpan, detail spot, profil kreator. | Pengalaman yang ditawarkan, urutan, landing point, total durasi, perpindahan, jam saran, kesempatan cahaya/cuaca relevan. | Menuju konfigurasi ringkas atau lanjut dengan default yang terlihat. Membuka detail tidak langsung memulai trip. |
| UX05 · T01/T02 ringkas | Menentukan kapan menjalankannya. | Gunakan waktu ini / Mulai sekarang; Ubah tanggal/jam. | Makna jam mulai, tanggal dan zona destinasi, perkiraan tiba di landing point, selesai, dan dampak cuaca/anchor. | Rencana untuk waktu pilihan terlihat sebelum menuju UX06; Batal kembali ke detail tanpa perubahan. |
| UX06 · T07/A01 varian akses | Mencapai landing point dari Agora. | Petunjuk ke titik awal; Pilih moda, lihat rundown. | Asal, spot awal yang spesifik, durasi/ETA, moda, bagian berjalan, catatan akses dan cuaca relevan. | Arah ke titik awal tersedia; kembali dari aplikasi navigasi memulihkan trip yang sama. Tidak menandai spot selesai. |
| UX07 · A01/A02 varian perjalanan | Mengikuti perpindahan ke spot aktif. | Lihat petunjuk; Rincian spot, rundown lengkap. | Tujuan aktif, instruksi yang tersedia, waktu/jarak estimasi dan spot berikutnya. | Kedatangan mengubah status/panel dengan jelas; tidak otomatis membuka kamera. Tidak menjanjikan turn-by-turn sebelum cakupan dipilih. |
| UX08 · A02 varian tiba | Mengalami dan mendokumentasikan spot. | Tambah foto; Lihat tips/konteks spot. | Nama spot, status lokasi, alasan/tips kunjungan, durasi saran dan progres spot. | UX09 setelah dipilih pengguna. Kedatangan GPS dan selesai kunjungan adalah state berbeda. |
| UX09 · J02 varian kamera/picker | Mengambil atau memilih foto untuk spot. | Ambil foto / pilih foto; Batal, ganti sumber. | Konteks spot dan kontrol sistem yang relevan. | UX10 dengan foto pilihan; Batal kembali ke spot, tanpa foto atau kunjungan palsu. Izin kamera diminta saat dipakai. |
| UX10 · J02 varian preview | Memastikan foto tepat dan menyelesaikan pencatatannya. | Simpan foto / Unggah foto sesuai tindakan nyata; Ulangi/ganti, cerita opsional. | Preview, spot, status lokasi saat tindakan, audience bila konten dibagikan, serta hasil simpan/kirim. | Sesudah berhasil: kembali ke spot dengan aksi “Ke spot berikutnya”; bila terakhir, “Lihat album”. Gagal mempertahankan foto/draft. |
| UX11 · A04 | Menutup rangkaian setelah spot terakhir. | Lihat album; Tinjau spot. | Perjalanan yang selesai dan hasil dokumentasi yang benar-benar tersedia. | UX12; dapat menjadi transisi atau state ringkas, tanpa layar ucapan selamat tambahan yang wajib. |
| UX12 · J01 varian album | Melihat kembali perjalanan Kota Tua. | Menjelajahi album; Bagikan, Selesai. | Foto menurut urutan/tempat, nama perjalanan, tanggal, hasil yang sudah tersimpan/terkirim sesuai lapisan. | Selesai kembali ke aplikasi dengan album tetap dapat ditemukan; berbagi tetap opsional. |
| UX13 · surface sistem | Memilih keluaran dan tujuan berbagi. | Bagikan keluaran yang dipilih; Batal. | Pratinjau isi, format gambar/album/tautan yang didukung, audience dan konsekuensi akses bila memakai tautan. | Share Sheet atau proses ekspor sesuai dukungan; pembatalan kembali ke album dan tidak menyatakan publikasi berhasil. |

**Penyederhanaan yang perlu diuji:** UX06 dan UX07 dapat memakai keluarga layar yang sama dengan konteks tujuan berbeda. UX08 dan keadaan foto berhasil juga dapat menggunakan keluarga yang sama. UX11 dapat langsung membuka UX12 setelah penutupan yang jelas. Tidak perlu mengubah setiap panah menjadi halaman baru.

**Landing point versus spot pertama:** pastikan apakah keduanya sama pada rundown. Jika sama, jangan menambahkan dua konfirmasi kedatangan/mulai yang tidak memiliki akibat berbeda. Jika berbeda, jelaskan perpindahan di antara keduanya. Makna jam mulai pada UX05 masih perlu diputuskan.

## 3. Status dan batas tindakan di perjalanan

| Keadaan | Aksi yang relevan | Batas |
|---|---|---|
| Belum memilih rundown | Cari / pilih. | Belum ada trip aktif yang dijalankan. |
| Rundown dipilih, belum berangkat | Atur waktu / menuju titik awal. | Tampilkan tanggal dan makna waktu. |
| Menuju landing point | Petunjuk / tinjau tujuan awal. | Tidak menyatakan sedang menikmati spot pertama. |
| Menuju spot aktif | Petunjuk / detail singkat. | Tidak menandai kunjungan selesai hanya karena melewati area. |
| Tiba, belum ada foto | Tambah foto. | Foto wajib dalam best-case; bukan perintah untuk mengabaikan halangan. |
| Foto dipilih | Tinjau / konfirmasi tindakan. | Memilih foto belum sama dengan berhasil mencatat/mengirim. |
| Foto sedang diproses | Tampilkan status proses yang akurat. | Hindari tap ganda yang menghasilkan entri duplikat; jangan menyatakan sukses sebelum hasil diketahui. |
| Foto berhasil dicatat sesuai kontrak | Ke spot berikutnya / lihat album terakhir. | Pengguna masih dapat menikmati tempat; jangan otomatis mengganti tujuan tanpa kejelasan. |
| Lokasi belum pasti | Coba periksa lagi / lihat alasan. | Tindakan manual “sudah tiba” bila kelak dipakai tidak mengesampingkan validasi GPS unggah. |

Aturan GPS saat menekan unggah tetap berlaku. Tidak ada izin permanen hanya karena pernah tiba. Label “Simpan foto” hanya tepat untuk tindakan simpan; bila mengirim atau memublikasikan, jelaskan tindakan serta audience-nya. Pilihan foto lama/galeri tidak dibatalkan oleh matriks ini; aturan capture dan kontribusi lebih rinci masih terbuka.

## 4. Cuaca sebagai cabang kontekstual

| ID / konteks | Tujuan dan aksi utama | Isi yang dibutuhkan | Kembali / hasil |
|---|---|---|---|
| WX01 · UX04/UX05/UX06 | Memahami persiapan atau dampak waktu; lihat detail bila perlu. | Kondisi pada spot/perpindahan yang relevan, waktu berlaku dan kebaruan data, alasan singkat. | Tutup detail kembali pada rundown dan waktu yang sama; tidak perlu tab cuaca baru. |
| WX02 · A03/T05 | Menilai usulan penyesuaian; Terapkan perubahan. | Penyebab, kegiatan/segmen terdampak, sebelum/sesudah, perubahan akhir dan anchor, sumber alternatif. | Batal mempertahankan rencana; setelah apply hasil terlihat. Undo hanya ditawarkan sejauh benar-benar dapat dipulihkan. |

Tidak mengunci otomatisasi sebagai keputusan final. Informasi biasa dapat berada inline; peringatan yang penting dan dapat ditindaklanjuti dapat memperoleh penekanan lebih tinggi. Perubahan cuaca tidak boleh menghapus foto, spot yang sudah dijalankan atau pilihan pengguna. Lihat [riset WeatherKit](../research/weatherkit-traveller-experience-research-2026-10-21.md) untuk batas wilayah dan data yang diperlukan.

## 5. Pemetaan seluruh 34 screen family v1

Tabel ini menjaga cakupan desain lama tetap dapat ditelusuri. **Kreator, merge dan pengaturan bukan syarat tambahan untuk menyelesaikan best-case Athar.** Kolom aksi adalah rekomendasi untuk review; sejumlah layar cukup mendukung navigasi dan tidak membutuhkan tombol besar.

| ID | Pekerjaan / aksi dominan yang diusulkan | Hasil dan kontrol yang perlu dijaga |
|---|---|---|
| E01 | Memahami kegunaan / Jelajahi rundown. | Bantuan opsional; tidak memaksa memilih peran atau menghafal fitur sebelum mencoba. |
| L01 | Menemukan tujuan / search dan jelajah peta. | Konteks area dan perjalanan aktif tetap dapat diakses. |
| L02 | Menemukan atau membandingkan hasil / pilih saran/rundown. | Input dan hasil merupakan varian; query, filter dan seleksi dipertahankan. |
| L03 | Menilai rundown / Gunakan rundown. | Bookmark tidak sama dengan memulai; dalam mode tambah, CTA menyebut perjalanan tujuan. |
| L04 | Memahami satu spot / kembali ke rundown. | Detail tidak memulai navigasi atau mengedit trip secara diam-diam. |
| L05 | Meninjau karya kreator / pilih rundown. | Kembali ke pilihan semula; tidak membutuhkan metrik sosial baru. |
| L06 | Mengakses referensi / buka rundown tersimpan. | Tidak menyatakan semuanya telah dijadwalkan atau tersedia offline. |
| T01 | Menentukan pelaksanaan / gunakan waktu. | Ringkas untuk sekarang; makna mulai, tanggal dan zona jelas. |
| T02 | Menilai hasil waktu / konfirmasi rencana bila diperlukan. | Dapat menyatu dengan T01 bila review tetap terbaca; Batal menjaga sumber. |
| T03 | Mengakses perjalanan / lanjutkan trip yang dipilih. | Hari ini, mendatang, selesai dibedakan; tab tidak mengeksekusi “Mulai”. |
| T04 | Memahami rencana pribadi / lanjutkan atau menuju awal sesuai state. | Edit/tambah tidak mengubah sumber kreator; konteks perjalanan tetap jelas. |
| T05 | Menyesuaikan waktu/urutan / simpan perubahan. | Draft dan dampak dapat ditinjau, Batal mengembalikan rencana. |
| T06 | Memahami geografi / pilih spot atau kembali ke kegiatan aktif. | Peta/daftar tersinkron; pan bukan perintah mengganti tujuan. |
| T07 | Memilih perpindahan / lihat petunjuk ke tujuan. | Asal/tujuan, moda dan ETA jelas; mencakup menuju landing point atau antarspot sesuai konteks. |
| M01 | Memastikan trip/hari tujuan penambahan / lanjut. | Jika trip/hari sudah diberikan konteks dan tunggal, pertimbangkan konfirmasi inline tanpa pemilihan ulang. |
| M02 | Memahami isi tambahan / tinjau perubahan. | Pemilihan sebagian tetap asumsi produk, bukan kewajiban HIG. |
| M03 | Menyelesaikan konflik / pilih hasil yang dipahami. | Alasan dan akibat pilihan terlihat; dapat kembali tanpa mutasi setengah jadi. |
| M04 | Menilai hasil gabungan / terapkan ke perjalanan. | Perubahan waktu/spot/sumber jelas; Batal dan hasil apply dapat dipahami. |
| A01 | Memahami keadaan sekarang / aksi sesuai tahap. | Menuju, tiba, dokumentasi, dan berikutnya tidak berlomba sebagai CTA setara. |
| A02 | Mengalami spot / tambah foto, kemudian lanjut. | Foto dan penyelesaian kunjungan terhubung dalam best-case; status bukan sekadar warna. |
| A03 | Menyesuaikan pelaksanaan / tinjau perubahan. | Dapat kembali ke trip yang sama; perubahan cuaca bukan alasan auto-skip tanpa keputusan. |
| A04 | Menutup perjalanan / lihat album. | Bedakan selesai seluruh urutan dengan berhenti lebih awal; pengecualian perlu dirancang terpisah. |
| J01 | Menemukan jurnal / buka album satu perjalanan. | Album perjalanan aktif/baru selesai mudah ditemukan; bukan hanya kumpulan entri tunggal. |
| J02 | Mendokumentasikan spot / konfirmasi foto. | Preview, lokasi dan hasil nyata terlihat; tulisan panjang tidak menjadi syarat baru. |
| J03 | Melihat satu momen / kembali ke album atau spot. | Edit bila didukung; state simpan lokal, terkirim dan publik tidak disamakan. |
| C01 | Mengelola karya / buat atau lanjutkan draft. | Tidak mengunci akun ke peran kreator permanen. |
| C02 | Menjelaskan rundown / lanjut menyusun. | Input minimum dan default wajar; metadata dapat disunting kemudian jika cocok. |
| C03 | Menyusun urutan / tambah atau edit spot, lalu preview. | Simpan draft tersedia; alternatif tombol untuk reorder. |
| C04 | Memilih lokasi spot / pilih hasil yang tepat. | Search berscope lokasi, pilihan pin dapat ditinjau; tidak sama dengan library rundown traveler. |
| C05 | Menjelaskan kunjungan/perpindahan / simpan ke draft. | Pisahkan durasi, jam saran, anchor dan catatan cuaca; beban metadata perlu diuji. |
| C06 | Menilai tampilan pembaca / lanjut ke distribusi. | Masalah menunjuk field/kegiatan yang perlu diperbaiki. |
| C07 | Memilih distribusi / tindakan dengan akibat eksplisit. | “Simpan draft”, “Publikasikan”, dan “Bagikan tautan” dibedakan jika memang didukung. |
| P01 | Mengelola preferensi/data / pilih pengaturan. | Tidak perlu CTA utama buatan; kembali ke konteks pemanggil. |
| P02 | Memenuhi kebutuhan identitas / masuk jika diperlukan. | Alasan dan pembatalan jelas; tidak menyembunyikan persyaratan tindakan di balik “lanjut tanpa masuk”. |

## 6. Pemetaan 16 state v1 dan pemulihan

State berikut adalah cakupan di luar best-case, bukan kekurangan sketsa tim. State dapat digabung ke surface pemiliknya, tanpa menjadikannya halaman baru.

| ID | Kondisi / aksi pemulihan | Konteks yang dipertahankan |
|---|---|---|
| S01 | Filter: Tampilkan hasil / hapus filter / batal. | Query, area dan trip tujuan; arti Batal versus apply konsisten. |
| S02 | Memuat: status proses; batalkan bila tugas mendukung. | Jangan mengosongkan hasil lama tanpa alasan atau menampilkan persen palsu. |
| S03 | Tidak ada hasil: ubah query/area/filter. | Bedakan dari gangguan jaringan; beri jalan kembali. |
| S04 | Offline: buka konten yang benar-benar tersedia. | Jelaskan cakupan teks, peta, routing dan cuaca secara terpisah; tidak menjanjikan antrean unggah dari luar radius. |
| S05 | Gagal memuat: Coba lagi. | Query, area dan seleksi tidak hilang. |
| S06 | Waktu tidak valid: perbaiki nilai terkait. | Input lain tetap ada; lintas hari dan zona dijelaskan bila relevan. |
| S07 | Izin belum diberikan: izinkan saat dibutuhkan atau kembali. | Browse manual tetap tersedia; fitur lokasi menjelaskan keterbatasannya. |
| S08 | Di luar radius: lihat lokasi dan alasan. | Foto tetap draft; lokasi pernah tiba bukan izin unggah permanen. |
| S09 | Posisi belum pasti: coba periksa lagi. | Tidak menganggap ketidakpastian sebagai pasti jauh/di dalam. |
| S10 | Gagal foto: coba tindakan yang gagal lagi. | Foto dan cerita dipertahankan; sukses dan progres perjalanan tidak dipalsukan. |
| S11 | Belum ada karya: buat rundown. | Empty state menjelaskan tujuan; bagian navigasi tetap dapat ditemukan. |
| S12 | Melewati kegiatan: tinjau dampak / batal. | Bukan bagian best-case; aturan foto wajib dan skip perlu keputusan terpisah. |
| S13 | Metadata batas prototipe. | Tetap di alat review; tidak harus menjadi layar produk. |
| S14 | Menutup edit: simpan draft / buang perubahan / lanjut edit bila diperlukan. | Konfirmasi dipakai saat ada risiko kehilangan pekerjaan; jangan menambahnya untuk setiap Back. |
| S15 | Apply gabungan gagal: tinjau/coba lagi atau batal. | Rencana awal dan keputusan yang belum diterapkan tetap dapat dipahami. |
| S16 | Publikasi gagal: coba lagi / kembali draft. | Tidak menyatakan tautan publik sudah ada bila belum berhasil. |

Tidak semua error perlu alert modal. Gunakan feedback dekat konteks untuk status biasa dan pilih interupsi sesuai konsekuensi. [Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback), [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)

## 7. Kontinuitas, aksesibilitas, dan adaptasi

- **Kembali dari detail:** query, filter, posisi daftar, area peta dan rundown terpilih tetap konsisten.
- **Kembali dari kamera/picker:** spot dan foto draft tetap benar; Batal tidak membuat jurnal.
- **Kembali dari navigasi eksternal:** perjalanan dan spot aktif dipulihkan; tidak mengklaim petunjuk eksternal telah selesai hanya karena app kembali aktif.
- **Kembali dari background:** tampilkan keadaan perjalanan yang dapat dipahami; tinjau kebaruan lokasi/cuaca sebelum klaim yang memerlukannya.
- **Teks besar/ruang sempit:** tujuan, status dan aksi penting tetap terbaca, konten boleh tersusun vertikal; CTA tidak tertutup keyboard atau panel.
- **iPad/ruang lebar:** peta dan daftar/panel dapat berdampingan; pilihan, draft dan fokus tetap kontinu ketika ruang berubah.
- **VoiceOver/alternatif gestur:** hasil, urutan spot, perpindahan dan aksi dapat diakses melalui daftar serta label; swipe/pinch bukan satu-satunya cara menyelesaikan tugas.
- **Navigasi global:** jika memakai tab, label dan tujuan stabil; kamera dapat menjadi tugas modal yang menutup navigasi sementara. Jumlah tab belum ditetapkan.

[Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [Gestures](https://developer.apple.com/design/human-interface-guidelines/gestures), [Layout](https://developer.apple.com/design/human-interface-guidelines/layout), [Designing for iPadOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ipados), [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars).

## 8. Keputusan yang masih diperlukan sebelum perilaku final

1. Makna jam mulai: berangkat dari lokasi sekarang atau mulai rundown di landing point.
2. Cakupan panduan: konteks perjalanan dan handoff Maps, atau turn-by-turn di aplikasi.
3. Makna hasil foto: jurnal pribadi, kontribusi dengan audience tertentu, atau keduanya melalui tindakan terpisah.
4. Aturan saat foto belum dapat diselesaikan: izin, GPS, koneksi, atau halangan cuaca; best-case tidak menetapkan pengecualian.
5. Tingkat otomatisasi penyesuaian waktu/cuaca dan bentuk kontrol pengguna.
6. Informasi kreator yang benar-benar tersedia: jam buka, anchor, durasi, indoor/outdoor dan alternatif.

Pertanyaan ini dicatat untuk review berikutnya; tidak menjadi permintaan konfirmasi atau penghambat pekerjaan riset. Wireframe dan kode v1 tetap utuh. Matriks ini belum membuktikan keberhasilan UX, integrasi native, aksesibilitas, persistence atau layanan cuaca.
