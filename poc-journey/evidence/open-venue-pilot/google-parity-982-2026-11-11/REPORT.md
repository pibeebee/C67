# Perbandingan Google Places dan OSM/Overture pada 982 kandidat C67

11 November 2026 WIB. Eksperimen lokal dengan dua pembandingan. Yang pertama mempertahankan roster Google untuk mengukur cakupan dan menyandingkan keluaran pada tempat yang sama. Yang kedua memulai penemuan dari OSM dan Overture dengan target volume yang sama.

## Pasangan tempat

| Roster Google historis | ID unik | Diterima dan berlabel di arsip | Pasangan terbuka terkonfirmasi | Pasangan dari baris Google yang berlabel |
|---|---:|---:|---:|---:|
| Batch Jakarta Selatan | 500 | 238 | 94 | 69 |
| Batch Jakarta lebih luas | 482 | 250 | 149 | 115 |
| Total | 982 | 488 | 243 | 184 |

Dari 982 ID, 548 belum memiliki kandidat pada kedua snapshot dengan aturan pencarian ini, 127 memiliki kandidat yang gagal terkonfirmasi, dan 64 tetap ambigu. Sebanyak 434 ID mendapat setidaknya satu calon padanan. Identitas terkonfirmasi untuk 243 ID, atau 24,7% dari roster. Di kelompok yang terpasang, proporsi baris dengan label Google lebih tinggi daripada pada roster penuh, sehingga kelompok ini tidak mewakili semua 982 kandidat. Angka ini mengukur cakupan gabungan snapshot dan prosedur padanan yang dipakai. ID unik dan dua hasil identitas konsisten belum memastikan deduplikasi fisik atau ketepatan pin.

Jev memproses 243 pasangan terbuka. Satu pasangan tidak memiliki keputusan Jev historis karena status geografis Google, sehingga tabel keluaran memakai **242 pasangan yang sama**.

| Sumber bukti dan penyaring Jev | Diterima | Ditolak | Bukti belum cukup | Diterima dan berlabel | Total label |
|---|---:|---:|---:|---:|---:|
| Google Places, arsip penyaring asli | 185 | 0 | 57 | 184 | 531 |
| OSM/Overture + web, penyaring asli | 18 | 1 | 223 | 5 | 11 |
| OSM/Overture + web, empat pemeriksaan | 6 | 0 | 236 | 5 | 11 |

Kedua cara penyaringan terbuka memberi label pada lima tempat yang sama. Kesebelas penetapan label tersebut juga muncul di arsip Google untuk tempat yang sama. Jumlah label dan kesepakatan antarjalur mengukur keluaran katalog, sementara kebenaran label, akurasi pin, kecocokan preferensi, dan urutan rekomendasi memerlukan acuan independen.

Perbedaan terbesar ada pada bukti. Dari 243 pasangan, 224 hanya memiliki tag peta, 11 juga mendapat potongan halaman yang menyebut cabang, dan delapan memakai catatan sumber publik yang sudah diperiksa. Kelima tempat yang berlabel memiliki catatan publik yang diperiksa. Kolektor mencoba 58 tautan, memperoleh 32 halaman, dan mengirim 98 permintaan web termasuk pemeriksaan robots.txt. Hasil mengukur kemampuan metode pengumpulan ini. Penelusuran publik yang lebih luas bisa menemukan bukti yang terlewat.

Museum Betawi mendapat `museum` dan `indoor` dari kedua jalur. Google juga memberi `outdoor` dan `heritage`; dua label tambahan ini membutuhkan validasi tersendiri. RPTRA Taman Sawo memperoleh tiga label yang sama, yaitu `park`, `outdoor`, dan `children_play_area`. One Satrio memperoleh `outdoor`, `walking_path`, dan `children_play_area` dari kedua jalur, dengan label Google tambahan `food_court` dan `garden_seating`. Contoh tersebut menggambarkan selisih keluaran, dengan hasil sumber publik tersimpan di bukti lokal.

## Roster terbuka dengan volume setara

