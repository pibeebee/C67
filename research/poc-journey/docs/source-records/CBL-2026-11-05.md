# CBL — Perencanaan trip personal dengan rekomendasi AI · C6

**Diperbarui:** 5 November 2026, Asia/Jakarta (WIB).
**Tim:** C6 — Pisang Besar Balaraja, Apple Developer Academy.
**Status:** kelayakan mesin inti PoC disepakati telah terbukti pada lingkup uji saat ini: penyusunan itinerary, penyimpanan lokal dan replanning manual tanpa backend tim/AI. Integrasi provider routing aktual mempunyai bukti awal pada macOS; validasi iPhone untuk alur routing, perjalanan nyata, kesesuaian pengalaman dan manfaat pengguna belum lengkap. PoC Foundation Models terpisah sudah berjalan dengan model lokal dan MapKit aktual pada Mac serta iPhone fisik, dengan mutu rekomendasi masih parsial; hasil dan batasnya dikunci pada bagian 0A. Eksperimen preferensi berikutnya menunjukkan profil lokal + aturan native + MapKit langsung + embeddings dapat menjalankan rekomendasi tempat dasar tanpa Foundation Model; mutu personalisasi dan manfaat pengguna masih perlu dibuktikan, sebagaimana dicatat pada bagian 0B. Keputusan produk 29 Oktober dipertahankan sebagai jejak konteks.

**Catatan teknis 3 November 2026:** pengguna mengunci **hybrid adaptif** untuk routing PoC: baseline tervalidasi terlebih dahulu, kemudian cheapest insertion + multi-start local search secara selektif. Implementasi dan pengujian lokal tersedia pada [laporan PoC native](../../apps/native-routing-lab/docs/verification/ADAPTIVE_ROUTING_REPORT_2026-11-03.md). Ini memperbarui status eksperimen routing; integrasi AI dan recalculation perjalanan aktif tetap mempunyai lingkup dan bukti tersendiri.

**Arah PoC lanjutan 3 November 2026:** fungsi inti direncanakan tetap dapat digunakan tanpa backend tim/AI, dengan penyimpanan lokal dan replanning manual. Pada checkpoint ini, eksplorasi Foundation Models ditangani teman Giovan pada jalur terpisah; Giovan kemudian mengambil alih eksplorasi tersebut, dengan hasil terbaru di bagian 0A. [Masterplan PoC native](../context/docs/poc/native-trip-replanning-masterplan-2026-11-03.md) memuat tahapan, gerbang kelulusan, matriks uji dan bentuk laporan; status implementasi tiap tahap dicatat terpisah. Keputusan produk bertanggal 29 Oktober di bawah tetap menjadi jejak konteks sebelum penyesuaian fokus PoC ini.

**Hasil P0–P1, 3 November 2026:** audit jalur native, deadline tiba di endpoint, serta penyimpanan/pemulihan draft dan itinerary pilihan telah diimplementasikan secara lokal. 24 XCTest baru dan 26 XCTest Jakarta lulus; UI simpan, kegagalan/retry dan relaunch diamati pada Simulator. [Laporan dan batas bukti P0–P1](../../apps/native-routing-lab/docs/verification/NATIVE_LOCAL_P0_P1_2026-11-03.md). Pada checkpoint P0–P1 itu, replanning aktif masih pekerjaan berikutnya; status terbarunya dicatat di bawah.

**Hasil P2A–P2B, 4 November 2026:** lifecycle manual, tambah durasi, skip, deadline, review/apply/reject, revision, cancellation dan pemulihan trip aktif sudah diimplementasikan. 59 XCTest lokal (35 khusus P2) + 26 Jakarta lulus; 144 run replay berpasangan tanpa error auditor. Di antara 66 pasangan layak, 18 lebih singkat, 48 seri, 0 lebih lama; request adaptif lebih tinggi. Alur +30 menit hingga apply/relaunch serta skip/end-only diamati di Simulator. [Laporan dan batas bukti P2](../../apps/native-routing-lab/docs/verification/NATIVE_TRIP_REPLANNING_P2_2026-11-04.md). Lingkup satu hari, satu moda jalan kaki atau taksi, anchor dikonfirmasi manual; private car/transit aktif belum didukung. Berikutnya P3 layanan live/iPhone, lalu P4 pengguna.

**Penajaman lingkup 4 November 2026:** pengguna membatasi wilayah uji awal ke Jakarta dan memprioritaskan mobil/motor serta ketepatan tempat dan routing. Cuaca memakai Open-Meteo; perbaikan WeatherKit dan optimasi waktu proses ditunda. [Lingkup, batas provider motor dan urutan perbaikan](../context/docs/poc/jakarta-routing-places-scope-2026-11-04.md). Implementasi build 9 dan batas bukti terbaru dicatat pada hasil berikut.

**Hasil perbaikan Jakarta build 9, 4 November 2026:** profil Jakarta/WIB dan mobil/taksi, pemeriksaan pin wilayah, perbaikan query serta pemilihan nama/cabang, dan Open-Meteo langsung sudah diterapkan. 77 XCTest lokal +26 Jakarta lulus. Source produksi dengan MapKit/Open-Meteo aktual pada macOS menghasilkan itinerary lima tujuan lengkap, replan +30, apply, skip/end-only dan restore; fakta kunjungan pada uji diskenariokan. Build iOS/layar awal Simulator diamati, sedangkan interaksi UI lengkap dan iPhone fisik masih perlu verifikasi. Algoritme hybrid adaptif tidak diubah; motor belum mempunyai provider terintegrasi. [Laporan hasil dan cara mencoba](../../apps/native-routing-lab/docs/verification/JAKARTA_ROUTING_FIX_2026-11-04.md).

**Eksperimen Weather Lab build 10, 4 November 2026:** strategi WeatherKit diuji pada layar awal terpisah dengan tab Rencana untuk planner sebelumnya. Diagnosis satu titik, pengelompokan radius 3 km, cache maksimal 15 menit, timeout 8 detik/provider, pemutus autentikasi dan fallback Open-Meteo sudah diterapkan. Source routing/replanning/penyimpanan lama tidak berubah. 100 XCTest lokal (23 khusus Weather Lab) +26 Jakarta lulus. Run live Simulator: enam titik menjadi empat kelompok, satu request WeatherKit gagal pada layanan autentikasi lalu empat request Open-Meteo berhasil dalam sekitar 2,29 detik; pengulangan memakai empat cache hit tanpa request baru. Autentikasi WeatherKit pada iPhone belum terbukti; jalur Jakarta di tab Rencana tetap memakai Open-Meteo langsung. [Laporan, cara mencoba dan batas bukti](../../apps/native-routing-lab/docs/verification/WEATHER_LAB_2026-11-04.md).

**Checkpoint Foundation Models, 5 November 2026:** hasil Foundation Lab v0.2 build 4 dikunci sebagai bukti kelayakan teknis asisten rekomendasi tempat dan jendela waktu, dengan validasi native serta fallback. Kemampuan menentukan jam kunjung terbaik tempat nyata dan manfaat mengurangi kontribusi pengguna belum terbukti. [Laporan PoC](../../apps/c67-foundation-lab/docs/verification/RECOMMENDATIONS_REPORT_2026-11-04.md) dan [hasil iPhone fisik](../../apps/c67-foundation-lab/docs/verification/recommendations-iphone-2026-11-05/REPORT.md); rincian keputusan pada bagian 0A.

**Checkpoint preferensi dan embeddings, 5 November 2026:** Foundation Lab v0.3 build 5 menguji profil lokal dan E5 pada katalog tersimpan; v0.4 build 6 melengkapi pencarian MapKit langsung hingga rekomendasi dan feedback. Satu run aktual iPhone selesai sekitar 2,06 detik, menerima 26 baris provider dan mempertahankan 14 kandidat. Ini membuktikan alur teknis, belum menjamin kecocokan seluruh preferensi. [Laporan v0.3](../../apps/c67-foundation-lab/docs/verification/PREFERENCE_LAB_REPORT_2026-11-05.md) dan [laporan v0.4](../../apps/c67-foundation-lab/docs/verification/PREFERENCE_LIVE_REPORT_2026-11-05.md); penilaian dan batas pada bagian 0B.

**Checkpoint fakta tempat dan waktu kunjungan, 5 November 2026:** Foundation Lab v0.5 build 7 menambahkan tab **03 · Waktu**. Sebelas fasilitas nyata Jakarta dari empat sumber resmi dipakai untuk menghasilkan opsi waktu berdasarkan jam layanan, aturan masuk dan konteks aktual. 28 tes package, 17 skenario bersumber serta empat UI test lulus; satu pipeline aktual iPhone selesai sekitar 1,41 detik. Ini belum membuktikan waktu pengalaman terbaik atau keadaan venue di lapangan. [Laporan, sumber dan batas runtime](../../apps/c67-foundation-lab/docs/verification/VISIT_TIMING_REPORT_2026-11-05.md); rincian pada bagian 0C.

**Hasil prioritas 2, 5 November 2026:** Foundation Lab v0.6 build 9 menambahkan tab **04 · Kecocokan**, membandingkan kategori, E5 dan ranking gabungan pada kandidat serta aturan bukti yang sama. 24 kasus memenuhi ekspektasi penyaringan; 17 menjalankan E5 aktual. Enam perbandingan preferensi lunak seri pada ukuran cakupan atribut bersumber, sehingga keunggulan ranking gabungan belum terbukti. Build final berhasil menjalankan E5 di iPhone sekitar 0,80 detik pada katalog tersimpan. [Laporan lengkap](../../apps/c67-foundation-lab/docs/verification/PREFERENCE_QUALITY_REPORT_2026-11-05.md); rincian pada bagian 0D.

**Pendalaman manfaat embeddings, 5 November 2026:** Foundation Lab v0.7 build 10 menambahkan eksperimen **05 · E5** sebelum prioritas 3. Pada 24 kasus ranking baru yang dibekukan sebelum inferensi, E5 membantu terutama pada parafrasa arahan terhadap deskripsi bersumber: NDCG@3 0,9770 dibanding BM25 0,8299; tujuh unggul, enam belas seri, satu kalah. Seluruh 30 kasus di iPhone menghasilkan metrik dan status sesuai, dengan beberapa perbedaan urutan bawah dibanding Mac. Ini manfaat retrieval terbatas, bukan akurasi 97,7% atau manfaat pengguna yang telah terbukti. [Laporan lengkap](../../apps/c67-foundation-lab/docs/verification/EMBEDDING_BENEFIT_REPORT_2026-11-05.md); rincian bagian 0E.

