# Uji bukti per cabang dan keputusan Jev · 10 November 2026

Untuk pilot C67, hasil terbaik secara keseluruhan berasal dari bukti yang disusun per cabang, lalu Jev memeriksa identitas, akses, aktivitas, dan pengecualian produk secara terpisah. Pemeriksaan kedua terhadap label terpilih menambah beberapa label benar sekaligus menambah usulan yang belum cukup didukung pada sampel tambahan. Tempat dan label yang meragukan perlu masuk antrean pemeriksaan.

## Rancangan

Sampel diagnosis mencakup enam tempat yang sebelumnya diterima jalur historis Google tetapi ditahan jalur terbuka, empat pasangan lain, dan tiga kontrol sintetis. Setelah membandingkan metode pada sampel itu, enam tempat lain dari pilot terbuka dipakai untuk pemeriksaan transfer. Acuan dokumenter untuk tiap set dibuat sebelum panggilan Jev pada set tersebut. Satu penilai merangkum sumber dan menulis acuan, sehingga label acuan dan masukan bersumber dari dokumen yang sama. Referensi kasus dan label yang diharapkan dipakai untuk penilaian dan pemilihan panggilan diagnostik, sedangkan isi prompt hanya berisi kebijakan, bukti, dan pertanyaan Jev.

Semua panggilan menggunakan `typesafe/jev-1.14-20261014` dari TypeSafe. Ambang keputusan 0,80, ambang label 0,90. Pada A, B, dan C pertanyaan kelayakan serta definisi label sama. D mengganti pertanyaan kelayakan dengan empat pemeriksaan dalam satu panggilan, dengan label C dipakai ulang untuk menjaga pembandingan. E memeriksa ulang usulan label dari 62 skor Jev pada kandidat yang lolos D. Sebagian label dihitung secara diagnostik pada tempat layak yang tertahan di tahap kelayakan. Tabel menghitung label yang keluar setelah kedua tahap.

| Metode | Keputusan cocok, 10 tempat diagnosis | Destinasi tepat diterima, dari 9 | Diterima saat acuan masih belum cukup | Label acuan yang lolos, dari 20 |
| --- | ---: | ---: | ---: | ---: |
| A · potongan lama | 2 | 2 | 1 | 5 |
| B · potongan lama + catatan sumber | 7 | 7 | 1 | 9 |
| C · catatan sumber saja | 6 | 5 | 0 | 11 |
| D · C + empat pemeriksaan Jev | 8 | 7 | 0 | 13 |
| E · D + pemeriksaan kedua pada usulan label | 8 | 7 | 0 | 15 |

Pada tiga kontrol sintetis, metode lama cocok 2/3 dan D cocok 3/3. Ketiganya menguji kontraktor yang tidak memiliki fasilitas kunjungan, data cabang lain, dan perpustakaan kampus dengan larangan akses publik. Perubahan pada kontrol terakhir adalah dari belum cukup menjadi ditolak.

| Enam tempat tambahan | A | D | E |
| --- | ---: | ---: | ---: |
| Keputusan sesuai acuan | 5/6 | 5/6 | 5/6 |
| Label acuan yang lolos | 7/9 | 7/9 | 8/9 |
| Label di luar daftar acuan terbatas | 2 | 1 | 5 |

Jumlah label di luar daftar bukan jumlah kesalahan. Pemeriksaan isi menemukan contoh yang belum memiliki dukungan memadai. D masih memberi `outdoor` pada Museum Betawi ketika area luar yang dijelaskan adalah bagian dari kawasan induk. E memberi `art_museum` dan `public_art` pada Museum Layang-Layang tanpa bukti spesifik untuk kedua label itu. Pada E, peningkatan cakupan label disertai penambahan usulan untuk ditinjau. Untuk sekarang pilih D sebagai penyaring dan pakai E untuk usulan tambahan yang perlu diperiksa per sumber.

## Apa yang berubah per tempat

