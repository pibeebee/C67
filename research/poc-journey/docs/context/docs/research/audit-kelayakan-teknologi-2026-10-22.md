# Audit kelayakan teknologi C6 — aplikasi iOS dan server

**Status konteks — 29 Oktober 2026:** Audit ini menilai spesifikasi 0.1 dengan kreator dan scheduler urutan tetap. Penilaian layak serta alasan tidak memerlukan LLM hanya berlaku pada scope tersebut. Engine AI/browser, capability data dan active replanning memerlukan evaluasi baru; audit tidak dijalankan ulang melalui pembaruan dokumen. Lihat [acuan aktif](../technology/11-ai-planning-engine.md).

**Tanggal:** 22 Oktober 2026, Asia/Jakarta. **Objek:** [spesifikasi teknologi 0.1](../technology/README.md), satu indeks dan 10 bab. **Metode:** review arsitektur, penelusuran kontrak/state/data, pemeriksaan terbatas sumber native, dan verifikasi kemampuan platform ke sumber resmi. **Status:** audit rancangan; bukan pengujian integrasi atau sertifikasi produksi.

## 1. Penilaian utama

**Aplikasi ini memungkinkan secara teknologi. Stack yang diusulkan sesuai untuk membangun MVP dan dapat dikembangkan lebih lanjut. Namun spesifikasi 0.1 belum siap diterjemahkan seluruhnya menjadi sistem produksi tanpa revisi kontrak, keputusan produk, dan technical spike.**

Tidak ditemukan kebutuhan dasar yang memerlukan penemuan teknologi baru: konten kreator berversi, salinan trip, penjadwalan urutan tetap, jurnal foto privat, album, pencarian geografis, cache lokal, dan konteks cuaca mempunyai pendekatan implementasi yang tersedia. Ini penilaian engineering atas rancangan, bukan hasil implementasi C6.

Risiko terbesar terletak pada **semantik dan reliabilitas foto/GPS, kelengkapan model perpindahan, distribusi konten kreator, serta banyaknya kemampuan yang hendak dikerjakan bersamaan**. Mengganti database tidak menyelesaikan risiko tersebut.

| Dimensi | Penilaian | Dasar / batas |
|---|---|---|
| Kelayakan teknis fungsi inti | Layak | Relasi, transaksi, penyimpanan media, API dan adapter native cocok dengan kebutuhan. Belum ada bukti integrasi C6. |
| Pemilihan stack | Masuk akal | Supabase/PostgreSQL/PostGIS + SwiftData mempunyai pembagian tugas yang jelas. Pemilihan final tetap keputusan tim. |
| Konsistensi spesifikasi | Perlu revisi | Ditemukan celah landing → stop pertama, cakupan moderasi kreator, dan beberapa transisi/kontrak belum lengkap. |
| Kesiapan memulai implementasi terbatas | Layak setelah scope dipilih | Fondasi dan slice copy-trip dapat dimulai tanpa menunggu semua kemampuan lanjutan. |
| Kesiapan pilot foto/GPS | Belum terbukti | Timing presence, parameter lokasi, ingress, worker dan recovery belum diuji bersama pada iPhone fisik. |
| Kesiapan distribusi luas | Belum | Auth/deletion, sumber konten, moderasi, kapasitas, biaya dan recovery belum mempunyai bukti pelaksanaan. |
| Kelayakan jadwal/anggaran tim | Belum dapat dinilai | Belum diketahui deadline, jam kerja, kemampuan backend anggota, volume pengguna dan anggaran layanan. Tidak diberikan estimasi minggu atau biaya seolah terukur. |

Istilah **layak** di sini berarti terdapat jalur implementasi yang masuk akal. Istilah itu tidak berarti semua requirement dapat dipenuhi sekaligus atau bahwa sistem sudah berjalan.

## 2. Cakupan dan bukti

