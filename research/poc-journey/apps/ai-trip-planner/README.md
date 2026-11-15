# PoC penyusun itinerary tanpa AI (v4)

Jalur utama sekarang menyusun itinerary melalui **algoritme deterministik**, Google Places, Google Routes, dan Open-Meteo. Tidak memerlukan OpenRouter, model AI, atau browser. Eksperimen AI sebelumnya tetap tersedia sebagai pembanding; lihat [panduan lama](LEGACY_AI_README.md). Perintah `plan:ai:legacy`, `plan:quality`, dan `plan:research:v2` tetap memerlukan konfigurasi versi masing-masing.

## Tujuan dan batas

- Menerima daftar acak 1–20 tempat, tanggal, zona waktu, jam berangkat, titik awal dan titik akhir.
- Default kunjungan **30 menit**, dapat diubah per tempat. Titik transfer mendapat nol menit kunjungan tambahan. Aktivitas foto di stasiun tetap merupakan kunjungan.
- Membandingkan opsi **WALK dan TRANSIT** yang didukung provider. Mobil pribadi dan pelacakan posisi kendaraan belum termasuk lingkup. Pilihan yang gagal/tidak didukung tetap ditampilkan sebagai status, bukan nol menit atau penggantian moda diam-diam.
- Mempertahankan semua tempat, termasuk saat tidak ditemukan jadwal yang memenuhi batas.
- Menampilkan kandidat tercepat yang dievaluasi dan kandidat dengan pertimbangan cuaca bila datanya cukup. Hasil pencarian terbatas tidak diklaim sebagai optimum global.
- Output CLI berupa JSON dan Markdown; tidak ada UI baru.

## Menjalankan

Kebutuhan runtime: Node.js 24 atau lebih baru.

```sh
npm install
# Isi GOOGLE_MAPS_API_KEY dalam .env lokal; jangan masukkan kunci ke Git.
npm run config
npm run plan -- \
  --input examples/funabashi-2026-12-01-routing.json \
  --out results/funabashi-run-baru
```

