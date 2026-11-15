# Riset Apple HIG dan UX travel: tujuan, aksi, dan hasil tiap layar

**Status konteks — 29 Oktober 2026:** Temuan UX bertanggal dipertahankan. Pemetaan aksi pada konsep kreator perlu dibaca bersama alur target AI; tidak ada audit UI/HIG atau pemeriksaan sumber baru pada update ini. Lihat [acuan aktif](../product/ai-trip-planning-user-flow-2026-10-29.md).

**Tanggal akses:** 21 Oktober 2026, Asia/Jakarta.  
**Status:** riset dan usulan desain untuk revisi wireframe; bukan audit kepatuhan native atau implementasi.  
**Hasil pendamping:** [matriks aksi layar](../product/rundown-screen-action-spec-2026-10-21.md) dan [register sumber](travel-ux-hig-sources-2026-10-21.csv).  
**Dasar produk:** cerita Athar, klarifikasi waktu fleksibel dan WeatherKit, [CBL.md](../../../source-records/CBL.md), [wireframe v1](../../../missing-evidence.md#missing-06b84a4df0de), serta [riset WeatherKit](weatherkit-traveller-experience-research-2026-10-21.md).

## 1. Kesimpulan untuk aplikasi kita

Rancangan perlu membantu pengguna menjawab tiga hal pada setiap keadaan: **saya sedang melakukan apa, informasi apa yang diperlukan untuk memutuskan, dan apa hasil tindakan berikutnya**.

Pekerjaan pengguna berubah sepanjang perjalanan:

1. **Menemukan dan membandingkan:** mencari Kota Tua dan memilih pengalaman yang cocok.
2. **Menentukan pelaksanaan:** mengetahui landing point, memilih waktu mulai, memahami waktu dan kondisi perjalanan.
3. **Menjalankan:** menuju tempat yang benar, menikmati spot, mengambil foto, lalu melanjutkan.
4. **Mengenang dan membagikan:** memperoleh album serta memilih apakah dan bagaimana membagikannya.

Karena itu, peta dapat menjadi konteks yang berkelanjutan, sedangkan isi panel dan aksi utama mengikuti keadaan. Tiga belas baris alur pada matriks pendamping adalah **surface/keadaan tugas**, bukan keharusan membuat tiga belas halaman.

Prioritas revisi yang disarankan:

- Membawa search/peta ke entry sesuai cerita Athar, dengan daftar hasil yang mudah dibandingkan.
- Menjelaskan perbedaan menuju landing point dan menjalankan urutan spot.
- Menyederhanakan konfigurasi untuk penggunaan langsung; tanggal/jam tetap dapat diedit.
- Menghubungkan dokumentasi foto dengan penyelesaian kunjungan dalam best-case.
- Menghasilkan album satu perjalanan dengan pilihan selesai tanpa berbagi.
- Menempatkan cuaca dekat keputusan yang dipengaruhinya.

Semua bentuk tombol, pemisahan layar, dan pilihan presentasi dalam laporan ini adalah **Proposed**, kecuali disebut sebagai perilaku yang terdokumentasi atau konteks yang diberikan pengguna.

## 2. Metode, bukti, dan baseline

### Evidence labels

- **Observed:** terlihat pada sketsa atau teks sumber wireframe yang diperiksa. Tidak membuktikan perilaku runtime.
- **Documented:** dinyatakan dokumentasi resmi platform atau produk.
- **Inferred:** interpretasi dari bukti; tingkat keyakinan dicatat bila berdampak.
- **Proposed:** pilihan desain yang diperkenalkan untuk ditinjau.
- **Needs confirmation:** keputusan produk yang belum ditetapkan pengguna.

### Artefak yang ditinjau

| ID | Artefak | Cakupan inspeksi | Batas |
|---|---|---|---|
| V01 | Foto papan fabea1ee…jpg | Reviewed: alur Athar di kiri dan rangkaian layar di kanan; map/search, ongoing/arrived, foto, hasil perjalanan. | Foto statis; beberapa tulisan kecil/refleksi terbatas. |
| V02 | Foto papan 60756e84…jpg | Reviewed: search/result, detail rundown, GO, detail tempat, ongoing/arrived, album, serta catatan tambahan. | Foto statis; onboarding/gamifikasi di sisi papan bukan keputusan fitur dari cerita 14 langkah. |
| W01 | screens.js wireframe v1 | Reviewed: 34 screen family dan 16 definisi state, label aksi, isi, dan catatan asumsi. | Pemeriksaan sumber HTML/JS, bukan walkthrough runtime pada pekerjaan ini. |
| W02 | wireframe.js | Reviewed secara terarah: handler mulai, selesai kunjungan, selesai perjalanan, pemilihan dan unggah foto. | Tidak menjalankan ulang prototipe atau semua handler. |
| C01 | Cerita pengguna dan riset WeatherKit | Given: best-case dan tambahan fleksibilitas/cuaca. | Ketersediaan API di destinasi serta manfaat UX belum diuji. |

Baseline yang diperiksa ulang pada project.pbxproj di proyek lokal: target iOS **18.0**, Swift language mode **5.0**, target device family **iPhone dan iPad**. Toolchain/SDK aktif, runtime, build, Dynamic Type, VoiceOver, dan pengujian perangkat fisik tidak diperiksa ulang. Proyek terdapat di <LOCAL_HOME>/Programming/software/ios/poc-c67; tidak ada kode proyek yang diubah.

HIG yang dibaca adalah halaman resmi terkini pada tanggal akses. Changelog yang terlihat mencakup Search fields 8 Juni 2026, Sheets 24 Maret 2026, dan Buttons 16 Desember 2025. Tanggal akses berbeda dari tanggal pembaruan sumber. Saran sistem visual baru tidak otomatis tersedia pada semua runtime iOS 18; riset aksi ini tidak menaikkan deployment target atau menetapkan API baru.

## 3. Prinsip HIG → implikasi aksi per layar

### A. Tugas dan hierarki tindakan

**Documented:** Apple menyarankan membantu pengguna berkonsentrasi pada tugas utama, membatasi kontrol yang terlihat, dan membuat detail/aksi tambahan tetap ditemukan. Halaman Buttons menyarankan satu atau dua tombol berpenampilan menonjol per view, label yang mengomunikasikan tujuannya, dan target sentuh umum setidaknya 44 × 44 pt. [H01 — Designing for iOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ios), [H05 — Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)

**Proposed:** tentukan satu keputusan dominan pada tiap keadaan. Contoh label: “Lihat rundown”, “Menuju titik awal”, “Tambah foto”, “Ke spot berikutnya”, “Lihat album”. Kontrol seperti kembali, lokasi saya, atau daftar spot tetap dapat tersedia. Ini bukan aturan bahwa setiap layar hanya boleh memiliki satu tombol.

### B. Search dan hasil yang dapat dibandingkan

**Documented:** search penting perlu mudah ditemukan, scope jelas, dan hasil disederhanakan. Saran pencarian dapat mengurangi pengetikan. Apple membahas beberapa penempatan search; pilihan bergantung hubungan dengan konten dan kontrol lain. [H03 — Searching](https://developer.apple.com/design/human-interface-guidelines/searching), [H04 — Search fields](https://developer.apple.com/design/human-interface-guidelines/search-fields)

**Proposed:** scope traveler adalah mencari rundown di suatu tujuan. Setelah memilih Kota Tua, tampilkan rundown dengan atribut sebanding: titik awal, jumlah spot, perkiraan durasi, karakter pengalaman, serta waktu/kondisi relevan. Search lokasi pada editor kreator adalah tugas berbeda.

Untuk jelajah peta, pertahankan hubungan query, area pencarian, kartu terpilih, dan geometri rute. “Cari di area ini” merupakan kandidat interaksi untuk diuji; pembaruan otomatis juga mungkin, tetapi perilakunya harus jelas dan tidak menghapus seleksi tanpa alasan. HIG tidak menetapkan satu mekanisme pencarian area yang wajib.

### C. Peta sebagai konteks dan daftar sebagai alat keputusan

**Documented:** peta diharapkan interaktif; elemen yang dipilih perlu terlihat jelas. HIG mendukung clustering pin berdekatan dan menyarankan menjaga lokasi terpilih tetap terlihat saat menampilkan detailnya. [H02 — Maps](https://developer.apple.com/design/human-interface-guidelines/maps)

**Proposed:** hasil rundown dapat dibaca lewat kartu/daftar yang tersinkron dengan peta. Mengetuk satu kartu menyorot rundown yang sama; daftar urutan spot menjelaskan hal yang sulit dibandingkan melalui pin saja. Pan/zoom tidak boleh diam-diam mengubah rundown aktif. Pengembalian kamera ke posisi pengguna sebaiknya jelas melalui kontrol atau mode follow.

### D. Navigasi, sheet, dan tugas sementara

**Documented:** tab bar digunakan untuk berpindah bagian utama, sedangkan toolbar menampung aksi di konteks. Sheet cocok untuk tugas sementara; alur panjang dapat memerlukan presentasi lain. Pengguna perlu jalan keluar yang jelas dan tidak ditumpuki sheet berlapis. [H06 — Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars), [H25 — Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars), [H07 — Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets), [H08 — Modality](https://developer.apple.com/design/human-interface-guidelines/modality)

**Proposed:** filter atau pemilihan waktu singkat dapat memakai sheet. Detail rundown bisa menjadi tujuan navigasi; panel nonmodal di atas peta layak dieksplorasi bila pengguna masih perlu berinteraksi dengan peta. Kamera/preview membutuhkan ruang cukup. Pilihan tiga/empat tab v1 tetap usulan; HIG tidak memilih jumlah tab produk kita.

### E. Waktu fleksibel dan input yang proporsional

**Documented:** gunakan default wajar, minimalkan input yang dapat diperoleh sistem, dan pertimbangkan pilihan alih-alih mengetik. Picker tanggal/jam perlu tetap terkait dengan field yang diedit. [H11 — Entering data](https://developer.apple.com/design/human-interface-guidelines/entering-data), [H12 — Pickers](https://developer.apple.com/design/human-interface-guidelines/pickers)

**Proposed:** penggunaan langsung tidak perlu diawali form nama perjalanan. Sediakan konteks “Sekarang” dan opsi mengubah tanggal/jam; jelaskan apakah itu jam berangkat dari posisi pengguna atau jam tiba di landing point. Tampilkan akhir perjalanan serta kesempatan yang terpengaruh. Default tidak boleh menyembunyikan tanggal atau menggeser sunset dan jam operasional.

### F. Izin muncul saat tugas membutuhkannya

**Documented:** akses data perlu sesuai kebutuhan fitur dan diminta ketika alasannya jelas. Onboarding dapat berupa bantuan kontekstual dan tutorial opsional. [H10 — Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy), [H09 — Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding)

**Proposed:** browse dan search manual tetap dapat dilakukan tanpa lokasi. Lokasi diminta saat pengguna menginginkan posisi/rute dari dirinya atau ketika validasi foto membutuhkan akses. Kamera diminta ketika kamera dipilih. Pemilihan foto melalui picker sistem dapat dilakukan tanpa meminta akses seluruh library; izin penyimpanan ke Photos adalah kebutuhan berbeda. [T01 — Photos picker](https://developer.apple.com/documentation/photokit/selecting-photos-and-videos-in-ios)

Jangan membuat pre-permission screen yang meniru dialog iOS atau mengubah pilihan penolakan menjadi jebakan. Penolakan izin perlu penjelasan fitur yang terdampak dan jalan kembali.

### G. Feedback dekat tindakan dan progres yang bermakna

**Documented:** status dapat ditempatkan dekat konteksnya; alert dipakai hemat untuk hal penting dan dapat ditindaklanjuti. Progress proses perlu sesuai data yang benar-benar diketahui. [H13 — Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback), [H14 — Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts), [H15 — Progress indicators](https://developer.apple.com/design/human-interface-guidelines/progress-indicators)

**Proposed:** “Tiba di spot” dapat menjadi perubahan status pada panel, tanpa modal ucapan selamat pada setiap perhentian. Bedakan “spot 2 dari 5”, “foto 2 tersimpan”, dan progres unggahan. HIG Progress indicators membahas proses; visual progres perjalanan adalah adaptasi produk, bukan ketentuan gamifikasi dari Apple.

Sukses penyimpanan/unggah perlu sesuai hasil nyata. Draft dan pilihan foto dipertahankan jika gagal; alasan tombol tidak tersedia serta langkah pemulihan terbaca.

### H. Foto, album, kontribusi, dan berbagi

**Documented:** Share Sheet menyajikan aktivitas berbagi yang familier dan sesuai konteks. Pengguna perlu memahami akses serta penggunaan data mereka. [H16 — Activity views](https://developer.apple.com/design/human-interface-guidelines/activity-views), [H10 — Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy)

**Proposed:** preview foto menampilkan spot tujuan, foto, dan tindakan nyata yang dilakukan. Cerita panjang tidak menjadi syarat baru. Sesudah kunjungan terakhir, album muncul sebagai satu perjalanan dan memiliki opsi selesai tanpa ekspor.

Kewajiban foto dalam best-case tidak menyatakan bahwa foto otomatis dipublikasikan. Kontribusi kepada traveler lain, penyimpanan jurnal, dan ekspor media sosial memerlukan penjelasan audience serta akibat tindakan yang berbeda. Aturan kontribusi masih **Needs confirmation**; jangan menyamarkannya dengan label “Simpan” bila sebenarnya memublikasikan konten.

### I. Cuaca dekat keputusan dan kontrol perubahan

**Proposed berdasarkan riset WeatherKit:** ringkasan cuaca muncul ketika membantu keputusan: membandingkan jam mulai, menyiapkan barang, atau menilai perpindahan berikutnya. Saat ada saran perubahan, tampilkan alasan, bagian terdampak, perubahan waktu/spot, serta opsi menerapkan atau mempertahankan rencana.

**Documented:** feedback dan notifikasi perlu sebanding dengan urgensi, tidak berulang untuk hal yang sama; hasil undo harus dapat dipahami. [H21 — Notifications](https://developer.apple.com/design/human-interface-guidelines/notifications), [H22 — Undo and redo](https://developer.apple.com/design/human-interface-guidelines/undo-and-redo)

Perubahan otomatis penuh belum diputuskan. Jangan mengganti tujuan secara mendadak saat pengguna sedang bertindak. Tidak ada janji alarm hujan per menit di Kota Tua; lihat batas wilayah pada [riset WeatherKit](weatherkit-traveller-experience-research-2026-10-21.md).

### J. Aksesibilitas dan penggunaan di lapangan

**Documented:** dukung pembesaran teks, kontras, feedback yang tidak bergantung satu indera, serta alternatif untuk gestur. Hierarki perlu tetap terbaca pada ruang dan ukuran teks berbeda. [H18 — Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [H19 — Typography](https://developer.apple.com/design/human-interface-guidelines/typography), [H17 — Gestures](https://developer.apple.com/design/human-interface-guidelines/gestures), [H20 — Layout](https://developer.apple.com/design/human-interface-guidelines/layout)

**Proposed:** informasi sekarang/berikutnya dapat dibaca singkat, tombol penting mudah dijangkau, dan status tiba/jauh tidak hanya menggunakan warna. Peta memiliki alternatif daftar; perpindahan, urutan, dan caption lokasi dapat dibaca VoiceOver. Swipe kartu dapat menjadi pintasan, sedangkan tindakan penting tetap memiliki kontrol yang dapat ditemukan.

Ini intent desain; belum bukti penggunaan satu tangan, kondisi silau, VoiceOver, atau Dynamic Type berhasil pada aplikasi kita.

## 4. Pembelajaran khusus dari travel dan mobile UX

| Sumber primer | Temuan yang terdokumentasi | Implikasi yang diusulkan | Batas penerapan |
|---|---|---|---|
| [P01 — komoot](https://support.komoot.com/hc/en-us/articles/10207935661338-Navigate-a-saved-route) | Petunjuk menuju start point dibedakan dari rute; instruksi berikutnya menonjol; pause dan finish merupakan tindakan berbeda. | Pisahkan akses ke landing point, pelaksanaan, dan penutupan; pertahankan orientasi sekarang/berikutnya. | Kategori outdoor navigation; tidak berarti kita telah memilih voice guidance atau membangun turn-by-turn. |
| [P02 — Wanderlog](https://help.wanderlog.com/hc/en-us/articles/5159565134875-See-time-and-distance-between-places) | Moda dan durasi dapat dibuka pada segmen antar-tempat. | Perpindahan menjadi objek yang dapat ditinjau langsung di rundown. | Artikel 2023; bukan UI native terkini yang diuji. |
| [P03 — Polarsteps](https://support.polarsteps.com/hc/en-us/articles/24266349354642-How-do-I-share-my-trip-with-family-and-friends) | Berbagi gambar dan berbagi tautan merupakan pilihan berbeda; tautan berdampak pada akses. | Bedakan keluaran album, tautan trip, dan audience. | Tidak mengadopsi follower/social model mereka sebagai kebutuhan kita. |
| [P04 — Google Maps](https://support.google.com/maps/answer/6291838?co=GENIE.Platform%3DiOS&hl=en) | Peta offline dan ketersediaan petunjuk per moda memiliki batas berbeda. | Label download harus menyebut apa yang tersedia. | Batas Google bukan batas pasti MapKit; aplikasi kita belum menjanjikan offline penuh. |
| [U01 — NN/g, 2014](https://www.nngroup.com/articles/mobile-maps-locations/) | Studi locator menemukan gestur peta yang berbenturan dengan scroll dan kesulitan memilih pin. | Sediakan hasil terstruktur dan uji konflik gestur map/panel. | Konteks store finder lama; bukan bukti map-first salah bagi aplikasi kita. |
| [U02 — NN/g, 2015](https://www.nngroup.com/articles/mobile-ux/) | Penggunaan mobile terinterupsi; konteks dan tugas perlu mudah dipulihkan. | Saat kembali dari kamera, Maps, atau lock screen, pulihkan rundown dan spot aktif. | Riset lintas kategori; tidak memvalidasi kebutuhan traveler C6. |

**Perbedaan sumber yang perlu dijaga:** NN/g 2014 mengkritik clustering yang membingungkan pada contoh tertentu; HIG Maps sekarang justru menyarankan clustering pin tumpang tindih. Rekomendasi kita adalah mengikuti pola platform yang jelas, menyediakan daftar, dan menguji pemilihan pin. Jangan mengubah temuan lama menjadi larangan universal.

## 5. Bagian v1 yang perlu ditinjau terhadap konteks baru

Ini **temuan alignment produk dari sumber desain**, bukan daftar pelanggaran HIG atau hasil audit runtime.

| Bukti v1 | Perbedaan dengan kebutuhan sekarang | Arah revisi yang diusulkan |
|---|---|---|
| L01: search dan kartu tanpa map penemuan. | Athar juga menjelajah area melalui peta. | Map/search dengan kartu atau daftar hasil yang terkait. |
| T01–T02: nama, tanggal, jam, review dan simpan sebelum pelaksanaan. | Best-case memuat niat berangkat langsung. | Default waktu yang terlihat dan konfigurasi singkat; form mendatang tetap tersedia ketika dibutuhkan. |
| T07: contoh perpindahan antarspot. | Perjalanan dari posisi pengguna ke landing point belum menjadi tugas yang jelas. | Tampilkan tujuan awal dan perjalanan menuju titik awal secara eksplisit. |
| A02: “Tambahkan jurnal foto” dan “Tandai kunjungan selesai” terpisah. | Foto wajib dalam best-case terbaru. | Hubungkan foto dengan penyelesaian kunjungan; pengecualian belum ditetapkan. |
| Handler complete-stop tidak memeriksa foto. | Selesai kunjungan belum mewakili rangkaian terbaru. | Modelkan status tiba, foto, hasil simpan/kirim dan kesiapan lanjut. |
| A04 → J01/J03: ringkasan hari dan entri jurnal. | Hasil yang diinginkan adalah album Kota Tua sebagai satu perjalanan. | Akses langsung ke album hasil perjalanan dan berbagi opsional. |
| L04/C05: cuaca sebagai detail. | Cuaca kini memengaruhi waktu, persiapan dan penyesuaian. | Ringkasan kontekstual pada keputusan terkait; detail tetap dapat dibuka. |

Referensi bukti: [screens.js](../../../missing-evidence.md#missing-83197e886c26) dan [handler wireframe](../../../missing-evidence.md#missing-31313f730cb2). Isi A02 dan handler selesai memang dapat dipisahkan dari unggah di sumber; belum diuji ulang interaksinya pada pekerjaan ini.

## 6. Aturan praktis untuk menggambar versi berikutnya

Gunakan kontrak sederhana untuk setiap surface:

1. **Tujuan:** keputusan atau tugas yang sedang diselesaikan.
2. **Informasi minimum:** yang dibutuhkan sebelum bertindak; detail lain tetap dapat dibuka.
3. **Aksi utama dan tambahan:** label menggambarkan hasil, prominence mengikuti prioritas.
4. **Akibat tindakan:** state apa berubah, dan pengguna berada di mana sesudahnya.
5. **Kembali/batal:** query, seleksi, foto dan input apa yang dipertahankan.
6. **Gagal/terinterupsi:** alasan, draft yang tersisa, dan cara melanjutkan tugas yang sama.
7. **Aksesibilitas:** padanan nonvisual dan alternatif gestur.

Tidak perlu membuat layar baru untuk setiap kalimat status. “Menuju”, “tiba”, dan “foto tersimpan” dapat menjadi varian satu keluarga layar jika tujuan dan hierarkinya tetap dipahami.

Pada ruang lebar, daftar rundown/panel perjalanan dapat berdampingan dengan peta; pada ruang sempit, gunakan disclosure atau panel yang sesuai. Pertahankan query, pilihan, draft dan fokus saat ukuran berubah; jangan sekadar memperbesar kanvas iPhone. [H23 — Designing for iPadOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ipados)

## 7. Validasi sebelum menyebut desain berhasil

| Tugas uji | Apa yang diamati | Keberhasilan yang dapat dinilai |
|---|---|---|
| Dari Agora, temukan rundown Kota Tua. | Search ditemukan, scope dipahami, pan/scroll tidak bertabrakan. | Pengguna memilih rundown dan tahu titik awalnya. |
| Mulai pada jam berbeda dari kreator. | Makna jam mulai dan dampak waktunya. | Pengguna memahami jadwal pribadi versus rekomendasi sumber. |
| Menuju titik awal, lalu spot berikutnya. | Orientasi asal/tujuan dan pergantian tahap. | Pengguna tidak salah mengira sudah menjalankan spot pertama saat masih di Agora. |
| Tiba, tambahkan foto, lalu lanjut. | Kejelasan tugas, konfirmasi dan hubungan foto dengan spot. | Foto terkait tempat benar, hasilnya dipahami, dan langkah berikutnya dapat ditemukan. |
| Kembali dari kamera/petunjuk eksternal/lock screen. | Query, rundown, spot, dan draft yang dipulihkan. | Tidak mengulang pekerjaan yang sudah selesai. |
| Tinjau perubahan karena cuaca. | Pemahaman alasan dan dampak waktu. | Dapat menerapkan atau menolak dengan sadar; tidak kehilangan perjalanan aktif. |
| Selesai tanpa berbagi. | Akses album dan jalan keluar. | Album tetap dapat ditemukan dan tidak ada publikasi yang tidak dipahami. |
| Ukuran teks besar dan VoiceOver. | Urutan baca, label aksi, kontrol yang terpotong, alternatif map. | Tugas utama dapat diselesaikan dengan konteks yang memadai. |

Jangan menjadikan jumlah tap sebagai satu-satunya ukuran. Catat keberhasilan tugas, salah pilih, salah tafsir status, kehilangan konteks, dan alasan keputusan. Belum ada peserta atau hasil uji baru pada pekerjaan ini.

## 8. Handoff dan pertanyaan terbuka

Prioritas menggambar berikutnya adalah rangkaian Athar dengan waktu fleksibel; perubahan cuaca digambar sebagai cabang tambahan yang diberi label. Editor kreator, merge, serta recovery tetap disimpan sebagai cakupan terpisah yang belum digambar tim dalam best-case.

Keputusan yang tetap terbuka: apakah mulai berarti berangkat atau tiba di landing point; seberapa jauh panduan navigasi dibangun di aplikasi; apakah perubahan cuaca otomatis; bagaimana foto menjadi kontribusi dan siapa audience-nya; serta pengecualian foto saat halangan. HIG membantu kejelasan interaksi, tetapi tidak menjawab keputusan produk tersebut.

Lihat [matriks aksi](../product/rundown-screen-action-spec-2026-10-21.md) untuk jalur utama, pemetaan semua screen family v1, dan state tambahan. Tidak ada kode, wireframe, konfigurasi proyek, atau CBL yang diubah pada pekerjaan ini.