Ditinjau: seluruh 11 berkas spesifikasi awal; konteks aktif pada [CBL.md](../../../source-records/CBL.md); model/kontrak database, API, media, sinkronisasi dan operasi; dokumentasi resmi Apple, Supabase dan PostgreSQL yang relevan.

Pemeriksaan native terbatas kembali menemukan target iOS 18 dan build setting `SWIFT_VERSION = 5.0` pada `project.pbxproj`; `DiaryModels.swift` mengarahkan penyimpanan ke `memories-v1.json`. Ini memverifikasi lapisan persistensi yang diperiksa masih lokal; bukan audit seluruh kode atau bukti tidak adanya layanan lain di seluruh mesin.

Tidak dijalankan dalam audit ini: migrasi SQL, aplikasi Supabase lokal, request WeatherKit/MapKit destinasi, build/test iOS, GPS lapangan, login/revocation Apple, worker media, load test, restore drill, provisioning atau deployment. Tidak ada akun/cloud atau kode aplikasi yang diubah. Penelusuran skenario di bawah adalah counterexample terhadap spesifikasi, bukan hasil tes runtime.

## 3. Kemampuan yang realistis dibangun

| Kemampuan | Kelayakan | Syarat / batas praktis |
|---|---|---|
| Akun kreator/traveller | Layak | Sign in with Apple native didukung Supabase; deletion/revocation tetap perlu diintegrasikan. [Apple login](https://supabase.com/docs/guides/auth/social-login/auth-apple). |
| Rundown berversi → trip independen | Layak | Snapshot, FK dan transaksi tepat untuk kebutuhan ini; immutable version dan hak distribusi harus dipisahkan. |
| Pengaturan tanggal, jam dan durasi | Layak | Scheduler urutan tetap cukup sebagai awal; zona waktu dan unknown duration harus eksplisit. |
| Merge manual A+B | Layak dengan kompleksitas menengah | Seleksi, overlap dan atribusi dapat dimodelkan; keputusan field/urutan tidak boleh diserahkan kepada deduplikasi nama. |
| Jurnal foto dan album privat | Layak | Gunakan metadata database + private Storage + validasi media server; album dapat berupa query/proyeksi. |
| Pemeriksaan dekat pin | Layak sebagai evaluasi lokasi yang dilaporkan | Core Location memberi estimasi dan ketidakpastian; bukan sertifikat kehadiran fisik. [Horizontal accuracy](https://developer.apple.com/documentation/corelocation/cllocation/horizontalaccuracy). |
| Cache trip dan draft offline | Layak | Persistensi lokal dan sinkronisasi tetap dua pekerjaan berbeda; draft belum accepted server. |
| Cuaca per lokasi/waktu | Layak dengan availability bersyarat | WeatherKit menyediakan Swift/REST; fitur regional dan horizon perlu diuji. Cuaca tidak menyuplai data routing/indoor. [WeatherKit](https://developer.apple.com/weatherkit/). |
| Estimasi/handoff navigasi | Layak sesuai kemampuan layanan | Transit pada MKDirections hanya didukung untuk estimasi kedatangan, bukan itinerary transit rinci. [Transit](https://developer.apple.com/documentation/mapkit/mkdirectionstransporttype/transit). |
| Penyesuaian rencana otomatis lengkap | Belum layak dijanjikan dari data saat ini | Memerlukan alternatif, jam buka/akses, moda, durasi dan aturan tujuan; bukan konsekuensi otomatis dari mengaktifkan WeatherKit. |

## 4. Temuan audit

Prioritas **tinggi** berarti memengaruhi alur inti atau harus selesai sebelum fitur terkait dibuka. Prioritas **menengah** berarti perlu diperjelas sebelum implementasi bagiannya. Ini prioritas perbaikan rancangan, bukan pernyataan ditemukannya eksploitasi pada aplikasi yang berjalan.

| ID | Prioritas | Jenis temuan | Ringkasan |
|---|---|---|---|
| F-01 | Tinggi | Risiko yang sudah terbuka, dipertegas audit | Presence saat transfer dan finalisasi membuat penerimaan foto bergantung pada waktu antrean worker. |
| F-02 | Tinggi | Celah model yang ditemukan | Landing yang berbeda dari stop pertama belum mempunyai segmen perpindahan eksplisit. |
| F-03 | Tinggi sebelum library UGC dibuka | Celah cakupan yang ditemukan | Moderasi perlu mencakup rundown/media kreator, bukan hanya kontribusi foto traveller. |
| F-04 | Tinggi untuk media | Batas platform dan dependency operasional | sharp/libvips tidak didukung di hosted Edge Functions; worker container yang sudah diusulkan tetap harus benar-benar tersedia. |
| F-05 | Menengah | Ambiguitas state yang ditemukan | Upload tambahan pada stop completed belum mempunyai guard yang mencegah penurunan ke documented. |
| F-06 | Tinggi sebelum distribusi nyata | Keputusan yang memang belum final | Hak salinan dan hard deletion sumber belum diturunkan menjadi strategi FK/redaction yang dapat dieksekusi. |
| F-07 | Menengah | Dependency data yang belum terbukti | WeatherKit, transit, search multibahasa dan metadata tempat belum diuji pada data/destinasi sasaran. |
| F-08 | Menengah | Kesiapan kontrak implementasi | Schema masih logis, beberapa kontrak media kreator/DTO belum lengkap; jumlah route bukan bukti seluruh protokol siap dibangun. |
| F-09 | Menengah | Kelayakan delivery dan operasi | Cakupan 25 tabel/34 route plus dua runtime server besar untuk dikerjakan sekaligus; waktu, biaya dan kapasitas belum dapat disimpulkan. |

### F-01 — Protokol foto terlalu bergantung pada waktu layanan

**Bukti:** [bab media bagian 7–9](../technology/05-media-location.md) mengharuskan worker menyelesaikan validasi sebelum finalisasi; finalisasi referensi meminta lokasi baru. Pengguna yang sudah meninggalkan pin ditolak. [Bab operasi](../technology/08-security-operations.md) baru memberi kandidat p95 job normal < 30 detik, belum hasil pengukuran.

**Counterexample:** traveller menekan unggah di dalam radius → transfer diterima → worker terlambat karena antrean atau retry → traveller bergerak ke spot berikutnya → media akhirnya valid → finalisasi ditolak karena sudah di luar radius. Kegagalan dapat terjadi meski perilaku pengguna memenuhi syarat kehadiran saat tap yang sudah ditetapkan.

Ini mungkin diimplementasikan, tetapi semantik yang lebih ketat membawa biaya reliabilitas dan waktu tunggu. Antrean yang baik sekalipun tidak dapat menjamin selalu selesai sebelum seseorang berjalan meninggalkan pin.

**Usulan revisi untuk diputuskan:** ikat presence baru pada tindakan transfer, user, stop, pin/policy, batas waktu dan hash bytes yang tepat; setelah bytes yang sama diterima dalam batas tersebut, validasi serta acceptance dapat diselesaikan server secara asinkron. Retry transfer baru tetap memerlukan presence baru. Receipt tidak boleh menjadi token bebas untuk mengunggah foto lain dari lokasi lain. Bila produk memang memilih presence kedua, requirement menunggu dan penanganan keterlambatan layanan harus diterima secara eksplisit.

Usulan ini mengubah DEC-04 dan **belum diterapkan**. Audit tidak melonggarkan aturan GPS pengguna secara diam-diam.

**Batas yang tetap berlaku pada kedua opsi:** server menerima koordinat/timestamp dari client. Nonce membatasi replay; menghitung jarak di PostGIS memeriksa konsistensi geometri. Keduanya tidak membuktikan sensor jujur. Apple mendefinisikan `horizontalAccuracy` sebagai radius ketidakpastian; syarat `distance + accuracy <= radius` adalah policy konservatif, bukan jaminan probabilitas mutlak. App Attest menguatkan integritas instance/request aplikasi; dokumentasi tersebut tidak menyediakan pengesahan koordinat GPS. [Core Location](https://developer.apple.com/documentation/corelocation/cllocation/horizontalaccuracy), [App Attest](https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity).

**Bukti berikutnya:** iPhone fisik, batas radius, lokasi indoor, reduced accuracy, jaringan lambat, app interruption dan worker tertunda. Ukur penolakan pada pengguna yang sebenarnya di dalam area dan waktu tap sampai keputusan; pilih parameter dari bukti tersebut.

### F-02 — Model landing → spot pertama belum lengkap

**Bukti:** [database bagian rundown legs dan trip legs](../technology/03-database.md) mendefinisikan `rundown_legs` dengan kedua endpoint wajib stop. `trip_legs.kind` hanya `access | between_stops`. Access ditujukan ke landing, sedangkan between_stops mensyaratkan dua stop. Pada domain/CBL, landing boleh berbeda dari stop pertama.

**Counterexample:** origin O → landing L → stop S1 → S2, dengan O, L dan S1 tiga titik berbeda. O→L dapat menjadi access; S1→S2 dapat menjadi between_stops; L→S1 belum mempunyai tipe/endpoint yang sesuai kontrak. Koordinat tersedia secara fisik pada kolom, tetapi semantik dan constraint-nya belum mengizinkan segmen tersebut dengan jelas. Jika diabaikan, jadwal bisa kehilangan durasi perpindahan setelah tiba di landing.

**Usulan:** tambahkan segmen landing_to_first dengan aturan endpoint khusus pada template/trip, atau modelkan typed route nodes yang dapat menunjuk origin/landing/stop. Untuk scope awal, segmen eksplisit lebih sederhana. Selaraskan DTO, scheduler, validation dan copy source. Jangan menjadikan landing sebagai stop berfoto wajib hanya untuk menghindari celah schema.

**Bukti berikutnya:** round-trip save/copy/schedule untuk O≠L≠S1 dan untuk L=S1, tanpa segmen hilang atau kedatangan duplikat. Tidak perlu mengganti PostgreSQL untuk mengatasi ini.

### F-03 — Rundown kreator juga konten pengguna

**Bukti:** [ekstensi kontribusi pada database](../technology/03-database.md) menempatkan publication/report/moderation sebagai perluasan kontribusi traveller. Sementara itu, baseline sudah mengizinkan kreator mengunggah tips/foto dan menerbitkan rundown untuk dibaca orang lain. `account_state=suspended` dan distribution withdrawal membantu tindakan admin, tetapi belum menjelaskan alur laporan/filtering/block dan tindak lanjut.

**Dampak:** menonaktifkan kontribusi foto traveller tidak menghilangkan kebutuhan pengelolaan konten library kreator. Apple memperlakukan konten kreator sebagai UGC; guideline 1.2 mencakup filtering, laporan beserta respons, blocking pengguna abusif dan kanal kontak. Ini memengaruhi kebutuhan backend/operasi selain kontrol pada aplikasi. [App Review 1.2 dan 1.2.1](https://developer.apple.com/app-store/review/guidelines/#user-generated-content).

**Usulan:** tentukan scope moderasi yang mencakup rundown/version/media dan akun kreator. Spesifikasikan report target, state review, hak/tindakan moderator, blocking, read filtering, audit dan penanggung jawab respons. Schema serta jumlah tabel/route dapat bertambah; inventori 25/34 bukan batas arsitektur.

Pilot terbatas dapat memakai katalog yang dikurasi pengelola dan penulis yang dibatasi, dengan jalur penanganan masalah yang jelas. Pilot tersebut belum membuktikan operasi platform kreator terbuka atau persetujuan App Review.

### F-04 — Worker gambar di luar Edge adalah kebutuhan nyata

**Bukti vendor:** hosted Supabase Edge Functions membatasi memory 256 MB dan CPU 2 detik per request; halaman limits secara eksplisit menyebut library multithreading seperti sharp/libvips tidak didukung. Angka dapat berubah dan harus diperiksa saat implementasi. [Function limits](https://supabase.com/docs/guides/functions/limits).

**Penilaian atas dokumen:** pilihan Node.js + sharp di container **sudah benar secara arah**; audit tidak menemukan kesalahan karena memilih runtime eksternal. Yang belum ada ialah keputusan host/region, executor hidup, kredensial, dispatch/polling, timeout, autoscaling atau kapasitas concurrency serta biaya aktualnya.

**Dampak:** backend baseline bukan sepenuhnya selesai dengan mengaktifkan project Supabase. Minimal ada komponen eksekusi media tambahan apabila sharp dipertahankan. File JPEG terkompresi kecil juga tidak menjamin penggunaan memori decode kecil. Pemrosesan lokal iPhone tidak menggantikan validasi terhadap client yang dimodifikasi.

**Usulan:** mulai dengan satu worker service/container terukur, colocated sedekat praktis dengan Storage/DB; jangan menambah mikroservis lain tanpa kebutuhan. Uji bounded ingress secara terpisah dari decode. Pisahkan deadline transfer, antrean, processing dan presence challenge agar semuanya tidak diasumsikan memakai timer yang sama.

**Bukti berikutnya:** file normal/rusak/dimensi berlebih, kerja paralel terbatas, worker mati setelah menulis output, lease takeover, restart, output fencing, dan pengukuran memory/CPU/latency. Desain lease/fencing di spesifikasi membantu, tetapi baru menjadi bukti setelah dijalankan.

### F-05 — Upload tambahan berpotensi meregresi status kunjungan

**Bukti:** [bab media bagian 1](../technology/05-media-location.md) mengizinkan beberapa entry untuk stop yang sama; langkah finalisasi bagian 8 menyatakan menandai stop `documented`. Domain juga mempunyai state `completed`.

**Counterexample bersyarat:** jika session untuk foto kedua pada stop yang sudah completed diperbolehkan saat trip masih aktif, finalisasi yang menerapkan instruksi itu secara literal mengubah completed → documented. Spesifikasi belum menegaskan apakah command tersebut harus ditolak atau mempertahankan completed. Ini ambiguitas kontrak, bukan bukti bug pada kode produksi.

**Usulan:** pisahkan fakta `has_accepted_journal` dari state penyelesaian, atau tetapkan transisi bersyarat yang mempertahankan completed. Nyatakan apakah foto tambahan setelah stop/trip selesai diizinkan. Penghapusan foto terakhir mengikuti completion policy eksplisit, bukan kebalikan otomatis dari upload.

**Bukti berikutnya:** dua jurnal pada stop yang sama; finalisasi foto kedua; penghapusan salah satunya/yang terakhir; status trip tidak mundur tanpa command/policy yang dinyatakan.

### F-06 — Snapshot stabil dan hard deletion memerlukan kontrak nyata

**Bukti:** trip menyimpan snapshot tetapi juga mempunyai FK sumber/atribusi sampai ke versi/stop kreator dan profile Auth. Dokumen sudah benar menandai DEC-06 serta menghindari cascade massal.

**Dampak:** archive biasa mudah, sedangkan penghapusan permanen kreator yang sumbernya dipakai traveller tidak bisa diselesaikan oleh satu cascade generik. Mengandalkan RESTRICT saja dapat memacetkan job; menyimpan snapshot saja tidak menetapkan hak mempertahankan foto/nama/konten.

**Usulan:** putuskan per kategori data apakah salinan tetap berlaku, di-redact, dianonimkan atau dihapus; pisahkan kredit historis minimum dari identitas aktif bila sesuai policy. Turunkan keputusan itu ke nullability/FK, triggers, cleanup media dan cache. Keputusan hak konten bukan sesuatu yang diputuskan audit teknologi ini.

**Bukti berikutnya:** creator deletion dengan beberapa traveller, source withdrawal di tengah copy, accepted journal yang masih dirujuk dan restore yang tidak menghidupkan kembali data yang sudah dihapus. Alur Apple revoke juga harus dibuktikan; native ID token/Supabase session tidak boleh dianggap sama dengan material provider yang diperlukan untuk revoke. [Apple TN3194](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple).

### F-07 — Integrasi dan mutu data membatasi kemampuan planner

WeatherKit layak sebagai sumber konteks, tetapi belum ada respons destinasi yang membuktikan dataset/interval yang diperlukan tersedia. MapKit transit tidak menjamin detail jalur kereta/bus. Jam buka, alternatif indoor, akses dan durasi realistis tetap harus berasal dari sumber lain. [WeatherKit](https://developer.apple.com/weatherkit/), [MapKit transit](https://developer.apple.com/documentation/mapkit/mkdirectionstransporttype/transit).

Discovery pada data kecil dapat dimulai dengan area + pencocokan teks sederhana. Namun GIN sebagai pilihan indeks tidak dengan sendirinya menetapkan tokenisasi, typo handling, atau pencarian Jepang/romaji/terjemahan. Dokumen sudah menunda language/config; itu pilihan yang tepat, tetapi kualitas search tetap belum dibuktikan. Supabase mendokumentasikan PGroonga untuk pencarian multibahasa sebagai salah satu opsi bila baseline tidak cukup, bukan dependency yang wajib dipasang sekarang. [PGroonga](https://supabase.com/docs/guides/database/extensions/pgroonga).

**Usulan:** awali satu destinasi dan metadata terkurasi, durasi kreator berlabel, urutan tetap, merge manual, cuaca informatif dan handoff navigasi sesuai kemampuan. Bedakan nama area/konten yang dimiliki C6 dari katalog provider. Uji terms/cache saat adapter dipilih; audit ini tidak menyatakan hak menyimpan seluruh data provider.

**Bukti berikutnya:** request lokasi contoh yang sama di perangkat; respons kosong/stale/error; beberapa query nyata Indonesia/Jepang dan alias; jadwal dengan unknown ETA. Bila data kurang, planner harus mengembalikan unresolved, bukan klaim feasible.

### F-08 — Spesifikasi logis belum kontrak yang dapat dieksekusi

Schema `text` mendeskripsikan kolom, tetapi belum membuktikan FK gabungan, circular pointer, deferrable order, trigger immutable, grants dan RLS dapat dipasang bersama. PostgreSQL mendukung constraint/transaksi yang dibutuhkan, tetapi aturan lintas row tidak boleh diasumsikan dapat ditulis sebagai CHECK biasa. [PostgreSQL constraints](https://www.postgresql.org/docs/current/ddl-constraints.html), [transaction isolation](https://www.postgresql.org/docs/current/transaction-iso.html).

Pada API, route `POST /creator-media-sessions` sudah ada, tetapi kontrak transfer/status/finalisasi media kreator belum diinventarisasi setara protokol jurnal. Menyalin endpoint jurnal begitu saja akan mencampur presence traveller dengan upload kreator. DTO lengkap, status/error dan batas retry tiap operasi juga masih perlu diwujudkan dalam implementasi/contract schema.

**Usulan:** buat migrasi + contract schema per slice, bukan seluruh server sekaligus; lengkapi protokol media kreator atau nyatakan katalog awal disuplai importer pengelola. Tentukan satu jalur penulis domain. Karena command server dapat memakai role yang melewati RLS, uji explicit owner/account checks pada RPC itu sendiri; keberadaan RLS pada jalur baca bukan pembuktian jalur admin aman. [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security).

**Bukti berikutnya:** rebuild database disposable, direct Data API/Storage/RPC dengan anon/A/B/server identities, dua command memakai revision sama, receipt replay setelah timeout, dan snapshot satu revision. Matriks tes pada bab 09 sudah menjadi titik awal yang relevan.

### F-09 — Scope delivery lebih besar daripada kebutuhan pembuktian awal

25 tabel dan 34 route tidak berlebihan secara kapasitas PostgreSQL hanya karena jumlahnya. Kompleksitas utama berasal dari interaksi Auth, copy/version, planner, media, presence, recovery, penghapusan, rights dan integrasi. Sebaliknya, membangun semua capability itu sekaligus memperbesar peluang integrasi terlambat ditemukan.

**Usulan:** pertahankan rancangan jangka panjang sebagai reference; pilih slice yang dapat berjalan dari aplikasi sampai server. Tim tidak perlu menambah Redis, Kubernetes, LLM, microservices umum atau realtime hanya untuk memenuhi kebutuhan baseline yang didokumentasikan. Tambahan komponen harus mempunyai alasan dari hasil pengukuran.

Operasi tetap mempunyai biaya di luar database: worker host, penyimpanan/egress foto, thumbnail, backup objek, environment, monitoring dan provider. Contoh volume pada bab 08 berguna untuk menghitung, tetapi bukan bukti anggaran cukup atau kapasitas aman pada jumlah pengguna tertentu.

Backup database yang terkelola tidak menyertakan bytes Storage. Pilihan ini sudah dijelaskan benar pada spesifikasi; jangan menurunkan prioritas backup objek hanya karena semua layanan bernama Supabase. [Database backups](https://supabase.com/docs/guides/platform/backups).

## 5. Batas kemampuan yang perlu disampaikan secara jujur

1. **Keaslian lokasi absolut:** tidak dijamin oleh GPS client + server distance check + nonce. Klaim yang sesuai ialah diterima berdasarkan lokasi perangkat yang dilaporkan dan policy tertentu.
2. **Jurnal accepted saat offline lalu pasti diterima setelah meninggalkan lokasi:** tidak didukung baseline yang mensyaratkan evaluasi server pada transfer. Perangkat dapat menyimpan draft, tetapi itu status yang berbeda. Alur lain membutuhkan perubahan trust/policy yang eksplisit.
3. **Pencabutan akses seketika terhadap foto yang sudah diunduh:** tidak dapat dijanjikan; server mengontrol akses berikutnya, bukan menghapus salinan yang sudah berada di luar kontrolnya.
4. **Transit rinci dari MapKit transit saja:** tidak didukung kontrak API yang dirujuk; gunakan provider tambahan atau handoff yang sesuai.
5. **Rute optimal berdasarkan cuaca saja:** input tidak cukup untuk menjamin itu. Rule-based suggestion dengan data/ketidakpastian jelas tetap memungkinkan.

Poin-poin ini membatasi janji fitur, bukan membatalkan aplikasi secara keseluruhan.

## 6. Stack yang saya pertahankan dan perubahan yang saya sarankan

| Bagian | Rekomendasi setelah audit |
|---|---|
| Swift/SwiftUI, target proyek iOS 18 | Pertahankan; tidak ada kebutuhan audit yang memaksa upgrade toolchain. |
| SwiftData + filesystem | Pertahankan untuk metadata lokal/draft/cache; bangun sync/recovery secara eksplisit. |
| Supabase Auth + Sign in with Apple | Pertahankan sebagai kandidat; buktikan full lifecycle native login sampai penghapusan. |
| PostgreSQL/PostGIS | Pertahankan; relasi/transaksi/geografi sesuai. Revisi model landing leg dan state guard. |
| Supabase Storage privat | Pertahankan; grants/RLS/path/URL dan backup bytes tetap pekerjaan tersendiri. |
| TypeScript Edge Functions + SQL RPC | Pertahankan untuk command/orkestrasi ringan; explicit authorization pada jalur privileged. |
| Node.js + sharp container | Pertahankan bila memakai sharp; pilih host dan uji resource/antrean sebelum menjadi dependency perjalanan. |
| MapKit + WeatherKit | Pertahankan sesuai kemampuan nyata; detailed transit dan automatic replanning tetap bersyarat. |
| Protokol presence dua tahap | Tinjau ulang DEC-04 lebih awal; referensi saat ini mungkin bekerja tetapi menambah ketergantungan pada waktu layanan. |
| Moderasi | Perluas scope ke library kreator sebelum distribusi konten pengguna; bukan hanya ekstensi foto traveller. |

Memakai backend terkelola tetap berarti ada backend/server di belakang aplikasi; tim tidak harus mengelola mesin database/Auth sendiri. Worker gambar adalah komponen runtime tambahan pada rancangan sekarang, bukan alasan membangun ulang semua fungsi Supabase sebagai server custom.

## 7. Urutan pembuktian yang paling bernilai

Kriteria berikut adalah usulan pekerjaan selanjutnya, belum tes yang dijalankan atau keputusan scope tim.

| Urutan | Slice/spike | Pertanyaan yang dijawab | Bukti minimum yang diminta |
|---|---|---|---|
| 1 | Database + copy trip | Apakah versi, kepemilikan dan graph jadwal konsisten? | Rebuild migrasi; A-v1/A-v2; A/B isolation; O≠L≠S1; concurrent revision; retry tanpa duplikasi. |
| 2 | Satu stop + satu foto end-to-end | Apakah aturan GPS kompatibel dengan jaringan/worker/pergerakan nyata? | iPhone → ingress → Storage → worker → acceptance; kegagalan/timeout/presence baru/relaunch; ukuran resource dan latency tercatat. |
| 3 | Local cache + draft recovery | Apakah pengguna dapat mempertahankan pekerjaan saat jaringan/app terputus? | Draft/file selamat setelah kill; read offline; account switch aman; reconnect di tempat lain tidak memalsukan accepted presence. |
| 4 | Weather/ETA satu destinasi | Data apa yang benar-benar tersedia? | Respons/error/availability asli, timestamps, attribution, quota/budget request dan fallback; belum optimizer global. |
| 5 | Lifecycle akun dan katalog | Apakah layanan dapat mengelola penghapusan dan konten bermasalah? | Apple flow, source deletion policy, reports/moderation scope, Storage cleanup dan isolated restore. |

Fondasi Auth harus tersedia saat slice yang memerlukannya dibangun; urutan tabel menekankan ketidakpastian, bukan izin menunda kontrol akses sampai akhir. Demikian pula keputusan source/moderasi diperlukan sebelum membuka konten nyata.

**Scope MVP teknis yang saya sarankan:** katalog rundown berversi pada satu destinasi → copy/schedule urutan tetap → pelaksanaan per stop → foto privat sesuai policy presence yang dipilih → album → cache bacaan dan draft. Katalog awal bisa dikurasi, dengan konsekuensi belum menguji alur authoring kreator terbuka. Merge A+B tetap bagian arah produk dan dibuktikan setelah slice utama, bukan dihapus dari roadmap. Saran cuaca, detail transit, social publication dan offline editing penuh ditambahkan setelah dependency masing-masing terbukti.

Tidak ada alasan teknis yang terlihat untuk mengganti seluruh stack sekarang. Keputusan yang paling berguna ialah **memperkecil slice pertama, memperbaiki model/kontrak yang konkret, dan menguji protokol foto/GPS lebih awal**. Peluncuran menyeluruh masih membutuhkan bukti di luar audit dokumen ini.

## 8. Hubungan dengan spesifikasi dan CBL

Audit ini adalah lapisan evaluasi atas spesifikasi 0.1; tidak diam-diam mengubah invariant, schema atau DEC-01 sampai DEC-12. Temuan F-02/F-03/F-05/F-08 menjadi usulan perubahan dokumentasi berikutnya. F-01/F-04/F-06/F-07/F-09 mempertegas risiko/dependency yang sebagian sudah diakui spesifikasi.

Progress dan status kelayakan dicatat pada [CBL.md bagian audit teknologi](../../../missing-evidence.md#missing-9daba7d4f2af). Implementasi berikutnya harus menyebut temuan mana yang diselesaikan dan bukti lapisan mana yang benar-benar dijalankan.
