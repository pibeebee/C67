# Riset pembanding algoritme urutan kunjungan — PoC C67

Tanggal: **3 November 2026**. Status: riset dan usulan eksperimen; belum implementasi atau benchmark. Kode aplikasi tidak diubah dalam pekerjaan ini.

## Temuan pada kode saat ini

Audit dilakukan pada `<LOCAL_HOME>/Programming/software/ios/poc-c67`.

- [Pembentukan urutan](../../../apps/native-routing-lab/poc-c67/Features/NativePlanner/NativeTripEngine.swift): nearest-neighbor memakai kedekatan geografis, kemudian pembalikan segmen mirip 2-opt, dibatasi dua pass. Hanya satu atau dua kandidat unik dibentuk dari urutan tersebut dan arah kebalikannya.
- [Penilaian kandidat](../../../apps/native-routing-lab/poc-c67/Features/NativePlanner/NativeTripEngine.swift): kandidat lengkap yang memenuhi batas diketahui didahulukan, kemudian total waktu perpindahan dan waktu menunggu. ETA diminta pada jam keberangkatan tiap ruas setelah perjalanan/singgah sebelumnya.
- [Layanan ETA](../../../apps/native-routing-lab/poc-c67/Features/NativePlanner/NativeTripAppleServices.swift): batas aplikasi 96 request ETA per run, jeda 450 ms untuk request baru, dan deadline 25 detik. Ini kebijakan PoC, bukan angka batas resmi Apple.

Implikasinya: fungsi penilaian sudah memakai ETA, tetapi pencarian kandidat masih terutama memakai geografi. Mengganti dasar pencarian lebih relevan daripada hanya menambah pass yang tetap mengoptimalkan jarak geografis. Ini kesimpulan audit kode, bukan hasil eksperimen kualitas rute.

## Bentuk masalah yang hendak diselesaikan

