# Evaluasi user simulasi terhadap PoC personal

Eksperimen dimulai 8 November 2026, Asia/Jakarta. User meminta assistant menjadi user simulasi dan menjalankan aplikasi. Tiga kebutuhan dibekukan sebelum hasil baru dilihat; hash dan batas penilaian ada pada [protokol](SYNTHETIC_USER_PROTOCOL_2026-11-08.md) serta `artifacts/synthetic-user-2026-11-08/frozen-briefs.json`.

## Cara membaca hasil

Ini evaluasi tiga persona buatan oleh assistant yang juga mengetahui implementasi. Bukan bukti kepuasan manusia, bukan penilaian buta, bukan benchmark populasi, dan bukan integrasi AnyJev. Narasi orang pertama di bawah adalah peran yang dimainkan, bukan pengalaman pribadi atau kunjungan lapangan.

Engine, prompt LLM dan perilaku UI tidak dituning selama evaluasi. Profil normal pengguna tidak dihapus; kampanye memakai penyimpanan profil UI-test terpisah. Server lama ditemukan tidak hidup, catatan PID diarsipkan setelah pemeriksaan dan server dipulihkan. Build koneksi diperbarui. Gangguan kesiapan ini dicatat terpisah dari waktu rekomendasi.

Ada dua pertanyaan terpisah: apakah aplikasi memenuhi bagian kebutuhan yang dapat dimasukkan, dan apakah hasil memenuhi keseluruhan keinginan user. “Unknown” bukan berarti salah, tetapi syarat wajib yang belum diketahui menghalangi penerimaan tanpa syarat. Kelulusan harness hanya berarti langkah pemeriksaan dijalankan, bukan berarti rekomendasi diterima.

## Persona U1 — Membaca dan ngopi tenang

**Keinginan sebelum hasil:** membaca90 menit di tempat duduk yang cukup tenang, kopi45 menit jika sempat, anggaran kegiatanRp150.000, Cikini/Menteng10.00–16.00, mobil dan kembali ke asal, menunggu maksimal15 menit. Profil Membaca+Kopi, ritme Santai.

**Yang dapat dimasukkan:** minat, ritme, area, tanggal dan jendela perjalanan. Durasi serta menunggu tersedia setelah memilih tempat. Kebutuhan tempat duduk, ketenangan dan anggaran tidak tersedia sebagai input normal rekomendasi.

**Hasil live:** enam kandidat: Flash Coffee Menteng Huis; Pelopor Books Menteng; ARAH Coffee Cikini; Galeri Buku Bengkel Deklamasi; Kopi Tarik Edwin Premium Cikini; Perpustakaan Jakarta dan Pusat Dokumen Sastra HB Jassin/Cikini. Ketiga minat membaca ditempati dua `book_store` lalu satu `library`. Saya memilih library sebagai bukti kegiatan yang lebih mendekati membaca di tempat, bukan menerima toko buku sebagai bukti tempat duduk. Flash Coffee dipilih sebagai kegiatan tambahan untuk diagnosis.

**Hambatan:** Google library dipadankan ke Apple Jakarta Provincial Library, alamatJalan Cikini Raya 73, beda pin sekitar63 m. Tombol konfirmasi dinonaktifkan karena nama tidak cocok menurut guard. Pencarian ulang dengan alias Perpustakaan HB Jassin Cikini menghasilkan padanan yang sama dan tetap ditolak. Ini kandidat masalah alias/entitas gabungan; kedekatan dan alamat belum menjadi bukti lapangan bahwa bagian aktivitasnya sama. Guard tidak dilewati, tidak diganti toko buku yang kurang didukung hanya supaya itinerary jadi.

**Penilaian sebagai user:** “Saya menemukan perpustakaan yang lebih relevan daripada toko buku, tetapi belum bisa memastikan tempat duduk, ketenangan atau biaya. Saya juga tidak bisa melanjutkan pilihan perpustakaan. Saya belum menerima perjalanan ini sebagai memenuhi kebutuhan saya.” Rekomendasi bersyarat; itinerary tidak tercapai. Detail U1 ada di `U1-judgment.json` dan UI captures.

