# Rencana validasi — Diary perjalanan, jejak orang lain, dan foto di lokasi

**Status konteks — 29 Oktober 2026:** Rencana ini belum menjadi validasi engine baru. Pertanyaan tentang motivasi kreator, diary dan game dipertahankan sebagai riwayat dengan scope asalnya. Lihat [acuan aktif](ai-trip-planning-validation-plan-2026-10-29.md).

Tanggal: **19 Oktober 2026**. Status: **rancangan penelitian; belum direkrut atau dijalankan**. Dasar: [desk research](../research/travel-diary-photo-gamification-desk-research-2026-10-19.md).

## 1. Keputusan yang ingin dibantu

Pertanyaan utama: **apakah orang mendapat nilai dari menjalani dan menambahkan foto pada jejak perjalanan seseorang, di luar manfaat diary pribadi atau daftar tempat yang bisa disimpan sendiri?**

Empat keputusan turunannya:

1. Siapa yang paling punya alasan membuat dan mengikuti map?
2. Kegiatan mana yang memberi kesenangan: diary, koleksi tempat, hubungan dengan pembuat, tantangan foto atau aktivitas bersama?
3. Apakah aturan lokasi saat upload dianggap sepadan dan bisa dipakai di kondisi nyata?
4. Apakah hasil yang tersimpan dan alasan kembali cukup bernilai untuk melanjutkan eksperimen?

Riset ini tidak harus berujung pada aplikasi penuh. Map sederhana, contoh diary asli dan simulasi alur submission cukup untuk sebagian pertanyaan. Pemeriksaan GPS teknis memerlukan kegiatan terpisah dan tidak bisa digantikan dengan walkthrough fasilitator.

### Jejak dari bukti menuju pengujian

Kode G dan R merujuk pertanyaan serta requirement sementara dalam laporan; kode H digunakan di rencana ini. Isi kolom bukti adalah alasan layak diteliti, bukan hasil hipotesis sudah benar.

| Hipotesis | Pertanyaan/requirement | Dasar desk research | Pengujian yang membedakan penjelasan |
|---|---|---|---|
| H1: hasil pribadi cukup bernilai bagi pembuat. | G1; R1. | Motif foto/sharing dan pencatatan personal: A01, A03, A10, A16. | Buat map dari bahan sendiri tanpa menjanjikan pengikut atau hadiah; amati hasil yang ingin disimpan. |
| H2: hubungan/tema pembuat menambah alasan mengikuti. | G2, G5; R2, R5. | A09, A13, A24; pembanding P06, P11, P31. | Bandingkan map setara dengan konteks creator berbeda; bedakan membaca/save dari memilih kunjungan. |
| H3: game menambah nilai kegiatan/hasil. | G3; R3, R8. | A01–A02, A04–A07, A15, A18–A20, A23. | Diary biasa vs satu mekanisme, konten setara; catat pilihan sukarela, kesenangan dan usaha. |
| H4: aturan GPS dipahami dan sepadan. | G4; R4, R8. | T01–T04, T06–T08; P19–P21. | Aturan upload di lokasi pada skenario berhasil/gagal; pisahkan penilaian konsep dari hasil perangkat. |
| H5: ada nilai setelah kesempatan pertama. | G6; R6. | A10–A12; P33–P35; F03. | Follow-up akses arsip dan kesempatan berikutnya; jangan samakan tidak sempat dengan menolak memakai. |
| H6: pasokan dan pemeliharaan sanggup ditanggung. | G6; R7. | A27–A28; P09, P18, P28–P30, P37; T05, F05. | Catat kontribusi sukarela, waktu kerja dan siapa mengurus laporan; jangan anggap setiap pembuat kurator. |

G7 tentang pembanding memberi alternatif pada tugas H2–H3; ia tidak ditutup oleh klaim fitur belum ditemukan. G8 merupakan keseluruhan rencana bukti langsung ini. Requirement di atas tetap sementara dan dapat berubah mengikuti hasil.

## 2. Hal yang sudah diberikan dan hal yang masih terbuka

**Diberikan pengguna:** semua orang boleh membuat map; contoh pembuat memakai perjalanan lampau; pengikut mengunjungi pin dan mengunggah foto bebas; GPS pengikut harus berada dalam area saat unggah; gamifikasi belum dipilih.

