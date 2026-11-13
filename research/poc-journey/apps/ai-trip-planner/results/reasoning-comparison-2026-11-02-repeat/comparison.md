# Perbandingan reasoning — Nemotron

Model: `nvidia/nemotron-3.5-super-vl:free`. Kandidat dari run 2026-11-02T10:09:39.094Z; rute/cuaca tidak diambil ulang.

Prompt identik: **true**. JSON Schema identik: **true**.

Perbandingan dua konfigurasi dengan satu sampel masing-masing. Reasoning dan budget output berubah bersama; hasil ini belum mengisolasi efek reasoning atau membuktikan keunggulan umum. Latensi/caching provider dapat berbeda.

| Ukuran | Reasoning off | Reasoning on |
|---|---|---|
| Batas completion token | 2500 | 16384 |
| Input token | 6775 | 6775 |
| Completion token terpakai | 924 | 3803 |
| Reasoning token | 0 | 2805 |
| Token terlihat (completion − reasoning) | 924 | 998 |
| Cached input token | 4336 | 4336 |
| Waktu AI (detik) | 7.86 | 30.03 |
| Finish reason | stop | stop |
| Lolos validasi struktur/referensi | true | false |
| Kandidat pilihan | D/B/C:wait | — |
| Skor (lebih rendah lebih baik) | 126.59 | — |
| Selesai WIB | 17:31 | — |
| Biaya yang dilaporkan API | 0 | 0 |

**Batas validasi:** lulus struktur/referensi tidak membuktikan semua prosa benar. Teks reasoning internal tidak disimpan atau ditampilkan. Token completion mencakup reasoning dan jawaban akhir.

## Reasoning off

Rute pilihan: D → B → C, dengan tunggu di C agar kunjungan luar ruang memasuki jendela sunset. Rute ini feasible dan memiliki skor terbaik (126.59, ranked 1). Selesai pukul 17:31:43 WIB, sebelum batas 19:00 WIB. Diterapkan sesuai preferensi: semua tujuan tetap dikunjungi, C diwaktu jendela 16:46:43–17:46:43 WIB. Catatan risiko: probabilitas hujan pada kunjungan outdoor C adalah 100%, dan rainExposureMinutes 45 menit hanyalah proxy peranking, bukan prediksi durasi hujan. Kunjungan B (indoor) pada 14:59:25–15:59:25 WIB memiliki probabilitas hujan 92.87%, tapi berada di ruangan.

### Fakta jadwal dari kode

| Tujuan | Mulai WIB | Selesai WIB | Durasi menit |
|---|---|---|---:|
| D | 14:05 | 14:50 | 45 |
| B | 14:59 | 15:59 | 60 |
| C | 16:46 | 17:31 | 45 |

### Alasan akhir AI

- **D:** Tiba pukul 14:05:42 WIB dan selesai 14:50:42 WIB. Kunjungan indoor untuk baca, weather evidenceIds: input:D, route:A/D@1793689200, weather:D. Probabilitas hujan 80%, suhu 32.5°C, tidak ada exposure luar ruang.
- **B:** Kopi indoor dan baca pukul 14:59:25–15:59:25 WIB, cocok untuk aktivitas di ruangan sambil menunggu cuaca luar ruang. weather evidenceIds: input:B, route:D/B@1793692242, weather:B. Probabilitas hujan 92.87%, suhu 31.41°C, exposure 0 menit karena indoor.
- **C:** Tunggu 33.5 menit agar kunjungan outdoor dimulai pukul 16:46:43 WIB, tepat dalam jendela sunset 16:46:43–17:46:43 WIB, dan selesai 17:31:43 WIB. weather evidenceIds: input:C, route:B/C@1793696365, weather:C. Probabilitas hujan 100%, rainExposureMinutes 45 (proxy ranking, bukan prediksi durasi hujan).

### Tradeoff

- Skor 126.59 lebih baik daripada B/D/C:wait (134.37) meski waktu tunggu lebih lama (33.5 vs 23.13 menit), karena rute D→B→C lebih pendek secara perjalanan (28.22 vs 38.58 menit) dan jarak lebih hemat. C sama-sama memiliki probabilitas hujan 100 dan rainExposureMinutes 45 di semua candidate yang mencakupnya, jadi risiko cuaca outdoor tidak bisa dihindari dengan memilih rute lain dalam data ini. Tidak ada pelanggaran jendela waktu atau melebihi batas selesai 19:00 WIB.

