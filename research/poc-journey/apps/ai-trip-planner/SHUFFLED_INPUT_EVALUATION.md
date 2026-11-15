# Evaluasi PoC: daftar acak Kamakura–Enoshima

Tanggal evaluasi: 3 November 2026 (WIB).

**Hasil: belum lulus uji end-to-end.** Model membuat draf urutan yang memuat seluruh 15 tempat, tetapi tidak ada proposal yang diterima, simulasi itinerary lengkap, ataupun review akhir. Status hasil utama adalah `no_valid_proposal`, dengan alasan `planner_stalled`. Draf di bawah tidak dapat dipakai sebagai itinerary yang telah tervalidasi.

## Input yang dipakai

- Trip satu hari: **1 Desember 2026**, zona waktu Asia/Tokyo.
- Apartment dihapus mengikuti koreksi pengguna.
- Stasiun Funabashi menjadi titik berangkat dan kembali, sebagai asumsi lanjutan dari skenario sebelumnya.
- Seluruh 15 tempat dipertahankan dalam urutan acak pengguna; tidak ada jam, durasi, atau batas pulang dari pengguna.
- Tidak ada pasangan kereta, coastal walk wajib, maupun petunjuk pasangan jalan kaki dari skenario lama. Tidak ada kegiatan makan atau illumination yang ditambahkan ke daftar wajib.
- Model: `nvidia/nemotron-3.5-super-vl:free`; reasoning aktif. Batas completion setiap peran 32.768 token dan batas konteks request 1.000.000 token.

**Batas pengujian:** nama/alamat rujukan sebagian besar tempat disediakan melalui konteks lokasi yang sudah tersedia. Jadi ini menguji riset, pengurutan, dan penyusunan itinerary dengan konteks tersebut; belum membuktikan sistem mampu menyelesaikan identitas semua tempat dari nama mentah saja. Toko suvenir belum ditentukan secara spesifik; beberapa lokasi pantai, jalan, dan menara jam masih berupa rujukan area.

Input: [daftar tempat](examples/shuffled-japan-2026-12-01.json) dan [konteks lokasi](examples/shuffled-japan-place-context.json).

## Dua eksekusi yang dilakukan

| Aspek                              | Run 1                  | Run 2 setelah perbaikan adaptor |
| ---------------------------------- | ---------------------- | ------------------------------- |
| Status                             | no_valid_proposal      | no_valid_proposal               |
| Alasan berhenti                    | planner_request_failed | planner_stalled                 |
| Panggilan model                    | 18                     | 21                              |
| Akumulasi token tercatat           | 791.896                | 618.904                         |
| Plafon akumulasi token seluruh run | 1.000.000              | 2.000.000                       |
| Proposal diterima                  | Tidak                  | Tidak                           |
| Simulasi itinerary lengkap         | Belum                  | Belum                           |
| Reviewer                           | Belum                  | Belum                           |

Angka token adalah akumulasi pemakaian request, termasuk konteks yang dikirim kembali; bukan ukuran satu konteks percakapan unik. Plafon run kedua dinaikkan sementara melalui environment proses, tanpa mengubah file .env. Batas konteks per request tetap 1.000.000.

Run pertama menemukan kesalahan pada adaptor yang saya tambahkan: titik awal/akhir Funabashi tidak diizinkan oleh tool rute karena berada di luar daftar aktivitas. Ada juga ketidakjelasan nama ID lokasi dan format waktu pada argumen tool. Ini masalah implementasi PoC dan tidak boleh dianggap sebagai ketidakmampuan model memahami geografi. Run pertama akhirnya tertahan pemeriksaan reservasi budget sebelum request berikutnya, walaupun angka pemakaian tercatat masih di bawah plafon.

Sebelum run kedua, titik awal/akhir diizinkan, schema tool rute diperjelas dengan ID kanonis, dan waktu ISO dengan tanggal trip yang sesuai dapat dikonversi untuk query rute. Trace run kedua memperlihatkan query Funabashi berhasil mencapai provider, sehingga kesalahan izin adaptor tersebut sudah teratasi. Namun kegagalan berikutnya tetap terjadi.