**Belum diputuskan:** segmen, negara, bentuk koleksi/rute, urutan wajib, semua titik wajib, radius, hak visibility, reward, monetisasi, apakah foto dapat diedit setelah unggah, dan cara memulihkan upload gagal. Solo/group merupakan konteks, belum segmentasi kebutuhan.

**Tidak diasumsikan:** harus mengisi waktu luang, pulang sebelum tenggat, mengganti tour leader, membuat itinerary otomatis atau membuktikan keaslian foto lewat computer vision.

## 3. Rekrut berdasarkan perilaku yang sudah terjadi

Mulai dengan kelompok kecil yang dapat dijangkau tim. Contoh rencana awal: **6–8 pembuat/pencatat perjalanan dan 6–8 calon pengikut**, boleh ada orang yang masuk kedua peran. Ini rentang praktis untuk eksplorasi, bukan ukuran sampel representatif atau jaminan saturation.

| Kelompok | Bukti perilaku yang dicari | Hindari memilih hanya karena |
|---|---|---|
| Orang yang membuat kenangan perjalanan | Pernah menyusun album, menulis catatan, membuat map atau memberi rekomendasi setelah trip terakhir. | Sering bepergian atau mengaku suka fotografi. |
| Orang yang mengikuti inspirasi orang lain | Dapat menunjukkan contoh tempat yang benar-benar dikunjungi setelah rekomendasi teman/creator/komunitas. | Mengikuti banyak travel account. |
| Orang yang menyukai koleksi/permainan eksplorasi | Pernah mengikuti stamp rally, check-in, photo challenge atau kegiatan serupa. | Menyukai game secara umum. |
| Orang dengan kebiasaan sederhana | Menyimpan foto dan memakai Maps/catatan tanpa diary khusus. | Tidak mengetahui aplikasi kompetitor. |

Sertakan beberapa orang yang berhenti menggunakan aplikasi diary/check-in agar tidak hanya mempelajari pengguna yang bertahan. Catat hubungan peserta dengan tim; teman dekat dapat merasa perlu menyenangkan pembuat konsep.

Gunakan peserta dewasa dan lokasi yang memang boleh dikunjungi. Minta izin sebelum melihat foto/catatan pribadi; peserta boleh menyembunyikan bagian yang tidak ingin dibagikan. Tidak perlu mencatat koordinat rumah, riwayat bergerak terus menerus, nama orang dalam foto atau identitas pihak ketiga.

## 4. Tahap A — Rekonstruksi pengalaman terakhir, sebelum menunjukkan ide

**Tujuan:** memahami alasan membuat diary, mengikuti rekomendasi dan berhenti mencatat tanpa menggiring jawaban.

**Bahan:** bila peserta bersedia, contoh foto, map, catatan atau percakapan rekomendasi dari satu perjalanan yang benar-benar terjadi. Jangan meminta seluruh galeri.

**Pertanyaan inti untuk pembuat:**

- Ceritakan perjalanan terakhir yang masih kamu dokumentasikan.
- Setelah mengambil foto, apa yang kamu lakukan berikutnya? Kapan kamu memilih dan mengeditnya?
- Tunjukkan satu hasil yang pernah kamu simpan atau bagikan. Kepada siapa dan mengapa?
- Bagian mana yang tidak jadi dicatat? Apa yang terjadi saat itu?
- Kapan terakhir membuka lagi catatan tersebut? Apa yang ingin kamu cari?
- Pernah ada orang mengikuti rekomendasimu? Bagaimana kamu mengetahuinya?

**Pertanyaan inti untuk pengikut:**

- Ceritakan terakhir kali kamu mengunjungi tempat setelah melihat pengalaman seseorang.
- Siapa orang itu? Apa yang membuat kamu mempercayainya atau tertarik?
- Setelah melihat kontennya, langkah apa yang kamu lakukan sampai berangkat?
- Apa yang kamu ikuti persis, dan apa yang kamu ubah?
- Apakah kamu memberitahu pembuat atau menyimpan hasil kunjunganmu? Tunjukkan jika nyaman.
- Ceritakan rekomendasi menarik yang akhirnya tidak kamu kunjungi. Apa yang membatalkannya?