**Integrasi prioritas 3, 5 November 2026:** aplikasi terpisah C67 Trip Integration **v0.1 build 3** sudah berhasil diverifikasi: **35 test package, 2 test UI Simulator dan 7 skenario live iPhone lulus**. WeatherKit bekerja tanpa fallback; rute tiga tempat, revisi durasi +30 menit dan penolakan deadline tidak layak menghasilkan bukti yang konsisten. Ini bukti integrasi teknis pada dataset/perangkat yang diuji, belum bukti kepuasan atau pengurangan beban pengguna. [Laporan hasil](../../apps/c67-trip-integration/docs/VERIFICATION_REPORT_2026-11-05.md); rincian bagian 0G.

## 0. Kesepakatan pencapaian PoC — 4 November 2026

Giovan menyepakati penilaian pencapaian berikut sebagai acuan untuk saat ini. **PoC sudah menjawab kelayakan mesin inti aplikasi; pembuktian bahwa hasilnya sesuai kebutuhan dan membantu pengguna menjalani perjalanan masih belum lengkap.** Kesepakatan ini berlaku pada lingkup eksperimen, bukan klaim kesiapan produksi atau validasi manfaat seluruh konsep.

### Motivasi yang tetap dipertahankan

Membantu seseorang mengubah daftar tempat pilihannya menjadi perjalanan yang masuk akal: menentukan urutan, waktu kunjungan dan perpindahan, lalu memahami konsekuensi ketika rencana berubah. Fungsi inti harus tetap dapat dipakai ketika backend tim/OpenRouter atau model AI tidak tersedia. Kemandirian ini tetap membutuhkan layanan peta/ETA dan, saat digunakan, provider cuaca; routing baru sepenuhnya offline belum dibuktikan.

### Pencapaian yang sudah mempunyai bukti

| Kebutuhan | Pencapaian dan batas bukti |
| --- | --- |
| Menyusun daftar tempat menjadi itinerary | Hybrid adaptif menghasilkan urutan dan jadwal pada lingkup uji; tidak ada klaim optimum global. |
| Menghitung waktu secara utuh | Perjalanan, menunggu, singgah dan deadline tiba di endpoint diperhitungkan. Kelayakan berlaku terhadap data dan batasan yang diketahui. |
| Menyesuaikan perjalanan yang berubah | Perpanjangan kunjungan, skip eksplisit, perubahan deadline, replan sisa, review/apply/reject serta pemulihan state telah diuji. Fakta kunjungan sebelumnya dipertahankan. |
| Menjaga fungsi inti tanpa backend AI | Jalur native untuk menyusun, menyimpan dan menyesuaikan trip tidak memerlukan OpenRouter/backend tim. Eksplorasi Foundation Models tetap terpisah. |
| Menggunakan provider aktual | MapKit/Open-Meteo melalui source produksi pada harness macOS menghasilkan itinerary lima tujuan Jakarta, replan +30 menit, apply, skip/end-only dan restore. Fakta kunjungan pada uji diskenariokan. |

Rujukan: [hasil P0–P1](../../apps/native-routing-lab/docs/verification/NATIVE_LOCAL_P0_P1_2026-11-03.md), [hasil P2A–P2B](../../apps/native-routing-lab/docs/verification/NATIVE_TRIP_REPLANNING_P2_2026-11-04.md), dan [hasil Jakarta build 9](../../apps/native-routing-lab/docs/verification/JAKARTA_ROUTING_FIX_2026-11-04.md). Laporan terakhir mencatat 77 XCTest lokal +26 Jakarta lulus. Hasil tersebut tidak menggantikan bukti perangkat fisik atau observasi pengguna.

Profil aktif saat ini: satu hari di Jakarta/WIB, mobil/taksi on-demand, cuaca Open-Meteo, dan pencatatan kunjungan manual. Motor belum mempunyai provider terintegrasi; penggunaan mobil pribadi dan transit pada trip aktif belum didukung. AI/Foundation Models dapat melengkapi pengalaman tanpa menjadi syarat fungsi inti. Transjakarta telah dibahas sebagai kemungkinan perluasan dengan data jaringan sendiri; belum diimplementasikan.

### Hal yang belum terjawab sepenuhnya

1. **Ketepatan data tempat.** Identitas/cabang, jam operasional, akses masuk dan durasi kunjungan perlu diperiksa. Kasus provider aktual terakhir belum memasukkan jam operasional dan memakai singgah 30 menit per tujuan; hasilnya belum membuktikan itinerary siap diikuti di lapangan.
2. **Kesesuaian dengan pengalaman yang diinginkan.** Perhitungan waktu sudah mempunyai dasar teknis. Preferensi seperti ingin tinggal lebih lama di D sambil mengejar kesempatan golden hour di C masih memerlukan pembuktian konsekuensi dan pilihan yang dapat dipahami pengguna. Pengambilan prakiraan belum membuktikan manfaat keputusan berbasis cuaca.
3. **Keandalan selama perjalanan nyata.** Alur lengkap versi Jakarta terbaru di iPhone, jaringan terputus/pulih, penutupan aplikasi, ETA di lapangan dan waktu akses/menunggu kendaraan masih perlu diuji. Bukti harness macOS dan Simulator tetap dicatat terpisah dari bukti iPhone/perjalanan.
4. **Manfaat dibanding cara pengguna sekarang.** Belum ada bukti bahwa PoC mengurangi pekerjaan menyusun jadwal, mempercepat keputusan saat terlambat, atau membantu pengguna memahami perubahan tanpa bantuan. Unit test dan benchmark tidak menjawab manfaat tersebut.

### Keputusan untuk kelanjutan evaluasi

Hybrid adaptif tetap dikunci dan eksperimen pemilihan algoritme dinilai cukup untuk iterasi ini. Prioritas berikutnya adalah melengkapi **P3 → P4** pada [masterplan](../context/docs/poc/native-trip-replanning-masterplan-2026-11-03.md): validasi data dan alur iPhone/provider, kemudian walkthrough serta perjalanan terbatas bersama calon pengguna. Keduanya masih pekerjaan berikutnya; seluruh gerbang P3/P4 belum dinyatakan lulus.

Usulan pengujian berikutnya memakai 3–5 tempat Jakarta dengan jam dan akses yang diperiksa, perubahan kunjungan +30 menit, serta satu preferensi waktu yang penting bagi peserta. Bandingkan dengan cara peserta biasanya merencanakan perjalanan dan catat bantuan, koreksi, pemahaman konsekuensi serta pilihan mereka. Foundation Models dan Transjakarta tetap mempunyai jalur evaluasi tersendiri.

## 0A. Kesepakatan hasil PoC Foundation Models — 5 November 2026

Atas permintaan Giovan, hasil dan temuan berikut **dikunci sebagai checkpoint untuk saat ini**. Penilaian yang disepakati: **Foundation Model layak dilanjutkan sebagai asisten rekomendasi dengan batas yang jelas dan validasi aplikasi.** PoC membuktikan kelayakan teknis pada skenario yang diuji; mutu seluruh rekomendasi, kebenaran penjelasan, dan pengurangan pekerjaan pengguna belum terbukti sepenuhnya.

### Tujuan, lingkup dan pembagian tanggung jawab

Motivasinya adalah mengurangi input serta koreksi pengguna melalui bantuan aplikasi, sambil menjaga fungsi inti tetap tersedia ketika backend AI tim tidak dilanjutkan. Foundation Lab dibuat sebagai aplikasi SwiftUI iPhone dan runner Mac terpisah di [proyek Foundation Lab](../../apps/c67-foundation-lab/README.md). Pengguna dapat mulai tanpa itinerary/tempat pilihan atau memilih tempat sendiri, lalu memberikan minat, ritme dan arahan opsional.

**Foundation Model tidak mengurus routing.** Perannya dalam PoC ini adalah membantu memahami preferensi, menilai kandidat tempat dari MapKit, mengusulkan jendela kunjungan dan memberi penjelasan. Pencarian, pemeriksaan wilayah/duplikat, validasi referensi dan pemilihan maksimal tiga hasil ditangani aplikasi. Model menilai shortlist; hasilnya belum membuktikan pemeringkatan terbaik seluruh tempat Jakarta. Tempat pilihan pengguna dipertahankan dengan prioritas setara tanpa menetapkan tujuan utama secara otomatis.

Lingkup awal adalah Jakarta, satu hari, maksimal enam tempat yang dinilai. Model menggunakan `SystemLanguageModel.default` lokal; kontrol berbahasa Indonesia dan teks bebas/model berbahasa Inggris. Pada runtime yang diuji, English didukung dan Indonesian dilaporkan belum didukung. Tidak ada endpoint AI hosted yang dipakai pada jalur ini; pencarian MapKit tetap memerlukan layanan data, sehingga ini bukan bukti aplikasi sepenuhnya offline. Integrasi rekomendasi ke jadwal/routing belum dilakukan dan keputusan hybrid adaptif tetap dipertahankan.

### Hasil per kemampuan

| Kemampuan | Hasil dan batas yang dikunci |
| --- | --- |
| Preferensi/onboarding | Pilihan terstruktur dan arahan opsional tersedia. Pada satu skenario koreksi Inggris yang diulang tiga kali di Mac, model menangkap minat budaya/fotografi dan menghindari kopi. Ini belum membuktikan seluruh variasi bahasa/negasi. Uji iPhone memakai teks kosong sehingga tahap ekstraksi teks dilewati. |
| Rekomendasi tempat | Model lokal dapat menilai kecocokan umum kandidat MapKit berdasarkan konteks yang diberikan. Pada uji iPhone, sepuluh kandidat diperoleh, enam dinilai dan tiga ditandai sebagai rekomendasi. Kategori/nama tidak membuktikan tempat tenang, kursi untuk membaca, harga, popularitas, aksesibilitas atau kelayakan perjalanan. |
| Rekomendasi waktu | Model dapat memberi saran aktivitas umum seperti pagi untuk minum kopi dan memakai fakta yang diberikan seperti preferensi foto sore pada fixture sintetis. **Jam kunjung terbaik tempat nyata secara andal belum terbukti.** Tanpa fakta waktu yang relevan, hasil dapat tetap `any`/tidak ada jendela khusus atau unknown. |
| Informasi/penjelasan | Penjelasan terstruktur tersedia, tetapi masih ditemukan klaim berlebihan walaupun bentuk dan referensinya valid. Ringkasan model pada uji iPhone ditolak karena referensi salah; ringkasan yang ditampilkan berasal dari template deterministik. Belum layak menerima seluruh penjelasan tanpa pemeriksaan. |