- Periplus Lotte semula hanya memiliki uraian merek. Direktori Periplus memberi gerai, unit LG 08, dan jam Senin–Minggu 10.00–22.00. D menerima kandidat. E menambahkan label `bookstore` yang sebelumnya tertahan. [Direktori gerai](https://www.periplus.com/_index_/Store-Locator)
- Nyi Ageng Serang awalnya hanya memiliki judul artikel dalam potongan. Panduan Pemprov menjelaskan akses memakai keanggotaan, membaca dengan buku yang dibawa sendiri dalam tas transparan, dan larangan minuman di ruang baca dengan pengecualian air mineral dalam tumbler. D menerima dan menghasilkan `library` dan `indoor`. Izin membawa buku dan aturan kopi adalah fakta kunjungan terpisah di luar 62 label Jev. [Panduan Jakarta Smart City](https://smartcity.jakarta.go.id/id/blog/06-2026-panduan-jelajahi-perpustakaan-jakarta-nyi-ageng-serang/)
- Taman Tabebuya tetap ditahan pada D. Jadwal PSBB 2020 hanya berlaku saat itu. Agenda perpustakaan keliling dan berita perbaikan jalan pada 2026 mengonfirmasi nama lokasi, dengan cakupan yang belum cukup untuk akses dan jam rutin. [Berita PSBB](https://m.beritajakarta.id/read/80439/taman-tabebuya-mulai-beroperasi-di-masa-psbb-transisi) · [Agenda Jaklitera](https://perpustakaan.jakarta.go.id/mobile-library/a21518d1-9b7f-4f13-bb92-80a1b5ca8970)

Satu putaran pencarian terarah dilakukan setelah hasil utama untuk tiga tempat yang masih tertahan. Freedom diterima dan memperoleh `library` serta `indoor` setelah bukti akses dari laporan terbaru ditambahkan. Jam tutup berbeda antara laporan dan laman perpustakaan, sehingga tetap perlu konfirmasi. Kios Ojo Keos diterima setelah direktori reseller mengikat kegiatan penjualan buku dengan alamat kios, tetapi skor label belum melewati ambang. Setiabudi One masih ditahan pada akses rutin setelah ditemukan undangan acara dari Periplus. Putaran ini terpisah dari skor di atas. [Laporan akses Freedom](https://www.cnnindonesia.com/gaya-hidup/20261109064157-269-1424758/6-perpustakaan-gratis-di-jakarta-punya-sudut-baca-yang-nyaman) · [Perpustakaan Freedom](https://perpustakaanfreedom.com/index.php?p=libinfo) · [Reseller Seumpama](https://seumpama.com/resellers/) · [Acara Periplus](https://blog.periplus.com/2026/06/06/meilinda-sutanto/)

## Pembacaan sumber yang bisa diotomatisasi

Prototipe pembacaan HTML memverifikasi tiga bentuk struktur pada halaman yang dapat diambil dengan kebijakan kolektor. Heading Kemang membatasi blok alamat dan jam sebelum heading cabang berikutnya. Kios Ojo Keos menyimpan tujuh pasangan hari dan jam dalam daftar bisnis Jetpack, termasuk pengecualian Sabtu. Jakarta Smart City menyimpan isi artikel di `__NEXT_DATA__`, termasuk prosedur masuk, jadwal dan aturan ruang baca. Pengambilan otomatis Periplus tidak lolos pemeriksaan akses kolektor. Bukti Periplus pada eksperimen berasal dari pencarian dan penelaahan halaman operator. [Audit pembacaan HTML](source-block-probe.json)

Alur untuk batch berikutnya adalah memilih halaman cabang, mempertahankan batas blok sumber, menyimpan URL dan cakupan waktu tiap fakta, lalu memakai D. Saat D mengembalikan belum cukup, cari bukti untuk pemeriksaan yang gagal. Usulan label spesifik seperti tempat duduk taman, seni publik, dan izin kopi memerlukan dukungan langsung pada venue atau subarea yang tepat sebelum masuk katalog. Tahap penyiapan catatan bukti pada eksperimen masih dikerjakan manual. Prototipe HTML memverifikasi tiga struktur dan belum menjadi pengambil bukti otomatis untuk seluruh 54 kandidat.

Total 116 panggilan Jev dengan biaya yang dilaporkan **US$0,015032682**. Panggilan baru memakai bukti publik independen dan data sintetis. Hasil terbatas pada 16 tempat nyata yang dipilih untuk diagnosis dan transfer, tiga kontrol sintetis, satu putaran per kondisi, dan satu penilai dokumenter. Belum ada pengukuran representatif untuk 982 tempat atau verifikasi lapangan atas akses, jam, dan pin.

- [Acuan dan catatan sumber diagnosis](cases.json)
- [Acuan enam tempat tambahan](validation-cases.json)
- [Keputusan A/B/C](results.json)
- [Keputusan D dan perinciannya](split-results.json)
- [Hasil sampel tambahan serta pemeriksaan label E](validation-results.json)
- [Hasil pencarian lanjutan per tempat](rescue-results.json)

Run diagnosis: `python3 -B run.py`. Setelah selesai, jalankan `python3 -B run_split_gate.py`, lalu `python3 -B validate_method.py`. Keputusan tersimpan di checkpoint berdasarkan hash masukan. Jalankan `python3 -B probe_source_blocks.py` untuk memeriksa versi halaman publik saat itu.