**Temuan tambahan tampilan:** ARAH Coffee menampilkan00:00–00:00. Itu belum membuktikan jam rusak—bisa merupakan interval ke hari berikutnya—tetapi UI tidak menjelaskan tanggal atau “24jam”, sehingga ambigu bagi pengguna.

## Persona U2 — Seni dan fotografi arsitektur

**Keinginan sebelum hasil:** seni indoor60 menit sebagai kegiatan utama, fotografi bangunan45 menit jika sempat dan diutamakan mulai15.00–16.00, akses serta izin foto diketahui, Kota Tua13.00–19.00, kembali ke asal, menunggu maksimal15 menit.

**Yang dapat dimasukkan:** minat Seni+Arsitektur, area, tanggal dan waktu. Input khusus indoor sebagai kebutuhan rekomendasi, izin fotografi dan aktivitas memotret belum tersedia. Toggle waktu15–16 baru ada pada tempat terpilih; bukan bagian kebutuhan yang dikirim pada tahap rekomendasi. Tipe paparan dapat diisi kemudian tetapi harus berdasarkan fakta yang diketahui, bukan mengarangnya dari label galeri.

**Hasil live:** dua kandidat: Batavia Galeri & Kafe (`art_gallery`) dan Museum Seni Rupa dan Keramik (`art_museum`). Tidak ada kandidat dengan dukungan kategori arsitektur, bahkan dalam fakta kandidat yang dikirim ke LLM. Artinya keragaman tidak bisa dipenuhi dari pool ini; bukan bukti bahwa Kota Tua tidak memiliki bangunan yang sesuai. LLM tidak dapat memilih kandidat yang tidak disediakan. Di bawah aturan pilihan yang dibekukan, Batavia menjadi tujuan wajib diagnosis. Padanan Apple dengan nama sama, beda pin tampilan0m, dapat dikonfirmasi.

**Hambatan:** asal yang dicari Stasiun Jakarta Kota menghasilkan Google Jakarta Kota diJl.Lada. Hasil Apple yang dikembalikan antara lain Monumen Proklamator Soekarno-Hatta, Rumah Sakit Agung, YELLO Hotel Manggarai dan Manggarairailwaystation, sekitar8,1–9km dari pilihan. Semuanya ditolak. Tidak ada bypass dan tidak ada itinerary utama. Ini kegagalan menuntaskan identitas asal, bukan bukti bahwa semua rute dari Jakarta Kota mustahil.

**Penilaian sebagai user:** “Pilihan seni masuk akal untuk ditinjau, tetapi kebutuhan fotografi arsitektur belum terlayani. Saya belum mendapat bukti indoor atau izin fotografi. Lokasi awal juga belum bisa dikonfirmasi.” Rekomendasi bersyarat; itinerary tidak tercapai pada percobaan utama. Detail ada di `U2-judgment.json` dan `U2-ui-observations.json`.

## Persona U3 — Kuliner vegetarian dan belanja singkat

**Keinginan sebelum hasil:** makan vegetarian60 menit, belanja produk/desain lokal atau oleh-oleh60 menit jika sempat, akses stroller tanpa tangga yang tidak dapat dihindari, anggaran makanRp100.000/orang, Blok M11.00–16.00, mobil/kembali ke asal dan menunggu maksimal15 menit.

**Hasil live:** enam kartu yang mencakup HAKA Dimsum Shop Blok M, dua ID bernama Soto KudusBlok M, Mal Blok M, Blok MPlaza dan Blok MSquare. Kategori makan/belanja didukung sumber. Menu vegetarian, harga, akses stroller dan produk lokal tidak tersedia dalam bukti yang ditampilkan. Dua nama Soto Kudus yang sama belum membuktikan entitas duplikat; perbedaan cabang perlu dijelaskan.