### Bukti pengujian dan kegagalan yang dipertahankan

- **Build dan tes:** Foundation Lab v0.2 build 4, prompt `recommendations-v1`; 57/57 tes otomatis lulus, build Simulator dan signed iOS berhasil. Walkthrough Simulator menggunakan fixture berlabel dan tidak dihitung sebagai inferensi iPhone.
- **Mac, 4 November:** tiga skenario baru, masing-masing tiga pengulangan, ditambah tiga pembanding tanpa model. 48/48 keluaran tahap lolos pemeriksaan struktur/referensi/aturan waktu. Angka ini bukan akurasi faktual; masih ditemukan klaim kecocokan dan penjelasan yang tidak didukung. Pengulangan greedy saling berkorelasi dan bukan holdout independen. [Laporan serta batas penilaian](../../apps/c67-foundation-lab/docs/verification/RECOMMENDATIONS_REPORT_2026-11-04.md).
- **iPhone fisik, 5 November:** build 4 pada iPhone 17, runtime iOS 27.0.1; model tersedia dengan konteks 4.096 token. Satu smoke test aktual dengan MapKit selesai dalam **23,04 detik**, menghasilkan tiga rekomendasi. **4/7 tahap lolos validasi**; dua penilaian tempat dan satu ringkasan ditolak lalu memakai fallback. Satu penilaian dan ringkasan merusak ID sumber; satu kandidat diberi kecocokan positif tanpa bukti minat yang memadai. Tidak ada timeout atau error panjang konteks pada run ini. [Laporan iPhone](../../apps/c67-foundation-lab/docs/verification/recommendations-iphone-2026-11-05/REPORT.md) dan [hasil mentah](../../apps/c67-foundation-lab/docs/verification/recommendations-iphone-2026-11-05/run.json).
- **Batas perbandingan:** saran pagi untuk kopi muncul di iPhone, sedangkan seri Mac memberi `any`. Run lintas perangkat tersebut bukan replay input identik yang terkontrol. Hasil Mac tidak digeneralisasi sebagai jaminan mutu iPhone. Belum ada pengulangan reliabilitas, walkthrough UI lengkap, atau perjalanan nyata untuk versi ini di iPhone.

### Batas makna informasi waktu

**Yang dikunci adalah kemampuan memberi saran jendela waktu, bukan mengetahui jam terbaik yang terverifikasi.** Waktu tiba, perpindahan dan jadwal hasil perhitungan engine routing berbeda dari pertanyaan pengalaman seperti “kapan tempat ini paling cocok dikunjungi”. Foundation Model tidak mengambil alih perhitungan routing tersebut.

Data MapKit yang diterima pada pengujian ini menyediakan identitas/kategori/koordinat; fakta waktu kunjung venue yang andal belum tersedia. Jam operasional, keramaian, kondisi pencahayaan, cuaca, harga dan karakter tempat hanya boleh dipakai sebagai fakta bila ada sumbernya. Preferensi foto sore pada fixture adalah ilustrasi, bukan pengukuran golden hour Jakarta. Saran “pagi untuk kopi” adalah ide aktivitas yang masih perlu pemeriksaan jam buka, bukan klaim tempat sudah buka atau lebih sepi.

### Keputusan dan pertanyaan yang tetap terbuka

1. Pertahankan Foundation Models sebagai lapisan bantuan opsional dengan validasi native, sumber/ketidakpastian yang terlihat, dan fallback yang diberi label. Fungsi inti tidak dijadikan bergantung pada model atau backend AI tim.
2. Pertahankan PoC Foundation Lab terpisah dari routing untuk checkpoint ini. Usulan tempat/waktu tidak otomatis diterapkan ke itinerary; kelayakan perjalanan dan integrasinya belum dibuktikan oleh eksperimen ini.
3. Jangan menganggap pilihan budget, hidden gems, transportasi atau toleransi berjalan sebagai filter yang terverifikasi ketika fakta pendukung belum tersedia. Pilihan tersebut baru merekam maksud pengguna.
4. **Hipotesis mengurangi kontribusi pengguna masih terbuka:** belum ada observasi yang membuktikan penurunan input, koreksi, pertanyaan lanjutan atau beban pengambilan keputusan. Counter run dan durasi proses tidak menggantikan pengujian manfaat pengguna.
5. Bila eksplorasi dilanjutkan, bukti yang masih diperlukan adalah mutu penjelasan secara semantik, fakta waktu/tempat yang dapat dipercaya, reliabilitas iPhone dan observasi pengguna. Ini daftar kebutuhan bukti, bukan pekerjaan baru yang otomatis dimulai atau klaim bahwa gerbang produk sudah lulus.

## 0B. Hasil PoC preferensi lokal, embeddings dan MapKit langsung — 5 November 2026

Atas permintaan Giovan, hasil eksperimen berikut dicatat sebagai checkpoint lanjutan. **Gabungan profil lokal, aturan native, MapKit dan embeddings sudah dapat menjalankan rekomendasi tempat dasar tanpa Foundation Model maupun backend AI tim pada skenario yang diuji.** Ini merupakan alternatif untuk sebagian tanggung jawab rekomendasi, dengan mutu yang masih terbatas; belum membuktikan penggantian seluruh kemampuan Foundation Model atau berkurangnya beban pengguna.

### Pertanyaan dan perjalanan eksperimen

Pertanyaannya adalah apakah aplikasi dapat menyusun preferensi dari sedikit sinyal—pilihan minat, arahan singkat atau satu tempat yang disukai—lalu merekomendasikan tempat tanpa bergantung pada model generatif Apple. Eksperimen ditempatkan di **02 · Preferensi** dalam aplikasi Foundation Lab yang sama. **01 · Foundation** dan eksperimen sebelumnya tetap tersedia sebagai jejak perjalanan; routing dan itinerary lama tidak diubah.

- **v0.3 build 5:** profil lokal dan pembanding kategori versus embeddings diuji pada 14 tempat fiktif dengan atribut ilustratif serta snapshot sepuluh identitas/kategori MapKit bertanggal 5 November. Mode ini belum melakukan pencarian baru. [Konfigurasi, hasil dan kegagalan v0.3](../../apps/c67-foundation-lab/docs/verification/PREFERENCE_LAB_REPORT_2026-11-05.md).
- **v0.4 build 6:** alur dilengkapi menjadi profil → query aktivitas → MapKit langsung → validasi/filter native → pemeringkatan → maksimal tiga saran → feedback untuk pencarian berikutnya. Mode sintetis dan snapshot tetap dapat dipilih. [Hasil integrasi v0.4](../../apps/c67-foundation-lab/docs/verification/PREFERENCE_LIVE_REPORT_2026-11-05.md).

Model yang dipakai adalah **`intfloat/multilingual-e5-small`**, berjalan lokal melalui ONNX Runtime 1.24.2 pada CPU, dengan vektor 384 dimensi dan aset sekitar 135,4 MB. Revision, hash, tokenizer dan batas numeriknya dicatat dalam laporan v0.3. Like memperbarui bobot atribut pada profil aplikasi, **bukan melatih ulang bobot model**. Embeddings mengukur kemiripan teks dengan informasi kandidat yang diberikan; tidak menghasilkan fakta tempat baru. Pencarian MapKit tetap memerlukan layanan data, sehingga jalur ini belum merupakan bukti penggunaan sepenuhnya offline.

### Alur yang sudah diimplementasikan

1. Pengguna boleh memberikan minat, arahan pendek Indonesia/Inggris, pilihan yang dihindari atau maksimal enam tempat yang disukai. Profil kosong diberi label penjelajahan umum. Profil, metadata feedback dan riwayat disimpan lokal serta dipisahkan dari eksperimen Foundation dan mode katalog lain.
2. Planner memilih maksimal tiga query aktivitas dari minat eksplisit, kata aktivitas yang dikenali dan atribut tempat yang disukai. E5 dapat mencocokkan teks ke prototipe aktivitas ketika belum ada sinyal aktivitas tersebut. Kosakata dibatasi sembilan jenis aktivitas; tanpa sinyal, aplikasi memakai penjelajahan umum. Query aktivitas yang dibatasi dikirim ke MapKit; profil lengkap tidak dikirim ke API AI hosted.
3. Setiap tindakan pencarian menjalankan **maksimal tiga pemanggilan `MKLocalSearch` secara berurutan**, masing-masing dengan deadline 20 detik tanpa retry otomatis. Mengubah preferensi/like saja belum memicu pencarian; pengguna menekan cari ulang. Pembanding kategori dan embeddings memakai kumpulan kandidat yang sama tanpa pencarian tambahan per tempat. Angka ini adalah pemanggilan API oleh aplikasi, bukan pengukuran request HTTP internal SDK.
4. Hasil digabung, diperiksa terhadap batas operasional Jakarta yang dipakai PoC sebelumnya, dibersihkan dari duplikat dan disaring menurut kecocokan aktivitas umum. Maksimal **20 kandidat** masuk tahap pemeringkatan; identitas yang sudah disukai/ditolak dan atribut yang diketahui dihindari dikeluarkan. Atribut yang belum diketahui tetap tidak terverifikasi.
5. Kategori dan E5 memberi **dua ranking terpisah**, masing-masing menampilkan maksimal tiga hasil, dengan identitas, sumber/tanggal, lokasi dan atribut unknown. Feedback dapat menjadi sinyal pencarian baru meskipun tempat asalnya tidak muncul lagi. Pembatalan dan perubahan input mencegah hasil lama menggantikan hasil terbaru. Kegagalan/hasil kosong MapKit terlihat; model unavailable memakai fallback kategori yang diberi label.

E5 tidak menghitung rute, ETA, jam kunjung, cuaca atau mengubah itinerary. **Skor kategori dan embedding belum digabung menjadi satu ranking**; filter native yang sudah ada berbeda dari usulan penggabungan skor tersebut.

### Bukti yang sudah diperoleh

