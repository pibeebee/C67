# Pilot katalog terbuka Jakarta Selatan

Pilot ini menilai apakah kandidat dari Overture Places dan OpenStreetMap dapat diperkaya dengan bukti yang berguna untuk rekomendasi C67. Unit evaluasinya adalah fakta tentang cabang atau fasilitas yang tepat. Identitas tempat, izin pengunjung, jam rutin, dan kegiatan dinilai terpisah.

## Pengumpulan batch baru

Batch penambahan terpisah berada di [campaigns/jaksel-expansion-30-2026-11-10/](campaigns/jaksel-expansion-30-2026-11-10/). Input berisi 30 kandidat baru dari snapshot OSM/Overture, dengan nama, alamat petunjuk, ID peta, dan URL pengelola/pemerintah hasil pencarian asisten. discovery.json menyimpan kategori dan catatan risiko sumber. Tidak ada permintaan Google Places baru. Batch ini tidak mengubah dataset Google/Jev 982 tempat.

Batch selesai dengan 23 ekstraksi dan tujuh no_source. Ada 40 halaman unik yang berhasil diambil dan 65 usulan field berstatus supported. Pemeriksaan sebagian keluaran mencatat 13 temuan terkait cakupan waktu, jadwal yang tidak lengkap, dan rujukan yang perlu diperbaiki. Seluruh data baru masih berada pada antrean telaah dan belum ditandai eligible untuk aplikasi. Model menyelesaikan 46 percobaan, termasuk 23 retry; median total proses per tempat 30,64 detik. Biaya respons tidak dilaporkan. Lihat [laporan batch](campaigns/jaksel-expansion-30-2026-11-10/REPORT.md).

~~~sh
python3 -B pilot.py collect --campaign jaksel-expansion-30-2026-11-10
python3 -B pilot.py infer --campaign jaksel-expansion-30-2026-11-10 --provider giovanc
python3 -B summarize_campaign.py --campaign jaksel-expansion-30-2026-11-10
~~~

--campaign memisahkan targets.json, .local/evidence.json, kunci proses, dan results dari benchmark lama. Inferensi memproses semua target secara default dan tetap dapat dibatasi dengan --limit. Koleksi ulang ditolak setelah kampanye memiliki hasil ekstraksi, untuk menjaga bukti yang menjadi dasar hasil. Buat kampanye dengan nama baru untuk sumber baru. Inferensi dapat dilanjutkan dari checkpoint dengan perintah yang sama.

summarize_campaign.py menghitung cakupan dan menulis results/summary.json serta results/review-queue.json. Antrean mencantumkan klaim model, potongan pendukung, URL, hash halaman, tanggal pengambilan, ID sumber peta, dan catatan cabang/waktu. Data yang belum ditelaah dan pin yang belum diverifikasi belum ditandai eligible untuk aplikasi. Skor akurasi tidak dihitung pada batch baru karena tidak ada acuan evaluasi independen yang dibekukan. evaluate.py tetap ditujukan untuk benchmark lama.

## Ekstraksi aktif melalui luna-provider.example

Perintah infer membaca endpoint, model, dan key dari konfigurasi privat Preference Lab yang sudah tersedia. Provider yang dipilih adalah https://luna-provider.example/v1 dengan model cx/gpt-6-luna(max). Alias respons yang diterima adalah gpt-6-luna(max). Kunci dipakai pada header permintaan melalui stdin curl. Metadata hasil menyimpan ID model yang diminta dan ID yang dilaporkan.

~~~sh
python3 -B pilot.py infer --provider giovanc
python3 -B evaluate.py
python3 -B compare.py
~~~

Ketujuh field, status, tipe nilai, ID bukti, dan finish_reason stop harus lolos validasi. Kegagalan diulang dengan model yang sama dan disimpan dalam checkpoint. Hasil berada di results/giovanc/. Tidak ada pergantian ke model cadangan. Endpoint ini belum melaporkan biaya pada respons yang telah diterima, sehingga biaya dicatat sebagai unknown.

Adaptor menambahkan instruksi JSON dan skema ke prompt serta menghilangkan parameter temperature sesuai pola integrasi endpoint yang sudah ada. Source, prompt ekstraksi utama, acuan evaluator, dan skema bidang tetap memakai snapshot pilot yang dibekukan. Nemotron dan endpoint ini memakai cap keluaran 1.600 token, sedangkan run Qwen terdahulu memakai 700 token. Perbandingan ini adalah satu kampanye ekstraksi terkontrol dengan perbedaan runtime dan wrapper provider yang dinyatakan.

## Perbandingan tiga run, 10 November 2026