Kandidat kedua dimulai dari data peta independen. Batch 500 memakai enam jendela dan pasangan kategori/jendela yang digunakan pada eksperimen Jakarta Selatan. Batch 482 memakai enam jendela dan urutan kategori pencarian Jakarta lebih luas. Pemetaan kategori OSM dan Overture mengatur pencarian kandidat, sementara keputusan kelayakan dan label ditentukan Jev. Urutan dalam setiap halaman ditetapkan dengan hash deterministik, dan rekaman dengan nama normalisasi yang sama dalam 95 meter digabung sebelum pemilihan. Kueri peta terbuka memiliki pengurutan dan taksonomi sendiri.

Aturan halaman pertama menyediakan 479 kandidat untuk batch pertama. Sebanyak 21 slot diisi dari kandidat berikutnya di jendela dan kategori yang sama. Pada batch kedua, jendela Kepulauan Seribu menghasilkan 30 kandidat. Sebanyak 32 slot dialihkan ke daratan agar jumlah tetap 482. Distribusi akhir menurut jendela pemilihan adalah Jakarta Pusat 91, Barat 91, Utara 90, Timur 90, Selatan 90, dan Kepulauan Seribu 30. Setelah aturan batas untuk batch luas diterapkan, 39 kandidat tetap di roster dengan status luar wilayah atau batas belum terverifikasi. Penamaan jendela dan posisi OSM/Overture belum membuktikan letak pintu masuk.

Dari 943 kandidat yang masuk proses Jev, 27 mendapat potongan halaman yang menyebut cabang. Kolektor mencoba 149 tautan, memperoleh 70 halaman, dan mengirim 195 permintaan web termasuk robots.txt. Kandidat ini memakai hasil pengumpulan otomatis dan tag peta. Catatan manual yang dipakai pada delapan pasangan di uji pertama tidak ditambahkan ke roster independen.

| Roster dan penyaring Jev | Kandidat | Diterima | Ditolak | Bukti belum cukup | Batas luar/belum terverifikasi | Diterima dan berlabel |
|---|---:|---:|---:|---:|---:|---:|
| Google Places historis, penyaring asli | 982 | 545 | 6 | 412 | 19 | 488 |
| OSM/Overture + web, penyaring asli | 982 | 16 | 2 | 925 | 39 | 1 |
| OSM/Overture + web, empat pemeriksaan | 982 | 2 | 3 | 938 | 39 | 1 |

Masing-masing penyaring terbuka menghasilkan satu kandidat berlabel, dengan tempat berbeda: Hanamasa pada penyaring asli dan Yakiniku Like pada penyaring empat pemeriksaan. Keduanya mendapat dua label, `restaurant` dan `japanese_cuisine`. Batch Jakarta Selatan menyumbang satu dari 500 kandidat terbuka berlabel, dibandingkan 238 dalam arsip Google pada ukuran yang sama. Batch lebih luas menyumbang nol dari 482, dibandingkan 250 dalam arsip Google. Hasil menunjukkan cakupan data siap label pada alur yang diuji. Perbandingan per tempat tetap memakai tabel pasangan karena kedua roster berukuran 982 berisi tempat yang berbeda.

Uji volume mengirim 1.903 panggilan Jev sukses dari 1.911 percobaan dan biaya yang dilaporkan US$0,178910088. Gabungan kedua uji mencatat 2.407 panggilan sukses dan biaya Jev US$0,227816484. [Ringkasan uji volume](volume-summary.json)

## Protokol dan batas