| Lingkup | Hasil dan batas bukti |
| --- | --- |
| Katalog tersimpan v0.3 | Dua belas kasus pengembangan Mac: sepuluh perbandingan semantik, satu profil kosong dan satu pembanding kategori. Like pada kafe versus galeri mengubah ranking. Dua run inferensi aktual iPhone pada katalog fiktif selesai 0,874 dan 0,733 detik. Data sintetis yang kaya atribut tidak membuktikan mutu rekomendasi tempat Jakarta nyata. |
| Tes otomatis v0.4 | **29/29** tes package preferensi dan **57/57** tes Foundation sebelumnya lulus; build Simulator serta signed iPhone berhasil. Ini bukti implementasi dan regresi dalam lingkup tes, bukan akurasi preferensi pengguna. |
| Interaksi Simulator | **2/2** UI test lulus pada iPhone 18 Pro / iOS 27.2: cari → like → cari ulang dengan pengecualian → relaunch/riwayat → ekspor, serta cancellation dan akses tab lama. Provider memakai replay berlabel dengan inferensi E5 aktual. Run MapKit aktual terpisah pada Simulator selesai sekitar 2,00 detik, 26 baris → 14 kandidat. |
| MapKit aktual Mac | Enam skenario integrasi selesai tanpa error query: empat semantik, satu penjelajahan umum dan satu pembanding kategori. Pencarian baru dari metadata like juga diuji. Masing-masing satu run dengan hasil provider yang dapat berubah; ini bukan benchmark mutu independen. |
| iPhone fisik v0.4 | Satu smoke test pada **iPhone 17, iOS 27.0.1 (24A446)**, selesai **2,06 detik**, status `semantic_completed`, tanpa error query. Dua query kopi/toko buku menerima **26 baris → 14 kandidat → tiga saran teratas**. Bukti ini menguji pipeline aktual, belum walkthrough UI lengkap di perangkat fisik atau perjalanan nyata. [Run tersimpan](../../apps/c67-foundation-lab/docs/verification/preference-live-2026-11-05/iphone/run.json). |

Angka durasi v0.3, v0.4 dan run Foundation 23,04 detik **tidak menjadi perbandingan kecepatan langsung**: data, tugas generatif, pencarian, perangkat dan kondisi layanannya berbeda. Laporan masing-masing mempertahankan kegagalan, provenance, log serta pemeriksaan source lama.

### Temuan, kegagalan dan arti penggantian Foundation Model

| Kebutuhan | Penilaian saat checkpoint |
| --- | --- |
| Membentuk preferensi dari pilihan dan like | Berjalan melalui profil/aturan aplikasi; satu like dapat mengubah ranking. Belum membuktikan bahwa semua atribut tempat yang disukai memang disukai pengguna. |
| Mencari dan memberi saran tempat MapKit | Berjalan tanpa Foundation Model melalui gabungan query planner, MapKit, filter dan E5. E5 sendiri tidak menggantikan seluruh workflow. Identitas/sumber dibawa oleh aplikasi, bukan ditulis ulang model generatif. |
| Memahami bahasa bebas, negasi dan kebutuhan gabungan | Masih parsial. Pada v0.3, arahan “ngopi tetapi tidak ingin tempat ramai” tetap mengangkat tempat dengan atribut ramai. Pilihan avoid eksplisit ditegakkan native atas atribut yang diketahui; negasi teks bebas belum andal. |
| Memberi jam kunjung terbaik | **Belum terjawab.** Embeddings tidak menambah jam buka, pola keramaian atau fakta waktu tempat. Kebutuhan data bersumber pada bagian 0A tetap berlaku. |
| Menjelaskan itinerary secara bebas | Belum digantikan eksperimen ini. Penjelasan sederhana dapat dibuat dengan template; pemahaman/penjelasan generatif tetap merupakan peran opsional yang berbeda. |

Kebutuhan **kopi sambil membaca** memperlihatkan batas penting: tiga hasil teratas run iPhone adalah Toko Buku Ojan, Toko Buku Bintang Cipinang dan Toko Buku. Identitas itu nyata dari provider, tetapi data yang diterima **tidak membuktikan adanya kopi atau kursi membaca**. Kemiripan semantik dan kecocokan kategori belum menjamin seluruh kebutuhan terpenuhi pada satu tempat. Pada katalog fiktif pun perpustakaan dapat mengungguli kafe untuk arahan gabungan.

Belum ditemukan keunggulan konsisten embeddings terhadap pembanding kategori. Pembanding kategori tidak membaca teks bebas; skor nol pada input teks saja tidak boleh ditafsirkan sebagai kemenangan terhadap sistem kategori yang sudah dikonfigurasi lengkap. Skor cosine bukan probabilitas kecocokan pribadi. Kategori/nama yang tipis, pemetaan like ke beberapa atribut, pembatasan query dan filter aktivitas juga dapat melewatkan tempat yang sebenarnya sesuai. Keandalan numerik lintas build masih terbatas pada dua probe yang mendekati referensi, belum identik; konsumsi RAM/baterai dan reliabilitas lintas perangkat belum diprofilkan.

**Pembelajaran utama:** sebagian kebutuhan rekomendasi dapat dipenuhi dengan profil dan pemeringkatan lokal yang lebih terbatas daripada asisten generatif. Namun kemampuan menghitung kemiripan tidak menyelesaikan kekurangan fakta tempat. Belum ada observasi pengguna yang membuktikan lebih sedikit input, koreksi, pertanyaan atau beban keputusan.

### Keputusan checkpoint dan usulan berikutnya

1. Catat profil lokal + aturan native + MapKit + E5 sebagai alternatif yang layak dilanjutkan untuk **rekomendasi tempat dasar**. Foundation Model tetap dapat menjadi bantuan bahasa/penjelasan opsional; hasil ini belum menjadi keputusan menghapusnya atau klaim penggantian penuh.
2. Pertahankan kedua layar eksperimen dan bukti terdahulu. Hasil rekomendasi belum diintegrasikan ke planner routing; metode hybrid adaptif tetap mengikuti kesepakatan sebelumnya.
3. **Usulan yang belum diimplementasikan/diuji:** bandingkan kategori, embeddings dan ranking gabungan keduanya pada profil serta kandidat bersumber yang dibekukan sama. Uji kebutuhan gabungan, avoid eksplisit, koreksi dan atribut unknown, lalu minta penilaian kecocokan serta catat input/koreksi pengguna. Ranking gabungan ini berbeda dari hybrid adaptif routing.
4. Prioritaskan pembuktian mutu dan kelengkapan data pada PoC ini sebelum berpindah ke model baru. Pengujian berikutnya tersebut masih usulan; pencatatan checkpoint ini tidak memulai eksperimen baru.

## 0C. Hasil PoC fakta tempat dan opsi waktu kunjungan — 5 November 2026

Giovan meminta prioritas pertama dikerjakan end-to-end dengan kasus aktual dan layar terpisah. **03 · Waktu** ditambahkan dalam Foundation Lab v0.5 build 7; layar Foundation dan Preferensi serta source package keduanya dipertahankan. Proyek routing tidak diubah.

**Pertanyaan yang diuji:** apakah fakta tempat bersumber dapat menghasilkan opsi waktu kunjungan yang beralasan tanpa mengandalkan pengetahuan venue dari model generatif? Hasilnya mendukung pendekatan tersebut pada katalog terbatas; data dan pengalaman terbaik untuk seluruh tempat belum terjawab.

- **Fakta aktual:** sebelas fasilitas Jakarta, meliputi delapan lokasi layanan perpustakaan, Museum MACAN, Ragunan dan Hutan Kota GBK, dikurasi dari empat halaman resmi yang diambil 5 November. Jam reguler, jeda check-in, batas masuk terakhir, sumber/tanggal dan atribut unknown dipertahankan. Pengumuman MACAN tutup sementara juga diperiksa tampil pada browser; usulan ditahan meskipun tabel jam reguler masih ada. Jam akhir pekan yang tidak tercantum tidak dianggap tutup maupun buka.
- **Perhitungan:** aplikasi memberi pilihan mulai berinterval 15 menit; seluruh durasi harus muat dalam sesi layanan dan rentang pengguna. Jeda check-in membatasi masuk, bukan otomatis mengakhiri kunjungan yang sudah dimulai. Durasi default 60 menit adalah asumsi perencanaan yang dapat diubah. Tanpa konteks tambahan, hasil disebut opsi menurut jam layanan, bukan waktu terbaik.
- **Konteks aktual:** untuk dua venue luar ruang, MapKit mencari pin dan Open-Meteo menyediakan prakiraan per jam serta sunrise/sunset. Pilihan hujan lebih rendah, daylight atau mendekati sunset memakai aturan aplikasi yang terlihat. Ragunan tidak memperoleh opsi mendekati sunset karena tutup reguler pukul 16.00 sementara sunset provider sekitar 17.47 WIB. Sunset tidak membuktikan kualitas golden hour atau pandangan di lokasi. Adapter layar ini memakai Open-Meteo; keberhasilan WeatherKit yang dilaporkan Giovan pada PoC routing tetap mempunyai lingkup tersendiri.
- **Bukti:** 28/28 tes VisitTiming, regresi 57/57 Foundation dan 29/29 preferensi, serta 17/17 skenario publikasi lulus. Empat UI test Simulator lulus, termasuk dua regresi preferensi, riwayat/ekspor dan hasil yang bertahan saat berpindah tab. Empat run layanan aktual Mac selesai; satu smoke test iPhone 17/iOS 27.0.1 menghasilkan tiga opsi dalam 1,407 detik. Ini bukan walkthrough fisik lengkap atau perjalanan nyata. Penamaan field JSON dirapikan setelah run iPhone; build dan run Mac final lulus, sedangkan pemasangan ulang binary cleanup tertahan koneksi CoreDevice. Batas identitas binary dan kegagalan tersimpan pada laporan.
- **Keusangan:** fakta mempunyai kebijakan pemeriksaan tujuh hari dan prakiraan berlaku maksimal 15 menit. Tanggal lama tidak digeser. Sumber yang perlu diperiksa ulang serta prakiraan salah tempat/tanggal, hilang atau kedaluwarsa tidak menjadi fakta baru.

**Pembelajaran:** native code dapat menjelaskan dan menyaring waktu berdasarkan fakta yang tersedia. Kekurangan utama berikutnya berada pada cakupan serta pemeliharaan data: katalog masih dikurasi manual dan dibundel, belum pengambilan fakta web otomatis. Delapan perpustakaan berbagi satu sumber; sampel ini tidak mewakili seluruh tempat Jakarta. Hari libur/perubahan mendadak, kapasitas, keramaian, fasilitas, durasi ideal dan manfaat bagi pengguna belum diverifikasi di lapangan.

