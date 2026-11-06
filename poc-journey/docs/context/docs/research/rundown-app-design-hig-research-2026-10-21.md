# Riset desain aplikasi rundown perjalanan dan Apple HIG

**Status konteks — 29 Oktober 2026:** Riset UI/HIG ini adalah referensi bertanggal. Pemetaan library/kreator/rundown di bawah belum diselaraskan ke alur AI; temuan pola antarmuka bukan bukti diferensiasi atau usability konsep baru. Lihat [acuan aktif](../product/ai-trip-planning-user-flow-2026-10-29.md).

**Tanggal akses:** 21 Oktober 2026, Asia/Jakarta.  
**Dasar produk:** [CBL.md](../../../source-records/CBL.md), setelah klarifikasi langsung pengguna tentang Kreator A/B dan User A.  
**Tujuan:** menyiapkan dasar keputusan untuk wireframe keseluruhan aplikasi pada tahap berikutnya. Belum membuat wireframe atau mengubah kode.

## 1. Kesimpulan untuk desain

Produk perlu memperlihatkan tiga pekerjaan yang terhubung: **menemukan rundown kreator → menyiapkan rencana pribadi → menjalankan perjalanan**. Foto, pin, cerita, dan GPS mendukung journaling perjalanan tersebut. Tampilan peta saja tidak cukup memperlihatkan urutan kegiatan, durasi, transportasi, atau benturan waktu.

Referensi paling dekat adalah **Stippl** untuk penggunaan ulang itinerary kreator, **Wanderlog** untuk pengaturan kegiatan dan perpindahan, serta **Japan Travel by NAVITIME** untuk hubungan timeline dan transportasi. **TripIt** memberi contoh merge yang eksplisit; **Mindtrip** memberi konteks pemisahan inspirasi, koleksi, dan trip; **Polarsteps** memberi konteks journaling. Ini pilihan referensi berdasarkan kecocokan tugas, bukan penilaian bahwa salah satu memiliki UX terbaik.

**Rancangan yang paling membutuhkan perhatian adalah penggabungan rundown.** Pengguna harus memahami rencana tujuan, apa yang berubah, dan efek waktunya sebelum menerapkan perubahan. Ini rekomendasi desain kita, bukan fitur pesaing yang sudah terbukti sama atau keputusan algoritme.

## 2. Metode dan batas bukti

- **Observed:** terlihat langsung di halaman publik atau screenshot resmi yang diperiksa melalui browser.
- **Documented:** dijelaskan sumber resmi produk; tidak berarti interaksinya sudah diuji sendiri.
- **Proposed:** rekomendasi untuk aplikasi kita berdasarkan analisis.
- **Needs confirmation:** keputusan produk yang belum ditetapkan pengguna.

Sumber: situs produk, help center resmi, screenshot pemasaran/App Store, dan Apple HIG. Tidak membuat akun, mengubah trip orang lain, atau menginstal aplikasi pesaing. Tidak menguji aplikasi native secara langsung, usability peserta, performa, VoiceOver, maupun semua variasi UI pesaing. Screenshot pemasaran bisa mewakili versi/desain yang berbeda dari versi native saat ini.