- Google memakai arsip gabungan 10 November 2026. Kedua batch historis memakai Jev `typesafe/jev-1.14-20261014` untuk keputusan dan label. Eksperimen terbuka memverifikasi versi model yang sama, memakai kebijakan katalog, taksonomi 62 label, ambang kelayakan 0,80 dan ambang label 0,90 yang sama. Kedua penyaring terbuka berbagi hasil penilaian label pada bukti yang sama. Empat pemeriksaan menilai identitas, akses, kegiatan dan pengecualian, lalu menggabungkannya dengan aturan tetap.
- Padanan privat memakai shortlist nama dan, untuk batch kedua jika tersedia, jarak. Koordinat Google dipakai untuk pembandingan jarak privat pada tahap pemadanan. Kueri verifikasi hanya memakai nama, alamat petunjuk dan koordinat dari kandidat independen, meminta respons `places.id`, dan menerima hasil konsisten dari dua variasi kueri. Sebanyak 85 tautan sumber historis ikut dipakai setelah pemeriksaan kompatibilitas nama. Sebanyak 659 kandidat diuji dengan IDs Only, dengan sembilan kandidat ambigu dicek ulang memakai konteks DKI Jakarta. Kesembilannya tetap ambigu. Dua ID yang dikembalikan di luar shortlist nama tidak dipasangkan. Tidak ada panggilan Google Place Details baru. [Dokumentasi Place ID](https://developers.google.com/maps/documentation/places/web-service/place-id) · [Tarif IDs Only](https://developers.google.com/maps/billing-and-pricing/pricing)
- Snapshot Overture Places rilis 2026-10-21.0 memakai kotak 106.47, -6.36, 106.98, -5.54 dan menghasilkan 323.406 rekaman yang memenuhi pemeriksaan lisensi dan nama. OSM memakai Overpass pada jendela Jakarta daratan dan Kepulauan Seribu dengan 5.157 rekaman bernama. Kotak unduhan mencakup area sekitar Jakarta. Ketentuan distribusi mengikuti lisensi sumber per rekaman. [Dokumentasi Overture Places](https://docs.overturemaps.org/guides/places/) · [OpenStreetMap dan ODbL](https://www.openstreetmap.org/copyright)
- Masukan Jev berasal dari bukti independen. Arsip Google dipakai untuk pencocokan dan pembanding keluaran lokal. Jalur independen memakai data OSM/Overture dan bukti publiknya sendiri. Penggunaan data Google sebagai bahan katalog atau penilaian model terpisah dari benchmark keluaran ini. [Ketentuan Google Maps Platform](https://cloud.google.com/maps-platform/terms)
- Pada eksperimen pilot terdahulu, pembacaan catatan manual hanya merangkai field `context` dan melewatkan `text`. Benchmark ini membawa kedua field catatan yang tersedia pada delapan pasangan terkonfirmasi. Karena format bukti dan komposisi sampelnya berubah, metrik pilot itu tidak dipakai sebagai skor pembanding di tabel ini.
- Benchmark pasangan mengirim 504 panggilan Jev sukses dengan biaya yang dilaporkan US$0,048906396. Median waktu Jev per panggilan 0,562 detik. Waktu ini tidak termasuk pencocokan identitas, pengumpulan web, atau waktu pencarian di aplikasi.

## Artefak dan reproduksi

[Ringkasan pasangan](summary.json) menyimpan agregat. Roster, bukti, hasil per ID, dan checkpoint ada di `.local` dan tidak masuk Git. Tidak ada deploy atau integrasi ke aplikasi. Jalankan perintah dari folder ini.

1. `python3 -B prepare.py` membentuk shortlist dengan snapshot yang sudah ada. Cocokkan `.local/queue.json` terhadap `.local/roster-ids.json` dengan `../../../c67-preference-lab/scripts/match-catalog-place-ids.py` menggunakan field ID saja. Simpan hasil sebagai `.local/id-checks.jsonl`.
2. `python3 -B prepare.py --rescue` membuat shortlist alias kedua. Cocokkan `.local/queue-rescue.json` dan lanjutkan ke log yang sama. Hindari membangun ulang shortlist bila bukti sudah dibekukan.
3. `python3 -B benchmark.py inspect` memeriksa cakupan identitas. `python3 -B benchmark.py collect` membekukan bukti. `python3 -B benchmark.py classify` memakai atau membuat checkpoint Jev dan menghitung ringkasan pasangan.
4. `python3 -B volume.py prepare`, `python3 -B volume.py collect`, lalu `python3 -B volume.py classify` menjalankan uji volume independen. Roster dan bukti yang telah dibekukan dapat dipakai ulang langsung oleh perintah `classify`.