Semua tujuan pengguna wajib dipertahankan, titik awal/akhir ditetapkan, ada durasi singgah dan batas satu hari, serta waktu perjalanan bisa bergantung arah, moda dan waktu keberangkatan. Jam operasional menjadi batas tambahan jika tersedia. Dalam istilah optimasi, arahnya adalah **time-dependent asymmetric TSP/path dengan time windows**, bukan sekadar TSP jarak simetris. Riset time-dependent TSPTW menggunakan pemodelan waktu dan label yang lebih kaya daripada TSP statis. [Lera-Romero dkk., 2022](https://pubsonline.informs.org/doi/10.1287/ijoc.2022.1236).

Apple menyediakan `departureDate` sebagai konteks untuk optimasi rute. Transit MapKit hanya mendukung estimasi waktu kedatangan; optimizer tidak boleh menganggap data itu sudah berisi detail jalur, platform atau seluruh paparan cuaca transfer. [Apple: departureDate](https://developer.apple.com/documentation/mapkit/mkdirections/request/departuredate), [Apple: transit](https://developer.apple.com/documentation/mapkit/mkdirectionstransporttype/transit).

## Kandidat yang layak dibandingkan

Penjelasan metode bersumber dari dokumentasi/paper; penilaian prioritas dan kecocokan Swift berikut adalah usulan untuk PoC ini, bukan klaim keunggulan yang sudah terukur.

| Kandidat | Mekanisme inti | Penilaian untuk PoC | Batas utama |
|---|---|---|---|
| Multi-start nearest ETA + local search | Mulai dari beberapa konstruksi awal berbasis waktu; pindahkan satu tujuan atau tukar dua tujuan untuk memperbaiki urutan. | Prioritas pertama; perubahan paling dekat dengan engine sekarang. | Masih bisa berhenti pada solusi lokal. Semua perubahan harus dinilai ulang dengan arah dan waktu yang benar. |
| Cheapest insertion + local search | Mulai dengan awal–akhir; masukkan tujuan pada posisi dengan tambahan biaya terkecil, lalu perbaiki urutannya. | Pembanding konstruksi awal terhadap nearest-neighbor. | Insertion yang murah secara statis belum tentu baik setelah waktu kunjungan bergeser. |
| Time-aware beam search | Pertahankan sejumlah alternatif urutan parsial, bukan satu pilihan greedy, sambil memperbarui waktu tiba/berangkat. | Prioritas berikutnya untuk efek jam buka dan transit. | Lebar beam serta kebutuhan ETA harus dibatasi; tidak menjamin optimum. |
| Large Neighborhood Search / ALNS | Lepas beberapa tujuan dari kandidat, masukkan kembali, lalu pilih strategi perbaikan yang membantu. | Tahap lanjut untuk banyak batas dan perencanaan ulang. | Lebih banyak parameter dan evaluasi; tujuan yang dilepas sementara wajib kembali pada kandidat final. |
| OR-Tools + Guided Local Search | Gunakan solver yang menyediakan strategi konstruksi/perbaikan dan batas waktu pencarian. | Pembanding eksternal pada Mac lebih dulu, bukan kewajiban menambah backend ke aplikasi. | Model dan data tetap harus disiapkan; contoh matriks waktu statis tidak otomatis menyelesaikan transit bergantung waktu. |
| Exact solver pada kasus kecil | Enumerasi seluruh urutan atau DP klasik pada model statis yang sesuai. | Acuan optimum untuk mengukur selisih heuristik, bukan default semua trip. | Optimum hanya berlaku terhadap model/data yang diuji. DP klasik bukan pengganti langsung untuk seluruh batas time-dependent. |

Strategi nearest-arc, insertion dan pilihan metaheuristic didokumentasikan pada [OR-Tools Routing Options](https://developers.google.com/optimization/routing/routing_options). Beam search untuk TSPTW mempertahankan sejumlah node pada setiap level; penerapan waktu perjalanan dinamis pada PoC merupakan adaptasi yang perlu diuji. [Wu, Ting & Lan, 2011](https://www.jstage.jst.go.jp/article/easts/9/0/9_0_702/_article/-char/en).

ALNS berasal dari literatur routing berkendala, termasuk penggunaan beberapa subheuristik dengan pemilihan adaptif. Studi asal yang dirujuk membahas pickup/delivery; hasilnya tidak dapat langsung dianggap bukti keunggulan untuk itinerary wisata kita. [Røpke & Pisinger, 2006](https://orbit.dtu.dk/en/publications/an-adaptive-large-neighborhood-search-heuristic-for-the-pickup-an/).

Landasan perbaikan pertukaran rute dapat ditelusuri pada [Croes, 1958](https://pubsonline.informs.org/doi/10.1287/opre.6.6.791); adaptasi biaya waktu dan multi-start di sini merupakan usulan implementasi. Untuk acuan exact, lihat [Held & Karp, 1962](https://epubs.siam.org/doi/abs/10.1137/0110015). Contoh time windows solver menggunakan matriks waktu dan batas kunjungan tersedia di [OR-Tools VRPTW](https://developers.google.com/optimization/routing/vrptw). OR-Tools adalah perangkat lunak optimasi yang dapat diberi data dari model eksperimen; memilihnya sebagai pembanding tidak berarti beralih ke Google Routes API.

## Persyaratan evaluator yang sama

Sebelum memilih pemenang, semua algoritme harus dinilai oleh evaluator yang sama:

1. Pertahankan seluruh tujuan, durasi singgah pengguna, serta awal/akhir. Tujuan yang berulang tetap menjadi occurrence berbeda.
2. Jangan menyamakan biaya A→B dan B→A. Untuk 2-opt pada biaya berarah, pembalikan segmen juga mengubah arah ruas-ruas di dalam segmen; jangan memakai delta empat ruas dari kasus simetris tanpa menghitung dampak itu.
3. Setelah urutan berubah, propagasikan ulang waktu hingga akhir. ETA pukul 07.00 tidak boleh dianggap berlaku untuk semua ruas sepanjang hari.
4. Periksa jam buka yang diketahui, tunggu buka, batas berjalan, dan batas selesai. Data kosong/provider gagal bukan durasi nol dan bukan bukti semua rute mustahil.
5. Pertahankan objektif utama yang disepakati: waktu perpindahan. Laporkan pula waktu menunggu, singgah, waktu selesai dan total durasi trip; waktu perpindahan minimum tidak selalu memberi total rundown minimum.
6. Jangan membiarkan pemangkasan tujuan atau hasil parsial mendapat skor seolah lebih baik daripada itinerary lengkap.

Poin 2–6 adalah persyaratan rancangan yang diturunkan dari model PoC. Untuk masalah dengan biaya dinamis, menunggu dengan sengaja juga dapat menjadi bagian solusi terbaik; jangan menyatakan solusi optimum bila ruang pencarian tidak mencakup keputusan waktu tersebut. [Vu, Hewitt & Vu, 2023](https://arxiv.org/abs/2311.08111).

Jika pilihan moda ingin dioptimalkan bersama urutan, moda dan waktu tiba perlu dipertahankan sebagai bagian kandidat. Memilih moda tercepat pada satu ruas tidak dengan sendirinya membuktikan optimalitas seluruh itinerary untuk semua objektif dan batas.

## Anggaran request dan model ETA

Matriks lengkap tidak gratis secara jumlah request. Contoh: 15 tujuan ditambah satu titik awal/kembali berarti 16 lokasi, sehingga ada **16 × 15 = 240 pasangan berarah per moda**, sebelum sampel waktu lain. Angka ini hasil penghitungan pasangan, bukan kuota layanan.

Usulan: cache sementara per eksperimen; isi ETA secara bertahap sesuai pasangan yang dibutuhkan; gunakan perkiraan per kelompok waktu hanya untuk menyaring kandidat; evaluasi ulang kandidat final pada jam keberangkatan masing-masing ruas. Jumlah waktu sampel dan lebar pencarian merupakan parameter eksperimen, bukan standar.

Apple memperingatkan request yang terlalu sering dapat terkena throttling. Pencarian lebih luas perlu dibandingkan dengan anggaran request dan waktu tunggu yang setara. [Apple: loadingThrottled](https://developer.apple.com/documentation/mapkit/mkerror/code/loadingthrottled).

Menghitung ulang semua permutasi sambil memanggil MapKit pada setiap langkah bukan rancangan benchmark yang disarankan. Batas 96 request saat ini juga perlu dipisahkan dari batas CPU solver dan ditinjau berdasarkan hasil pengukuran, bukan sekadar dinaikkan tanpa data.

## Posisi cuaca

Usulan tahap pertama: bandingkan kualitas urutan transportasi dengan evaluator yang sama. Simpan beberapa alternatif layak dalam batas tambahan waktu, bukan hanya pemenang waktu tunggal, agar preferensi cuaca masih mempunyai pilihan yang bermakna.

Prakiraan tidak tersedia tetap unknown. Detail paparan transit yang tidak diberikan MapKit juga tetap unknown; jangan memberi paparan nol atau keterlambatan hujan buatan agar suatu kandidat terlihat unggul. Kemudian, jika data cukup, bandingkan waktu dan paparan sebagai tradeoff yang terlihat. Ini usulan penerapan pada PoC, bukan model keterlambatan cuaca tervalidasi.

## Rancangan pembandingan yang disarankan

Urutan eksperimen:

1. **A — baseline sekarang:** geografi + pembalikan segmen + paling banyak dua kandidat ETA.
2. **B — local search berbasis waktu:** beberapa seed, konstruksi nearest/insertion, relocate dan swap; penilaian waktu berarah.
3. **C — time-aware beam:** beberapa urutan parsial, waktu tiba/singgah menyesuaikan setiap langkah.
4. **D — acuan kecil:** enumerasi pada sekitar 5–8 tujuan; DP dapat ditambahkan untuk model statis yang memenuhi asumsi. Rentang ini pilihan awal eksperimen, bukan batas kemampuan teoretis.
5. Jika ada manfaat terukur, tambah ALNS atau OR-Tools sebagai pembanding berikutnya.

Mulai dari data sintetis terkontrol yang sama untuk memisahkan kualitas algoritme dari perubahan layanan. Gunakan skenario: 5/10/15/20 tujuan, rute searah/tidak simetris, stasiun yang dekat geografis tetapi memutar, jam buka sempit, perpindahan transit sensitif waktu, titik akhir berbeda, daftar tak muat satu hari, serta ETA yang gagal/sebagian tidak tersedia.

Sesudah itu validasi kandidat menggunakan MapKit. Perbandingan live memakai batas request setara, tanggal/jam input dan versi parameter yang tercatat, serta pengulangan; hasil live yang berbeda tidak otomatis disebabkan solver karena respons provider bisa berubah.

| Ukuran | Yang dicatat |
|---|---|
| Kualitas | Total perpindahan, menunggu, singgah, waktu selesai dan durasi total |
| Kepatuhan | Semua tujuan/awal/akhir/durasi tetap; konflik jam/batas selesai |
| Kelengkapan data | Berapa ruas diketahui, gagal, belum diperiksa atau memakai perkiraan |
| Selisih optimum | Selisih terhadap acuan exact, hanya untuk model dan kasus kecil yang sama |
| Performa | Waktu komputasi solver terpisah dari latensi jaringan; memori bila relevan |
| Biaya layanan | Request ETA baru, cache hit, timeout dan throttling |
| Stabilitas | Seed untuk metode acak; median dan rentang hasil beberapa pengulangan |

Log yang sudah ditambahkan dapat dikembangkan untuk merekam algorithm ID/version, seed, lebar pencarian, jumlah kandidat/evaluasi, jumlah request dan alasan penghentian. Ketika anggaran habis, statusnya **pencarian belum tuntas**, bukan **terbukti tidak ada itinerary**.

## Rekomendasi riset

Bandingkan **A vs B vs C**, gunakan **D** sebagai pemeriksa kualitas pada kasus kecil. B merupakan peningkatan awal yang paling dekat dengan kode; C menguji apakah mempertahankan alternatif dan konteks waktu menghasilkan perbedaan bernilai. ALNS dan OR-Tools disimpan sebagai tahap berikutnya berdasarkan bukti, tanpa menjadikan AI prasyarat perencana.

Belum ada algoritme yang dinyatakan menang. Tidak ada kode aplikasi, request ETA, build, atau test PoC yang dijalankan dalam pekerjaan riset ini.

## Tindak lanjut implementasi

Pendekatan penelitian ini sudah dihubungkan pada aplikasi PoC iOS yang sama: enam metode native termasuk baseline, serta pembanding OR-Tools melalui ekspor/impor helper Mac. Dokumen ini tetap mencatat pertimbangan sebelum implementasi. Lihat [panduan implementasi dan batas verifikasi](../../../apps/native-routing-lab/docs/NATIVE_ROUTING_LAB.md).