## Perbandingan urutan input dengan draf model

Urutan berikut diambil dari tiga percobaan `simulate_candidate` yang **ditolak**, bukan dari output itinerary final. Ketiganya memberikan urutan kunjungan yang sama. Semua tempat muncul sekali, dan 14 dari 15 posisi berbeda dari urutan input. Angka tersebut hanya menunjukkan pengurutan ulang, bukan kebenaran atau optimalitas rute.

| Posisi | Urutan input pengguna                      | Draf urutan model — belum valid            |
| ------ | ------------------------------------------ | ------------------------------------------ |
| 1      | Kamakura Seaside Park (Cape Inamuragasaki) | Stasiun Kamakura                           |
| 2      | Stasiun Inamuragasaki                      | Komachi Street                             |
| 3      | Toko Suvenir Enoshima Station              | Tsurugaoka Hachimangu                      |
| 4      | Enoshima Ohashi Bridge                     | Shichirigahama Beach                       |
| 5      | Enoshima Sea Candle                        | Stasiun Kamakurakokomae                    |
| 6      | Stasiun Kamakurakokomae                    | Stasiun Inamuragasaki                      |
| 7      | Tsurugaoka Hachimangu                      | Kamakura Seaside Park (Cape Inamuragasaki) |
| 8      | Shichirigahama Beach                       | Stasiun Enoshima                           |
| 9      | Fujisawa City Tourist Center               | Toko Suvenir Enoshima Station              |
| 10     | Stasiun Fujisawa (Menara Jam)              | Oiwayamichi Street                         |
| 11     | Stasiun Enoshima                           | Enoshima Sea Candle                        |
| 12     | Oiwayamichi Street                         | Enoshima Ohashi Bridge                     |
| 13     | Stasiun Katase-Enoshima                    | Stasiun Katase-Enoshima                    |
| 14     | Komachi Street                             | Fujisawa City Tourist Center               |
| 15     | Stasiun Kamakura                           | Stasiun Fujisawa (Menara Jam)              |

Funabashi tetap menjadi origin/return di luar 15 kunjungan. Jam yang muncul dalam draf tidak ditampilkan sebagai jadwal yang bisa diikuti karena belum lolos pemeriksaan. Urutan ini juga belum membuktikan perjalanan bebas bolak-balik atau memenuhi jam fasilitas.

## Data yang benar-benar diperoleh pada run kedua

- Browser mencoba 10 halaman; 7 halaman dapat dibaca. Status HTTP 200 saja tidak dihitung sebagai keberhasilan ekstraksi teks.
- Tidak ada klaim riset baru yang diterima. Tiga pengajuan klaim ditolak karena kutipannya tidak cocok dengan teks halaman yang tersimpan. Fakta umum yang disediakan dalam konteks awal tetap berbeda dari temuan browser baru.
- Ada 10 hasil query rute: 8 TRANSIT mengembalikan `no_route`, dan 2 WALK memperoleh estimasi. `no_route` berarti query provider tersebut tidak menemukan hasil; tidak membuktikan kereta sebenarnya tidak tersedia.
- Estimasi WALK Kamakura Station → Komachi sekitar 5,7 menit / 410 meter, dengan peringatan kecocokan alamat parsial.
- Estimasi WALK Katase-Enoshima Station → Fujisawa Station sekitar 49,4 menit / 3.519 meter. Ini hasil jalan kaki, bukan keberhasilan mendapatkan rute kereta.
- Empat area cuaca berstatus `outside_forecast_horizon`. Tidak ada prakiraan atau jam matahari spesifik tanggal trip yang diada-adakan.

Query rute individual di atas berbeda dari simulasi seluruh kandidat itinerary; simulasi lengkap belum sempat berjalan.

## Penyebab utama hasil belum valid

