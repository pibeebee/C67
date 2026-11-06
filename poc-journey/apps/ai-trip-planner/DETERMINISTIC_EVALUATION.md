# Evaluasi PoC deterministik v4 — Funabashi

Tanggal evaluasi: 3 November 2026 (WIB).

**Implementasi dan tes otomatis berhasil; uji live tidak menghasilkan itinerary Jepang yang layak satu hari dengan provider yang tersedia.** Status run utama: `no_feasible_candidate`. Tidak ada panggilan AI. Hasil WALK di bawah adalah kandidat diagnostik, bukan rekomendasi perjalanan yang dapat diikuti.

## Input dan asumsi

- Tanggal: **1 Desember 2026**, berangkat **07.00 Asia/Tokyo**.
- Awal dan akhir: **Stasiun Funabashi**; apartment dihapus.
- Semua **15 tempat** dari daftar acak pengguna dipertahankan. Tidak ada urutan rute lama atau pasangan kereta yang dipaksakan.
- Default singgah **30 menit**. Empat stasiun transfer (Inamuragasaki, Enoshima, Katase-Enoshima, Kamakura) mendapat 0 menit kunjungan tambahan.
- Kamakurakokomae untuk foto dan Fujisawa untuk menara jam tetap kunjungan 30 menit. Total singgah: **330 menit / 5 jam 30 menit**.
- Batas selesai belum diberikan pengguna, sehingga digunakan batas teknis 23.59 pada tanggal trip.
- Paparan indoor/outdoor/mixed ditandai manual dalam fixture. Parameter cuaca rainWeight=2 dan maxExtraMinutes=15 adalah asumsi eksperimen yang dapat diganti.
- Toko suvenir memakai referensi area Stasiun Enoshima, menara jam memakai referensi area Stasiun Fujisawa, dan Oiwayamichi memakai rujukan Nakamuraya dari konteks sebelumnya. Ketiganya masih bersyarat; jam referensi tidak dipakai sebagai jam aktivitas sebenarnya.

Input: [fixture v4](examples/funabashi-2026-12-01-routing.json).

## Perubahan yang diterapkan

Jalur utama `npm run plan` sekarang menjalankan Google Places/Routes dan Open-Meteo dengan mesin perhitungan deterministik. Kunci/model AI tidak diperlukan. Eksperimen AI lama dipertahankan melalui perintah legacy.

Pencarian urutan memakai beam terbatas untuk 1–20 tempat, bukan seluruh permutasi. Kandidat akhir dihitung ulang dengan waktu keberangkatan tiap ruas, termasuk durasi singgah dan menunggu jam buka. Ruas kembali ke titik akhir selalu disertakan. Seluruh opsi WALK/TRANSIT yang dikembalikan disimpan beserta statusnya. Rute yang hilang tidak menjadi nol menit dan tempat tidak dihapus agar jadwal muat.

Informasi Google Places didapat melalui pencarian/details. Jam reguler menjadi acuan bersyarat; currentOpeningHours hanya diterapkan pada cakupan tujuh hari. Hasil nama ambigu meminta pemilihan placeId.

## Dua uji live

| Aspek               | Run 1                                   | Run 2                                    |
| ------------------- | --------------------------------------- | ---------------------------------------- |
| Lokasi berkoordinat | 13 dari 16 termasuk origin              | 16 dari 16, termasuk tiga referensi area |
| Status              | needs_location_selection                | no_feasible_candidate                    |
| Penyebab            | Nama stasiun memiliki beberapa Place ID | Kandidat WALK melewati batas satu hari   |
| Kandidat lengkap    | 0                                       | 4                                        |
| Panggilan AI        | 0                                       | 0                                        |

Run pertama berhenti dengan benar sebelum routing karena hasil Funabashi, Fujisawa, dan Kamakura ambigu. Untuk run kedua, Codex memilih pin stasiun sesuai nama/alamat dari respons Google, lalu memasukkannya ke fixture. Ini bukan pin pintu masuk yang telah dikonfirmasi pengguna. [Catatan pemilihan pin](results/funabashi-2026-12-01-v4-run1/pin-selection.json).

Run kedua membuat **37 request**: 3 Places Details, 12 Places Search, 4 Route Matrix, dan 18 query ruas. Pencarian melakukan **11.873 ekspansi** dengan beamWidth 128; empat kandidat diperiksa. Tidak ada request prakiraan karena tanggal di luar horizon, dan tidak ada query TRANSIT Jepang yang sia-sia setelah cakupan resmi diketahui.

## Perbandingan urutan

Kolom terakhir adalah salah satu kandidat diagnostik WALK yang diperiksa, bukan urutan optimal atau itinerary yang layak. Kandidat ini memiliki konflik jam operasional dan batas selesai.

| Posisi | Input pengguna                             | Kandidat diagnostik WALK                   |
| ------ | ------------------------------------------ | ------------------------------------------ |
| 1      | Kamakura Seaside Park (Cape Inamuragasaki) | Komachi Street                             |
| 2      | Stasiun Inamuragasaki                      | Stasiun Kamakura                           |
| 3      | Toko Suvenir Enoshima Station              | Stasiun Inamuragasaki                      |
| 4      | Enoshima Ohashi Bridge                     | Shichirigahama Beach                       |
| 5      | Enoshima Sea Candle                        | Stasiun Kamakurakokomae                    |
| 6      | Stasiun Kamakurakokomae                    | Stasiun Katase-Enoshima                    |
| 7      | Tsurugaoka Hachimangu                      | Toko Suvenir Enoshima Station              |
| 8      | Shichirigahama Beach                       | Stasiun Enoshima                           |
| 9      | Fujisawa City Tourist Center               | Stasiun Fujisawa (Menara Jam)              |
| 10     | Stasiun Fujisawa (Menara Jam)              | Fujisawa City Tourist Center               |
| 11     | Stasiun Enoshima                           | Oiwayamichi Street                         |
| 12     | Oiwayamichi Street                         | Enoshima Sea Candle                        |
| 13     | Stasiun Katase-Enoshima                    | Enoshima Ohashi Bridge                     |
| 14     | Komachi Street                             | Kamakura Seaside Park (Cape Inamuragasaki) |
| 15     | Stasiun Kamakura                           | Tsurugaoka Hachimangu                      |