HAKA dipilih sebagai tujuan wajib untuk diagnosis teknis dan Mal Blok M sebagai opsional. Ini bukan persetujuan bahwa HAKA memenuhi vegetarian. Durasi60/60 dan batas menunggu15 menit benar-benar diterapkan melalui UI. Paparan tetap unknown; saya tidak mengarang klasifikasi indoor dari nama restoran/mal.

**Review identitas:** harness v2 sempat memilih Apple Hong TangPlaza Blok M sebagai asal Google Blok MPlaza karena tombolnya enabled. Itu tenant, bukan entitas mal yang dimaksud. Rencana v2 dan auditor numeriknya disimpan sebagai **bukti ditolak**. Pada v3, operator memilih hasil Apple Plaza Blok M yang juga tersedia, sekitar19 m dari pin Google. Engine/prompt tidak diubah. Oracle tambahan memeriksa kesetaraan cakupan entitas asal dan kini menolak rencana v2. Ini perbaikan cara menguji, bukan bukti bahwa guard produksi sudah menyelesaikan kasus tenant.

**Itinerary v3:** HAKA11.15–12.15, total menunggu11,15 menit, kembali12.17.09, komputasi5,230 detik dengan5 call ETA. Mal Blok M dihilangkan sebagai opsional. Tujuan wajib60 menit, batas menunggu15 menit dan waktu kembali dipenuhi. Penghilangan opsional diizinkan oleh brief, sehingga bukan pelanggaran wajib dengan sendirinya. Namun user hanya mendapat satu kegiatan dan alasan teknis `operating_hours_options` tidak menjelaskan keputusan. Alamat Apple Mal Blok M juga berbeda jalan dari alamat Google meskipun nama sama dan pin144 m; karena tidak dikunjungi, itu tidak membatalkan ruas HAKA tetapi tetap memerlukan pemeriksaan identitas/akses jika dipakai kemudian.

**Penilaian sebagai user:** “Saya bisa melihat jadwal makan yang memenuhi durasi dan batas waktu, tetapi belum tahu apakah menunya vegetarian, harganya sesuai atau aksesnya aman untuk stroller. Belanja hilang meskipun hari masih panjang, dan alasannya belum jelas. Saya belum menerima perjalanan ini tanpa pemeriksaan tambahan.” Hasil bersyarat, bukan rekomendasi yang sudah terbukti sesuai seluruh kebutuhan.

## Ringkasan hasil dan waktu

| Persona | Waktu daftar pertama | Kandidat | Hasil alur | Penilaian keseluruhan |
|---|---:|---:|---|---|
| U1 Membaca+kopi | 12,181 detik | 6 | Berhenti pada identitas perpustakaan | Bersyarat; tempat duduk/tenang/harga tidak diketahui |
| U2 Seni+arsitektur | 5,601 detik | 2 | Tujuan seni dapat dikonfirmasi; asal tidak | Bersyarat; arsitektur tidak tersedia, indoor/izin belum diketahui |
| U3 Vegetarian+belanja | 7,078 detik | 6 | Setelah koreksi harness/identitas, satu itinerary diagnostik | Bersyarat; diet/harga/akses/produk lokal belum diketahui |

U3 v1 terhenti karena helper tap memakai batas navigasi yang salah. U3 v2 mencapai itinerary tetapi asalnya tenant sehingga dibatalkan sebagai bukti. U3 v3 memperbaiki pilihan operator, dengan input kebutuhan tetap sama. Waktu daftar tambahan U3 adalah7,937 dan7,130 detik; keduanya disimpan, bukan digabung sebagai tiga pengguna baru. Lima operasi rekomendasi seluruhnya berhasil dengan E5 aktual dan LLM gratis berbiaya terlapor$0. Sampel adaptif ini bukan estimasi SLA dan tidak dibandingkan langsung dengan41,35 detik itinerary tiga tujuan sebelumnya: jumlah/tempat/constraint/ruasnya berbeda.