**Pengujian ekstrem lanjutan, 5 November — v0.5.1 build 8, policy v2:** atas permintaan Giovan, 31 fungsi tes ditambahkan sehingga VisitTiming menjadi **59/59 lulus**. Tercakup 1.155 kombinasi aturan publikasi, 308 pemeriksaan bahwa pengetatan batas tidak menambah waktu yang valid, serta 200 permintaan simpan bersamaan dengan 20 pembacaan riwayat di antaranya. Ini pengujian terkait pada katalog terbatas, bukan 1.155 perjalanan nyata independen.

Pengujian awal menemukan kegagalan pada tanggal tidak baku/pemeriksaan waktu berlalu, referensi bukti, urutan sesi, prakiraan duplikat atau tidak valid, prioritas ranking hujan, dan integritas riwayat. Perbaikannya disertakan: tanggal serta zona katalog diperketat, konteks tidak valid dibersihkan sebelum hasil keluar, komponen matahari/hujan ditangani terpisah, prioritas hujan tidak dicampur bobot jam, dan ID eksperimen tidak boleh menimpa hasil berbeda. Kerusakan buatan diberi label fault injection; fakta sumber dan fixture prakiraan asli tidak diubah.

Regresi 57 tes Foundation dan 29 tes preferensi serta empat UI test Simulator lulus; satu smoke aktual Mac dengan MapKit/Open-Meteo juga berhasil. Build 8 belum diuji/dipasang pada iPhone fisik, sehingga hasil iPhone build 7 di atas tidak dipakai untuk membuktikan perbaikan ini. [Laporan uji ekstrem, kegagalan awal dan batas bukti](../../apps/c67-foundation-lab/docs/verification/VISIT_TIMING_EXTREME_REPORT_2026-11-05.md).

### Kesimpulan checkpoint prioritas 1

**Prioritas 1 dicatat cukup untuk melanjutkan prioritas 2 dalam lingkup PoC.** Hipotesis yang mendapat dukungan adalah bahwa aplikasi dapat menghasilkan opsi waktu kunjungan yang dapat dijelaskan dari fakta bersumber, durasi asumsi dan konteks yang tersedia, tanpa pengetahuan tempat dari model generatif. Pengujian ekstrem memperkuat ketepatan aturan dan penanganan data; keberhasilannya tidak menjadi klaim kesiapan produksi atau jaminan semua keadaan sudah aman.

Yang masih terbuka adalah pemeliharaan fakta manual, perubahan hari libur/penutupan mendadak, waktu pengalaman terbaik, kebenaran kondisi di lapangan, manfaat bagi pengguna, serta verifikasi build 8 pada iPhone fisik. Tidak ada kebutuhan untuk menyatakan seluruh hal tersebut selesai sebelum memulai evaluasi pemeringkatan pada dataset terbatas yang telah diperiksa.

**Arah prioritas 2:** mulai dengan kandidat tempat nyata yang lebih beragam dan atribut relevan beserta sumbernya. Katalog prioritas 1 didominasi perpustakaan dan jam layanan; datanya belum cukup untuk menilai kebutuhan gabungan seperti “ngopi sambil membaca”. Pisahkan syarat wajib, preferensi lunak dan atribut unknown, lalu bandingkan kategori, embeddings dan ranking gabungan pada input/kandidat yang sama. Ini arah pengujian berikutnya, belum hasil atau implementasi prioritas 2; pencatatan ini tidak memulai pekerjaannya.

Opsi belum diterapkan ke itinerary dan tidak menghitung kelayakan tiba, perpindahan maupun konflik jadwal antartempat. Evaluasi mutu preferensi dan integrasi ke engine yang sudah ada tetap pekerjaan terpisah. [Laporan lengkap dan cara mencoba](../../apps/c67-foundation-lab/docs/verification/VISIT_TIMING_REPORT_2026-11-05.md).

## 0D. Hasil prioritas 2 — kecocokan preferensi berbasis bukti, 5 November 2026

Giovan meminta prioritas kedua dikerjakan setelah checkpoint prioritas pertama. Layar terpisah **04 · Kecocokan** ditambahkan pada Foundation Lab **v0.6 build 9**. Tiga layar lama, source/resource package terdahulu dan proyek routing dipertahankan. Ini pencatatan hasil implementasi dan pengujian, bukan kesepakatan baru bahwa kualitas rekomendasi sudah selesai.

### Alur dan data yang sudah diimplementasikan

Profil lokal → syarat wajib, preferensi lunak dan avoid → penyaringan fakta per area → perbandingan kategori/E5/gabungan → feedback aspek yang disukai atau kandidat yang dilewati → hitung ulang → riwayat dan ekspor. Semua metode memakai kandidat eligible yang sama; bobot gabungan tetap **60% kategori + 40% cosine yang dinormalisasi**, sebagai pilihan eksperimen, bukan probabilitas kepuasan.

Katalog berisi **12 catatan area dari sembilan venue Jakarta**, dikurasi manual dari **11 halaman bersumber** yang diambil 5 November. Baca Di Tebet mempunyai catatan terpisah untuk RBBJ, ruang hening dan kafe; MACAN mempunyai catatan galeri dan kafe. Jumlah area tidak sama dengan jumlah tempat unik. Sumber, tanggal, hash dan atribut unknown disimpan. Data ini merupakan publikasi operator/pemerintah, belum inspeksi lapangan atau jaminan layanan masih tersedia; halaman operator Newsroom yang diperiksa ulang berasal dari 2023.

**Pelajaran kebutuhan gabungan:** izin minum kopi dan membaca harus berlaku pada area yang sama. Dalam katalog ini, hanya RBBJ memenuhi kedua syarat wajib tersebut. Ruang hening mendukung membaca dengan aturan hening tetapi melarang minuman; membaca di area kafe belum diketahui. Karena itu, kebutuhan kopi + membaca + hening tidak dipaksakan memperoleh hasil. “Kopi” berarti boleh diminum di area tersebut, bukan kepastian dijual atau tersedia. Quiet policy bukan pengukuran kebisingan.

Syarat wajib membutuhkan bukti `yes`; avoid membutuhkan bukti `no`. Unknown/konflik perlu verifikasi dan tidak dianggap cocok. Penutupan sementara MACAN mengalahkan informasi reguler, dan program membaca ASHTA yang berakhir 2025 tetap kedaluwarsa. Fakta membutuhkan pemeriksaan ulang setelah tujuh hari menurut kebijakan aplikasi. Ini belum sistem pembaruan informasi otomatis.

Like meminta pengguna memilih satu aspek yang didukung sumber; atribut lain tidak ikut dipelajari. Koreksi avoid mengalahkan sinyal like terdahulu. Arahan bebas memakai pengenal kata positif terbatas dengan konfirmasi; negasi dan koreksi tetap perlu pilihan terstruktur. Tidak ada klaim pemahaman bahasa bebas penuh atau pelatihan ulang model.

### Bukti, kegagalan dan pembanding

- **Evaluasi akhir:** 24/24 kasus buatan berbasis fakta cocok dengan ekspektasi kandidat/review. Sebanyak 17 menjalankan perbandingan E5; sisanya tiga tanpa kecocokan terverifikasi, dua perlu review, satu preferensi belum didukung dan satu daftar umum. Tidak ada ID top-three di luar set eligible yang diharapkan. Ini terutama membuktikan aturan native bersama, bukan kemampuan E5 memahami semua persyaratan atau akurasi universal.
- **Mutu ranking:** pada enam perbandingan preferensi lunak yang selesai, gabungan unggul atas kategori **0**, kalah **0**, seri **6** menurut cakupan atribut bersumber. Urutan berbeda belum membuktikan manfaat. Kasus dan sumber dipakai saat pengembangan; ini bukan holdout buta atau penilaian pengguna independen. Pengulangan berkorelasi, bukan sampel baru.
- **Perbaikan dari kegagalan:** v1 masih memberi alternatif semantik ketika aspek art yang disukai tidak mempunyai kandidat lain yang terbukti; v2 menandainya sebagai `no_supported_preference`. Pencocokan kata diperketat agar “Jakarta” tidak terbaca sebagai “art”. Kontrol perluasan hasil yang gagal pada UI test diganti dengan tombol eksplisit; kegagalan awal tetap disimpan. Gold ID dan bobot ranking tidak diubah untuk mengejar hasil model.
- **Regresi:** 20 fungsi tes baru PreferenceQuality lulus, ditambah VisitTiming **59/59**, TripIntelligence **57/57**, PreferenceLearning **29/29**, serta **7/7 UI test Simulator**. Tercakup pemisahan area, unknown/konflik, kedaluwarsa, fallback model, negasi/review, like satu aspek, koreksi, cancellation, penyimpanan, ekspor dan relaunch. Embedding double hanya bukti engineering; evaluasi model memakai E5 asli.
- **iPhone fisik:** binary final build 9 berhasil dipasang dan menjalankan E5 lokal aktual dalam **0,802 detik**, setelah Giovan membuka kunci perangkat. Profil smoke memakai kopi wajib dan membaca diutamakan, bukan keduanya wajib; hasilnya RBBJ, kafe BDT dan Newsroom, dengan membaca hanya didukung pada RBBJ. Run ini memakai katalog tersimpan tanpa MapKit; bukan walkthrough UI fisik lengkap atau ukuran waktu umum.
- **MapKit aktual Mac:** tiga pencarian identitas pada run pengembangan v1; dua area BDT cocok dengan pin provider yang sama, Newsroom tidak menemukan identitas yang cocok. Hasil hilang bukan bukti venue tutup. Pemeriksaan nama dan batas Jakarta kasar tidak membuktikan cabang, fasilitas ruangan atau kelayakan rute. Uji ini terpisah dari inferensi iPhone final v2.

Sumber dan runner dibekukan dengan hash sebelum seri akhir; source yang dipakai evaluasi disalin bersama manifest. Perubahan entry point, konfigurasi/generated project dan penambahan file baru tidak mengubah package lama. Hasil terdahulu dipertahankan sebagai riwayat pengembangan. [Laporan, langkah mencoba dan seluruh bukti](../../apps/c67-foundation-lab/docs/verification/PREFERENCE_QUALITY_REPORT_2026-11-05.md).

### Arti hasil dan batas kelanjutan