## Hasil kandidat diagnostik

- Perpindahan: **2363.3 menit**, sekitar 39 jam 23 menit.
- Singgah: **330 menit**.
- Perkiraan selesai dalam model: **3 Dec 2026, 03:53:18**.
- Konflik: `OPENING_WINDOW:P05`, `OPENING_WINDOW:P04`, `OPENING_WINDOW:P01`, `OPENING_WINDOW:P07`, `FINISH_LIMIT: lewat 1675 menit`.
- Semua 15 aktivitas muncul sekali dan ruas pulang ada.

Bahkan batas bawah berbasis matrix WALK tersimpan—minimum ruas dari origin + minimum ruas kembali + singgah, tanpa perjalanan antartempat di tengah—sudah **2329.2 menit**, dibanding 1019 menit yang tersedia. Ini menjelaskan bahwa model berjalan kaki yang tersedia tidak cocok untuk trip satu hari; tidak membuktikan trip dengan kereta sebenarnya tidak memungkinkan.

**Batas provider:** Google menyatakan Routes API mengecualikan mitra transit Jepang. Karena itu, opsi kereta ditandai `unsupported_region`, bukan layanan yang tidak ada dan bukan durasi yang diestimasi AI. Rute kereta memerlukan provider Jepang terpisah atau fixture berlabel simulasi. [FAQ Google](https://developers.google.com/maps/faq#transit_directions_countries).

**Cuaca:** semua titik berstatus `outside_forecast_horizon`. Pengaruh cuaca belum tervalidasi live untuk tanggal 1 Desember pada hari evaluasi ini. Pengaruhnya sudah diperiksa melalui tes sintetis, yang menunjukkan pilihan lebih lambat dengan lebih sedikit paparan hujan dapat dipilih dalam batas tambahan waktu. Nilai prakiraan sintetis tidak dimasukkan ke run live. [Horizon Open-Meteo](https://open-meteo.com/en/docs).

**Jam operasional:** provider tidak mengembalikan jam untuk semua kunjungan, termasuk Tourist Center pada hasil ini. Data yang tidak ada tetap unknown. Ini menunjukkan bahwa Google Places dapat menjadi sumber utama, tetapi kelengkapan setiap tempat tidak terjamin.

## Perbandingan dengan eksperimen AI terakhir

| Aspek                         | v3, input acak tanpa jam pengguna  | v4, input 07.00 JST                                 |
| ----------------------------- | ---------------------------------- | --------------------------------------------------- |
| Pengambil keputusan inti      | AI researcher/planner/reviewer     | Algoritme pencarian dan perhitungan waktu           |
| Panggilan AI pada run utama   | 21                                 | 0                                                   |
| Status                        | no_valid_proposal                  | no_feasible_candidate                               |
| Penyusunan timeline           | Ditolak pada kontrak format tool   | Empat kandidat lengkap dihitung                     |
| Kelengkapan tempat dan pulang | Belum ada proposal diterima        | Semua 15 tempat + ruas pulang ada                   |
| Hambatan utama                | Kontrak tool/validasi dan evidence | Cakupan transit Jepang, data cuaca/jam dan pin area |

Input kedua versi berbeda pada jam berangkat, durasi default, dan penetapan titik transit. Perbandingan ini menunjukkan perubahan perilaku pipeline, bukan benchmark terkontrol kualitas rekomendasi.

## Verifikasi

- `npm run check`: lolos.
- `npm test`: **55 lulus, 0 gagal**, termasuk 14 tes baru.
- `npm run format:check` dan `git diff --check`: lolos. Fixture konteks daftar acak sebelumnya hanya dirapikan format JSON-nya.
- Tes otomatis mencakup urutan terarah, perangkap tetangga terdekat, 15 tempat, ruas kembali, propagasi jam, jam buka lintas malam/sesi terpisah, ambiguitas lokasi, data hilang, cuaca, batas tambahan waktu, dan CLI tanpa OpenRouter.
- Tes otomatis memakai fixture/HTTP stub. Dua uji live di atas memakai Google sebenarnya.
- Hash source saat laporan dibandingkan manifest run kedua: **tidak berubah**. Hasil run tidak diedit untuk mengubah statusnya.

## Artefak

- [Report lengkap run utama](results/funabashi-2026-12-01-v4-run2/report.md)
- [Report JSON](results/funabashi-2026-12-01-v4-run2/report.json)
- [Evidence provider](results/funabashi-2026-12-01-v4-run2/provider-evidence.json)
- [Assessment dan pemeriksaan hash](results/funabashi-2026-12-01-v4-run2/assessment.json)
- [Manifest source](results/funabashi-2026-12-01-v4-run2/manifest.json)

Artefak results disimpan lokal dan diabaikan Git; fixture, kode, serta laporan evaluasi ini dapat dilacak dalam repo.