### Ketidakpastian

- Cuaca adalah estimasi probabilistik, bukan jaminan. Jam buka adalah asumsi user, bukan fakta terverifikasi. Tidak ada waktu pulang yang termasuk dalam jadwal.

## Reasoning on

Hasil: AI must explain every remaining destination (expected 3 rationale entries, received 6).

### Jawaban akhir yang ditolak

```json
{
  "candidateId": "D/B/C:wait",
  "summary": "Pilih candidate D/B/C:wait: urutan D → B → C, tunggu 33,5 menit di B sebelum lanjut ke C sehingga kunjungan outdoor C dimulai tepat 16:46:43 WIB, awal jendela preferensi 16:46:43–17:46:43 WIB (preferredWindowMissMinutes = 0). Selesai 17:31:43 WIB, masih sebelum batas 19:00, feasible tanpa overtime maupun pelanggaran. Skor 126,59 (scoreRank 1) lebih rendah dari kandidat lain, dan perjalanan 28,22 menit lebih singkat dari B/D/C:wait yang selesai sama.",
  "rationale": [
    {
      "placeId": "D",
      "reason": "Baca (indoor) pertama: tiba 14:05:42, berangkat 14:50:42 WIB; cuaca kunjungan supplied rainProbability 80, suhu 32,5 °C, cloudCover 53. Jarak terdekat dari A (1.237 m). evidenceIds: input:D, route:A/D@1793689200, weather:D.",
      "evidenceIds": [
        "input:D",
        "route:A/D@1793689200",
        "weather:D"
      ]
    },
    {
      "placeId": "B",
      "reason": "Ngopi (indoor) kedua: tiba 14:59:25, berangkat 15:59:25 WIB; cuaca kunjungan supplied rainProbability 92,87, suhu 31,41 °C, cloudCover 27,25. Tempat dalam ruang sebelum aktivitas luar ruang. evidenceIds: input:B, route:D/B@1793692242, weather:B.",
      "evidenceIds": [
        "input:B",
        "route:D/B@1793692242",
        "weather:B"
      ]
    },
    {
      "placeId": "C",
      "reason": "Outdoor ketiga ditangguhkan agar kunjungan 16:46:43–17:31:43 WIB overlap penuh dengan jendela preferensi 16:46:43–17:46:43 WIB, keterlewatan 0 menit. Cuaca kunjungan supplied rainProbability 100 (tinggi), suhu 30,37 °C, cloudCover 55,67; rainExposureMinutes 45 hanyalah proxy perankingan, bukan ramalan hujan dalam menit. Semua kandidat menunjukkan C dengan peluang hujan tinggi, jadi hindaran penuh tidak tersedia dalam data ini, tetapi jendela pengalaman terpenuhi tanpa keterlewatan. evidenceIds: input:C, route:B/C@1793696365, weather:C.",
      "evidenceIds": [
        "input:C",
        "route:B/C@1793696365",
        "weather:C"
      ]
    },
    {
      "placeId": "D",
      "reason": "candidate:D/B/C:wait",
      "evidenceIds": [
        "candidate:D/B/C:wait"
      ]
    },
    {
      "placeId": "B",
      "reason": "candidate:D/B/C:wait",
      "evidenceIds": [
        "candidate:D/B/C:wait"
      ]
    },
    {
      "placeId": "C",
      "reason": "candidate:D/B/C:wait",
      "evidenceIds": [
        "candidate:D/B/C:wait"
      ]
    }
  ],
  "tradeoffs": [
    "Semua tujuan pilihan tetap dikunjungi (D, B, C); tidak ada yang dihilangkan. Preferensi 'ngopi sambil membaca' terpenuhi secara terpisah karena B dan D beide indoor, tidak dalam satu kunjungan bersama. C memiliki probabilitas hujan supplied 100 pada kunjungan outdoor, sehingga keinginan menghindari hujan tinggi di luar ruang tidak terpenuhi sepenuhnya pada data yang tersedia."
  ],
  "uncertainties": [
    "Cuaca adalah probabilitas per jam, bukan jaminan; jendela sebelum sunset adalah preferensi pengguna, bukan bukti visibilitas atau golden hour."
  ]
}
```