**Prioritas 2 selesai diimplementasikan dan diverifikasi secara teknis dalam lingkup katalog ini.** Aturan fakta per area memberi dasar rekomendasi yang dapat dijelaskan tanpa Foundation Model. E5/gabungan sudah bisa dijalankan, tetapi kelebihannya terhadap kategori belum terbukti; belum ada dasar menjadikannya komponen wajib. Ini juga bukan bukti penggantian seluruh fungsi generatif dari eksperimen lama.

Kekurangan utamanya ialah cakupan serta pemeliharaan fakta, bukan kurangnya model baru. Wi-Fi, izin membaca, paparan rokok, harga, kepadatan dan keadaan aktual sering belum diketahui; similarity tidak menciptakan fakta tersebut. Sembilan venue tidak mewakili Jakarta. Counter input/koreksi/review telah tersedia untuk observasi berikutnya, tetapi belum membuktikan kontribusi pengguna berkurang.

Usulan berikutnya adalah memperluas kasus/venue yang ditinjau independen, mempertahankan pembanding kategori, lalu mengukur kecocokan dan beban input bersama pengguna. Integrasi rekomendasi dengan opsi waktu/engine routing serta pengamatan perjalanan tetap tahap terpisah yang belum dikerjakan pada eksperimen ini. Tidak ada proposal otomatis yang ditulis ke itinerary atau storage planner lama.

## 0E. Pendalaman nilai tambah embeddings sebelum prioritas 3 — 5 November 2026

Giovan meminta manfaat tambahan embeddings diperiksa end-to-end sebelum melanjutkan prioritas 3. **Prioritas 3 belum dimulai.** Eksperimen terpisah **05 · E5 — Nilai tambah E5** ditambahkan pada Foundation Lab **v0.7 build 10**, dengan empat eksperimen lama dipertahankan. Label tab dipendekkan menjadi FM, Minat, Waktu, Cocok dan E5 setelah label panjang teramati bertumpuk; isi layar lama tetap tersedia.

### Pertanyaan dan cara menguji

Hasil enam seri pada bagian 0D tetap berlaku untuk ukuran cakupan atribut terstruktur saat itu. Pendalaman ini menguji apakah E5 membantu membedakan tempat dengan kategori sama ketika pengguna menyampaikan minat lebih spesifik menggunakan kata-kata berbeda dari deskripsi sumber.

Korpus baru berisi **19 catatan area pada 16 venue Jakarta**, dengan deskripsi Inggris yang diparafrasakan manual dari sumber. Tujuh catatan museum menambah variasi tema; penutupan MACAN, program ASHTA kedaluwarsa dan pemisahan ruang BDT dipertahankan. Ada tiga belas URL berbeda termasuk sumber lama. Dua halaman resmi baru dibaca melalui tool web setelah curl gagal; hash keduanya secara eksplisit untuk catatan kurasi, bukan HTML sumber. Kelayakan masuk daftar penemuan tidak membuktikan venue sedang menerima pengunjung.

**24 kasus ranking buatan** membentuk dua belas pasangan intent: kalimat langsung dan parafrasa. Enam kasus lain menguji syarat wajib/avoid, kombinasi pada area sama, unknown, penutupan, program kedaluwarsa dan negasi belum dikonfirmasi. Ini skenario realistis dengan tempat/fakta aktual, bukan rekaman permintaan atau penilaian pengguna. Pembuat eksperimen juga menulis relevansi; bukan holdout buta independen.

Protokol, data, label relevansi, algoritme dan runner di-hash sebelum inferensi aktual baru. Nama venue, nama area, alamat dan ID tidak diberikan dalam teks evaluasi utama. Semua metode memakai kandidat eligible sama: kategori; kategori dengan tie-break BM25; kategori dengan tie-break E5; gabungan 60/40 lama. Tidak ada pelatihan model atau tuning bobot untuk mengejar hasil. Exact tie pada metrik dihitung sebagai nilai harapan agar urutan alfabet tidak memberi keuntungan semu.

### Hasil dan batas bukti

| Pengukuran NDCG@3 | Kategori | Kategori + BM25 | Kategori + E5 | Gabungan 60/40 |
| --- | ---: | ---: | ---: | ---: |
| Semua 24 kasus ranking | 0,4962 | 0,8299 | 0,9770 | 0,9770 |
| Dua belas kalimat langsung | 0,4962 | 0,9840 | 0,9855 | 0,9855 |
| Dua belas parafrasa | 0,4962 | 0,6758 | 0,9686 | 0,9686 |

E5 dibanding BM25 tetap: **tujuh unggul, enam belas seri, satu kalah**. Selisih rata-rata +0,1471; bootstrap deskriptif atas dua belas kelompok intent memberi rentang +0,0475 sampai +0,2591. Tiga proses Mac menghasilkan urutan sama, tetapi pengulangan bukan tambahan sampel independen. Ini **bukan akurasi 97,7%, probabilitas kepuasan atau bukti semua tempat Jakarta dapat direkomendasikan dengan benar**.

Contoh manfaat: arahan tentang cara orang membayar dahulu dan bagaimana uang negara dikelola mengangkat Museum Bank Indonesia tanpa menyebut nama venue atau istilah numismatik. Pada satu kasus sejarah kota, BM25 mempertahankan hasil relevan parsial lebih baik di posisi ketiga. Pada kebutuhan yang sudah tercakup pilihan terstruktur, seperti aturan hening dan izin minum sambil membaca, kategori sudah memadai dan semua metode seri.

Pemeriksaan sensitivitas setelah hasil utama memperbaiki pembentukan query kata kunci tanpa tuning kasus: BM25 menjadi **0,8423**, E5 tetap **0,9770**, dengan tujuh unggul/lima belas seri/dua kalah. Ini diagnosis pada kasus sama, bukan validasi independen. Stemming, kamus sinonim atau taksonomi lebih rinci belum dibandingkan. Perhitungan Python independen mereproduksi skor BM25 serta metrik seri dari Swift.

**Engineering:** 20 fungsi tes baru ditambah 20 tes prioritas 2 lulus; regresi waktu 59/59, Foundation 57/57 dan preferensi 29/29 lulus. Build signed iPhone dan Simulator berhasil. Uji awal UI penuh 8/9 menemukan helper tes lama mengetuk kontrol di belakang floating tab bar; hierarki membuktikan kontrol belum terbuka. Helper diperbaiki untuk menempatkan kontrol di atas bar dan memeriksa hasil ekspansi. Rerun seluruh suite berhasil **9/9 UI test**; log kegagalan dan hasil akhir disimpan pada laporan.

Setelah Giovan membuka kunci perangkat, **30/30 kasus lengkap pada iPhone 17/iOS 27.0.1** memenuhi ekspektasi status/penyaringan dan mereproduksi setiap metrik kasus Mac. Namun dua belas ranking lengkap berbeda, termasuk empat top-three pada dua kasus, menghitung E5 dan gabungan terpisah. Perbedaan berada pada hasil bernilai relevansi sama/nol, sehingga metrik tidak berubah; cosine berbeda maksimal sekitar 0,00373. Ini inferensi katalog tersimpan dengan clock evaluasi dibekukan, tanpa request MapKit, walkthrough manusia atau perjalanan nyata.

### Penilaian dan kelanjutan

**Ada manfaat tambahan terbatas untuk retrieval semantik dari deskripsi yang cukup kaya, terutama parafrasa.** Peran yang didukung ialah bantuan pencocokan minat lunak setelah pemeriksaan fakta. Kategori dan fallback kata kunci tetap berguna. Gabungan 60/40 tidak lebih baik daripada tie-break E5 pada data ini; bobotnya belum terbukti optimal.

Hasil ini tidak menunjukkan embeddings menciptakan fakta, mengetahui keramaian/harga/jam yang hilang, memahami seluruh negasi, mempelajari preferensi pribadi secara otomatis atau mengurangi kontribusi pengguna. Katalog terkurasi, bias penulis kasus, beberapa venue dari sumber sama, kondisi operasional serta pemeliharaan fakta tetap batas penting. Manfaat pengguna memerlukan penilaian relevansi dan observasi input/koreksi secara terpisah.

Secara teknis, bukti cukup untuk **mengusulkan** prioritas 3 dengan native gate, kategori dan E5 opsional. Integrasi preferensi → waktu → routing → cuaca belum dijalankan; perlu dataset venue/area bersama dan pengujian konsistensi sendiri. Metode routing hybrid adaptif serta storage planner lama tidak diubah. [Laporan lengkap, protokol, runner, sumber, kegagalan dan reproduksi](../../apps/c67-foundation-lab/docs/verification/EMBEDDING_BENEFIT_REPORT_2026-11-05.md).

## 0F. Persiapan integrasi prioritas 3 — 5 November 2026

Setelah pendalaman E5 dan riset pendekatan rekomendasi berkomputasi rendah, Giovan meminta **prioritas 3 dikerjakan sebagai aplikasi terpisah**, menggabungkan preferensi → rekomendasi tempat → fakta/waktu kunjungan → routing → cuaca pada jadwal → penjelasan. [Catatan riset](../context/docs/research/low-compute-recommendation-approaches-2026-11-05.md) disimpan sebagai referensi; usulan penggantian encoder dari riset belum diadopsi otomatis.

**Status checkpoint ini: implementasi sumber disiapkan, seluruh build dan testing sengaja belum dijalankan.** Giovan akan mengaktifkan kapabilitas WeatherKit untuk App ID baru terlebih dahulu. Pengujian baru dilanjutkan setelah konfirmasi tersebut diterima. Hasil PoC sebelumnya bukan bukti bahwa integrasi baru ini sudah berhasil.

Aplikasi **C67 Trip Integration v0.1 build 1** berada di [poc/c67-trip-integration](../../apps/c67-trip-integration/README.md), dengan Bundle ID **`giovanchristoffel.c67-trip-integration`**, Team **`DP5XP7C2AM`**, minimum iOS 26. Proyek Xcode disiapkan dari XcodeGen; entitlement WeatherKit tercantum. Foundation Lab v0.7 dan PoC routing lama dipertahankan, termasuk storage masing-masing.

Implementasi menggunakan package preferensi/E5 dan waktu kunjungan yang sudah ada, katalog venue/area bersumber dengan identitas bersama, serta salinan engine routing hybrid adaptif. Adapter integrasi memeriksa semua rentang mulai kunjungan yang valid setelah ETA aktual, sehingga jeda sesi GBK dan aturan masuk Jumat tidak disederhanakan menjadi satu rentang buka–tutup. Tujuan pilihan tetap dipertahankan dengan prioritas setara; lokasi atau fakta yang belum cukup meminta koreksi, tanpa substitusi diam-diam.

