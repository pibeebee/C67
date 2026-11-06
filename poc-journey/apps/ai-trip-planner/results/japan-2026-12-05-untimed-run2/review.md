# Review eksperimen tanpa jam — 5 Desember 2026

**Hasil: usulan itinerary lengkap berhasil dibuat, tetapi kelayakan perjalanan belum terverifikasi.** Semua jam berasal dari AI. Tidak ada jam atau durasi baseline pengguna di input awal.

## Kebutuhan dan normalisasi input

- Kontrak produk terbaru dari pengguna: tempat + waktu tiap tempat yang diharapkan adalah komponen wajib. Waktu berangkat, tanggal, batas pulang, preferensi dan konteks lain opsional. Eksperimen ini sengaja menghilangkan waktu per tempat sesuai permintaan khusus pengguna.
- Tanggal 2026-12-05, satu hari, Asia/Tokyo. Berangkat dan kembali ke JR Funabashi Station; tidak ada apartment pada batas perjalanan.
- Empat belas aktivitas dari daftar lama, ditambah coastal walk dan enam pasangan perpindahan kereta. Dua baris Sea Candle/illumination tetap merupakan dua aktivitas di lokasi sama. Baris transfer lama tidak dihitung sebagai kunjungan wisata tambahan.
- Semua waktu/durasi lama dihapus. Jam operasional dan jadwal acara adalah konteks resmi terpisah; tidak diklaim sebagai pilihan jam pengguna.

## Percobaan nyata

- Tahap pertama mengumpulkan 10 estimasi walking terarah dari Google tanpa departureTime, lalu memanggil OpenRouter nyata.
- Normalisasi input pertama belum menegaskan enam pasangan kereta. Draf AI melewatkan Kamakura→Inamuragasaki serta Katase-Enoshima→Fujisawa sebagai perpindahan antarestasiun. Validator terbaru menolak draf pertama. Draf dan hasil lamanya tetap tersimpan untuk jejak evaluasi.
- Perbaikan menambahkan keenam pasangan kereta dari daftar pengguna sebagai constraint, lalu memakai draf AI pertama sebagai bahan repair. Jam draf tersebut berasal dari AI, bukan dari baseline pengguna. Sepuluh hasil walking awal dipakai ulang; AI dipanggil sekali lagi dan rute draf hasil repair diperiksa ulang.
- Hasil repair: 14/14 aktivitas, 6/6 pasangan kereta, dan coastal walk dipertahankan. Keberangkatan 07:00 dan kembali 22:00 JST adalah usulan AI.
- Sebanyak 11/21 perpindahan menghasilkan estimasi Google; seluruh 11 alokasi tersebut setidaknya sepanjang estimasi provider. Enam query transit berstatus no_route dan empat leg restoran berstatus unresolved_location. Tidak ada klaim bahwa kereta nyata tidak tersedia.
- Pemeriksaan jam Tourist Center (14:40–15:30), Sea Candle (16:53–17:25), dan illumination (17:35–18:20) berada dalam jam umum/periode sumber yang diberikan. Penutupan khusus, antrean, harga dan jadwal kereta belum terkonfirmasi.

## Temuan review yang masih terbuka

1. **Buffer terlalu tipis:** 8/11 perpindahan yang memiliki estimasi hanya menyisakan kurang dari satu menit; seluruh 11 kurang dari lima menit. Batas lima menit hanya pembanding review, bukan standar universal. Cuaca, keramaian, tangga dan antrean dapat mengubah waktu nyata.
2. **Narasi menunggu keliru:** AI menyebut 17:25–17:35 sebagai menunggu penyalaan, padahal sumber menyatakan acara mulai menyala 17:00. Slot tersebut mungkin dipakai sebagai buffer, tetapi alasan yang ditulis AI tidak cocok dengan sumber. Jawaban mentah tidak diubah.
3. **Alokasi transit belum berdasar jadwal:** termasuk Funabashi→Kamakura 75 menit dan Fujisawa→Funabashi 80 menit. Keduanya hanya alokasi AI karena query provider belum menghasilkan rute.
4. **Identitas tempat belum lengkap:** restoran, toko suvenir, depan sekolah, perempatan dan menara jam belum seluruhnya ditentukan. Rute ke pusat area bukan bukti rute ke tempat spesifik tersebut.
5. **Cuaca dan sunset belum tersedia dalam evidence eksperimen:** 5 Desember berjarak 33 hari pada 2 November, di luar horizon forecast hingga 16 hari. Tidak ada probabilitas hujan atau jam sunset yang dikarang. Ketiadaan sunset di sini adalah batas evidence eksperimen, bukan klaim astronomi tidak dapat dihitung jauh hari.
6. **Kualitas bahasa:** ringkasan AI masih bahasa Inggris meskipun diminta Indonesia; beberapa istilah seperti “kaki kaki”/“penyaluran iluminasi” kurang tepat. Keberhasilan JSON tidak membuktikan kualitas prosa.
7. **Batas mesin:** rute diperiksa mandiri pada jam draf; keterlambatan belum dipropagasikan. Ini jalur proposal–validasi eksperimental, bukan optimizer deterministik 24 tempat atau sistem pemulihan otomatis.

## Metadata

- Model: nvidia/nemotron-3.5-super-vl:free; reasoning on; completion budget 16.384; plafon konteks 1.000.000 per request.
- Generasi awal: 18.789 token; repair: 18.766 token. Jumlah penggunaan kedua panggilan: 37.555 token. Reasoning sudah termasuk completion.
- Repair: input 6.739, reasoning 8.829, jawaban akhir 3.198; total 18.766 token. Sekitar 71 detik untuk AI repair; generasi awal sekitar 151 detik.
- Kedua tahap: 42 request Google total (10 walking awal + 15 pemeriksaan pertama + 17 pemeriksaan repair), 2 request AI, tanpa request forecast yang pasti berada di luar horizon. Ini jumlah request, bukan perhitungan tagihan.
- Typecheck, format, dan 41 tes backend PoC lulus. Pemeriksaan lokal tidak membuktikan kelayakan perjalanan atau seluruh prosa AI benar.

## Artefak

- [Input pengguna tanpa jam](user-input.json)
- [Evidence provider sebelum AI](collected.json)
- [Proposal AI + metadata](proposal.json)
- [Jadwal dan pemeriksaan lengkap](report.md)
- [Hasil mesin](report.json)
- [Draf percobaan pertama](../japan-2026-12-05-untimed-run1/report.md)

## Sumber resmi yang diperiksa ulang

- [Shonan no Hoseki 2026–2027](https://enoshima-seacandle.com/information/post-4136/): periode 1 Desember 2026–28 Februari 2027; 5 Desember masuk periode, jadwal Sabtu 17:00–21:00. Identitas acara merupakan interpretasi sistem atas illumination pengguna dan perlu ditinjau pengguna.
- [Sea Candle: jam umum](https://enoshima-seacandle.com/opening-hours/): jam umum berbeda dari jam event; perpanjangan acara tidak otomatis berlaku untuk setiap fasilitas.
- [Fujisawa City Tourist Center](https://www.fujisawa-kanko.jp/info/tourist_Information.html): jam umum 08:30–17:00.
- [Open-Meteo](https://open-meteo.com/en/docs): horizon prakiraan hingga 16 hari.