**Hasil yang dicatat:** urutan tindakan, alat, waktu relatif terhadap kunjungan, penerima cerita, usaha, pilihan yang dibatalkan dan hasil yang ingin disimpan. Pisahkan tindakan yang ditunjukkan dari ingatan/pendapat yang tidak dapat diperiksa.

**Jangan bertanya pada tahap ini:** “Kalau ada aplikasi gamifikasi diary, mau pakai?” Pertanyaan itu mengukur reaksi terhadap pitch dan tidak memberi bukti perilaku sebelumnya.

## 5. Tahap B — Apakah pembuat mau menghasilkan map yang bermakna?

### Pemeriksaan framing sebelum mencoba alur

Jika tim ingin membandingkan cara menjelaskan konsep, gunakan tiga framing dari bagian 13.1 laporan: kenangan pribadi, jejak seseorang dengan cerita sendiri, dan koleksi kunjungan. Jaga panjang teks, kualitas foto dan informasi praktis setara. Tampilkan satu per satu dengan urutan yang dibagi; jangan menambahkan janji reward/fitur yang belum diputuskan hanya pada satu versi.

Minta peserta menjelaskan dengan bahasanya sendiri: siapa yang membuat, apa yang harus ia lakukan, apa hasilnya, dan apakah ia ingin melanjutkan melihat contoh map. Catat salah tafsir seperti itinerary wajib, foto harus meniru, atau kunjungan dapat dicatat dari rumah.

Pilihan slogan hanya bukti pemahaman dan reaksi awal. Tetap jalankan tugas/perilaku di bawah sebelum menyimpulkan pesan yang disukai adalah produk yang akan digunakan. Jika bagian framing berpotensi menggiring penjelasan pengalaman lampau, lakukan **setelah Tahap A**, bukan sebelumnya.

### Aktivitas pembuatan map

**Hipotesis H1:** pembuat dapat menghasilkan map yang ingin ia simpan dari bahan miliknya, meski belum ada reward atau pengikut.

**Aktivitas:** peserta memilih sendiri beberapa tempat dari satu atau beberapa perjalanan. Minta ia membuat map/diary sederhana, termasuk foto yang ia pilih dan cerita yang dianggap perlu. Jangan mewajibkan jumlah pin, review lengkap, jadwal atau tips jika peserta tidak menginginkannya.

**Perhatikan:**

- Bagian yang dibuat dengan sukarela dibanding bagian yang hanya dibuat karena instruksi.
- Waktu dan usaha memilih foto, menandai tempat dan menulis.
- Apakah ia ingin menyimpan hasilnya setelah sesi.
- Konten yang bersedia dibagikan dan yang ingin tetap pribadi.
- Apakah kumpulan tempat itu dimaknai sebagai kenangan, rekomendasi atau rute.

**Sinyal positif:** peserta melihat manfaat hasil pribadi dan dapat menjelaskan kapan akan menggunakannya. **Sinyal negatif:** seluruh nilai bergantung pada “kalau nanti banyak yang follow” sementara ia tidak ingin menyimpan hasilnya sendiri.

Ukuran sampel kecil hanya membantu memutuskan eksperimen berikutnya. Jangan menyimpulkan kontribusi konten akan tumbuh sendiri dari beberapa map yang dibuat dalam sesi berbayar.

## 6. Tahap C — Mengapa memilih jejak seseorang?

**Hipotesis H2:** hubungan dengan pembuat atau tema yang cocok menambah alasan mengikuti map di luar daftar tempatnya.

**Aktivitas:** tampilkan beberapa map nyata dengan izin pembuat, masing-masing jelas tema, cakupan dan usahanya. Bandingkan konteks:

1. Map dari orang yang dikenal peserta.
2. Map dari orang asing dengan minat yang cocok.
3. Daftar tempat dengan informasi praktis tetapi cerita pembuat minimal.

Jika menguji pengaruh identitas, jaga tempat, jumlah pin, jarak dan informasi praktis setara sejauh mungkin. Urutan tampilan dibagi antar peserta. Jangan menyebut pembuat sebagai teman/ahli jika itu tidak benar. Identitas boleh disembunyikan dengan izin, tetapi tidak dipalsukan.

**Pertanyaan setelah memilih:** “Apa yang membuat pilihan ini pantas dijalani?”, “Apa yang ingin kamu lihat atau lakukan di sana?”, dan “Bagian mana yang ingin kamu ubah?”

