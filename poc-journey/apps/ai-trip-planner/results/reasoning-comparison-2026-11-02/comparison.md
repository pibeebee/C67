# Perbandingan reasoning — Nemotron

Model: `nvidia/nemotron-3.5-super-vl:free`. Kandidat dari run 2026-11-02T10:09:39.094Z; rute/cuaca tidak diambil ulang.

Prompt identik: **true**. JSON Schema identik: **true**.

Perbandingan dua konfigurasi dengan satu sampel masing-masing. Reasoning dan budget output berubah bersama; hasil ini belum mengisolasi efek reasoning atau membuktikan keunggulan umum. Latensi/caching provider dapat berbeda.

| Ukuran | Reasoning off | Reasoning on |
|---|---|---|
| Batas completion token | 2500 | 16384 |
| Input token | 6775 | 6775 |
| Completion token terpakai | 1059 | 2821 |
| Reasoning token | 0 | 2102 |
| Token terlihat (completion − reasoning) | 1059 | 719 |
| Cached input token | 4336 | 4336 |
| Waktu AI (detik) | 58.23 | 39.81 |
| Finish reason | stop | stop |
| Lolos validasi struktur/referensi | false | false |
| Kandidat pilihan | — | — |
| Skor (lebih rendah lebih baik) | — | — |
| Selesai WIB | — | — |
| Biaya yang dilaporkan API | 0 | 0 |

**Batas validasi:** lulus struktur/referensi tidak membuktikan semua prosa benar. Teks reasoning internal tidak disimpan atau ditampilkan. Token completion mencakup reasoning dan jawaban akhir.

## Reasoning off

Hasil: AI must explain every remaining destination.

## Reasoning on

Hasil: AI must explain every remaining destination.