WeatherKit diminta lebih dahulu, termasuk hourly, data matahari bila tersedia, metadata dan atribusi. Fallback Open-Meteo bersifat opt-in dan diberi label. Diagnosis WeatherKit berjalan terpisah tanpa fallback. Cuaca yang hilang tetap unknown, dengan grup titik maksimal 3 km dan cache bersyarat 15 menit. Ini desain implementasi yang **belum diuji dalam app baru**, bukan pengulangan klaim keberhasilan Weather Lab.

Alur mencakup peninjauan usulan, penerimaan/penolakan, penyimpanan lokal terpisah dengan backup, ekspor eksperimen/rute/log dan perubahan durasi **+30 menit sebagai revisi draf sebelum trip**. Seluruh draf dihitung ulang dan jadwal yang diterima tetap tersimpan sampai usulan baru diterapkan. Pelacakan trip aktif, keterlambatan yang benar-benar teramati dan validasi manfaat pengguna tetap di luar checkpoint ini. Saran waktu per tempat tetap bersifat advisory; objective routing elapsed-time serta alternatif cuaca terbatas tidak menjadi klaim optimizer global seluruh preferensi waktu.

**Disiapkan, belum dijalankan:** 33 test package, 2 test UI dan 10 skenario live. Kasus jadwal menggunakan aturan publik yang bertanggal; ETA, koordinat dan cuaca replay serta fault injection dilabeli sintetis. Belum ada hasil kompilasi, inferensi, MapKit/WeatherKit live, Simulator maupun iPhone untuk app baru. [Matriks test dan kriteria penerimaan](../../apps/c67-trip-integration/docs/TEST_MATRIX.md) serta [status implementasi/handoff](../../apps/c67-trip-integration/docs/IMPLEMENTATION_STATUS.md) memisahkan persiapan dari bukti yang nanti harus dikumpulkan.

## 0G. Hasil verifikasi integrasi prioritas 3 — 5 November 2026

Setelah Giovan mengonfirmasi kapabilitas WeatherKit aktif, build dan testing yang ditunda pada checkpoint 0F dilanjutkan. Binary akhir **C67 Trip Integration v0.1 build 3** dengan Bundle ID **`giovanchristoffel.c67-trip-integration`** berhasil ditandatangani, dipasang dan dijalankan di **iPhone 17 / iOS 27.0.1**. Aplikasi normal dikembalikan ke layar awal setelah evaluasi; pengujian memakai storage evaluasi terpisah.

**Hasil akhir:** **35/35 test package** dalam empat suite lulus, **2/2 test UI** di Simulator iPhone 18 Pro / iOS 27.2 lulus, dan **7/7 skenario otomatis provider asli di iPhone** lulus. Enam pencarian identitas MapKit dari Mac juga berhasil pada policy akhir. Bukti Simulator menggunakan replay sintetis; bukti inferensi E5, WeatherKit dan ETA asli berasal dari iPhone, bukan dari replay.

Alur tanpa profil menghasilkan tiga venue unik: Cikini **09.15–10.15**, Erasmus Huis **10.45–11.45**, BDT RBBJ **12.30–13.30**, kembali ke titik MapKit Bundaran HI **13.55.21 WIB** pada rencana Jumat **6 November 2026**. Ini rencana berdasarkan ETA/prakiraan yang diambil pada 5 November, bukan perjalanan yang sudah dilakukan. Profil kosong diberi label general, bukan personalisasi yang sudah mengetahui selera pengguna.

Perubahan durasi BDT dari 60 menjadi 90 menit mempertahankan semua tempat, menghitung ulang rute/cuaca, dan mengubah estimasi kembali menjadi **14.29.46**. Selisih **34 menit 25 detik** mencakup tambahan kunjungan 30 menit dan perubahan estimasi perjalanan pada waktu berangkat baru. Proposal kemudian ditolak dan baseline yang sudah diterima tetap tersimpan. Deadline yang sengaja terlalu pendek menghasilkan status `conflicted`; tujuan tidak dihapus agar jadwal terlihat muat.

WeatherKit mengembalikan hourly, metadata, data matahari dan atribusi Apple pada provider flow ini, dengan fallback **dimatikan**. Kasus outdoor GBK–Ragunan lolos pemeriksaan seluruh durasi/sesi layanan dan menghasilkan saran waktu berstatus `context_ranked`. Source ID, set tujuan, jumlah request, raw native report dan ekspor diperiksa silang. Sepuluh file source routing asli tetap identik dengan hash awal; metode hybrid adaptif tidak diganti.

Pengujian live menemukan satu masalah nyata: MapKit menamai cabang Cikini **“Jakarta Provincial Library”**, sehingga filter nama Indonesia semula menolaknya. Ditambahkan alias khusus Cikini dengan alamat cabang tetap wajib, beserta dua regression test yang menerima nama benar dan menolak cabang Nyi Ageng Serang. Kesalahan compiler actor pada adapter, asumsi usia cache dalam test, serta helper scrolling `Form` juga diperbaiki sebelum hasil akhir dinyatakan lulus.

**Pengukuran terbatas:** rangkaian tiga tempat sekitar **29,47 detik**, dengan empat search, 24 ETA dan dua fetch grup cuaca; routing sendiri sekitar **27,82 detik**. Revisi +30 menit sekitar **29,15 detik**, dengan prakiraan valid dipakai dari cache. Pada satu profil berisi 13 kartu/10 eligible, tahap preferensi E5 panggilan pertama sekitar **0,778 detik**, pengulangan dengan cache **1,31 ms**, dan kategori sekitar **0,53 ms**. Angka cache bukan benchmark inferensi baru; belum ada benchmark RAM/energi atau klaim SLA.

**Kesimpulan yang dapat dikunci:** pipeline lokal dan provider Apple dapat menghasilkan draf yang saling konsisten pada kasus ini tanpa backend AI tim. Kesesuaian nyata dengan selera pengguna, cakupan venue Jakarta luas, live 4–6 tujuan, runtime iOS 26, interaksi fisik saat jaringan putus/background, dan manfaat mengurangi input pengguna belum terbukti. Saran waktu tetap advisory, kapasitas/hari libur/antrean tidak dijamin, dan pelacakan trip aktif belum masuk scope.

[Laporan lengkap beserta data, kegagalan awal, perbaikan dan batas bukti](../../apps/c67-trip-integration/docs/VERIFICATION_REPORT_2026-11-05.md). [Matriks uji](../../apps/c67-trip-integration/docs/TEST_MATRIX.md). [Ringkasan mesin](../../apps/c67-trip-integration/artifacts/verification-summary.json).

## 1. Konsep aktif dan cara membaca sumber

Aplikasi membantu pengguna menyusun tujuan pilihannya menjadi perjalanan sesuai waktu tersedia, lalu menyesuaikan urutan serta jadwal ketika perjalanan berubah. **Fungsi inti PoC kini dijalankan engine native tanpa ketergantungan pada backend tim/AI.** Data lokasi, rute, cuaca dan informasi tempat menjadi bahan pertimbangan sesuai ketersediaannya. Pengguna tetap menentukan pilihan destinasi dan pengalaman yang ingin dijalani; personalisasi dan manfaat rekomendasi masih perlu evaluasi.

Pengalaman dasarnya berkesinambungan: punya minat/tujuan → memperoleh rencana → mengunjungi tempat → menyesuaikan perjalanan. Arah 29 Oktober mengusulkan AI sebagai engine rekomendasi; penajaman 3–4 November memastikan penyusunan dan penyesuaian trip tetap dapat berjalan tanpa AI. Jalur Foundation Models kemudian diambil alih Giovan dan diuji pada aplikasi terpisah; checkpoint 5 November di bagian 0A membatasi perannya sebagai asisten rekomendasi dengan mutu yang masih parsial. Bagian 0B mencatat eksperimen lanjutan pada layar terpisah dalam aplikasi yang sama: profil lokal dan embeddings dengan MapKit langsung untuk menjalankan rekomendasi dasar tanpa Foundation Model.

**Cara membaca riwayat:** bagian 2–9 mempertahankan rincian konsep dan keputusan 29 Oktober. Pernyataan tentang AI wajib, backend/browser, framework atau implementasi yang masih dirancang pada bagian tersebut harus dibaca bersama checkpoint terbaru di bagian 0, 0A, 0B, 0C, 0D dan 0E serta hasil bertanggal di awal dokumen.

Klarifikasi eksplisit terbaru pengguna mengungguli dokumen lama. Urutan baca:

