# Pengumpulan data Jakarta Selatan — batch 30

Kampanye `jaksel-expansion-30-2026-11-10` menambahkan 30 kandidat dari snapshot OSM/Overture yang sudah tersedia. Pencarian asisten memilih URL pengelola dan pemerintah. Kolektor mengambil potongan halaman, kemudian model melalui luna-provider.example mengusulkan tujuh field beserta ID bukti. LLM tidak melakukan browsing dalam alur ini.

| Ukuran | Hasil |
| --- | ---: |
| Kandidat baru | 30 |
| Memiliki URL awal | 25 |
| Memiliki potongan sumber | 23 |
| Ekstraksi selesai | 23 |
| Masih memerlukan sumber | 7 |
| Halaman unik berhasil diambil | 40 |
| Percobaan model / retry | 46 / 23 |
| Median waktu per tempat, termasuk retry | 30.64 detik |
| Jumlah waktu inferensi | 777.33 detik |
| Tambahan panggilan Google Places | 0 |

Model diminta `cx/gpt-6-luna(max)`. Model yang dilaporkan `gpt-6-luna(max)`. Biaya tidak dilaporkan endpoint.

## Cakupan usulan model

Angka berikut menghitung status keluaran model pada seluruh kandidat, termasuk kandidat tanpa sumber. Angka ini belum menjadi jumlah fakta yang lolos telaah isi.

| Field | Supported | Contradicted | Unknown |
| --- | ---: | ---: | ---: |
| identity | 23 | 0 | 7 |
| public_visit | 14 | 0 | 16 |
| regular_hours | 10 | 0 | 20 |
| visitor_activity | 17 | 0 | 13 |
| read_own_book | 1 | 0 | 29 |
| read_with_coffee | 0 | 0 | 30 |
| last_entry | 0 | 0 | 30 |

## Status penggunaan

Usulan berada pada antrean telaah. Pin masih berasal dari sumber peta dan belum diverifikasi. Tidak ada data baru yang otomatis diterima atau dimasukkan ke aplikasi. Periksa identitas cabang, bukti akses, kegiatan, tanggal dokumen, syarat program, dan pasangan hari/jam. Tanggal pengambilan halaman tidak membuktikan bahwa berita lama masih berlaku.

Batch ini tidak mempunyai acuan evaluasi independen yang dibekukan sebelum inferensi. Tidak ada skor akurasi baru atau klaim peningkatan kualitas model. Sampel dipilih secara purposif; sebagian venue tidak memiliki halaman operator yang memadai. Dataset Google/Jev 982 tempat dan tiga arsip benchmark sebelumnya tetap terpisah.

## Berkas

- [Ringkasan JSON](results/summary.json)
- [Antrean telaah dengan klaim, potongan, URL dan hash sumber](results/review-queue.json)
- [Keluaran model asli dan log retry](results/giovanc/extraction.json)
- [Audit pengambilan halaman](results/source-audit.json)
- [Input kandidat](targets.json)
- [Penemuan URL dan risiko sumber](discovery.json)

- [Catatan pemeriksaan isi sebagian keluaran](results/review-notes.json)