**Yang dibedakan:** memilih untuk dibaca, disimpan, dibagikan dan benar-benar dijalani. Jangan menghitung save atau like sebagai kunjungan.

**Sinyal negatif penting:** peserta ingin mendatangi tempatnya tetapi tidak peduli cerita pembuat atau relasi antardiary. Ini tidak membatalkan kegunaan tempat, tetapi melemahkan proposisi “mengikuti jejak seseorang”.

## 7. Tahap D — Bandingkan kegiatan saat berkunjung

**Hipotesis H3:** mekanisme yang dipilih menambah kesenangan atau hasil yang bermakna dengan usaha yang masih layak.

Gunakan kawasan publik yang mudah dijangkau dan beberapa titik yang memang bisa dikunjungi. Tidak perlu menunggu perjalanan ke Jepang. Contoh cakupan awal: 2–3 titik yang dapat diuji dalam satu sesi pendek; durasi sesungguhnya ditentukan kondisi dan peserta.

### Kondisi pembanding

| Kondisi | Yang diberikan | Pertanyaan yang dijawab |
|---|---|---|
| Praktik biasa | Konten tempat setara, ditangani memakai alat yang biasa dipakai peserta. | Apakah aplikasi usulan menambah nilai terhadap kebiasaan nyata? |
| Diary/map tanpa game tambahan | Cerita pembuat, pin dan tempat untuk menyimpan foto sendiri. | Apakah nilai datang dari diary dan hubungan cerita? |
| Diary/map dengan satu mekanisme game | Bahan sama dengan satu mekanisme yang jelas, misalnya koleksi stamp. | Apakah mekanisme memberi tambahan yang dapat diamati? |

Jangan menguji semua mekanisme sekaligus. Pemilihan mana yang dicoba lebih dulu mengikuti hasil Tahap A–C. Untuk perbandingan, bedakan urutan atau gunakan rute setara agar kelelahan, cuaca dan pengulangan tidak otomatis menguntungkan salah satu kondisi.

Jika prototipe belum punya GPS sungguhan, fasilitator boleh menandai proses sebagai **simulasi**. Hasilnya hanya bukti pemahaman/kegiatan, bukan akurasi lokasi atau ketahanan sistem.

### Yang diamati

- Waktu melihat layar dibanding menikmati tempat; alasan membuka aplikasi kembali.
- Pilihan jenis foto, kebutuhan mengedit dan hambatan unggah.
- Bantuan yang diberikan fasilitator.
- Keputusan melewati, melanjutkan atau berhenti, beserta sebabnya.
- Apakah titik berikut dipilih secara sukarela setelah tugas minimum selesai.
- Hasil yang ingin disimpan atau ditunjukkan kepada orang lain.

Setelah kegiatan, peserta dapat menilai kesenangan, usaha dan nilai hasil pada butir sederhana berskala 1–7. Jika menggunakan butir buatan tim, sebut sebagai pertanyaan evaluasi praktis; jangan mengklaimnya instrumen psikometrik tervalidasi.

Jumlah foto/check-in perlu dicatat bersama konteksnya. Tiga foto karena instruksi fasilitator berbeda dengan tiga kunjungan yang dipilih sendiri.

## 8. Tahap E — Apakah aturan GPS sepadan?

**Hipotesis H4:** peserta memahami dan menghargai arti pencapaian lokasi, serta dapat pulih dari kegagalan yang wajar.

**Aturan aktif untuk diuji:** GPS pengikut di area saat upload. Jangan diam-diam menggantinya dengan EXIF foto atau check-in manual.

Tunjukkan kondisi berikut dalam prototipe atau walkthrough yang diberi label:

- Ada di lokasi dengan koneksi baik.
- Ada di lokasi tetapi akurasi perangkat buruk.
- Foto sudah diambil, pengguna ingin mengedit dan mengunggah di hotel.
- Upload mulai di lokasi, lalu pengguna meninggalkan area sebelum transfer selesai.
- Izin lokasi ditolak/perkiraan, atau aplikasi memakai sampel lokasi lama.
- Foto lama ada dalam galeri, tetapi pengguna sekarang di tempat lain.