Ketiganya menggunakan 24 kandidat dan snapshot potongan sumber yang sama. Ada 17 kandidat dengan bukti dan tujuh no_source. Skor ekstraksi dibatasi pada sembilan tempat beracuan yang benar-benar masuk model, sebanyak 63 field. Tujuh field tanpa sumber tidak menambah skor model. Arsip Qwen dan Nemotron serta hash bukti dan acuan tidak berubah.

| Ukuran | Qwen lokal Q4 | Nemotron OpenRouter | luna-provider.example |
| --- | ---: | ---: | ---: |
| Ekstraksi berhasil | 17/17 | 17/17 | 17/17 |
| Status sesuai acuan | 60/63 | 57/63 | 57/63 |
| Fakta didukung yang ditemukan | 17/20 | 19/20 | 20/20 |
| Klaim non-unknown saat acuan unknown | 0 | 5 | 6 |
| Median waktu per tempat, termasuk retry | 14,70 dtk | 3,30 dtk | 36,11 dtk |
| Jumlah waktu proses 17 tempat | 273,74 dtk | 61,34 dtk | 628,51 dtk |
| Percobaan / retry kampanye | 17 / 0 | 18 / 1 | 34 / 17 |
| Pemeriksaan kontrol sintetis benar | 7/7 | 7/7 | 7/7 |

Run luna-provider.example meminta cx/gpt-6-luna(max) dan seluruh respons berhasil melaporkan alias gpt-6-luna(max). Tidak ada fallback pada klien. Semua tempat membutuhkan satu retry karena kategori invalid_schema_or_evidence. Log kategori ini menggabungkan kesalahan parsing JSON, bentuk skema, dan kontrak rujukan. Respons gagal tidak diarsipkan, sehingga penyebab yang lebih spesifik tidak dapat disimpulkan dari run ini. Median permintaan yang akhirnya berhasil adalah 15,00 detik. Dua kontrol sintetis dijalankan terpisah setelah kampanye, dengan tiga percobaan termasuk satu retry, dan tidak masuk angka waktu atau percobaan tabel.

Model endpoint baru memulihkan identitas Nyi Ageng Serang yang terlewat pada dua run terdahulu, tetapi belum menjaga batas bukti cabang dan waktu secara konsisten. Misalnya, identity Periplus Lotte diberi supported walaupun nilai keluarannya sendiri menyatakan cabang Lotte belum terkonfirmasi. Klaim kegiatan di sana memakai keterangan umum merek. Jam kontak umum One Fifteenth diterapkan ke Kemang, daftar lokasi/jam Gramedia dijadikan dukungan akses publik, dan fasilitas RPTRA dari berita lama dijadikan kegiatan saat ini. Enam klaim ini memerlukan bukti tambahan atau status unknown menurut acuan pilot. Sejumlah nilai juga ditulis dalam bahasa Inggris meskipun prompt meminta bahasa Indonesia; pemeriksa struktur tidak memvalidasi bahasa.

Dalam sampel ini Qwen paling konservatif terhadap klaim tambahan, Nemotron paling cepat, dan konfigurasi luna-provider.example menemukan seluruh fakta didukung acuan dengan waktu proses dan jumlah retry tertinggi. Status yang sesuai belum membuktikan bahwa seluruh isi nilai dan sitasinya tepat. Biaya respons berhasil Nemotron dilaporkan USD 0. Qwen berjalan lokal tanpa biaya API berbayar, dengan biaya perangkat dan energi tidak diukur. luna-provider.example tidak melaporkan biaya, termasuk untuk percobaan gagal, sehingga penghematan biaya belum dapat dinilai.

Ini membandingkan ekstraksi dari bukti yang dibekukan. Belum menguji pencarian URL, browsing oleh LLM, ketepatan pin, atau kualitas rekomendasi aplikasi. Satu sampel purposif dan satu acuan reviewer membatasi generalisasi. Perbedaan cap keluaran, prompt wrapper, parameter provider, dan runtime membuat hasil ini perbandingan konfigurasi provider/model yang tersedia, bukan isolasi pengaruh provider saja. Perbandingan dapat dihitung ulang tanpa API lewat compare.py. Rincian berada di [results/comparison.json](results/comparison.json), [results/giovanc/extraction.json](results/giovanc/extraction.json), [results/giovanc/summary.json](results/giovanc/summary.json), dan [results/giovanc/controls.json](results/giovanc/controls.json).

## Ekstraksi melalui OpenRouter

Opsi --provider openrouter memakai nvidia/nemotron-3.5-super-vl:free. Seluruh tujuh field, status, tipe nilai, dan ID bukti harus lolos validasi sebelum hasil disimpan sebagai berhasil. Permintaan juga harus selesai dengan finish_reason stop, melaporkan model yang diminta, dan mencatat biaya nol.

