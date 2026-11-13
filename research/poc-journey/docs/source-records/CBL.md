# CBL — Perencanaan trip personal dengan rekomendasi AI · C6

**Updated:** 13 November 2026, Asia/Jakarta (WIB).
**Tim:** C6 — Pisang Besar Balaraja, Apple Developer Academy.
**Current status:** Travelant uses the native Pocket Engine with seven preference themes and 62 labels, Apple-first discovery/routing, independent catalogue evidence and optional constrained Luna advice. Google Places and the old 982-place dataset are excluded from the replacement engine. Build 0.1.0 (1) was uploaded and last observed Waiting for Review; external availability is not confirmed. The latest agreed scope is Jakarta only, but area expansion and the development-time catalogue pipeline remain unimplemented. Read [the current handoff](#current-handoff) and sections 0J–0P before resuming. Sections 0–0I retain dated evidence through 9 November; their earlier active-runtime claims are historical.

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

**Checkpoint alur ringkas dan arah pengembangan, 6 November 2026:** Trip Integration **v0.2 build 4** melewati 220 tes package, 12 tes app-flow, tujuh kasus UI Simulator, dua kasus UI iPhone dengan replay sintetis, dan tiga skenario live iPhone menggunakan E5, MapKit serta WeatherKit tanpa fallback. Laporan v0.2 (original local evidence, omitted from this publication). Diskusi selanjutnya memetakan enam jalur pengembangan yang tidak harus sekuensial. Untuk eksperimen paling ringan, rekomendasi saat ini **E1 benchmark terbatas dan C2 audit ETA**; pilihan belum dikunci pengguna. Roadmap beserta dependensi dan batas (original local evidence, omitted from this publication); ringkasan bagian 0H.

**Checkpoint terbaru, 9 November 2026:** mulai dari [alur Context Lab](../../apps/c67-local-server-lab/ContextHarness/README.md), [momen perjalanan](../../apps/c67-local-server-lab/docs/PERSONAL_SUNSET_MOMENT_2026-11-09.md), dan [peta interaktif v0.5](../../apps/c67-local-server-lab/docs/INTERACTIVE_ROUTE_MAP_2026-11-09.md). Diagram [dari minat ke rute](../../apps/c67-local-server-lab/artifacts/moment-sunset-2026-11-09/c67-flow.html) memperlihatkan urutan proses. Rincian keputusan, kekurangan dan pekerjaan berikutnya ada pada bagian 0I.

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

## 0H. Variabel planner, opsi pengembangan dan dependensi — 6 November 2026

Giovan meminta kesepemahaman mengenai variabel yang benar-benar dipakai planner, mengusulkan cuaca, kemacetan dan jalan kaki untuk didalami, lalu meminta roadmap berbentuk pilihan arah. Pengguna menanyakan jalur paling mudah/cepat dan ketergantungannya, serta meminta pembahasan disimpan sebelum melanjutkan. **Pencatatan ini tidak memulai eksperimen atau mengunci kategori berikutnya.**

### Acuan runtime dan pembagian keputusan

Acuan diskusi adalah **C67 Trip Integration v0.2 build 4**, aplikasi terpisah dari PoC routing awal dan Foundation Lab. Alur ringkas sudah diuji; eksperimen lama tetap tersedia. Bukti terakhir mencakup 220 tes package, 12 tes model aplikasi dengan provider terkontrol, tujuh kasus UI Simulator, dua kasus UI perangkat fisik dengan replay sintetis, dan tiga skenario otomatis provider asli pada iPhone 17/iOS 27.0.1. Ini perhitungan rencana, bukan perjalanan yang sudah dilakukan atau studi pengguna. Hasil, kegagalan awal dan batas verifikasi (original local evidence, omitted from this publication).

| Keputusan | Variabel yang digunakan saat ini | Batas yang perlu dibaca |
| --- | --- | --- |
| Memilih tempat | Katalog lokal; preferensi disukai/wajib/hindari; bukti atribut pada area yang sama; ranking kategori dan E5 bila digunakan; tujuan wajib; jumlah tujuan; tanggal, durasi dan slot layanan; status serta freshness sumber | Memilih tempat mendahului routing. Tanpa preferensi, rekomendasi bersifat umum. MapKit memverifikasi identitas/lokasi, bukan melengkapi seluruh fakta jam/karakter tempat. |
| Menyusun urutan dan jadwal | Koordinat untuk kandidat awal; ETA sesuai waktu tiap ruas; sesi layanan/aturan masuk; durasi, menunggu, deadline, dan total waktu | Semua tujuan pilihan dipertahankan. Saran jendela pengalaman belum menjadi target wajib optimizer. Hasil hybrid terbatas tidak membuktikan optimum global. |
| Menilai cuaca | Prakiraan per jam, rentang kunjungan, serta exposure indoor/outdoor/mixed/unknown | Pengambilan cuaca sudah berhasil. Pada run v0.2 terakhir, alternatif cuaca tidak terpilih karena paparan perjalanan automobile dan sebagian exposure tempat masih unknown. Keberhasilan WeatherKit tidak membuktikan cuaca mengubah urutan. |
| Menentukan moda | Profil Jakarta memakai automobile dengan asumsi on-demand, mulai dan kembali ke Bundaran HI | Belum memilih kombinasi jalan kaki atau melacak posisi kendaraan pribadi. ETA mobil belum menjadi bukti ETA/rute motor. |

Pada satu run live tiga tempat, total sekitar **29,67 detik**, dengan preferensi **0,870 detik**, pencarian **1,653 detik**, cuaca **0,297 detik**, dan routing **26,579 detik**; empat search dan 23 request ETA. Ini observasi satu run, bukan SLA atau bukti distribusi performa. Temuan tersebut menjadi alasan mengukur biaya provider/routing sebelum menganggap penggantian model sebagai solusi percepatan.

### ETA, kemacetan dan waktu yang diminta

Kode mengisi `request.departureDate` lalu memakai `calculateETA()`. Evaluasi kandidat dimulai dari jam berangkat trip dan meneruskan waktu selesai kunjungan sebagai waktu berangkat ruas berikutnya; cache automobile membedakan waktu keberangkatan. Snapshot pencarian awal memakai waktu awal trip, lalu kandidat diperiksa/refinement secara terbatas. [Permintaan ETA](../../apps/c67-trip-integration/Packages/TripIntegration/Sources/TripIntegration/VendorRouting/NativeTripAppleServices.swift), [evaluasi ruas](../../apps/c67-trip-integration/Packages/TripIntegration/Sources/TripIntegration/VendorRouting/NativeTripEngine.swift), [snapshot pencarian](../../apps/c67-trip-integration/Packages/TripIntegration/Sources/TripIntegration/VendorRouting/NativeTripRoutingBridge.swift).

Dalam hasil v0.2, rencana dibuat 6 November untuk keberangkatan 7 November: ruas awal pukul 09.00 WIB, ruas sesudah Cikini 10.15, sesudah BDT 11.45, dan ruas pulang sesudah Erasmus 13.00. Ini mendukung bahwa permintaan memakai **depart at**, bukan seluruh ruas memakai waktu sekarang. Dokumentasi Apple menyatakan ETA memperhitungkan expected traffic. Namun PoC belum mengukur kemacetan sebagai nilai terpisah, belum memvalidasi error terhadap perjalanan aktual Jakarta, dan belum mencari semua pasangan lokasi pada semua kemungkinan waktu. [Apple ETA](https://developer.apple.com/documentation/mapkit/mkdirections/etaresponse/expectedtraveltime), [departureDate](https://developer.apple.com/documentation/mapkit/mkdirections/request/departuredate).

### Jam operasional Google: kemampuan dan pertanyaan izin yang belum selesai

Google Places menyediakan `regularOpeningHours`, `currentOpeningHours` untuk tujuh hari termasuk hari ini, serta `businessStatus`. Jadwal membutuhkan sesi yang mencakup seluruh durasi kunjungan pada tanggal kedatangan; `openNow` saja tidak cukup. Field jam Place Details masuk Enterprise SKU. Data tersebut belum otomatis melengkapi last entry, aturan area, exposure, atau kepastian penerimaan pengunjung. [Referensi data](https://developers.google.com/maps/documentation/places/web-service/reference/rest/v1/places), [field dan SKU](https://developers.google.com/maps/documentation/places/web-service/place-details).

Giovan mengklarifikasi bahwa data jam hanya akan menjadi variabel optimizer, bukan dikirim langsung ke MapKit atau ditampilkan sebagai data jam pada peta. Secara teknis pola tersebut dapat dibangun. **Izin penggunaannya belum terkonfirmasi:** ketentuan standar non-EEA §14.1 mengizinkan Places API tanpa Google Map, sementara §14.2 membatasi penggunaan bersama peta non-Google; ketentuan umum §3.2.3(e) memakai cakupan penggunaan yang lebih luas daripada marker/teks. [Ketentuan khusus](https://cloud.google.com/maps-platform/terms/maps-service-terms), [ketentuan umum](https://cloud.google.com/maps-platform/terms).

Interpretasi diskusi: alur **jam Google → optimizer → itinerary yang ditampilkan dengan MapKit** masih berpotensi masuk penggunaan bersama peta non-Google. Ini interpretasi terhadap bunyi ketentuan, bukan keputusan tertulis Google untuk kasus optimizer tersebut. Belum ditemukan contoh resmi yang secara eksplisit memastikan boleh/tidak untuk skenario persis ini. Tidak menampilkan jam atau memprosesnya di engine sendiri belum membuktikan pengecualian. Places UI Kit mempunyai pengecualian bagi komponennya, bukan bukti otomatis izin mengekstrak data ke planner/storage. Ketentuan akun/region dapat berbeda; akun penagihan tim tidak diperiksa dalam diskusi ini.

Pertanyaan konkret yang disarankan untuk konfirmasi tertulis Google: apakah Places API opening hours boleh dipakai hanya sebagai kendala optimizer itinerary, sementara koordinat, ETA dan peta seluruhnya berasal dari Apple MapKit, tanpa menampilkan jam Google? Belum ada pertanyaan yang dikirim atau jawaban Google yang diterima. Pemeriksaan ketentuan dilakukan dalam diskusi 6 November 2026; periksa kembali sebelum adopsi. Jalur A2 tetap **perlu konfirmasi hak penggunaan**, bukan dianggap otomatis boleh atau diputuskan pasti terlarang untuk seluruh variasi arsitektur.

### Berjalan kaki dan kendaraan

Usulan variabel meliputi waktu pintu ke pintu, waktu akses/parkir/menunggu jemputan, cuaca selama perpindahan, batas berjalan per ruas dan total sehari, kebutuhan mobilitas/barang, serta kualitas jalur bila datanya tersedia. Kondisi trotoar, penyeberangan, tangga, penerangan, keteduhan dan perlindungan hujan tidak dapat disimpulkan hanya dari kedekatan pin atau tersedianya ETA berjalan. [ITDP Pedestrians First](https://pedestriansfirst.itdp.org/neighborhood-tool/step-1). Penelitian pilihan jalur di Singapura mendukung pentingnya paparan matahari, tetapi bobot penelitian tidak langsung menjadi kebijakan Jakarta. [Studi paparan matahari](https://pmc.ncbi.nlm.nih.gov/articles/PMC8844002/).

On-demand + berjalan dan kendaraan pribadi merupakan cabang eksperimen berbeda. Pada kendaraan pribadi, pengguna yang berjalan dari A ke B belum membawa kendaraannya ke B; lokasi kendaraan dan perjalanan mengambilnya kembali harus masuk perhitungan. Pola parkir sekali → mengunjungi beberapa tempat dengan berjalan → kembali mengambil kendaraan masih usulan. Data parkir dan audit kualitas jalur belum dimiliki PoC.

### Roadmap berupa pilihan arah

| Kategori | Opsi | Keputusan yang hendak dibuktikan |
| --- | --- | --- |
| A · Data dan sumber | A1 katalog kecil terpelihara; A2 sumber terstruktur berskala luas | Fakta cukup, mutakhir, tepat area, dan boleh digunakan. |
| B · Pemilihan tempat | B1 kategori/lexical/E5 bersyarat; B2 kombinasi tempat + perjalanan; B3 preferensi dengan input/koreksi singkat | Relevansi dan kelayakan meningkat dengan komputasi serta kontribusi pengguna yang rendah. |
| C · Waktu dan kondisi | C1 pengaruh cuaca; C2 audit ETA menurut waktu; C3 preferensi waktu pengalaman | Konteks benar-benar memengaruhi jadwal tanpa melanggar batas wajib. |
| D · Moda | D1 jalan + on-demand; D2 kendaraan pribadi/parkir sekali; D3 kualitas jalur | Pilihan moda konsisten terhadap seluruh trip dan kebutuhan pengguna. |
| E · Kinerja dan ketahanan | E1 pengukuran baseline dan optimasi terukur | Biaya waktu, request, komputasi dan pemeliharaan dapat dikendalikan dengan kualitas tetap. |
| F · Penggunaan nyata | F1 observasi perencanaan/koreksi; F2 perjalanan dan perubahan sisa trip | Rencana diterima, dapat dijalani, dan mengurangi kontribusi pengguna dalam konteks uji. |

Roadmap lengkap berisi 14 opsi, hipotesis, skenario, dependensi, kriteria adopsi dan batas (original local evidence, omitted from this publication).

### Ketergantungan dan rekomendasi fokus terakhir

Ketergantungan berlaku antarbagian eksperimen, bukan kewajiban menuntaskan kategori A–F secara berurutan. C1 membutuhkan jam/exposure terverifikasi pada sampel A1; C3 membutuhkan jam dan konteks aktivitas; B2 membutuhkan kandidat yang cukup lengkap serta evaluasi kelayakan perjalanan. D1 membutuhkan ETA kedua moda, batas berjalan dan aturan penilaian; D2 membutuhkan state pengguna/kendaraan serta pengambilan kendaraan. Optimasi performa perlu baseline E1 agar perbaikannya dapat dibandingkan.

**E1, C2, F1 dan pembanding B1 dapat dimulai dengan fondasi sekarang.** Untuk uji live, kesegaran dan kesesuaian fakta sampel tetap diperiksa. Ini pekerjaan A1 terbatas, bukan kewajiban menyelesaikan A2 atau keputusan Google. Uji replay memakai snapshot/fixture berlabel dan tidak dipresentasikan sebagai bukti keadaan venue saat ini.

Rekomendasi asisten berdasarkan kriteria paling mudah/cepat: **E1 benchmark terbatas**, dengan pembanding 1/3/6 tujuan, cold/warm, waktu tiap tahap, request/cache dan kualitas/kelengkapan hasil. Belum mencakup seluruh RAM/energi, background atau ketahanan lapangan. **C2 audit ETA** adalah alternatif ringan untuk membuktikan perilaku planner; keduanya disarankan sebagai eksperimen yang saling melengkapi. Pengukuran live enam tujuan memerlukan sampel dengan fakta lengkap, bukan memaksa katalog sekarang atau menghapus batas validasi.

Rekomendasi berdasarkan nilai yang hendak dibuktikan tetap berbeda: **A1 + C1** untuk itinerary adaptif terhadap cuaca; **B3 + F1** untuk kontribusi pengguna yang lebih sedikit. Tidak ada deadline, budget, SLA, bobot kenyamanan atau pilihan implementasi berikutnya yang telah dikunci. Menyimpan pembahasan ini hanya menghasilkan pembaruan dokumentasi lokal; kode, provider, pengujian aplikasi dan publikasi tidak dijalankan.

## 0I. Context Lab aktif, pembelajaran dan kelanjutan — 9 November 2026

### Tujuan dan perubahan fokus

Pertanyaan yang sedang dijawab adalah bagaimana aplikasi membantu orang menemukan tempat yang cocok, memilih urutan serta jam kunjungan, dan menikmati kesempatan pengalaman yang belum ia ketahui. Giovan membedakan **kecepatan** sebagai lama pemrosesan rute atau urutan, termasuk validasi ETA yang diperlukan, dari **akurasi** sebagai kesesuaian hasil terhadap keinginan pengguna. Waktu tempuh trip, waktu menunggu dan waktu komputasi dilaporkan sebagai ukuran berbeda.

Pengguna memilih melanjutkan lab server lokal ini setelah mempertimbangkan keterbatasan komputasi perangkat. Homelab dan penggabungan seluruh PoC ke aplikasi produksi belum menjadi pekerjaan aktif. Paket Foundation Lab dan Trip Integration tetap menjadi dependency lokal untuk implementasi yang digunakan ulang. Pilihan server memberi ruang akuisisi data, evaluasi dan LLM, sedangkan E5 tetap berjalan di perangkat sebagai pembantu kecocokan semantik. Kemampuan replanning aktif dan penyimpanan native terdahulu mempunyai bukti tersendiri yang belum otomatis berpindah ke Context Lab.

### Keputusan produk yang menjadi acuan

| Keputusan | Makna pada PoC aktif |
| --- | --- |
| Pengguna memilih preferensi dengan kontrol terstruktur seperti onboarding dating app | Minat dan ritme disimpan lokal. Area, tanggal, jam berangkat dan batas pulang merupakan konteks perjalanan. Pengguna tidak diwajibkan menulis brief panjang. |
| Minim interaksi yang berulang | Profil dipakai ulang. Pengaturan lanjutan dibuka bila diperlukan. Koreksi pengguna tetap dimungkinkan. |
| Pilihan tempat dapat bertambah | **Cari lainnya** menambah kandidat unik dan mempertahankan tujuan yang sudah dipilih. Maksimal enam tujuan dalam satu rencana berbeda dari maksimal enam kartu per putaran. |
| Pengguna memutuskan tujuan wajib dan opsional | Tujuan wajib tidak boleh dihapus diam-diam. Penghilangan opsional dan pencarian yang terpotong ditampilkan. |
| Cuaca otomatis ketika kegiatan outdoor dikenali | Taman/kebun yang jelas dan jalan pesisir bersumber dapat memperoleh paparan outdoor. Paparan yang belum jelas tetap unknown. |
| Pengalaman berkesan memerlukan saran waktu | Aplikasi perlu menemukan kesempatan yang relevan tanpa pengguna mengetahui jam terbaik sebelumnya. Pilot saat ini adalah kunjungan menjelang matahari terbenam di Pantai Indah Ancol. |
| UI utama ringkas | Tab **Jelajah** dan **Rencana**. Bukti, pengaturan kegiatan dan lab diagnosis berada di bagian yang dapat dibuka saat dibutuhkan. |
| Model utama dan cadangan | `stealth/crouton-alpha`, lalu `nvidia/nemotron-3.5-super-vl:free` dalam anggaran waktu yang sama. Validasi biaya nol dan bukti diterapkan. |
| Pembelajaran preferensi terbatas | Interaksi memperbarui facet di dalam minat eksplisit. Bobot minat utama tidak diubah hanya karena sering membuka kategori tertentu. |
| E5 menggunakan bahasa Inggris | Representasi `en-v1` memakai kategori/kegiatan yang diketahui, dengan checkpoint multilingual E5 yang sama. UI serta identitas tempat tetap memakai bahasa aslinya. |
| Ide kompleks ditahan | Pengelolaan katalog oleh operator, pengetikan konfigurasi panjang dan AnyJev belum menjadi tahap implementasi yang dipilih. Istilah operator pada laporan lama merujuk penyusun skenario uji. |

### Alur aplikasi dan pembagian peran

1. Pengguna memilih minat dan ritme, kemudian area, tanggal, waktu berangkat dan batas kembali.
2. Backend mencari kandidat melalui Google Places dan memeriksa identitas dasar serta irisan jam operasional.
3. E5 pada perangkat memberi skor semantik. OpenRouter menilai seluruh ID kandidat, dengan alasan dan rujukan bukti yang dibatasi oleh data yang diberikan. Server memvalidasi keluaran dan menjaga keragaman minat.
4. Jelajah menampilkan kandidat. Cari lainnya memakai kelanjutan pencarian, mengecualikan ID yang sudah ditampilkan dan mempertahankan pilihan sebelumnya.
5. Pengguna menandai tujuan wajib/opsional dan mengonfirmasi padanan Apple Maps. Lokasi awal juga dikonfirmasi.
6. Saat Susun rencana, backend memvalidasi pilihan, jam buka, durasi penuh, batas menunggu, waktu pulang, cuaca kegiatan outdoor dan ETA Apple pada waktu keberangkatan tiap ruas.
7. Mesin menyusun jadwal biasa. Bila ada bukti momen yang berlaku, mesin mencoba alternatif dengan tempat yang sama dan sisa anggaran ETA yang tersedia.
8. Jadwal biasa yang sudah mencakup momen dapat langsung ditampilkan. Alternatif tanpa tambahan berkendara maupun menunggu dapat dipilih langsung. Jika ada pertukaran waktu yang layak dinilai, LLM memilih di antara dua rencana yang telah divalidasi.
9. Hasil menampilkan urutan, jam, alasan, momen bila tercakup dan tujuan opsional yang belum terjadwal. Garis jalan dimuat sesudah jadwal. Pengguna membuka peta di dalam aplikasi dan menyorot tiap ruas dari nomor peta atau daftar.

LLM peringkat tempat menerima minat/ritme, konteks perjalanan, nama/kategori/deskripsi kategori, status jam ringkas, skor E5, facet affinity, ID bukti dan ringkasan cuaca area jika tersedia. Penilai jadwal menerima dua kandidat yang sudah layak, urutan ID tempat, waktu selesai, total berkendara/menunggu serta ID dan sumber momen. Keluaran penilai berupa pilihan ID rencana dan kode alasan yang dapat diperiksa. Rumusan kartu alasan berasal dari data tervalidasi.

E5 memberi sinyal relatif dan tidak menambah fakta tempat. Mesin itinerary menentukan kelayakan waktu, bukan LLM. Google menyediakan data tempat/jam, sedangkan Apple menyediakan identitas peta, ETA dan geometri. Layanan yang gagal, data kedaluwarsa dan informasi yang belum tersedia mempunyai perilaku eksplisit. Kegagalan ranking LLM menghasilkan error/retry. Kegagalan penilaian alternatif mempertahankan jadwal biasa.

### Pilot momen dan peta yang sudah berjalan

Pilot sunset memadankan satu Google place ID Pantai Indah Ancol dengan sumber Jakarta Tourism. Pengambilan data jam dan prakiraan tetap aktual. Jendela **45 menit sebelum sunset**, minimal **20 menit irisan kunjungan**, peluang hujan maksimal **45%**, tutupan awan maksimal **75%**, dan tambahan jalan+tunggu maksimal **15 menit** adalah kebijakan PoC yang dipilih saat implementasi. Pengguna belum memvalidasi angka tersebut sebagai toleransi pribadi. Bukti sumber mendukung kegiatan pesisir, sementara kualitas cahaya dan pandangan pada waktu kunjungan masih perlu observasi.

Jam manual yang dipilih pengguna didahulukan. Alternatif mempertahankan tempat pada jadwal biasa, durasi penuh dan batas perjalanan serta tidak memperburuk penalti preferensi yang sudah aktif. Rencana biasa memakai anggaran ETA penuh. Cache exact-departure dan sisa anggaran dipakai untuk alternatif. Jika data momen tidak cukup atau alternatif tak ditemukan dalam pencarian terbatas, sistem memakai jadwal biasa.

Penelusuran identitas menemukan hasil Apple berupa tenant Bakso pada Pantai Festival dan Lawson pada Pantai Indah. Keduanya ditolak sebagai padanan pantai. Pantai Indah yang benar berada sekitar **41 m** dari pin referensi, sementara Lawson sekitar **38 m**. Pilot pantai memakai nama/alias yang jelas dan jarak maksimal **100 m**. Aturan umum nama+jarak untuk venue lain masih memerlukan perbaikan.

Peta v0.5 membuka layar **Peta itinerary** di aplikasi. Setiap ruas mempunyai warna, nomor, jam berangkat/tiba dan jarak geometri. Memilih ruas menonjolkan garis serta memusatkan kamera. Seluruh rute mengembalikan gambaran lengkap. Garis sukses dipertahankan ketika ruas lain belum tersedia. Geometri peta merupakan permintaan MapKit terpisah dari ETA server dan tidak mengubah jadwal yang sudah dihitung.

### Bukti yang sudah tersedia dan arti angkanya

| Kampanye | Hasil yang diamati | Batas perbandingan |
| --- | --- | --- |
| Context Simulator 7–8 November | 54 observasi terkontrol, 16 rencana live. Lima tujuan first-feasible grid 15 median client **9,53 detik**, grid 5 **26,39 detik**. | Pemilihan tempat sudah disiapkan sebelum timer. Metode tercepat pada tiga tujuan kehilangan preferensi taman sore. |
| Rekomendasi personal 8 November | Tiga live recommendation median **8,52 detik** sampai daftar tampil. Satu itinerary tiga tujuan **41,35 detik**, 35 ETA call. | Ranking tempat dan komputasi rute mengukur tahap berbeda. |
| Jelajah v0.3, 9 November | Dua putaran menghasilkan **12 kandidat unik**, **15,00** dan **5,98 detik** sampai tampil. Pilihan putaran pertama tetap dirutekan. | Satu skenario pengembangan, bukan distribusi latensi atau kepuasan. |
| Momen v0.4, Simulator | Kunjungan Pantai Indah **17.00–18.00 WIB**, irisan momen **45 menit**, menunggu **25,95 menit**. Susun rencana **3,06 detik**, 3 ETA call. | Satu tujuan, tanggal 10 November, profil uji dan prakiraan saat eksperimen. Tahap judge jadwal dilewati karena rencana biasa sudah memuat momen. |
| Momen v0.4, backend live CLI | Kunjungan **16.25–17.25 WIB**, irisan **22,12 menit**, tambah tunggu **10 menit** dan jalan **1 detik**. Nemotron memilih alternatif. Endpoint plan **15,45 detik**, termasuk **7,61 detik** judge, biaya LLM **$0**. | CLI tidak menjalankan E5 perangkat. Crouton tetap utama tetapi hasil run ini berasal dari fallback. |
| Peta v0.5, Simulator | Satu tes UI live lulus dari onboarding hingga peta. Pilih ruas pergi/pulang dari daftar dan nomor, kembali ke seluruh rute, tutup peta dan tetap di aplikasi. | Satu tujuan dan dua ruas. Lebih banyak tujuan, kegagalan geometri, background/reopen serta iPhone fisik belum diuji untuk UI baru. |

Regresi paket menjelang v0.4 menjalankan **107 kasus**, terdiri atas **106 lulus dan satu benchmark opsional dilewati**. Tes momen memeriksa batas hujan/awan, prakiraan berlubang, jam tutup, batas tunggu, preferensi eksplisit, anggaran ETA, serta ID bukti LLM yang salah. v0.5 menambah verifikasi UI peta setelah build sukses. Angka tes disajikan menurut kampanye dan tidak dijumlahkan sebagai sampel pengguna.

Review kode benchmark sebelumnya memperbaiki cache/budget ETA, pembacaan ETA parsial dan pelabelan pencarian terpotong. Hasil lama tetap merupakan rekaman eksekusi pada versi saat itu. Penilaian assistant sebagai user simulasi menemukan kehilangan syarat kegiatan, kekurangan kandidat, salah padanan tenant dan dampak grid. Run yang gagal dipertahankan sebagai bagian bukti.

Rujukan utama adalah [validasi kode benchmark](../../apps/c67-local-server-lab/docs/BENCHMARK_CODE_VALIDATION_2026-11-07.md), [cuaca/jam dan 3–5 tujuan](../../apps/c67-local-server-lab/docs/DYNAMIC_CONTEXT_SIMULATOR_RESULTS_2026-11-08.md), [rekomendasi personal](../../apps/c67-local-server-lab/docs/PERSONAL_RECOMMENDATION_RESULTS_2026-11-08.md), [user simulasi](../../apps/c67-local-server-lab/docs/SYNTHETIC_USER_RESULTS_2026-11-08.md), [Jelajah v0.3](../../apps/c67-local-server-lab/docs/PERSONAL_SIMPLIFIED_RESULTS_2026-11-09.md), [momen v0.4](../../apps/c67-local-server-lab/docs/PERSONAL_SUNSET_MOMENT_2026-11-09.md), dan [peta v0.5](../../apps/c67-local-server-lab/docs/INTERACTIVE_ROUTE_MAP_2026-11-09.md).

### Blind spot yang berkurang dan yang masih terbuka

| Kelompok dari BLINDSPOT | Yang sudah ditangani sebagian | Yang masih membutuhkan kode, data atau evaluasi |
| --- | --- | --- |
| Maksud pengguna dan syarat kegiatan | Profil terstruktur, wajib/opsional, durasi dan batas tunggu/pulang | Membaca di tempat vs membeli buku, tenang, vegetarian, harga, akses dan prioritas kompromi yang dapat dinyatakan dengan sedikit interaksi |
| Penemuan dan kecocokan tempat | Google discovery dinamis, kelanjutan pencarian, keragaman minat, validasi alasan | Kelengkapan kandidat niche, atribut aktivitas lebih rinci, holdout baru, keuntungan E5/LLM/learning dibanding baseline |
| Identitas dan cakupan aktivitas | Konfirmasi Apple, nama+jarak, penolakan tenant pada dua pantai | Kompleks vs tenant, alias bersumber, pintu masuk, akses nyata dan duplikasi tempat secara umum |
| Jam dan kesempatan pengalaman | Sesi buka serta durasi penuh, satu pilot sunset | Last entry, tiket, antrean, pengecualian tanggal, event lain, sumber yang segar untuk lebih banyak venue |
| Cuaca | Otomatis untuk kegiatan outdoor yang dikenali, hujan sepanjang kunjungan, cloud/sunset pada pilot | Paparan saat menunggu/berpindah, kegiatan campuran dan konteks mikro venue |
| Kualitas pencarian rute | Cache/budget bersama, cutoff eksplisit, optional subset dan pemeriksaan alternatif | Grid 15 menit bisa menciptakan tunggu, kandidat waktu berbasis kejadian, ketahanan terhadap input order dan prioritas antarpenalti |
| Keandalan pengalaman | Error/retry, fallback LLM dan jadwal biasa ketika judge gagal, peta per ruas | Pemulihan pilihan/jadwal setelah app/server berhenti, sesi kedaluwarsa, jaringan lambat/putus, concurrent users, background dan perangkat fisik |
| Akurasi dan manfaat | Audit aturan serta beberapa observasi live yang dapat diperiksa | Kepuasan manusia, berkurangnya usaha menyusun trip, kualitas pengalaman dan ETA/kondisi lapangan |

[BLINDSPOT.md](BLINDSPOT.md) mempertahankan analisis rinci dan benturan antarsolusi. Status bertanggal di dokumen tersebut perlu dibaca bersama checkpoint ini. Cakupan satu pantai tidak menyelesaikan seluruh masalah waktu kunjungan.

### Arah berikutnya dan kriteria keputusan

Urutan berikut adalah rekomendasi setelah implementasi terakhir dan belum menjadi kampanye baru yang dijalankan.

1. **Stabilkan hasil yang sudah bisa dicoba.** Simpan draft/pilihan/jadwal, tangani expiry dan server restart, perjelas alasan tujuan opsional terlewat, lalu uji ulang beberapa tujuan beserta peta/background/retry. Selesai ketika state dan alasan tetap konsisten setelah kegagalan yang dipicu.
2. **Lengkapi maksud dan data yang mengubah keputusan.** Tambahkan pilihan kegiatan atau satu pertanyaan lanjutan hanya ketika jawabannya berpengaruh. Modelkan syarat wajib/preferensi dan bukti didukung/bertentangan/unknown. Cari data operator tentang jam masuk, aktivitas dan karakter venue untuk sampel kecil.
3. **Uji urutan dengan waktu berbasis kejadian.** Bandingkan grid 15, grid 5 dan jam berbasis tiba/buka/kejadian pada tempat, brief, snapshot dan anggaran ETA yang sama. Pertahankan durasi penuh, tujuan wajib dan batas tunggu/pulang.
4. **Ukur nilai tambah setiap komponen.** Bandingkan tanpa/dengan momen dan tanpa/dengan judge jadwal. E5 serta facet learning juga diuji pada kandidat yang sama. Bekukan brief sebelum melihat hasil, acak urutan alternatif dan simpan kegagalan. Ukur discovery, E5, LLM, routing/ETA, geometri dan total client secara terpisah.
5. **Minta penilaian manusia lalu lakukan perjalanan kecil.** Peserta menyatakan keinginan serta batasnya terlebih dahulu. Nilai pilihan, koreksi, alasan menerima/menolak dan usaha yang diperlukan. Bandingkan rencana yang layak pada 3 dan 5 tujuan, kemudian amati waktu tiba, pintu masuk, akses, cuaca dan momen di lapangan.

Memperluas semua venue sekaligus, menambah banyak panggilan LLM, mengganti model lagi, atau menambahkan event tanpa sumber belum mempunyai bukti manfaat. Kebutuhan material berikutnya adalah sumber venue yang bisa diperiksa, brief peserta baru, perangkat fisik/jaringan yang siap serta anggaran request provider yang tercatat. API yang sudah dikonfigurasi berada pada konfigurasi privat Mac.

### Lokasi, pengoperasian dan handoff

Entrypoint adalah `poc/c67-local-server-lab/ContextHarness/C67ContextLab.xcodeproj`, scheme `C67ContextLab`, bundle `giovanchristoffel.c67-context-lab`. Jalankan backend menurut [panduan ContextHarness](../../apps/c67-local-server-lab/ContextHarness/README.md). Konfigurasi model dan kredensial berada di `.env.local` yang diabaikan Git. Helper start membuat token sementara untuk Simulator. Restart normal merotasi token sehingga resource koneksi perlu dibangun ulang. Backend hidup sebagai proses lokal dan dapat berhenti setelah lingkungan sesi berubah. Keberhasilan health check hanya berlaku pada saat diperiksa.

Batas pilot saat ini adalah Jakarta/WIB, satu hari, mobil, maksimal enam tujuan terpilih dan satu momen yang disumberkan. Pencarian menggunakan konteks area dan batas Jakarta, sementara geofence kecamatan belum diterapkan. Hasil E5 tidak otomatis mendukung seluruh karakter venue. Potensi Google Places dalam keputusan itinerary dan kewajiban provider tetap memerlukan penilaian penggunaan yang sesuai sebelum adopsi di luar lab.

Dokumen ini menjadi sumber konteks dan status untuk lanjutan kerja. Source, laporan ringkas dan bukti yang telah ditinjau sudah dipush ke branch `gi/context-lab-checkpoint` melalui [C67 PR #11](https://github.com/pibeebee/C67/pull/11). Folder aktif di GitHub adalah `poc-journey/apps/c67-local-server-lab`, dan CBL publik berada di `poc-journey/docs/source-records/CBL.md`. Verifikasi salinan ekspor menjalankan 106 tes lulus dengan satu benchmark opsional dilewati, XcodeGen, build unsigned Simulator, format Swift, tautan lokal dan checksum publikasi. Merge menunggu review repository. Rekaman lama dan ketidaktersediaan artefak dicatat; kredensial, token, model unduhan, log privat serta binary lokal tidak disertakan dalam commit.

## 0J. Preference evidence and the retired Google/Jev baseline — 10 November 2026

This continuation was documented on **13 November 2026, Asia/Jakarta**, from the inspected chat history, retained reports and current code. Sections 0–0I retain their original dates and experiment boundaries. New explanatory text is English under the repository instructions; the earlier Indonesian source record is preserved.

### What the earlier dataset actually represented

The historical collection grew from 500 to **982 unique Google Place IDs** after 482 additional records. The combined report recorded **545 accepted destinations**, of which **488 had at least one accepted label and 57 had none**. The new batch contributed 262 accepted destinations, including 250 with labels and 12 without. Of the 482 new records, 19 were outside the boundary or not geographically verified; 463 reached the eligibility classifier. Unique provider IDs did not prove unique physical venues. Eligibility, having a label, matching a traveller's preference, and being visitable on a particular date were separate questions.

These figures come from the dated local Jakarta-wide/Jev report inspected for this update. Its raw provider dataset remains excluded from this publication. **This is historical lineage only: none of these 982 records, their Jev labels, or their venue list is an input or acceptance oracle for the replacement engine.**

The user requested fair comparisons with Context Lab, including broader briefs and speed. Comparable inputs and validators mattered, but controlled candidate matching, live discovery, model ranking and itinerary construction had different work boundaries. Fast matching against a prepared catalogue did not establish a faster end-to-end application. Unlabelled cases and failed requests could not be dropped to improve the result.

An earlier 60-place diagnostic varied the evidence supplied to Jev: categories/status, then amenities, then editorial text, then visitor reviews. Status agreement increased from 20/60 to 48/60 across the first and last bundles; accepted reference destinations increased from 2/33 to 29/33, and reference labels surviving both gates from 0/80 to 55/80. The sample was purposive and only selected labels were scored. The lesson was that evidence content affected labels; it was not a measurement of personal recommendation accuracy or a reason to continue Google usage.

### Evidence extraction, judgement and browsing are different capabilities

Preference Lab also compared source rules, hosted extraction and actual local AnyJev. On 12 authored cases with 72 labels, source-guarded LLM and source-guarded LLM plus AnyJev both reached 72/72 policy agreement; the literal rule baseline also reached 72/72. AnyJev did not add a demonstrated benefit on that structured vocabulary. The tested hosted endpoint did not expose the token scores needed by that AnyJev adapter; the local Qwen judge was not the hosted Luna model.

The accompanying 20-entity real-source sample had 7 supported and 113 unknown claims out of 120. Model execution did not fill missing evidence for reading one's own book while drinking coffee in the same area. See [Preference Lab methods and results](../../apps/c67-preference-lab/CATALOG_RESULTS_2026-11-10.md). This remains a separate experiment from the production recommender.

## 0K. Independent discovery, web enrichment and the no-Google decision — 10–11 November 2026

### Open-venue pilot and provider changes

The user explored OSM/Overture plus web evidence as a cheaper replacement for Google Places. A separate pilot first used the requested DavidAU Qwen3.5 9B GGUF model at 4-bit quantization, then Nemotron through OpenRouter, then the user's `ai.giovanc.com` provider. The later hosted configuration requested **`cx/gpt-6-luna(max)`**; the returned model name was **`gpt-6-luna(max)`**. These are requested/reported identities, not verification of the provider's internal upstream.

The same 24 candidates and frozen source excerpts were used in the three extraction runs. Seventeen candidates had source material; seven had none. Nine reference venues reaching inference supplied 63 scored fields:

| Measure | Local Qwen Q4 | OpenRouter Nemotron | Hosted Luna configuration |
| --- | ---: | ---: | ---: |
| Completed extractions | 17/17 | 17/17 | 17/17 |
| Status agreement | 60/63 | 57/63 | 57/63 |
| Supported reference facts recovered | 17/20 | 19/20 | 20/20 |
| Non-unknown claims where reference was unknown | 0 | 5 | 6 |
| Median processing per venue, including retries | 14.70 s | 3.30 s | 36.11 s |
| Attempts / retries | 17 / 0 | 18 / 1 | 34 / 17 |

The hosted run recovered more supported claims but also overreached on branch identity, opening times and historical activity. It was not universally more accurate. Output caps and provider wrappers differed. Hosted cost was not reported, so its cost remained unknown. See the [pilot comparison and limitations](../../apps/c67-open-venue-pilot/README.md).

**The model did not independently browse in this extraction comparison.** The assistant supplied initial official-page links, the collector fetched evidence, and the model read supplied excerpts. A model endpoint without search/browser tools is not a browsing agent. URL discovery, page retrieval, extraction, semantic verification and venue eligibility must be measured independently.

A later 30-candidate expansion reported 23 extractions, seven `no_source` outcomes and 65 proposed supported fields, with 13 issues found in partial review. Proposals remained in a review queue; successful extraction did not make all 30 venues application-ready. The pilot README retains this dated summary; some raw/local campaign attachments were not included in the public export.

### Explicit boundary: stop Google Places

After receiving a bill, the user explicitly stopped further Google Places API use. The subsequent fresh engine effort also excludes the old 982-place dataset and labels. Requests to compare equal-sized catalogues before this decision do not authorize new Google requests or reuse that dataset in the new engine. Preserve earlier reports as history, not as a live dependency.

The user requested Apple-first technology, with OSM/Overture and independent public evidence as complements. A separate **C67 Venue Context Lab** was created rather than replacing Context Lab in place. It experimented with Apple search/ETA, independent candidate identities, Firecrawl or Playwright retrieval, hosted extraction, validation and a 30-day cache.

### Firecrawl and Playwright: executed results and their limits

| Campaign | Observed result | What it did not establish |
| --- | --- | --- |
| Firecrawl connectivity | Authentication and balance reading succeeded before collection | A valid key did not establish useful retrieval |
| Firecrawl three-venue smoke | 10 of 12 reserved credits used; 0/9 facts verified; 0/3 ready to schedule | No full replacement for Places; Apple matching was unconfirmed |
| Playwright three-venue smoke | 1/9 facts verified; no Firecrawl credits | Official URLs also changed, so the collector's isolated effect was unknown |
| Playwright 30-venue run | One verified fact, 68 unknown fields, seven venues without a fact result | Technical failures were not evidence that the venues lacked those attributes |
| Strengthened retrieval replay on that roster | Three accepted facts, 72 unknown fields, five inaccessible venues | Still no venue with the complete hours/access evidence needed by that pilot |

The three accepted items in the strengthened run were regular hours for One Fifteenth Kemang and Periplus Lotte, and a literacy-event hall at Perpustakaan Nyi Ageng Serang. They were heterogeneous fields, not three complete venue profiles. The strengthened run reported 16 Swift tests and three browser tests passing; repeating after restart caused no new retrieval or extraction. These are dated results, not reruns performed while documenting this continuation.

See [Venue Context Lab behaviour, configuration and diagnostics](../../apps/c67-venue-context-lab/README.md). That lab's request-triggered background enrichment remains experimental. It is **not** the agreed trigger for the new development-time catalogue pipeline described in section 0P.

## 0L. Pocket Engine scope, product rules and benchmarks — 11–12 November 2026

### Fresh architecture and the six-part product flow

The user requested a fresh Apple-first design, a separate PoC and initially compilation only, followed by explicit testing. **Pocket Engine** keeps preference matching, bounded scheduling, MapKit ETA, WeatherKit handling and trip storage on device. A small server supplies independent catalogue evidence and constrained hosted advice. This is not an iPhone-only system, and it does not move itinerary ownership to a model.

The intended product remains:

1. Collect traveller preferences.
2. Recommend places matching those preferences.
3. Suggest visit order, timing and routes using operational and travel constraints.
4. Let the traveller adjust the proposal.
5. Recalculate timing/routes while preserving the traveller's requested order.
6. Present and save the final result.

Much of the replacement effort concerns step 2 and the facts required by step 3. Preference input alone is not the unresolved discovery problem. Earlier routing, weather, active-trip and manual-adjustment experiments remain separate evidence until integrated and tested in the actual product path.

### Product decisions to preserve

| Topic | Agreed direction and important boundary |
| --- | --- |
| Preference vocabulary | Keep the seven Hi-Fi themes and 62 existing labels. A refinement such as Japanese cuisine narrows Foodie; it must not become an OR with any restaurant. |
| Required / liked / avoided | Required needs supporting evidence on the correct branch; liked affects ranking; avoided excludes a supported avoided attribute. Unknown, contradicted, expired and conflicting evidence are distinguishable. |
| Minimum recommendations | A recommendation list requires at least three distinct valid places. This is different from named-place search or the number of visits in an accepted shortened itinerary. |
| Multiple interests | Prefer a different place for each representable interest. The earlier implementation plan allowed at least three results with an explicit missing-interest warning; the current production adapter instead suppresses the list when any interest is absent. Reconcile this documented policy difference before changing behaviour. |
| Departure window | An 08.00–19.00 window can mean departure at any time within it, not mandatory departure at 08.00. Keep fixed departure as a separate mode. |
| Dinner as the final visit | Keep the restaurant last. Do not silently define dinner as 17.00–18.00. Propose/confirm a lower time bound, distinguish required from preferred time, and include the return leg before the deadline. |
| Required visit time | A requested 14.00 may be preferred or required according to the traveller's choice. Do not silently turn a preference into a hard appointment or ignore an actual appointment. |
| Place absent from Apple name search | A sourced, verified coordinate can be routed to and given the application's venue name. Apple text-search success is not a prerequisite for a valid independent destination. |
| Too many visits for the window | Offer a shorter validated proposal, preserve mandatory visits/times and return constraints, explain omissions, and ask before applying the reduction. Do not claim maximum/global optimality when search is truncated. |
| Rain / waiting / ETA failure | Try permitted alternatives and bounded transient retries. Never invent ETA or weather; seek consent for extra waiting. A missing required leg or return leg blocks a valid itinerary. |
| Model selection | Prefer accuracy over speed. Use the configured Luna model without a fallback model; failures must be visible. The newer bounded production proxy is not an infinite retry loop. |
| Acceptance target | At least 10 of 12 new evidence-backed briefs should return at least three valid recommendations. Required-condition violations are separately blocking. Repetitions and expected rejections are not extra successful user briefs. |

The [implementation plan](../../apps/c67-pocket-engine-lab/docs/RECOMMENDATION_AND_ITINERARY_IMPLEMENTATION_PLAN.md) records the earlier grill-me decisions and subsequent work. Testing used delegated Terra Medium agents when requested; the main agent retained implementation and evaluation responsibility. An agent's completion report alone was not treated as acceptance evidence.

### Failures that changed the planner

The user's Echigoya brief used 15 November 2026, an 08.00–19.00 window, South Jakarta, food/Japanese cuisine and Echigoya as dinner/final stop. A second brief used 14 November, animal/art/garden, Museum MACAN around 14.00 and five places. The user explicitly rejected assistant-composed answers as a substitute for actual engine output, relaxed departure/visit-time assumptions, and allowed routing to independent coordinates. Initial failures were retained rather than filled with a manually authored itinerary.

The broader synthetic acceptance suite initially passed **11/18** cases. It exposed fixed-only departure, dinner in the wrong position/time, ignored museum timing, early-closing search failure, failure to wait for improving weather, and no transient ETA retry. After the planner revision the same fixture suite reached **18/18**, with an independent invariant checker. See [initial failures](../../apps/c67-pocket-engine-lab/docs/ACCEPTANCE_BENCHMARK_2026-11-11.md) and [revision](../../apps/c67-pocket-engine-lab/docs/PLANNER_REVISION_2026-11-11.md). ETA, weather and venue availability in this comparison were synthetic. The fix did not verify Echigoya or MACAN's actual future availability.

### Measurement boundaries and model comparison

The early [Pocket versus Context engine replay](../../apps/c67-pocket-engine-lab/docs/ENGINE_BENCHMARK_2026-11-11.md) used the same synthetic 10-minute legs and bounded request budget, but different scheduling policies: arrival-based timing versus Context's 15-minute grid/first-feasible search. For three loose-window stops the recorded medians were 0.150 ms and 1.003 ms respectively. These were local computation timings without network calls, not application latency or a fair isolation of identical algorithms. Both engines could exhaust search budgets; one six-stop early-closing case had a Context solution that Pocket initially missed.

The expanded model comparison used the same 12 authored cases, reference, evidence and output validator: Foundation Models returned the expected decision on **3/12**, Luna Max on **12/12**. Both returned readable IDs on 12/12. Median times were **432.61 ms** and **2610.82 ms**. This supported the user's preference for Luna on that task despite latency. It did not establish general factual accuracy, browsing ability, or added value over the deterministic planner's first valid option.

Apple Maps, OSRM and Valhalla were also compared separately. OSRM/Valhalla used the same local OSM extract; Apple was remote and had different traffic/profile information. Three itinerary runs completed in 2764.94 ms, 42.48 ms and 141.74 ms respectively, but this local-versus-remote topology and differing ETA inputs did not identify the most accurate engine. No observed travel-time ground truth was collected. Apple remained the primary product route provider; Valhalla was not adopted solely from this comparison.

The final standalone integration took **35.22 s**, including a 14,835-identity catalogue sync, 16 real Apple ETA requests and about 5.24 s for Luna. Three venues were preselected, hours/access were hypothetical, weather was unavailable, the last stop equalled the origin, and search was truncated. Only five identities in that large seed had any facts and none had structured hours. It was not automatic destination-selection acceptance. The [complete statistics](../../apps/c67-pocket-engine-lab/docs/TEST_STATISTICS_2026-11-12.md) preserve the three preceding integration failures, synthetic controls, model results and release replay build failure.

## 0M. Native UI integration, live places and CI policy — 12–13 November 2026

### UI and application integration

After pulling `origin/dev` at `26cf144`, branch `gi/pocket-ui` connected the existing Hi-Fi/VIPER UI through C67Domain/C67Data to the extracted Foundation-only `packages/PocketEngine`. The production app keeps its iOS 18 minimum; newer Simulator/SDK evidence does not raise that deployment target. The initial integrated path was **preferences → recommendations → visit confirmation → itinerary → local save/history**, with explicit mock and legacy modes retained.

The UI exposes seven themes and 62 refinements. Synthetic integration verified Foodie/Japanese cuisine excluding a Korean-only candidate; a required quiet condition without evidence yielded no recommendations; missing access/hours blocked scheduling until a trip-specific user confirmation was supplied. Such confirmation does not become public verified catalogue evidence. Initial checks passed 47 shared-client/adapter tests, 12 core tests and 29 app/Simulator tests, plus Debug/Release builds, contracts and formatting. Those were synthetic integration checks, not live recommendation acceptance.

The later live test used **iPhone 18 Pro Max Simulator** and actual places without initial destinations or Google data. Recorded corrected candidate counts were:

| Brief | First → corrected | Evidence limit |
| --- | ---: | --- |
| South Jakarta, Nature + Park | 12 → 12 | Three top parks gained published hours/access evidence |
| South Jakarta, Japanese cuisine | 0 → 3 | Sushi Hiro Senopati; Sushiro Gandaria City and PIM 1; hours/access still unconfirmed |
| South Jakarta, Culture + Art | 5 → 5 | Independent catalogue only when Apple search failed; visit readiness unconfirmed |
| Kemayoran, Nature + Park | 11 → 7 | Obvious parking/home false positives removed; remaining Apple-only candidates still required review |

The normal UI displayed Taman Bendera Pusaka, Tebet Eco Park and Taman Literasi Martha Tiahahu for Nature. A separate actual engine run from Blok M on 13 November, 09.00–18.00, driving with flexible departure and return to origin produced:

| Stop | Visit WIB | Incoming Apple ETA |
| --- | --- | ---: |
| Taman Bendera Pusaka | 09:02:59–09:47:59 | 179 s |
| Tebet Eco Park | 10:12:25–10:57:25 | 1466 s |
| Taman Literasi Martha Tiahahu | 11:28:09–12:13:09 | 1844 s |
| Return | About 12:13:30 | 21 s |

One run took 125.85 s with repeated WeatherKit authentication failures; after cooldown handling a replay took **6.82 s** for planning, including 15 successful ETA calls and 3.83 s at the Luna proxy. These are two observations on an amended diagnostic scenario, not a p50/p95 distribution or a held-out success rate. Weather was unknown after HTTP 401. Enabling the later WeatherKit capability/profile did not itself prove runtime weather recovery.

The final bundled catalogue grew to **36 identities**, with only **three venues containing facts and hours**. Do not confuse it with the separate 14,835-identity standalone seed or the full homelab database. The source [live report at the integration revision](https://github.com/pibeebee/C67/blob/ac0a211/docs/tasks/pocket-live-testflight-handoff.md) retains earlier signing/public-HTTPS blockers; section 0N records the later progress instead of rewriting those historical claims.

### GitHub and verification workflow

PR 16 was repaired for SDK compatibility, Search behaviour and UI tests, then approved and squash-merged to `main` as `06f9d9c` after eight passing checks on head `3057876`. PR 17's manual-order/recalculation work encountered iOS 18 drag/accessibility issues and long Simulator runs. The user paused it to reduce CI overhead, then requested active runs be cancelled. Cancelled jobs are not passed jobs.

The agreed replacement workflow uses feature PRs to **`dev`**, local scoped checks first, and automatic compact cloud gates only on same-repository **`dev` → `main`** promotion PRs. Required promotion checks are `integration` and `ios-smoke`; full suites and PoC checks remain manual. Do not keep a promotion PR open throughout frequent dev updates. CI does not automatically deploy the server or upload TestFlight builds.

PR 17 was reconciled with dev and approved after local checks (22 planning tests, 36 Swift tests, policy/contracts/format); it was included in the dev revision pulled before UI integration. Later, the user authorized a `MorpKnight` review-requirement bypass for self-owned PRs. GitHub still disallows formal self-approval: a bypass-enabled merge is not a fabricated APPROVED review. Preserve the other branch protections and check current remote settings before relying on this dated observation. See [policy](https://github.com/pibeebee/C67/blob/c978e7de371c8eb0acc22428e2100a95a3b6d491/docs/tasks/dev-main-ci-policy.md).

## 0N. Homelab, encryption and external TestFlight — 13 November 2026

### Deployed service: last verified observation

The user authorized a dedicated `c67-pocket-beta` homelab deployment and manually configured the Cloudflare Tunnel route. The observed path was **iPhone HTTPS → Cloudflare → cloudflared → `cf-tunnel` → Nginx proxy → Pocket service**. Only the proxy joins the tunnel network; Pocket/SQLite remain on the project network, with no published host ports. Read and write tokens are different and private; Luna initially had a shared 20-attempt daily cap.

At verification, public health returned 200, catalogue returned 401 without a token and 200 with a read token for 36 venues. Public import and TomTom endpoints returned 404. One Luna request for Tebet Eco Park returned 200, reported `gpt-6-luna(max)`, selected 09.00–09.45 from supplied options and took 4.21 s through Cloudflare. An initial file-permission startup failure was corrected. Default Python user-agent traffic was blocked by Cloudflare while curl and an iOS-like test agent worked. Actual TestFlight-client connectivity remained a separate check. This documentation update does not recheck server health or deploy anything.

The maintained service/deployment entry points after restructuring are [Pocket service](https://github.com/pibeebee/C67/tree/c978e7de371c8eb0acc22428e2100a95a3b6d491/server/pocket) and [homelab deployment](https://github.com/pibeebee/C67/tree/c978e7de371c8eb0acc22428e2100a95a3b6d491/server/deploy/pocket). Do not incidentally redeploy or mutate the existing tunnel when continuing catalogue work.

### Release submission is not external availability

The user logged into Xcode and Apple, authorized WeatherKit activation/profile regeneration and supplied review contact information directly. Travelant **0.1.0, build 1**, bundle **`io.pibeebee.c67.starter`**, was signed, exported, validated and uploaded. The first validation found missing iPad orientation declarations; local configuration was corrected for the uploaded IPA. The user deferred those iPad source changes from PR 18, which they merged themselves. A new release must reconcile its source revision/local differences rather than assume the current checkout exactly reproduces build 1.

The user explicitly approved the export-compliance choice for Apple system cryptography and sharing the Pocket read token privately with the Apple reviewer. The beta uses no traveller username/password login. The token is for catalogue sync/Luna, not a prerequisite for bundled-catalogue plus Apple recommendations. Never copy it into this record or public test instructions.

The external group **Travelant External Beta** was prepared for up to **20 compatible iPhone testers**. The last observed build status in this chat was **Waiting for Review**; its invitation was not accepting testers. Automatic distribution was off. After approval, **Start Testing and verify invitation/device availability** remain necessary. This is a historical status, not a fresh App Store Connect check. Upload, passing Apple validation, review submission and external publication are separate milestones. See [release procedure](https://github.com/pibeebee/C67/blob/c978e7de371c8eb0acc22428e2100a95a3b6d491/docs/operations/testflight.md).

### Encryption and access boundaries

- Release requires HTTPS and blocks redirects; Cloudflare Tunnel transport is encrypted, while the internal Docker origin connections use HTTP.
- The read token uses Apple Keychain `AfterFirstUnlockThisDeviceOnly`. Saved trips use iOS `completeFileProtectionUntilFirstUserAuthentication` and atomic writes.
- CryptoKit SHA-256 supplies hashes; it does not encrypt itinerary content. There is no application-level end-to-end encryption: Cloudflare and the service process request contents.
- Homelab disk/backup encryption and restore reliability were not verified. Per-tester access/revocation, shared quota management and backup/restore remain operational work.
- Reassess Apple's encryption declaration if a later build changes cryptography. The previously approved answer is not a permanent declaration for unknown future implementations.

## 0O. Repository layout and reproducibility — 13 November 2026

The user approved a separate layout worktree and README rewrite using `create-readme`, followed by commit, push and pull request. [PR 19](https://github.com/pibeebee/C67/pull/19) contained commit **`c978e7de371c8eb0acc22428e2100a95a3b6d491`** on **`gi/repository-layout`**. GitHub confirms it merged into `dev` as **`dd2e6aa`**.

| Previous checkout path | Restructured path |
| --- | --- |
| `ios-ui/` | `apps/ios/` |
| `ios-backend/` | `packages/C67Backend/` |
| PoC-contained Pocket server | `server/pocket/src/` with tests and deployment recipes |
| `poc-journey/` | `research/poc-journey/` |
| `tripsense-poc/`, `evaluations/` | `research/tripsense-poc/`, `research/evaluations/` |
| `Claude outputs/` | `design/branding/` |
| Flat documentation | `docs/product`, `architecture`, `guides`, `operations`, `testing`, `tasks`, `history` |

Swift module names remain C67Domain, C67Data and PocketEngine. Production Pocket no longer imports its live service code from an experimental snapshot. Moving folders did not redeploy the existing server or change the already uploaded binary. Ignored client configurations need deliberate relocation; preserve the original checkout's unrelated iPad edits.

Executed layout checks passed: 12 core tests, 47 shared-client tests, four Python Pocket HTTP/CLI tests, four promotion-policy tests, 66 research Python tests, 22 planning tests, contracts, formatting, Compose parsing and Docker smoke checks. The recorded iPhone 18 Pro Max layout smoke runtime was **iOS 27.0**, distinct from the earlier iOS 27.2 live campaign. Two selected UI flows passed; two opt-in live cases were skipped. These counts are separate suites, not a recommendation-accuracy percentage.

The restructure preserved hashes for 3415 imported files and 32 existing maintained-source evolutions. Sixty-one missing historical attachments were reproduced before the move and registered as exact exceptions, not replaced with invented evidence. See the [layout task](https://github.com/pibeebee/C67/blob/c978e7de371c8eb0acc22428e2100a95a3b6d491/docs/tasks/repository-layout.md) and [migration guide](https://github.com/pibeebee/C67/blob/c978e7de371c8eb0acc22428e2100a95a3b6d491/docs/guides/repository-layout.md).

## 0P. Priority 1, Jakarta-only expansion and blind-spot review — 13 November 2026

### Latest user direction and the corrected scope

The latest discussion returned to **priority 1: reliable venue data and preference matching**. The intended catalogue stores branch-specific places paired with the existing labels, plus identity, coordinates, access, hours, sources, quotes and verification dates. A place may have several labels; unproven claims remain unknown.

**For the present phase, collection/enrichment is a batch development activity before publication, outside individual traveller recommendation requests.** Runtime recommendations use the prepared catalogue plus the existing Apple session search. Automatic crawling on every recommendation request is not an agreed requirement. The earlier request-shaped priority-1 diagram was clarified by this decision.

The user expanded the intended scope from South Jakarta/Kemayoran to **Jakarta only**, excluding Tangerang, Bekasi, Depok and Bogor destinations. This expansion is approved direction, **not implemented coverage**. At inspection the UI picker, repository guard and bundled area registry still support only the two original areas.

OSM extracts and Overture files can be processed on the server without a per-query monthly vendor quota once downloaded; their public API endpoints and infrastructure still have limits/costs. OSM public Nominatim is not a bulk all-POI discovery service. Overture release dates and OSM snapshot freshness do not prove that each venue was recently checked. Apple Maps Server API/MapKit JS's documented shared 25,000 service calls per day per team must not be applied as a monthly native MapKit allowance; native services can still throttle. See [Apple server API](https://developer.apple.com/documentation/applemapsserverapi), [Nominatim policy](https://operations.osmfoundation.org/policies/nominatim/), [Overpass shared-service guidance](https://dev.overpass-api.de/overpass-doc/en/preface/commons.html), and [Overture Places](https://docs.overturemaps.org/guides/places/).

The user manually found no useful Japanese-restaurant information in their OSM/Overture Blok M search. That observation is a coverage warning, not proof that neither dataset contains any such venues. Audit extraction/schema, names, taxonomy and geographic filters, but **do not keep OSM/Overture membership as a mandatory discovery gate**. Web sources, official branch locators, operator/menu pages and relevant official directories need their own candidate-discovery path. OSM/Overture are complements, not completeness guarantees. Coordinates must be sourced or reviewed; never guessed by a model.

Jakarta's administrative scope includes five cities and Kepulauan Seribu. Catalogue inclusion and supported transport are distinct: current walking/driving cannot establish an inter-island itinerary. Mark unsupported travel explicitly rather than silently removing the islands from the meaning of Jakarta. Destination boundaries, an origin/return point outside Jakarta and a road route crossing a boundary are also separate policies to resolve. See [Jakarta's official overview](https://www.jakarta.go.id/tentang-jakarta).

### Consolidated blind spots: findings are not completed fixes

| Finding at inspection | Consequence | Proposed work within priority 1 / Jakarta expansion |
| --- | --- | --- |
| Importer accepts only `osm-`/`overture-` IDs | Web-discovered independent places cannot enter without those source IDs | Internal branch ID with optional external IDs and reviewed identity/coordinate provenance |
| Known-URL retrieval is not candidate discovery | A successful crawler can still miss entire venue clusters | Separate and measure candidate/URL discovery, page reading, extraction and acceptance |
| 62 selectable labels, limited underlying evidence/category mapping | UI completeness can conceal empty label/region coverage | Track region × label coverage and supported/unknown/contradicted claims; audit source-to-taxonomy mapping |
| `reviewed: true`, HTTPS host and branch quote are structural guards | The current importer does not prove the quote occurs in the fetched document or entails the claim | Retain source excerpts/hash; validate quote occurrence, semantic support, branch and date; review uncertain claims |
| Name/alias plus distance ≤125 m drives merging | Nearby branches/tenants may merge; aliases may leave duplicates | Use branch address/unit/source IDs; quarantine ambiguity; preserve and resolve conflicting hours |
| Base categories have no freshness gate comparable to facts/hours | Old categories can continue producing matches after evidence expires | Version/category provenance and separate snapshot/fetch/verification/expiry times |
| Fresh entries are skipped until expiry | Known mistakes or verified closure corrections can be held for the cache lifetime | Propose an auditable correction/invalidation path distinct from routine refetch; this policy refinement is not yet approved |
| Matching a category is not visit readiness | Recommendations can fail later on access, booking, sessions or hours | Separate recommendation eligibility from itinerary readiness; consider last entry, split hours and date exceptions |
| One area-wide Apple rectangle, at most eight interest queries, no distance term in current relevance ranking | Wider boundaries can concentrate results or scatter them too far apart | Search bounded geographic clusters, deduplicate, then assess origin/time feasibility; expose truncation rather than infer absence |
| Maximum matching is attempted but the adapter's final coverage check uses the union of interests | Overlapping interests need explicit distinct-representative acceptance; partial-interest policy also differs from the earlier plan | Add a focused regression and enforce the agreed assignment/missing-interest behaviour; static concern, not a reproduced new runtime failure |
| Full catalogue fetch, client limits 20,000 venues / 30 MB | Expansion increases transfer and memory; the size check happens after downloading | Versioned/conditional sync and local cache, then region partitions or deltas if measurements justify them |
| Historical source rules, licences and web permissions vary | A renamed internal record does not remove source obligations | Retain per-source provenance/licensing; assess permitted retention/redistribution and keep Apple session material separate |
| Page count, supported proposals and candidate availability are weak success metrics alone | High collection volume can hide wrong pins, unsupported labels and unusable recommendations | Measure accepted correct venues, branch/pin errors, required-condition violations, recommendation readiness and cost per accepted usable venue |
| Current beta shares access and provider quota | A public invite is not per-tester authorization or operational reliability | Plan revocable tester access, usage caps and verified backup/restore as a separate operational slice |

The licensing distinction is explicit in [Overture's attribution page](https://docs.overturemaps.org/attribution/) and [Places guide](https://docs.overturemaps.org/guides/places/): Places and OSM-derived themes do not all share the same licence. Review the actual combination; do not assume an internal database cancels original obligations.

The audit read maintained `Domain.swift`, `Discovery.swift`, `Themes.swift`, `PocketPlanningRepository.swift`, `PocketAppleServices.swift`, `PocketServices.swift`, `server/pocket/src/server.py`, the area picker and resources at layout revision c978e7d. It ran no new live benchmark or mass ingestion. The 36/3/3 catalogue count is a checkout resource count, not a current homelab inventory. A model choosing a valid schedule ID is not proof of preference relevance or knowledge about the place.

### Proposed implementation order; not started by the final discussion

1. **Catalogue foundation:** internal branch identity, optional provider references, per-field provenance, review/publication status, freshness and an explicit correction policy. Keep immutable source/run manifests and resumable progress.
2. **Jakarta boundary integration:** sourced Polygon/MultiPolygon boundaries consistently across ingestion, core validation and UI. Test border cases and distinguish unsupported island transport. Settle origins/return/cross-boundary route semantics explicitly.
3. **Development-time batch pipeline:** multi-source candidate discovery → retrieve official/appropriate sources → Luna extraction → identity/quote/schema/semantic validation → review queue → publish a versioned catalogue. Preserve the no-Google/no-982 boundary.
4. **Representative pilot:** include Blok M Japanese dining and other neighbourhoods/interests across the five mainland cities. Do not equate Blok M success with Jakarta coverage. Maintain accepted / needs review / rejected outcomes with reasons; missing source is not a negative attribute.
5. **Matching and shortlist quality:** validate distinct-interest representation, resolve the partial-interest policy, preserve required conditions, distinguish data readiness, and consider geographic/time feasibility without changing the whole planner or replacing providers prematurely.
6. **Independent acceptance:** freeze 12 new briefs and reviewer references before tuning; keep those references out of model inputs. Retain the 10/12 target but report results by region/interest, retrieval versus ranking, readiness, conflicts, provider failure, latency and cost. Expected rejection/unsupported controls are separate from successful real recommendations.

Use persisted cache and per-source rate/concurrency/page/token/credit budgets. Retry technical failures with bounded backoff and checkpoints; do not cache a network failure as a factual 30-day unknown or retry endlessly. Reuse unchanged source material instead of repeated model extraction. Record the actual Firecrawl balance/pricing and provider usage before a future authorized live batch; no remaining balance, account-limit percentage or reset time is assumed from an earlier run.

### Handoff for the next chat

<a id="current-handoff"></a>

**Current objective:** prepare a trustworthy, independently sourced Jakarta catalogue for the existing 62-label Pocket recommender, through offline development batches, while keeping Apple-first runtime search/routing. **Do not start a batch, change architecture, deploy, commit or push merely because this document contains a plan.** The last authorized action in this chat was documentation.

- Read this section first, then 0L–0O and the linked reports. Sections 0–0I and 2–9 are dated history. Do not resume Google Places, import the 982-place dataset, or reactivate E5/AnyJev/Context Lab as a production requirement.
- Start from the current `dev` and check the checkout before editing. The repository now uses `research/poc-journey/`, `apps/ios/` and `packages/C67Backend/`. Older checkouts may still use `poc-journey/`, `ios-ui/` and `ios-backend/`. Preserve local iPad edits and private configuration.
- The seven themes/62 labels and native UI are already connected. The latest approved geographic direction is Jakarta only; implementation still accepts only South Jakarta/Kemayoran. The web batch pipeline and blind-spot fixes above are proposed and unimplemented.
- The live park example proves bounded technical plumbing. No independent 10/12 recommendation gate, physical TestFlight journey, observed ETA accuracy or full weather recovery is claimed. Do not sum synthetic tests, reruns and live briefs into one accuracy percentage.
- Last observed external TestFlight status was Waiting for Review. Verify current Apple state before taking any distribution action. Public service health likewise needs a fresh read-only check if operational work resumes.
- Confirm the multi-interest/partial-result policy and the exceptional correction policy before dependent behavioural changes. Keep routine 30-day reuse, source expiry, date-specific availability and technical backoff distinct.
- Continue with a bounded implementation brief for the catalogue foundation and Jakarta expansion, then tests proportional to that change. User-side preference input is not a reason to rewrite the UI or replace the scheduling engine again.

Documentation provenance: the 9 November Context Lab checkpoint; inspected 10–12 November pilot/benchmark reports; the preceding Pocket Engine and venue-enrichment chats; and this chat's PR, UI, homelab, TestFlight, catalogue and Jakarta/blind-spot discussions through 13 November. Missing raw/local attachments stay explicitly missing. This update records those observations and decisions; it does not repeat their experiments.


## 1. Current concept and source precedence — updated 13 November 2026

The app helps travellers choose places, review a feasible order/timing proposal, adjust it and save the trip. The current native product uses Pocket Engine through C67Domain/C67Data with MapKit, WeatherKit and optional catalogue/Luna services. Read sections 0J–0P and the [current handoff](#current-handoff) for the latest decisions, implementation, observed results and unresolved policies. Context Lab, Foundation Lab, E5 and earlier routing experiments retain their own dated evidence and are not automatically active production dependencies.

Sections 2–9 below preserve the 29 October concept and open questions. Later explicit user decisions take precedence. In particular, do not resume Google Places, assume browsing exists merely because an LLM is configured, or treat a TestFlight submission as external publication. The latest catalogue work is proposed offline development-time collection for Jakarta; it has not been executed by this documentation task.

Klarifikasi eksplisit terbaru pengguna mengungguli dokumen lama. Urutan baca:

1. [Konteks produk dan keputusan 29 Oktober](../context/docs/product/ai-trip-planning-context-2026-10-29.md).
2. [Alur pengguna baru](../context/docs/product/ai-trip-planning-user-flow-2026-10-29.md).
3. [Spesifikasi engine AI — rancangan](../context/docs/technology/11-ai-planning-engine.md) dan [indeks teknologi](../context/docs/technology/README.md).
4. [Rencana validasi baru](../context/docs/product/ai-trip-planning-validation-plan-2026-10-29.md).
5. Snapshot konteks sebelum pembaruan (original local evidence, omitted from this publication) untuk riwayat dan sumber bertanggal.
6. Pilihan pengembangan PoC, dependensi dan rekomendasi fokus 6 November (original local evidence, omitted from this publication) untuk melanjutkan diskusi teknis tanpa menganggap seluruh kategori sebagai tahapan wajib.

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

Chat ini menjadi acuan klarifikasi 29 Oktober; indeks chat (original local evidence, omitted from this publication) menunjuk diskusi terkait. Snapshot sebelum pembaruan (original local evidence, omitted from this publication) menyimpan rincian cerita A/B, Athar, Gerald serta catatan pengujian terdahulu.

Untuk melanjutkan: baca CBL ini dan dokumen aktif yang ditautkan di bagian 1, cek kode aktual bila hendak mengimplementasikan, lalu tentukan kontrak dan acceptance criteria untuk slice yang diminta pengguna.