Sebanyak14 kartu pada tiga penilaian lengkap ditinjau (6+2+6), dengan percobaan tambahan diarsipkan. Kebutuhan ini sengaja menekan keterbatasan kategori dan bukti; bukan sampel acak pengguna. Tidak ada penerimaan tanpa syarat dari ketiga persona. Ini **tidak diterjemahkan menjadi “akurasi0%”**, karena unknown, alur terblokir dan ketidakcocokan bukan hal yang identik.

## Diagnosis tambahan tanpa mengubah engine

### Grid bisa menghilangkan kegiatan yang sebenarnya dapat dijadwalkan

Kontrol baru menggunakan dua kegiatan60 menit, jendela11.00–16.00, perjalanan tetap5 menit per ruas dan total menunggu maksimal15 menit. Semua jam aktivitas tersedia, tanpa preferensi hujan/waktu tambahan. Input sama dijalankan melalui planner opsional produksi dengan dua grid:

| Grid | Kegiatan dipertahankan | Total menunggu | Call provider sintetis |
|---|---:|---:|---:|
| 15 menit | 1 | 10 menit | 5 |
| 5 menit | 2 | 0 | 20 |

Enumerasi Python independen menemukan tidak ada jadwal dua kegiatan pada grid 15 yang memenuhi tunggu15 menit: pembulatan menghasilkan sedikitnya20 menit tunggu. Grid5/1 menemukan11.05–12.05 lalu12.10–13.10, kembali13.15, tanpa menunggu. Ini membuktikan blind spot grid pada kontrol tersebut. **Belum membuktikan bahwa persis itulah satu-satunya penyebab penghilangan mal pada traffic live**, karena ETA live berubah menurut keberangkatan. Grid5 juga membutuhkan lebih banyak evaluasi dalam kontrol; jangan menganggapnya perbaikan kecepatan.

### Alasan penghilangan dapat menyesatkan

Konteks mal memiliki interval buka yang sesuai dan status `operating_hours_options`, yang artinya opsi jam tersedia. Endpoint membentuk alasan penghilangan dengan memeriksa apakah status mengandung kata `hours`, sehingga status sukses itu ikut dipakai sebagai “alasan”. User tidak mendapat penjelasan apakah penyebabnya menunggu, pencarian, budget, atau preferensi. Ini masalah penjelasan keputusan yang dapat diperbaiki dari kode, bukan kekurangan data eksternal.

### Guard identitas terlalu ketat sekaligus terlalu longgar

Kontrol fungsi nama mereproduksi bahwa alias perpustakaan ditolak dan nama tenant yang mengandung nama mal diterima. Dua tes diagnosis lolos karena **berhasil mereproduksi keterbatasan**, bukan karena perilakunya benar. Guard jarak/nama tidak boleh dianggap verifikasi entitas final. Perbaikan membutuhkan pemisahan kompleks vs tenant, alias yang bersumber, pemeriksaan alamat, serta mekanisme konfirmasi ketidakpastian yang tetap menolak entitas berbeda.

## Mengapa temuan ini bukan sekadar kesalahan LLM

- Kategori membaca menyatukan membeli buku dan membaca di tempat. LLM tidak menerima syarat tempat duduk/ketenangan, sehingga hasilnya tidak boleh dipakai untuk mengklaim telah memenuhi syarat tersebut.
- U2 tidak memiliki kandidat arsitektur sebelum LLM. Memperbaiki judge saja tidak memperbaiki kekurangan kandidat.
- Pemeriksaan identitas mencegah padanan salah tetapi juga dapat menghalangi padanan alias yang mungkin benar. Membuka guard begitu saja menghidupkan kembali risiko kedai tetangga/museum berbeda yang ditemukan pada kampanye sebelumnya.
- Jam buka dan kategori bukan bukti menu, harga, indoor, akses atau izin. Sumber fakta yang lebih lengkap dan cara menangkap kebutuhan diperlukan sebelum ranking dapat dinilai atas aspek-aspek itu.