1. **Kontrak waktu antara tool dan validator tidak selaras.** Model mengirim `2026-12-01T06:30:00+09:00`; validator mengharapkan `HH:mm`. Schema timeline hanya menyebut string. Pesan error yang muncul membahas urutan waktu, sehingga tidak cukup membantu model memperbaiki format. Semua tiga percobaan ditolak pada tahap ini. Lihat [schema dan validator](src/untimed.ts).
2. **Masih ada cacat struktur setelah format diperbaiki secara diagnostik.** Pada salinan data offline, waktu ISO dikonversi ke HH:mm dengan tanggal dan offset yang sesuai. Kandidat pertama kemudian ditolak karena lokasi antarbaris tidak tersambung; kandidat kedua dan ketiga ditolak karena jeda/overlap yang tidak direpresentasikan dengan baris wait. Ini pemeriksaan diagnostik pada salinan, bukan perbaikan hasil produksi. Tidak ada simulasi ataupun reviewer yang dijalankan pada salinan tersebut.
3. **Penerimaan evidence belum berjalan efektif.** Model gagal mendaftarkan kutipan yang sesuai teks sumber dan beberapa aksi tool tidak valid berulang. Pembatasan kutipan tetap diperlukan agar teks yang tidak didukung sumber tidak menjadi fakta.
4. **Data transportasi belum mencukupi.** Delapan query TRANSIT tanpa hasil belum digantikan bukti operator yang memadai untuk tanggal perjalanan. Jam fasilitas dan identitas toko tertentu juga belum terselesaikan.

Pemeriksaan diagnostik tidak menemukan ID evidence asing pada tiga draf. Hal itu tidak membuktikan isi setiap klaim atau estimasi sudah didukung evidence yang memadai.

Run kedua memakai 618.904 dari plafon 2.000.000 token dan berhenti karena aksi tool tidak valid berulang. Jadi menambah token lagi saja tidak menjelaskan atau menyelesaikan kegagalan ini.

## Perbaikan yang paling langsung sesudah evaluasi

1. Selaraskan schema waktu, contoh argumen, dan validator; kembalikan error dengan indeks baris, field, serta format yang diharapkan.
2. Pisahkan pengusulan urutan tempat dari pembentukan timeline lengkap, lalu periksa kontinuitas lokasi dan waktu secara deterministik sebelum simulasi layanan.
3. Bantu model mengambil kutipan persis dari paragraf sumber, mempertahankan verifikasi terhadap teks tersimpan, dan berikan umpan balik perbaikan yang lebih spesifik.
4. Tangani rute TRANSIT tanpa hasil melalui riset operator atau status belum terverifikasi yang jelas; bedakan stasiun transfer dari kunjungan yang memerlukan jam buka fasilitas.

Perbaikan inti tersebut belum diterapkan setelah run kedua. Hasil yang tersimpan tidak diubah agar tampak berhasil.

## Perubahan dan verifikasi pada pekerjaan ini

Adaptor input diperluas agar coastal walk/pasangan transit tidak harus ditentukan di awal, serta rute antartitik yang dipilih model dapat diperiksa. Fixture baru mempertahankan daftar acak dan tanggal koreksi. Pemeriksaan TypeScript `npm run check` dan format untuk file yang diubah telah dilakukan; unit test suite tidak dijalankan. Kompilasi tidak berarti uji end-to-end ini berhasil.

Hash seluruh source saat menyusun laporan dibandingkan manifest awal run kedua: **tidak ada perubahan source setelah eksekusi dimulai**.

## Artefak hasil

- [Assessment ringkas terstruktur](results/shuffled-japan-2026-12-01-v3-run2/assessment.json)
- [Report asli run kedua](results/shuffled-japan-2026-12-01-v3-run2/report.json)
- [Evidence run kedua](results/shuffled-japan-2026-12-01-v3-run2/evidence.json)
- [Percakapan tool planner](results/shuffled-japan-2026-12-01-v3-run2/conversations/planner-1.json)
- [Diagnosis salinan timeline](results/shuffled-japan-2026-12-01-v3-run2/format-diagnostic.json)
- [Manifest source dan konfigurasi run kedua](results/shuffled-japan-2026-12-01-v3-run2/manifest.json)
- [Report asli run pertama](results/shuffled-japan-2026-12-01-v3-run1/report.json)

Direktori results diabaikan Git sesuai konfigurasi PoC. Laporan ini dan fixture input dapat dilacak terpisah dari artefak runtime lokal.