**Pertanyaan:** “Menurutmu apa yang dicatat sebagai pencapaian?”, “Apa yang kamu harapkan terjadi?”, dan “Apa yang kamu lakukan setelah kondisi ini?” Jangan menjelaskan jawaban ideal sebelum mengamati pemahamannya.

Tanyakan juga siapa yang menurut peserta dapat melihat foto/kunjungannya dan kapan hal itu terlihat. Bedakan bukti lokasi untuk pencapaian dari pengumuman posisi ke publik. Hak visibility belum ditetapkan; walkthrough perlu menjelaskan varian yang ditampilkan agar asumsi peneliti dan peserta tidak bertukar tanpa disadari.

Untuk menilai alternatif B (mencatat kunjungan sekarang, melengkapi foto kemudian) atau C (arsip historis dengan status berbeda), tim perlu menyetujuinya sebagai **varian penelitian konsep**. Hasil perbandingan bukan izin otomatis mengubah aturan produk.

### Jika kelak dibuat spike teknis

Pisahkan pekerjaan ini dari uji desirability. Catat perangkat, OS, lokasi, kondisi bangunan, jaringan, izin presisi, radius target, usia sampel dan hasil yang diharapkan. Ukur penolakan keliru, penerimaan keliru, waktu memperoleh lokasi dan pemulihan. Uji batas dalam/luar area dan perpindahan ketika upload berlangsung.

Dokumentasi framework, simulator dan flag simulasi tidak membuktikan pengalaman GPS pada objek wisata sebenarnya. App Attest tidak dijadikan bukti foto asli atau identitas pengunjung. Tidak ada spike yang dijalankan dalam desk research ini.

## 9. Tahap F — Follow-up dan longevity

**Hipotesis H5:** nilai diary tetap ada setelah sesi dan peserta mempunyai alasan menggunakan kembali ketika kesempatan relevan muncul.

Contoh follow-up awal 7–14 hari dapat mengecek apakah hasil disimpan/dibuka lagi. Jangka itu **belum cukup membuktikan retensi antarliburan**.

Catat secara terpisah:

1. Membuka arsip karena ingin mengingat sesuatu.
2. Membagikan hasil tanpa diminta.
3. Melanjutkan map yang belum selesai ketika berada di kawasan relevan.
4. Memilih map lain atau membuat map sendiri.
5. Tidak mempunyai kesempatan berkunjung lagi.
6. Mempunyai kesempatan tetapi memilih tidak menggunakan.

Kategori 5 dan 6 tidak disatukan. Catat pula apakah fasilitator mengingatkan atau memberi insentif. Bila ada kompensasi, dasarkan pada waktu partisipasi, bukan jumlah unggahan atau kewajiban menyelesaikan semua titik.

### Definisi hasil agar longevity tidak menjadi angka yang menyesatkan

| Pertanyaan | Pembilang dan konteks yang dicatat | Batas interpretasi |
|---|---|---|
| Apakah map diikuti? | Orang yang benar-benar memulai kunjungan, dibanding orang yang melihat map dan punya kesempatan relevan. | Pembaca global yang belum berada di destinasi tidak otomatis termasuk peluang kunjungan saat itu. |
| Apakah game diteruskan? | Orang yang memilih titik berikut setelah tugas minimum, dibanding yang memang dapat melanjutkan. | Waktu habis, hujan, tempat tutup dan tidak ingin lanjut dicatat sebagai sebab berbeda. |
| Apakah arsip bernilai? | Membuka kembali untuk alasan tertentu, menyimpan/mengekspor atau menunjukkan hasil tanpa diminta. | Membuka karena reminder penelitian bukan akses spontan; ekspor saja juga bukan kepastian memakai app lagi. |
| Apakah kembali pada kesempatan berikut? | Pengguna lama yang memakai saat kesempatan relevan berikutnya, dibanding pengguna lama yang mempunyai kesempatan itu. | "Kesempatan" perlu disepakati operasional sebelum membaca hasil, bukan didefinisikan ulang agar angka bagus. |
| Apakah pasokan bertambah? | Map yang dibuat/diperbarui tanpa tugas penelitian, disertai asal pembuat dan usaha. | Map buatan tim atau sesi berbayar tetap dapat dipakai, tetapi tidak disebut kontribusi organik. |
| Apakah konten lokal cukup? | Sesi ketika peserta menemukan setidaknya satu map yang ingin/layak dijalani pada area dan kondisinya. | Banyak map secara global tidak menjawab kecocokan lokal; kriteria relevan perlu alasan peserta. |