Tidak ada angka akurasi gabungan yang dihitung dari tiga persona ini. Bukti kepatuhan aturan, pendapat user simulasi, ketersediaan provider dan ketepatan lapangan tetap dipisahkan.

## Prioritas setelah eksperimen

1. **Tangkap kegiatan dan syarat yang menentukan penerimaan.** Bedakan membaca di tempat vs membeli buku; diet, kebutuhan akses dan budget bukan sekadar kategori. Pertanyaan tambahan diberikan saat relevan, tidak harus memperpanjang onboarding semua orang.
2. **Hubungkan syarat itu dengan fakta yang dapat dibuktikan.** Jika bukti belum tersedia, tampilkan “belum diketahui” pada syarat spesifik dan minta verifikasi; jangan menganggap kategori sebagai bukti fasilitas/menu/izin.
3. **Perbaiki identitas kompleks/tenant/alias dan alasan penghilangan.** Kasus baru masuk daftar regresi. Pemeriksaan yang terlalu longgar dan terlalu ketat harus diuji bersama agar satu perbaikan tidak menghidupkan kesalahan lainnya.
4. **Uji kandidat waktu berbasis kejadian** (waktu tiba/jam buka), dengan validasi ETA final, terhadap kontrol grid tadi dan input live berpasangan. Mengganti grid saja dapat menambah biaya evaluasi.
5. Setelah input dan bukti tersedia, bandingkan ranking E5/kategori, LLM sekarang dan calon AnyJev pada brief/fakta yang sama, dengan penilaian manusia terpisah. Menambah judge belum menyelesaikan kebutuhan yang tidak pernah dikirim atau kandidat yang tidak pernah ditemukan.

Sinyal learning juga perlu hati-hati: membuka kartu untuk mengecek ketidakcocokan atau memilih tempat untuk diagnosis bukan persetujuan pengguna. Kampanye memakai profil uji terpisah; event-event tersebut tidak boleh dijadikan label bahwa persona menyukai tempat yang diklik.

## Bukti dan reproduksi

- `frozen-briefs.json` dan SHA-256: kebutuhan tidak ditulis ulang setelah hasil.
- `ui-captures.json`, `U1-judgment.json`, `U2/U3-ui-observations.json`, xcresult serta screenshot: observasi dan penilaian per langkah.
- `recommendations.json`/`benchmark.csv`: seluruh5 operasi, termasuk pengulangan harness.
- `U3-plan.json`: rencana final dengan asal mal; `U3-plan-rejected-tenant-origin.json` dan `audit-before-tenant-identity-review.json`: percobaan yang ditolak.
- `independent-audit.json`: pemeriksaan input, E5/model/cost/bukti, identitas asal, serta aritmetika jadwal. Auditor memasukkan kontrol negatif tenant setelah review visual; ini bukan holdout yang belum disentuh.
- `diagnostic-grid.json`, `grid-independent-reference.json`, `diagnostic-identity.json`, `diagnostic-tests.log`: diagnosis terkontrol terpisah dari live.
- Hash58 file engine/UI diperiksa tetap sama. Yang ditambahkan adalah harness, skrip audit/ekspor, artefak dan laporan; tidak ada tuning ranking, perubahan provider, commit, push atau deployment.

Jalankan `scripts/export-synthetic-user.py` untuk mengekspor kampanye dari container simulator terbaru, lalu `scripts/audit-synthetic-user.py`. UI persona berada di `ContextHarness/UITests/SyntheticUserUITests.swift`. Tes diagnosis terpisah: `swift test -j 4 --filter SyntheticUserDiagnosticsTests`, dengan `SYNTHETIC_USER_DIAGNOSTICS_OUTPUT` menunjuk folder artefak bila ingin menyimpan outputnya. Hasil per provider dan kondisi lapangan dapat berubah.