1. [Konteks produk dan keputusan 29 Oktober](../context/docs/product/ai-trip-planning-context-2026-10-29.md).
2. [Alur pengguna baru](../context/docs/product/ai-trip-planning-user-flow-2026-10-29.md).
3. [Spesifikasi engine AI — rancangan](../context/docs/technology/11-ai-planning-engine.md) dan [indeks teknologi](../context/docs/technology/README.md).
4. [Rencana validasi baru](../context/docs/product/ai-trip-planning-validation-plan-2026-10-29.md).
5. [Snapshot konteks sebelum pembaruan](../missing-evidence.md#missing-e4ef2b63f729) untuk riwayat dan sumber bertanggal.

Keputusan produk, usulan teknis, implementasi dan bukti pengujian adalah empat status berbeda. Dokumen yang lengkap tidak membuktikan kebutuhan, USP, mutu rekomendasi, akurasi data atau kesiapan produksi.

## 2. Alasan perubahan dan before–after

Pengguna melaporkan masukan mentor bahwa konsep sebelumnya terlalu bergantung pada rekomendasi orang lain. Ini laporan pengguna mengenai diskusi mentor, bukan kutipan atau studi pengguna yang diverifikasi terpisah.

| Aspek | Konsep sebelumnya | Konsep aktif |
|---|---|---|
| Dasar rencana | Rundown pengalaman kreator | Tujuan awal dan preferensi pengguna |
| Rekomendasi | Pilihan rundown yang sudah tersedia | Dihasilkan AI; tempat tambahan ditawarkan jika dibutuhkan |
| Routing | Mengikuti urutan sumber dan menyesuaikan pelaksanaannya | Merekomendasikan urutan dan waktu kunjungan berdasarkan konteks |
| Waktu | Jam kreator sebagai rekomendasi | Tanggal, jam berangkat dan batas selesai ditentukan pengguna |
| Perubahan | Penyesuaian template pernah dibahas | Rekomendasi dapat dihitung ulang selama trip |
| Framework fokus | Eksplorasi WeatherKit, HealthKit, MusicKit; fondasi peta/lokasi | MapKit, Core Location, WeatherKit |

Analogi internal yang digunakan adalah “Codex, but for trip planning—based on your places, preferences, weather, and time.” Ini shorthand diskusi untuk interaksi yang dapat diarahkan berulang, bukan klaim kesetaraan kemampuan atau USP tervalidasi.

## 3. Keputusan pengguna yang sudah jelas

| ID | Keputusan | Implikasi |
|---|---|---|
| P-01 | Rekomendasi trip full dari AI | Pengalaman pribadi kreator dan library rundown tidak menjadi prasyarat rekomendasi. Fakta pendukung tetap memerlukan sumber/data. |
| P-02 | Pengguna sudah mempunyai satu atau beberapa tujuan awal | Alur dapat dimulai dari daftar tempat pengguna sendiri. |
| P-03 | AI dapat memberi rekomendasi tempat tambahan | Pengguna memilih kandidat yang ingin dimasukkan; penambahan tidak otomatis wajib. |
| P-04 | Pengguna menentukan tanggal, jam berangkat dan batas selesai | Aplikasi memberi rekomendasi berdasarkan rentang waktu tersebut. |
| P-05 | Aplikasi memberi urutan terbaik yang disarankan | Menambah, mengganti atau melewati tujuan tetap keputusan pengguna. Definisi skor “terbaik” belum dipilih. |
| P-06 | Rekomendasi dapat dihitung ulang selama trip | Perubahan durasi kunjungan dan kondisi dapat mengubah sisa rencana. |
| P-07 | MapKit, Core Location dan WeatherKit menjadi kombinasi fokus | Kemampuan, moda, traffic dan cakupan wilayah yang benar-benar tersedia harus dibuktikan saat integrasi. |
| P-08 | AI diakses melalui API dari backend | Tidak merencanakan self-hosting model. Provider/model belum ditetapkan. |
| P-09 | Backend mempunyai kemampuan browser untuk mencari informasi tempat | Browser adalah bagian rancangan sistem; runtime, sumber, pembatasan dan cara verifikasi belum dipilih. |

Trip boleh menggunakan transportasi dan mengunjungi tempat populer. Walkable, niche, indie atau non-mainstream merupakan kemungkinan karakter trip, bukan syarat seluruh konten.

## 4. Cerita Johan yang menjadi acuan

Johan berasal dari Jogja dan pindah ke Jakarta untuk kegiatan Academy. Ia suka ngopi sambil membaca. Ini skenario rancangan dari pengguna, bukan persona atau hasil wawancara yang telah tervalidasi. Nama PlaceList pernah digunakan dalam naskah; status nama final belum dikonfirmasi kembali.

1. Johan ingin mengunjungi kafe/toko kopi di Cipete dan memasukkan tujuan awalnya.
2. Ia memberikan preferensi serta tanggal, jam berangkat dan batas selesai.
3. Jika ingin kegiatan tambahan, ia meminta rekomendasi dan memilih kandidat yang diminati.
4. Sistem mengumpulkan konteks perjalanan, cuaca pada waktu/lokasi yang relevan, serta informasi tempat melalui backend/browser.
5. AI memberikan usulan urutan dan waktu kunjungan beserta alasan, sumber yang relevan dan keterbatasan datanya.
6. Johan memilih rencana dan menjalani perjalanan.
7. Ketika Johan ingin lebih lama di D sementara C direkomendasikan pada golden hour, aplikasi menghitung ulang dan menjelaskan dampaknya.
8. Johan menentukan apakah berangkat sekarang, tinggal lebih lama dan menikmati C dengan kondisi berbeda, atau mengubah destinasi/rencana lainnya.

Golden hour dalam contoh adalah kesempatan pengalaman yang direkomendasikan. Terlewatnya kesempatan tersebut tidak otomatis membatalkan kunjungan. Tidak ada tanggal, prakiraan aktual atau jam golden hour Cipete yang ditetapkan melalui cerita ini.

## 5. Makna routing dan rekomendasi terbaik

Routing mencakup urutan destinasi, waktu tiba, durasi kunjungan dan perpindahan. Urutan menentukan waktu tiba; waktu tiba menentukan konteks cuaca dan kesempatan pengalaman; konteks tersebut memengaruhi evaluasi urutan.

Jarak atau waktu perpindahan terpendek hanyalah salah satu pertimbangan. Preferensi, waktu tersedia dan karakter kunjungan ikut diperhitungkan. Formula penilaian, prioritas saat terjadi konflik, durasi kunjungan default, titik akhir/pulang dan aturan moda masih terbuka.

[Tabel A/B/C/D dan skenario pembanding](../context/docs/product/ai-trip-planning-context-2026-10-29.md) adalah data ilustrasi pengguna. Angka tersebut tidak berasal dari MapKit, pengukuran lapangan, atau cuaca nyata.

## 6. Batas rancangan dan implementasi

| Lapisan | Status yang dapat digunakan |
|---|---|
| Arah produk AI | Dikonfirmasi dalam percakapan; didokumentasikan pada pembaruan ini. |
| Engine, browser, provider/model dan kontrak baru | Rancangan; belum ada implementasi atau uji baru pada pekerjaan ini. |
| Wireframe revisi 2 | Artefak HTML untuk konsep sebelumnya; belum didesain ulang untuk input tujuan dan rekomendasi AI. |
| PoC foto/GPS | Eksperimen terdahulu; hasil bertanggal tidak membuktikan engine baru. |
| Repository C67 | Dokumentasi mencatat starter katalog/trip, Auth/sesi, graph, planned edits serta server jurnal/album. Lihat bukti di repository untuk cakupan tiap lapisan. |
| Pembaruan selama perjalanan | Kemampuan target. Kontrak backend lama planned-only dan perlindungan jurnal perlu rancangan kompatibilitas baru. |

Auth, kepemilikan trip, revision dan perlindungan data yang ada tetap bahan implementasi yang berguna. Mengganti konteks tidak mengubah schema, API, deployment atau hasil tes lama.

Foto, album, aturan GPS saat unggah, kontribusi publik, gamifikasi dan penggabungan rundown belum ditetapkan ulang sebagai requirement engine baru. Riwayatnya tersimpan; jangan menganggap semuanya dihapus atau otomatis diwajibkan kembali. HealthKit/MusicKit bukan kombinasi fokus saat ini.

## 7. Investigate dan keputusan terbuka

- Siapa pengguna awal dan seberapa sering ia membutuhkan bantuan mengurutkan tujuan yang sudah dipilih?
- Apa bobot preferensi, waktu tempuh, biaya, cuaca dan kesempatan pengalaman ketika saling bertentangan?
- Bagaimana durasi tiap kunjungan ditentukan dan diubah; apakah ada tujuan dengan urutan/jam yang dikunci pengguna?
- Apa arti batas selesai: akhir kunjungan terakhir atau sudah tiba di titik pulang?
- Bagaimana cara menyampaikan rencana yang tidak muat dalam rentang waktu tanpa menghapus tujuan diam-diam?
- Kapan recalculation dipicu, seberapa sering data diperbarui, dan bagaimana pengguna meninjau/menerapkan usulan baru?
- Provider/model/API, runtime browser, sumber tempat, biaya, latensi, retensi dan fallback apa yang dipilih?
- Data routing, traffic, moda dan cuaca apa yang tersedia pada destinasi nyata, dengan ketentuan penyimpanan/pengiriman yang sesuai?
- Bagaimana mutu sumber, kesalahan fakta, hasil kedaluwarsa dan ketidakpastian diukur?
- Apa cakupan dokumentasi perjalanan dan penyelesaian trip dalam iterasi pertama?

## 8. Posisi CBL dan hipotesis nilai

Aktivitas tetap mencakup pengembangan solusi dan Investigate untuk asumsi yang belum terbukti. Ini pembacaan aktivitas, bukan keputusan fase formal baru seluruh tim.

**Deskripsi kerja:** membantu pengguna menyusun dan memperbarui perjalanan dari tujuan pilihannya berdasarkan preferensi, waktu dan kondisi yang relevan.

**Hipotesis nilai:** rekomendasi berbasis konteks membantu pengguna menjalani rencana yang lebih sesuai dan memahami dampak perubahan. Kualitas kemasan, penggunaan AI atau penggabungan framework belum membuktikan USP, adopsi atau manfaat.

Big Idea, Essential Question, Challenge Statement, Challenge Response dan App Statement formal setelah perubahan ini **belum dikonfirmasi ulang**. Rumusan lama tentang kenangan lintas waktu adalah riwayat; deskripsi kerja di atas tidak otomatis menggantikannya sebagai redaksi formal tim.

## 9. Jejak keputusan dan handoff

- Aviation, pilot-rest dan koordinasi tour leader merupakan arah historis.
- Pada 19–22 Oktober, eksplorasi diary berkembang menjadi rundown kreator, journaling, cuaca, wireframe dan spesifikasi teknis 0.1.
- Pada 26–28 Oktober, pembahasan framing, contoh Hasan dan cerita Johan memperjelas minat pengguna; batas walkable/non-mainstream dilepas dan kombinasi framework dieksplorasi.
- Pada 29 Oktober, pengguna menjelaskan masukan mentor, mengonfirmasi rekomendasi AI sebagai sumber rencana, tanggal/jam/batas selesai dari pengguna, serta recalculation selama trip.
- Pengguna kemudian menegaskan kesinambungan konsep pengalaman dan perubahan utama pada engine rekomendasi. Pembaruan dokumen diotorisasi; kode, schema, model/API live dan deployment tidak diubah oleh pekerjaan ini.

Chat ini menjadi acuan klarifikasi 29 Oktober; [indeks chat](../missing-evidence.md#missing-cf164b146107) menunjuk diskusi terkait. [Snapshot sebelum pembaruan](../missing-evidence.md#missing-e4ef2b63f729) menyimpan rincian cerita A/B, Athar, Gerald serta catatan pengujian terdahulu.

Untuk melanjutkan: baca CBL ini dan dokumen aktif yang ditautkan di bagian 1, cek kode aktual bila hendak mengimplementasikan, lalu tentukan kontrak dan acceptance criteria untuk slice yang diminta pengguna.