Pada sampel awal, laporkan kejadian dan x dari n dengan konteksnya. Belum perlu membuat satu skor gabungan yang menutupi kegagalan salah satu kegiatan. Tidak ada target persentase keberhasilan pasar yang ditetapkan dari desk research ini.

## 10. Uji beban kontribusi dan pemeliharaan

**Hipotesis H6:** map dapat dijaga tetap berguna dengan usaha yang sanggup ditanggung pihak yang bersedia.

Pada map percobaan, catat siapa yang menangani pin salah, perubahan akses, foto/cerita yang dilaporkan dan pencapaian yang gagal. Catat menit kerja serta alasan tindakan. Minta pembuat menjelaskan kesediaannya memperbarui tanpa menganggap semua pembuat akan menjadi kurator.

Bandingkan model yang berbeda: pembuat merawat sendiri, komunitas membantu melaporkan, atau pengelola menangani laporan. Ini keputusan operasional yang perlu diamati. UGC tetap membutuhkan aturan dan penanggung jawab.

## 11. Evidence log dan batas metrik

Gunakan kode peserta, bukan nama publik. Untuk setiap sesi, simpan:

| Kolom | Isi |
|---|---|
| Participant/context | Kode, kebiasaan relevan, hubungan dengan tim dan kesempatan bepergian. |
| Condition | Praktik biasa/diary/game, map, creator context dan aturan lokasi yang ditampilkan. |
| Observation | Tindakan berurutan, pilihan, waktu, bantuan, gangguan dan hasil. |
| Participant explanation | Alasan yang benar-benar dikatakan; kutipan hanya dengan catatan akurat dan izin. |
| Interpretation | Dugaan tim, dibedakan dari tindakan dan bahasa peserta. |
| Alternative explanation | Efek fasilitator, konten lebih menarik, hadiah, teman, cuaca atau urutan. |
| Decision | Hipotesis dipertahankan, direvisi, atau belum dapat dinilai. |

Laporkan jumlah sebagai x dari n pada kelompok dan tugas yang jelas. Hindari “80% traveller membutuhkan” dari sampel kenyamanan. Jangan menyamakan minat, save, instalasi, kunjungan pertama, pengulangan, retensi dan willingness-to-pay.

## 12. Cara mengambil keputusan tanpa memaksakan ide

| Pola hasil | Keputusan yang layak dipertimbangkan |
|---|---|
| Diary pribadi bernilai; mengikuti jejak tidak menarik. | Periksa apakah inti produk sebaiknya tetap arsip/berbagi; jangan mengklaim game sosial sudah terbukti. |
| Pengikut tertarik, pembuat enggan menyusun map. | Selidiki beban pembuatan atau model pasokan konten; jangan mengasumsikan marketplace UGC. |
| Tema menarik, identitas pembuat tidak berpengaruh. | Pertimbangkan apakah tema/kurasi lebih penting daripada relasi creator–follower. |
| Pengguna menikmati game tetapi tidak peduli hasil diary. | Periksa apakah produk lebih cocok sebagai aktivitas eksplorasi; itu arah yang berbeda dan perlu keputusan tim. |
| Pengguna menghargai pencapaian tetapi aturan upload menghambat. | Tinjau kebijakan verifikasi bersama tim, dengan konsekuensi bukti yang dinyatakan. |
| Hanya menarik selama fasilitator mengarahkan atau hadiah besar diberikan. | Kesenangan/pemakaian mandiri belum didukung; jangan menyebutnya retensi organik. |
| Hubungan cerita, kegiatan dan hasil semuanya dipilih sukarela. | Lanjutkan ke prototipe yang menguji penggunaan berikutnya dan operasi nyata. |

Sebelum sesi, tim perlu menuliskan pola mana yang cukup untuk melanjutkan atau merevisi. Kriteria itu untuk keputusan eksperimen kecil, bukan ambang statistik keberhasilan pasar. Hasil negatif perlu boleh mengubah arah; jika tidak, uji hanya akan menjadi cara mengumpulkan persetujuan.