Aktifkan **Places API (New)** dan **Routes API** pada proyek Google yang sesuai. Kunci yang sama dapat digunakan bila izin dan pembatasannya mendukung kedua layanan. `npm run config` hanya memeriksa keberadaan kunci, bukan akses layanan atau validitas kredensial. Open-Meteo tidak memerlukan kunci pada jalur ini. [Place Details](https://developers.google.com/maps/documentation/places/web-service/place-details), [Text Search](https://developers.google.com/maps/documentation/places/web-service/text-search).

Direktori output harus baru. Exit code: 0 untuk rencana tersedia/bersyarat; 2 untuk lokasi perlu dipilih, data rute tidak mencukupi, atau tidak ada kandidat layak; 1 untuk kegagalan teknis/input. Laporan tetap disimpan untuk hasil dengan exit code 2.

## Contoh input

```json
{
  "title": "Trip contoh",
  "date": "2026-12-01",
  "timeZone": "Asia/Tokyo",
  "startTime": "07:00",
  "regionCode": "JP",
  "origin": { "id": "origin", "query": "JR Funabashi Station Chiba Japan" },
  "defaultDwellMinutes": 30,
  "modes": ["WALK", "TRANSIT"],
  "places": [
    {
      "id": "park",
      "query": "Inamuragasaki Park Kamakura Japan",
      "exposure": "outdoor"
    },
    {
      "id": "station",
      "query": "Inamuragasaki Station Kamakura Japan",
      "role": "transfer"
    },
    {
      "id": "photo",
      "query": "Kamakurakokomae Station Japan",
      "role": "visit",
      "dwellMinutes": 45,
      "exposure": "outdoor"
    }
  ]
}
```

`returnTo` dapat diisi seperti origin; jika tidak, kembali ke origin. `finishBy` opsional, default 23:59 dalam zona waktu trip. Saat ini zona waktu yang diterima Asia/Tokyo dan Asia/Jakarta; trip satu hari. Perkiraan durasi/default berasal dari konfigurasi, bukan rekomendasi berdasarkan statistik kunjungan.

Untuk identitas, pilih `placeId` bila sudah diketahui. `acceptedNames` dapat berisi nama kanonis yang sudah diketahui untuk membedakan hasil pencarian. Beberapa kandidat tanpa kecocokan nama yang unik menghasilkan `needs_location_selection`; sistem tidak memilih hasil pertama. Semua kandidat disimpan dalam laporan.

`referenceNote` secara eksplisit menandai bahwa query hanya titik pendekatan suatu area. Jam operasional titik referensi tidak digunakan sebagai jam aktivitas yang belum spesifik. Pada contoh Jepang, toko suvenir belum dipilih, menara jam masih memakai referensi stasiun, dan Oiwayamichi memakai alamat rujukan dari konteks sebelumnya. Ketiganya tetap bersyarat.

## Alur perhitungan

1. Validasi input dan default/provenance durasi.
2. Text Search/Place Details untuk memperoleh identitas, koordinat, dan jam operasional.
3. Ambil matrix terarah per moda, dipecah menjadi request maksimum 100 elemen. Probe matrix memakai jam berangkat awal trip.
4. Pencarian beam terbatas mempertimbangkan biaya perjalanan, jam buka, dan ruas pulang. Konfigurasi default: beamWidth=128, shortlist=4. Tidak menggunakan seluruh permutasi.
5. Hitung ulang kandidat akhir; setiap ruas diminta berdasarkan waktu keberangkatan setelah kunjungan dan waktu menunggu buka sebelumnya. Semua opsi yang dikembalikan provider disimpan; durasi dan status tetap dapat diperiksa.
6. Pilih kandidat lengkap yang memenuhi batas terlebih dahulu, kemudian waktu perpindahan minimum; waktu menunggu buka menjadi pemecah seri. Jika semua kandidat berkonflik, tampilkan kandidat diagnostik dengan konflik, bukan rencana layak.
7. Pilih kandidat cuaca dari kandidat layak dengan cakupan cuaca/paparan cukup dan tambahan waktu terbatas.

[Google Route Matrix](https://developers.google.com/maps/documentation/routes/compute_route_matrix), [transit dan waktu keberangkatan](https://developers.google.com/maps/documentation/routes/transit-route). Estimasi provider tidak ditambah buffer kunjungan 30 menit pada titik transfer. Durasi berjalan/menunggu transfer bawaan provider tidak ditambahkan dua kali.

## Cuaca dan jam operasional

`weatherPolicy` opsional, default `{ "rainWeight": 2, "maxExtraMinutes": 15 }`. Ini **parameter eksperimen yang belum dikalibrasi**. Skor mempertimbangkan menit perpindahan ditambah rainWeight × perkiraan paparan hujan berbobot probabilitas. Nilai ini bukan estimasi tambahan keterlambatan akibat hujan. Batas tambahan waktu berlaku pada waktu perjalanan dan waktu selesai dibanding kandidat tercepat.

Paparan kunjungan ditandai manual sebagai indoor/outdoor/mixed/unknown. Mixed memakai faktor asumsi 0,5. Paparan perjalanan memakai bagian berjalan yang diketahui; menunggu terlindung/tidak terlindung dan perubahan cuaca sepanjang ruas belum dimodelkan rinci. Prakiraan yang hilang bukan nol persen hujan. Bila cakupan kurang, rekomendasi cuaca ditunda. Open-Meteo menyediakan horizon hingga 16 hari; 1 Desember 2026 berada di luar cakupan pada pengujian 3 November 2026. [Open-Meteo](https://open-meteo.com/en/docs).

Jam Google Places reguler dipakai sebagai acuan bersyarat. `currentOpeningHours` hanya dipakai bila tanggal trip berada dalam cakupan tujuh hari termasuk hari permintaan. Jadwal terpisah dan jam lintas tengah malam diinterseksikan dengan tanggal trip. Jam lokasi transfer tidak menjadi kewajiban kunjungan wisata.

## Batas khusus Jepang

**Google Routes API tidak mendukung mitra transit Jepang**, walaupun rute kereta dapat terlihat di aplikasi Google Maps. Karena itu TRANSIT dilaporkan sebagai `unsupported_region` dan tidak dipakai untuk membuat jadwal kereta palsu. WALK tetap dapat diperiksa; hasilnya mungkin melampaui batas satu hari. Rute kereta Jepang memerlukan provider lain atau fixture simulasi yang diberi label secara terpisah. [FAQ resmi Google](https://developers.google.com/maps/faq#transit_directions_countries).

## Artefak dan pemeriksaan

Setiap run menyimpan `manifest.json` (hash source), input yang telah dinormalisasi, progress, laporan JSON/Markdown, dan evidence request/response tanpa kunci. Hasil lama tidak ditimpa. Folder results dan .env diabaikan Git.

```sh
npm run check
npm test
npm run format:check
```

Tes otomatis memakai data sintetis/HTTP stub; tidak memanggil Google atau AI. Uji live dan hasil fixture dilaporkan terpisah. Panduan AI v3 tetap berada di [EVIDENCE_WORKFLOW.md](EVIDENCE_WORKFLOW.md); hasil daftar acak sebelumnya berada di [SHUFFLED_INPUT_EVALUATION.md](SHUFFLED_INPUT_EVALUATION.md).

Hasil implementasi dan pengujian Funabashi 1 Desember 2026 pukul 07.00 JST tersedia di [evaluasi v4](DETERMINISTIC_EVALUATION.md). Semua 15 tempat dihitung, tetapi rute Jepang belum layak satu hari dengan data WALK yang tersedia; TRANSIT Jepang memerlukan provider terpisah.