Jika transport, provider, JSON, skema, atau rujukan gagal, pipeline mengulang ke model yang sama sampai berhasil. Jeda antarpermintaan minimal 3,2 detik. Jeda retry bertambah sampai 60 detik dan mengikuti Retry-After yang lebih panjang. Fallback provider dimatikan dan hanya satu ID model dikirim. Hasil yang sudah tersimpan dilanjutkan dari checkpoint setelah proses terputus. Kunci proses mencegah dua kampanye menulis checkpoint yang sama.

Hasil OpenRouter berada di [results/nemotron/extraction.json](results/nemotron/extraction.json) dan [results/nemotron/summary.json](results/nemotron/summary.json). Berkas di results/extraction.json serta results/summary.json merekam kampanye Qwen sebelumnya.

~~~sh
python3 -B pilot.py infer --provider openrouter
python3 -B evaluate.py --extraction results/nemotron/extraction.json
python3 -B -m unittest test_openrouter -v
~~~

Kredensial dibaca dari OPENROUTER_API_KEY atau konfigurasi privat Context Lab yang sudah ada. Yang dikirim ke provider adalah nama dan petunjuk cabang beserta potongan halaman publik. Kebijakan data mengikuti pengaturan akun OpenRouter. Filter request data_collection deny yang ditambahkan pada preflight menyebabkan HTTP 404 pada endpoint model gratis; kontrol sintetis memakai routing akun berhasil. Enam percobaan preflight itu disimpan terpisah dalam results/nemotron/preflight-rejected.json. [Pengaturan routing OpenRouter](https://openrouter.ai/docs/guides/routing/provider-selection)

Lolos format dan rujukan berarti kontrak keluaran terpenuhi. Ketepatan isi fakta tetap dinilai terhadap sumber.

Run Nemotron selesai dengan 17 hasil ekstraksi dari 18 percobaan. Keluaran Erasmus Huis pada percobaan pertama gagal validasi, kemudian berhasil lewat model yang sama. Tujuh kandidat yang tidak memiliki potongan sumber mendapat status no_source. Biaya 17 respons berhasil yang dilaporkan provider adalah USD 0. Median permintaan berhasil 3,16 detik; median total proses per tempat 3,30 detik termasuk pacing dan retry. Jumlah waktu proses per tempat 61,34 detik. Enam kegagalan preflight routing dan dua kontrol konektivitas sintetis berada di luar angka kampanye 18 percobaan.

Pada sembilan tempat beracuan yang benar-benar masuk model, 57 dari 63 status sesuai acuan, dibanding 60 dari 63 pada Qwen. Nemotron memulihkan 19 dari 20 fakta berstatus didukung, dibanding 17 pada Qwen, sekaligus menghasilkan lima status didukung ketika acuan masih unknown. Contohnya jam harian pada kontak umum One Fifteenth Coffee diterapkan ke cabang Kemang, dan kontak lewat email/telepon disebut kegiatan pengunjung. Kegiatan herbal RPTRA dari berita lama juga dianggap kegiatan saat ini. Kasus-kasus itu memerlukan telaah isi meskipun JSON dan ID rujukannya valid.

## Input dan keluaran

- [targets.json](targets.json) membekukan 24 kandidat, ID sumber terbuka, dan tautan awal yang diperiksa. Kandidat dipilih secara purposif dan mencakup cabang serupa, venue tanpa sumber resmi yang ditemukan, dan satu kandidat dengan catatan delivery-only.
- [results/source-audit.json](results/source-audit.json) menyimpan asal kandidat, hash snapshot, status pengambilan, URL, serta tanggal cek. Input nama dan koordinat berasal dari snapshot Jakarta Selatan yang sudah tersedia di workspace. Halaman resmi diambil langsung pada putaran ini.
- Potongan bukti dan ID lokalnya berada di .local/evidence.json. Berkas lokal ini diabaikan Git. Laporan menyimpan sumber dan ringkasan temuan.
- [results/manual-reference.json](results/manual-reference.json) adalah acuan berbasis potongan yang sama untuk sepuluh tempat. Satu reviewer menyiapkannya sebelum inferensi. Ini menguji ekstraksi dan penanganan ketidakpastian, bukan ketepatan di lapangan atau kesesuaian hasil dengan selera pengguna.
- [results/extraction.json](results/extraction.json) menyimpan usulan model dan rujukannya. [results/summary.json](results/summary.json) membandingkan status dan memisahkan hasil tanpa sumber dari inferensi aktual.
- [results/reviewed-shortlist.json](results/reviewed-shortlist.json) menyimpan empat kandidat yang lolos telaah awal dan perbaikan terhadap keluaran model. [results/controls.json](results/controls.json) menyimpan dua kontrol sintetis.

Katalog sumber mencantumkan ID dan atribusi. Data OpenStreetMap © kontributor OpenStreetMap, tersedia dengan ODbL. Overture Places memiliki ketentuan menurut sumbernya. Periksa aturan distribusi sebelum menerbitkan dataset gabungan. [Lisensi OpenStreetMap](https://www.openstreetmap.org/copyright), [lisensi Overture](https://docs.overturemaps.org/guides/places/)

## Cara menjalankan ulang

Python membutuhkan Beautiful Soup 4. Kolektor memakai HTTPS, domain awal yang dipilih, robots.txt, jeda per domain, maksimum dua halaman awal dan satu tautan lanjutan yang lolos seleksi. Pemilihan tautan dilakukan dengan aturan. Model membaca potongan yang sudah dikumpulkan dan menghasilkan JSON dengan rujukan ID yang divalidasi.

Gunakan file MTP Q4_K_M pada revisi Hugging Face d5f3139249b7ee2535c20ab81125c9a6ab0c4915. Ukurannya 6.979.975.392 byte dan SHA-256 d7eb4fac9389d53fa576f64a6ff53e914a00bc7705dc354d1065887565147320. Runtimenya llama.cpp b12244 pada Apple M5, konteks 4.096, reasoning off, temperature 0. Putaran ini menjalankan bobot utama dari file MTP dengan speculative decoding nonaktif. Ollama 0.19.0 dapat mengimpor artefaknya tetapi gagal menginisialisasi tensor layer 32 ketika diminta menghasilkan keluaran. [File GGUF](https://huggingface.co/DavidAU/Qwen3.5-9B-The-Defiant-Fable-Uncensored-Heretic-NEO-IMATRIX-MAX-MTP-GGUF/tree/d5f3139249b7ee2535c20ab81125c9a6ab0c4915), [llama.cpp b12244](https://github.com/ggml-org/llama.cpp/releases/tag/b12244)

Jalankan dari folder pilot. Jalur model merujuk ke berkas GGUF yang sudah diunduh.

~~~sh
llama-server -m /path/to/model-Q4_K_M.gguf --host 127.0.0.1 --port 14948 \
  -c 4096 -ngl 99 -np 1 --jinja --reasoning off
python3 -B pilot.py infer --provider local
python3 -B evaluate.py --extraction results/extraction.json
~~~

Untuk kampanye baru, sediakan targets.json pada folder campaigns/nama-batch/ lalu jalankan collect dan infer dengan --campaign nama-batch. Jika ingin benchmark baru, bekukan acuan manual sebelum inferensi. Evaluator benchmark lama memeriksa hash untuk mencegah pencampuran hasil dengan kumpulan bukti yang berbeda.

## Hasil Qwen lokal, 10 November 2026

Putaran final memperoleh potongan sumber untuk 17 dari 24 kandidat. Tujuh kandidat tetap tanpa bukti, terdiri dari empat yang jalur aksesnya diblokir kolektor dan tiga yang tidak memiliki tautan resmi dalam input. Ada 42 permintaan HTTPS termasuk robots.txt. Crawl final berjalan 11,8 detik dengan lima pekerja. Penemuan URL awal dan telaah manual mempunyai biaya waktu terpisah.

Model menyelesaikan 17 ekstraksi. Median inferensi 14,7 detik per tempat dan total waktu inferensi 273,7 detik. Semua keluaran lulus pemeriksaan skema dan ID rujukan. Tidak ada biaya panggilan ke API Places atau model berbayar.

Pada sembilan tempat yang benar-benar masuk model dalam sampel telaah, 60 dari 63 status sesuai acuan. Model memulihkan 17 dari 20 status yang didukung. Tiga identitas terlewat, yakni One Fifteenth Coffee Kemang, Perpustakaan Nyi Ageng Serang, dan RPTRA Taman Sawo. Tempat ke-10 tidak memiliki sumber dan mendapatkan tujuh status unknown lewat aturan, sehingga skor workflow menjadi 67/70. Dari 17 klaim dengan status didukung yang sesuai, 13 dapat dipakai sebagaimana ditulis dan empat perlu pemotongan isi atau rujukan yang lebih langsung. Waktu inferensi pada sampel telaah 156,2 detik, sekitar 12 detik per klaim yang dapat dipakai sebagaimana ditulis. Waktu reviewer tidak diukur secara terkontrol.

Kedua kontrol sintetis menghasilkan status yang benar untuk izin dan larangan eksplisit membaca sambil minum kopi. Pada data nyata pilot, tidak ada potongan yang membuktikan syarat itu. Katalog terkurasi masih perlu mengecek pin dan keadaan pada hari kunjungan sebelum dipakai untuk itinerary.