Delapan tangkapan referensi beserta batas keterbacaannya tersedia di [indeks bukti visual](../../../missing-evidence.md#missing-fc7db660b099). Beberapa gambar merupakan referensi historis yang masih ditayangkan resmi; tanggal akses tidak sama dengan tanggal desain.

**Baseline proyek diperiksa dari konfigurasi aktual:** SwiftUI; `IPHONEOS_DEPLOYMENT_TARGET = 18.0`, `SWIFT_VERSION = 5.0`, `TARGETED_DEVICE_FAMILY = 1,2` pada `<LOCAL_HOME>/Programming/software/ios/poc-c67/poc-c67.xcodeproj/project.pbxproj`. Fokus wireframe yang diusulkan adalah iPhone, dengan catatan adaptasi iPad karena target proyek mencakup keduanya. Build/runtime tidak dijalankan ulang. Angka Xcode/runtime di CBL adalah bukti sebelumnya.

## 3. Referensi aplikasi dan pola yang dapat dipakai

### A. Stippl — itinerary kreator, salinan pribadi, dan timeline

**Documented:** kreator dapat membagikan itinerary agar pembaca menyalinnya ke rencana sendiri. Help center menjelaskan Copy trip dengan pilihan komponen. **Observed V01/V05:** peta rute dan daftar tujuan; pemisahan Route/Days/Bookings; daftar aktivitas dengan foto dan waktu/keadaan belum diberi waktu. [Creator offering](https://www.stippl.io/creators), [Copy trip](https://stippl.crisp.help/en/article/how-do-i-delete-duplicate-or-leave-a-trip-14mas3g/), [Itinerary planner](https://www.stippl.io/itinerary-planner).

**Proposed:** bedakan jelas rundown sumber kreator dan rencana milik pengguna. Sediakan pratinjau sebelum dipakai dan atribusi sumber. Jangan menyamakan menyalin trip dengan menggabungkan beberapa rundown; perilaku merge lintas kreator belum terverifikasi di sini. Budget, booking, eSIM, reward, dan AI mereka tidak otomatis masuk scope kita. Artikel Copy trip yang dibuka langsung diperbarui 13 Oktober 2026; utamakan isi halaman langsung dibanding cuplikan pencarian lama.

### B. Wanderlog — kegiatan, waktu, dan perpindahan

**Documented:** tempat dapat diberi waktu mulai/selesai; baris antar-tempat menampilkan estimasi perpindahan dan pilihan moda; tempat dari guide dapat dimasukkan ke trip. **Observed V03:** pemilih hari, urutan tujuan, detail tempat, Add time, dan akses peta. Screenshot bantuan berasal dari artikel 2023, bukan bukti visual versi terbaru. [Add time](https://help.wanderlog.com/hc/en-us/articles/5154820301851-Add-time-to-a-place), [Time and distance](https://help.wanderlog.com/hc/en-us/articles/5159565134875-See-time-and-distance-between-places), [Guide to trip](https://help.wanderlog.com/hc/en-us/articles/5159511810843-Add-a-place-from-a-guide-to-trip-plan).

**Proposed:** tampilkan kegiatan dan segmen transportasi sebagai dua jenis baris dalam rundown, dengan pemilihan hari yang jelas. Mempertahankan hari/trip tujuan saat mencari tambahan mencegah kehilangan konteks. Hindari menyalin kepadatan seluruh detail tempat ke layar pelaksanaan. Compact view yang didokumentasikan Wanderlog adalah fitur web; jangan menyebutnya hasil observasi native iOS. [Compact view](https://help.wanderlog.com/hc/en-us/articles/13356092870427-Itinerary-compact-view).

### C. Japan Travel by NAVITIME — timeline yang memperhitungkan mobilitas

**Documented:** itinerary memuat spot, aktivitas, transportasi, foto/deskripsi, serta dapat dicari dan dipakai sebagai referensi. Perhitungan rute terhubung data jadwal transportasi. **Observed V04:** pemilih tanggal, jam di sumbu timeline, kartu tempat, dan kartu transportasi berdurasi di antaranya. Gambar berasal dari landing page dengan footer 2019; rilis itinerary posting berasal dari 2023. [Planning](https://static.japan.travel.navitime.com/app-lp/en/index.html), [Itinerary posting](https://corporate.navitime.co.jp/en/topics/topics/202308/17_5634.html).

**Proposed:** jadikan perpindahan bagian eksplisit dari rundown, bukan catatan tersembunyi. Bedakan saran kreator dengan hasil perhitungan untuk tanggal perjalanan pengguna. Jangan menganggap semua jadwal atau kondisi cuaca otomatis tersedia bagi aplikasi kita hanya karena NAVITIME menyediakannya.

### D. Steller — library itinerary dengan identitas kreator

**Observed V02:** pencarian itinerary, kartu bergambar, nama kreator, judul perjalanan, angka pin, dan kontrol bookmark. **Documented:** situs memisahkan itineraries, destinations, videos, dan nearby. Ini observasi web responsif, bukan aplikasi native. [Library](https://steller.co/search?type=trips), [Situs resmi](https://steller.co/).

**Proposed:** manfaatkan kartu untuk memahami siapa pembuat dan pengalaman yang ditawarkan. Tambahkan metadata yang diperlukan tugas kita, seperti durasi dan rentang waktu; angka pin/foto saja belum menjawab apakah rundown cocok dijalankan. Durasi dan rentang waktu itu usulan kita, bukan klaim bahwa sudah terlihat pada Steller. Jangan mengadopsi feed video sebagai pusat produk tanpa alasan tugas.

### E. Mindtrip — inspirasi, koleksi, dan perjalanan pribadi

**Documented:** guides dari kreator, collections untuk ide, dan Trips untuk rencana; listing juga menjelaskan penambahan tujuan dan perubahan rencana. **Observed V06:** screenshot pemasaran memperlihatkan struktur trip dan navigasi, tetapi teks kecil/slide lain tidak seluruhnya terbaca. [App Store resmi](https://apps.apple.com/us/app/mindtrip-ai-travel-companion/id6503107567), [Situs resmi](https://mindtrip.ai/).

**Proposed:** pisahkan menyimpan inspirasi dengan menjadwalkan perjalanan. Rundown yang dibookmark belum otomatis menjadi kegiatan besok. Percakapan AI, booking, dan agen bukan prasyarat untuk menggunakan konsep kreator kita; tidak perlu dijadikan entry point. Tidak ada bukti dari inspeksi ini untuk algoritme merge yang identik dengan kebutuhan kita.

### F. TripIt — tindakan merge dan pemilihan tujuan

**Documented:** pengguna membuka sebuah trip, memilih Merge into Another Trip, lalu memilih trip tujuan. Ini referensi tindakan merge eksplisit, bukan penggabungan timeline kreator yang sudah teruji. Halaman bantuan yang dibuka mencantumkan langkah iOS. [Merge trips](https://help.tripit.com/en/support/solutions/articles/103000063429-merge-trips).

**Proposed:** label tindakan harus menyebut rencana tujuan; jangan membiarkan pengguna menebak apakah menambah atau mengganti. Pratinjau perubahan, pembatalan, dan pemulihan lebih relevan untuk tugas kita daripada menyalin letak menu TripIt. Interaksi native dan layar hasil merge belum diperiksa langsung.

### G. Polarsteps — dokumentasi perjalanan pada tempat/kegiatan

**Documented:** steps berisi lokasi dengan foto/teks; pemilihan foto dilakukan pengguna. Situs saat ini juga menampilkan planning, sehingga jangan mengulang klaim lama bahwa Polarsteps hanya diary. **Observed V07/V08:** pemisahan pesan planning/tracking dan kartu langkah perjalanan; V08 sebagian kecil dan tidak menunjukkan flow editor. [Steps](https://support.polarsteps.com/hc/en-us/articles/23760478173586-What-are-steps-and-how-do-I-add-or-edit-them), [Photos](https://support.polarsteps.com/hc/en-us/articles/24267419977874-How-do-I-add-photos-to-my-trip), [Situs resmi](https://www.polarsteps.com/).

**Proposed:** tautkan entri jurnal ke tempat/perjalanan pengguna, dengan tindakan tambah foto yang sederhana. Pisahkan jadwal rencana dan catatan kejadian aktual. GPS gate kita tetap aturan produk; jangan mengklaim Polarsteps menerapkan gate yang sama.

### Referensi tambahan untuk pilihan copy/import

**Documented:** Travefy membedakan salin ke trip baru, trip yang sudah ada, atau trip yang sama. AXUS menjelaskan pemilihan beberapa/semua booking serta tujuan baru/existing. Konteks keduanya alat travel advisor dan booking, bukan bukti langsung perilaku traveller kita. [Travefy](https://intercom.help/travefy/en/articles/108284-can-i-reuse-itineraries-for-future-trips-clients-the-copy-button), [AXUS](https://support.axustravelapp.com/hc/en-us/articles/208079663-How-to-Copy-Bookings-into-a-New-or-Existing-Itinerary).

**Proposed:** pastikan tindakan memakai rundown baru berbeda dari menambah ke perjalanan yang dimiliki. Pemilihan hanya sebagian kegiatan adalah kandidat yang dapat diuji, belum keputusan pengguna.

## 4. UI/UX yang diusulkan untuk kategori aplikasi ini

Seluruh butir bagian ini adalah **Proposed**, bukan aturan Apple atau temuan pengguna yang sudah tervalidasi.

| Masalah tugas | Arah desain | Pemeriksaan pada wireframe berikutnya |
|---|---|---|
| Memilih rundown yang cocok | Kartu menampilkan tujuan/area, kreator, durasi, jumlah spot, rentang kegiatan, serta pembaruan bila tersedia. | Bisa membedakan rute setengah hari dan aktivitas malam tanpa membuka banyak detail. |
| Memahami rundown sebelum mengambilnya | Detail mengutamakan ringkasan dan timeline; map menjadi tampilan pelengkap yang mudah diakses. | Urutan, lama tinggal, dan waktu pindah terbaca; pilihan list/map tidak menghilangkan posisi. |
| Memakai rundown pada tanggal sendiri | Konfigurasi tanggal, jam mulai, zona waktu destinasi, dan batas waktu bila relevan. | Jadwal saran kreator berbeda jelas dari jadwal pribadi pengguna. |
| Menambah rencana B ke A | Library dibuka dengan konteks perjalanan/hari tujuan tetap terlihat; ada tahap tinjau sebelum menerapkan. | Tidak menimpa kegiatan diam-diam atau mengubah hari yang keliru. |
| Benturan/duplikasi | Beri penjelasan tempat sama, jam bentrok, waktu transfer belum diketahui, dan efek selesai lebih malam. | Pengguna tetap mengontrol hasil; tidak dijanjikan auto-resolve sebelum aturannya dipilih. |
| Menjalankan perjalanan | Utamakan kegiatan sekarang/berikutnya, jadwal, transportasi, dan akses rundown lengkap. | Satu pandangan cukup untuk mengetahui langkah berikutnya; tidak perlu membaca deskripsi panjang. |
| Menambah jurnal | Masuk dari kegiatan/spot aktif dan dari jurnal perjalanan; pilih foto, pratinjau, simpan/unggah. | Status lokasi dan status simpan/kirim berbeda; foto tidak hilang setelah gagal. |
| Menyusun rundown kreator | Editor urutan dan transportasi, detail spot, pratinjau, draft, serta review sebelum publikasi. | Konten yang belum lengkap terlihat dan dapat dilanjutkan; tidak perlu memilih akun kreator permanen. |
| Menggunakan informasi dinamis | Bedakan catatan kreator, perkiraan, forecast, dan jadwal yang diverifikasi; tampilkan waktu pembaruan bila ada. | Data tidak tersedia tidak ditampilkan sebagai nol menit/cuaca pasti. |
| Koneksi buruk | Data tersimpan yang tersedia tetap dibaca; jelaskan data yang membutuhkan koneksi. | “Disimpan” tidak otomatis berarti seluruh basemap/transit offline. |

**Model konseptual untuk desain:** rundown sumber kreator, rencana perjalanan pengguna, kegiatan, segmen perpindahan, dan entri jurnal perlu dapat dibedakan. Ini kebutuhan pemahaman UI, bukan penetapan schema backend. Tautan ke rundown sumber tidak berarti edit pengguna mengubah milik kreator.

**Waktu memerlukan perhatian khusus:** waktu setempat destinasi, durasi versus jam mulai/selesai, kegiatan melewati tengah malam, buffer, jam buka, waktu tetap versus saran fleksibel, perubahan tanggal, dan kegiatan yang sudah berlangsung. Jangan memindahkan kegiatan yang sudah dijalankan saat menambah rundown malam tanpa persetujuan. Bila sampai tahap wireframe harus memakai data contoh, beri label simulasi, bukan estimasi perjalanan Jepang aktual.

## 5. Apple HIG yang relevan dan implikasi desain

Sumber diakses 21 Oktober 2026. Isi halaman topik diambil melalui Sosumi sebagai pembaca dokumentasi Apple; tautan di bawah adalah sumber resmi Apple. Root HIG melalui web membutuhkan JavaScript; endpoint topik berhasil dibaca. Ini riset panduan untuk rancangan berikutnya, **bukan audit kepatuhan aplikasi yang sudah selesai**. Tidak menyatakan pelanggaran dari UI yang belum dibuat.

| Topik resmi | Panduan yang relevan | Penerapan yang diusulkan untuk aplikasi kita |
|---|---|---|
| [Designing for iOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ios) | Prioritaskan tugas utama, tampilkan detail sekunder bertahap, dukung perubahan ukuran teks dan penampilan. | Hindari satu layar penuh map, foto, cuaca, tombol edit, dan semua metadata sekaligus. |
| [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars) | Tab untuk tujuan navigasi, bukan menjalankan tindakan; label jelas dan tujuan stabil. | “Tambah rundown” dan “Mulai perjalanan” adalah tombol dalam konteks. Jumlah/nama tab usulan desain, bukan mandat HIG. |
| [Searching](https://developer.apple.com/design/human-interface-guidelines/searching) | Search penting mendapat posisi jelas; lingkup pencarian harus terbaca. | Bedakan pencarian rundown di library, pencarian spot di editor, dan pencarian perjalanan sendiri. Halaman mencatat pembaruan 8 Juni 2026. |
| [Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets) | Tugas modal perlu jalan keluar; hindari tumpukan sheet; detent membantu pengungkapan bertahap. | Detail pin singkat cocok untuk sheet; proses merge panjang lebih mudah sebagai alur dengan navigasi. Pedoman posisi tombol diperbarui 24 Maret 2026. |
| [Maps](https://developer.apple.com/design/human-interface-guidelines/maps) | Interaksi map familiar, seleksi jelas, clustering untuk pin berimpit, logo/legal tidak tertutup terus. | List menjadi alternatif map; sinkronkan pin dengan baris terpilih. Logo/legal harus diperhitungkan saat ada panel bawah. |
| [Pickers](https://developer.apple.com/design/human-interface-guidelines/pickers) | Gunakan pilihan nilai yang terurut dan pemilih tanggal/waktu dalam konteks. | Gunakan pola date/time picker sistem untuk tanggal perjalanan; durasi diberi label berbeda. |
| [Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding) | Onboarding singkat, belajar melalui tugas, tunda setup yang belum diperlukan. | Biarkan pengguna memahami contoh rundown; pemilihan peran tidak perlu menjadi gerbang permanen. |
| [Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy) | Minta data minimum dan izin saat fiturnya membutuhkan, dengan alasan spesifik. | Browse library tanpa memaksa GPS; izin lokasi saat jarak/navigasi atau unggah, kamera saat mengambil foto. Jangan meminta izin kalender hanya karena ada jadwal internal. |
| [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) | Dynamic Type, VoiceOver, informasi lebih dari warna, alternatif gesture, kontrol nyaman. | Konflik ditandai teks/ikon; sediakan aksi pindah urutan selain drag. Target desain kontrol utama ≥44×44 pt untuk penggunaan di lapangan; ini pilihan konservatif kita. HIG saat diakses membedakan default iOS 44×44 dan minimum 28×28, sehingga jangan menyebut 44 sebagai satu-satunya batas minimum Apple. |
| [Undo and redo](https://developer.apple.com/design/human-interface-guidelines/undo-and-redo) | Pengguna perlu memprediksi dan melihat hasil pembatalan perubahan. | Tinjau merge sebelum apply; desain pembatalan/pemulihan untuk perubahan rencana. Ini tidak menentukan algoritme merge. |
| [Loading](https://developer.apple.com/design/human-interface-guidelines/loading) | Tampilkan isi yang tersedia dan progres yang sesuai tanpa membekukan seluruh tugas. | Bedakan memuat library, menyiapkan salinan, validasi lokasi, dan mengirim foto; jangan tampil sukses sebelum selesai. |
| [Materials](https://developer.apple.com/design/human-interface-guidelines/materials) | Liquid Glass membedakan lapisan kontrol/navigasi dari konten; jangan menggunakannya di semua kartu konten. | Wireframe fokus hierarki; kartu rundown dan timeline tetap mudah dibaca. Efek versi OS baru tidak menjadi alasan menaikkan deployment target iOS 18. |
| [Managing notifications](https://developer.apple.com/design/human-interface-guidelines/managing-notifications) | Tingkat interupsi harus sesuai urgensi dan menghormati preferensi/Focus. | Pengingat perjalanan, jika dipilih, tidak membuat semua saran foto/cuaca menjadi Time Sensitive. Push/Live Activity tetap perlu keputusan dan pemeriksaan teknis terpisah. |

Pemeriksaan aksesibilitas untuk wireframe: teks besar tidak memotong jam/nama tempat; urutan baca timeline dan transportasi logis; status lokasi tidak hanya warna; kontras baik di atas map/foto; Reduce Motion punya hasil ekuivalen; kontrol penting dapat dijangkau dan tidak bergantung gesture tersembunyi. Wireframe tidak dapat membuktikan VoiceOver atau kontras runtime, sehingga perlu pengujian saat implementasi.

**Adaptasi:** iPhone compact memakai list/detail/map yang dapat berpindah tanpa kehilangan seleksi. Bila iPad tetap dalam scope, gunakan ruang untuk daftar dan detail/map berdampingan; pertahankan hari, query, draft, seleksi, dan hasil tinjau saat ukuran berubah. Ini usulan, belum hasil uji layout.

## 6. Entry point: rekomendasi untuk diuji

**Proposed:** pengguna baru mulai dari Jelajah/Library yang dapat menunjukkan rundown. Pengguna kembali melanjutkan konteks terakhir, dengan akses menonjol ke perjalanan hari ini. Tautan rundown membuka detail yang dituju. Hindari pindah tab sendiri ketika jadwal berubah; pertahankan lokasi navigasi yang dapat diprediksi.

Pilihan struktur yang layak digambar pada tahap berikutnya:

| Pilihan | Kelebihan | Konsekuensi |
|---|---|---|
| Jelajah · Perjalanan · Jurnal; pembuatan lewat tombol dan workspace kreator | Tiga bagian utama mudah dipahami traveller. | Karya kreator perlu akses jelas agar tidak terkubur di pengaturan. |
| Jelajah · Perjalanan · Jurnal · Karya | Kedua peran punya area stabil; membuat/mengelola rundown mudah ditemukan. | Satu tab tambahan, dengan empty state untuk pengguna yang belum membuat karya. |

**Rekomendasi kerja:** mulai mengeksplorasi opsi empat bagian bila wireframe benar-benar mencakup kreator dan traveller. Ini belum persetujuan home/tab final. Tab Karya berisi daftar karya; tombol Buat di dalamnya, sesuai perbedaan navigasi dan tindakan. Profil/pengaturan cukup menjadi akses toolbar untuk tahap awal desain.

## 7. Persiapan wireframe berikutnya

Gunakan [handoff inventory](../product/rundown-wireframe-research-handoff-2026-10-21.md) untuk cakupan layar, keadaan, flow, dan asumsi. Prioritas walkthrough:

1. Pengguna baru menemukan rundown A dan menjadwalkannya untuk besok.
2. Besok pagi ia membuka perjalanan hari ini dan mencari tambahan malam.
3. Ia menambahkan B, memahami konflik/duplikasi, meninjau hasil, dan dapat membatalkan.
4. Ia menjalankan kegiatan dan membuat jurnal foto dengan GPS saat unggah.
5. Kreator menyusun, meninjau, menyimpan draft, dan membagikan rundown.

Belum ada bukti bahwa kombinasi fitur ini unik di pasar atau lebih bernilai daripada alternatif. Riset ini menyiapkan rancangan dan tugas uji, bukan validasi USP. Jangan mengubah aturan merge atau entry point menjadi keputusan pengguna hanya karena direkomendasikan dalam laporan ini.
