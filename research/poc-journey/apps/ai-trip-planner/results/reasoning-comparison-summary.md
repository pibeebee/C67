# Perbandingan reasoning Nemotron — 2 November 2026

Model: `nvidia/nemotron-3.5-super-vl:free`. Dua percobaan per konfigurasi. Data rute/cuaca berasal dari satu run live yang sama; tidak ada request Google atau cuaca tambahan pada eksperimen ini.

**Kontrol:** semua request memakai 6.775 token input, hash prompt yang sama dan JSON Schema yang sama. Yang berubah adalah reasoning, batas completion dan timeout. Kapasitas konteks model 1.000.000 token; input tidak ditambah supaya perbandingan tetap pada masalah yang sama.

## Pengulangan dengan jawaban akhir yang dapat diperiksa

| Ukuran | Reasoning off | Reasoning on |
|---|---|---|
| Batas completion token | 2500 | 16384 |
| Input token | 6775 | 6775 |
| Reasoning token terpakai | 0 | 2805 |
| Token jawaban akhir | 924 | 998 |
| Total completion terpakai | 924 | 3803 |
| Waktu respons AI | 7.86 detik | 30.03 detik |
| Lolos struktur/referensi | Ya | Tidak |
| Kandidat yang diusulkan | D/B/C:wait | D/B/C:wait |
| Jumlah alasan | 3 | 6 |

Completion mencakup reasoning dan jawaban akhir. Batas 16.384 tidak berarti seluruhnya harus digunakan. Keluaran on diterima API dan selesai normal, tetapi tidak diterima aplikasi karena enam alasan menduplikasi tiga destinasi.

## Semua percobaan, termasuk kegagalan

| Percobaan | Mode | Waktu (detik) | Reasoning token | Token akhir | Lolos validasi |
|---|---|---:|---:|---:|---|
| 1 | off | 58.23 | 0 | 1059 | Tidak |
| 1 | on | 39.81 | 2102 | 719 | Tidak |
| 2 | off | 7.86 | 0 | 924 | Ya |
| 2 | on | 30.03 | 2805 | 998 | Tidak |

**Lolos struktur/referensi:** off 1/2, on 0/2. Sampel ini terlalu kecil untuk menyimpulkan keunggulan umum; latensi provider berubah besar. API melaporkan biaya token nol pada keempat request.

## Review fakta pada pengulangan

- Keduanya mengusulkan `D/B/C:wait`, kandidat skor terendah 126,59 pada data ini. Pilihan kandidat yang sama tidak menjamin narasi yang sama benarnya.
- Off: jam dan durasi kunjungan yang dicantumkan sesuai tabel. Namun, narasi menyatakan peluang hujan C 100% di semua kandidat. Itu tidak tepat: kandidat `B/C/D:direct` memiliki peluang sekitar 94,64%, sedangkan kandidat wait berada pada 100%. Risiko tetap tinggi, tetapi angka tersebut tidak identik.
- On: menjelaskan alasan tiap destinasi lalu menambahkan tiga entri lagi hanya untuk referensi kandidat. Validator menolak enam entri untuk tiga tujuan; tidak menghapus duplikasi diam-diam.
- On: summary menyebut menunggu 33,5 menit di B. Jadwal yang dihitung kode menempatkan waktu menunggu di C, setelah tiba pada 16:13:13 dan sebelum mulai kunjungan pada 16:46:43. Menunggu di B merupakan jadwal lain dengan waktu keberangkatan/routing yang perlu dihitung ulang; ini tidak didukung kandidat terpilih.
- On: kalimat peluang hujan tinggi di seluruh kandidat lebih hati-hati daripada menyamaratakan semuanya sebagai 100%. Ini tidak meniadakan kesalahan lokasi menunggu dan duplikasi alasan.

## Fakta jadwal dari kode

| Tujuan | Mulai WIB | Selesai WIB | Durasi |
|---|---|---|---:|
| D | 14:05:42 | 14:50:42 | 45 menit |
| B | 14:59:25 | 15:59:25 | 60 menit |
| C | 16:46:43 | 17:31:43 | 45 menit |

Kandidat menunggu di C selama 33,5 menit, selesai sebelum batas 19:00 WIB. Fakta ini berasal dari perhitungan, bukan klaim prosa AI.

## Konfigurasi aktif setelah permintaan pengguna

```dotenv
OPENROUTER_MODEL=nvidia/nemotron-3.5-super-vl:free
OPENROUTER_REASONING=on
OPENROUTER_MAX_TOKENS=16384
OPENROUTER_TIMEOUT_MS=180000
```

API key tetap dipertahankan. Model diberi budget lebih besar dan berhasil menyelesaikan reasoning; kualitas alasan tetap perlu diperbaiki/diuji. Kapasitas input 1 juta token sudah merupakan kemampuan model, bukan nilai baru yang disetel oleh `max_tokens`.

## Artefak

- [Perbandingan pertama](reasoning-comparison-2026-11-02/comparison.md)
- [Perbandingan ulang dan jawaban akhir yang ditolak](reasoning-comparison-2026-11-02-repeat/comparison.md)
- [Data mentah perbandingan ulang](reasoning-comparison-2026-11-02-repeat/comparison.json)
