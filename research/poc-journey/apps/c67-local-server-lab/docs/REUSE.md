# Asal engine dan batas adaptasi

Source asli tidak diubah. `fixtures/original-source-manifest.json` memuat 66 hash baseline dari benchmark sebelumnya; seluruhnya diverifikasi tetap identik. `Sources/PlannerBenchCLI/OriginalIntegrationModel.swift` adalah salinan byte-identik orkestrasi aplikasi asli. A bergantung langsung pada package TripIntegration asli dan memakai driver tipis untuk injeksi oracle atau native provider.

`Sources/PlannerEngine` diawali sebagai salinan source TripIntegration. Objective, evaluator, urutan prioritas kandidat, aturan durasi, jendela waktu, deadline endpoint dan hybrid adaptif tidak ditulis ulang. B/C memakai salinan engine yang sama.

Adaptasi pada file warisan:

| File | Perubahan |
| --- | --- |
| IntegrationPipeline.swift | Flag dan closure adapter lab, hook bulk, pelabelan `live_rest` yang berbeda dari replay, pemeriksaan departure live tetap aktif |
| NativeTripAppleServices.swift | Hook prime snapshot batch; cache dan budget logis tetap memakai pasangan/moda/departure engine |
| NativeTripRoutingBridge.swift | Memanggil bulk boundary sebelum loop akuisisi snapshot; urutan pasangan dan reserve tetap sama |
| ReplayFixtures.swift | Menghapus compile guard DEBUG di salinan lab, agar mode replay eksplisit tersedia; server REST tidak dapat fallback ke fixture |

File lain yang disalin mempertahankan kontennya. File baru LabRuntime, LabProvider, LabREST, LabEmbeddingCache dan LabE5Embedding menampung orkestrasi/provider terpisah. Jarak masih memakai CoreLocation Apple. Ini belum migrasi Linux.

LabE5Embedding berasal dari E5Embedding asli: pemeriksaan aset, tokenizer, prefix query/passage, pooling, normalisasi dan konfigurasi ONNX CPU tetap sama. Cache in-memory milik implementasi asal dihapus dari salinan runtime ini agar B tidak mendapat cache passage lintas-job; metadata dibuat lewat Codable karena initializer package asal internal. Runtime E5 tunggal digunakan bergantian oleh B/C. C mempunyai cache vektor di disk dengan area IDs, hash konten, preprocessing dan model revision pada identity. Query tidak ditulis ke disk. Unit test membandingkan seluruh 384 elemen dengan implementasi asli (toleransi 1e-7), lalu menguji key area dan reload cache.

Initialisasi model server dan passage precompute dikeluarkan dari timer per-job dan dilaporkan terpisah. B tetap meng-encode passage tiap job; C memuat passage yang disiapkan. A fresh memuat pipeline/runtime sesuai aplikasi asli. Inisialisasi yang diamortisasi merupakan bagian perubahan sistem A→B; B→C lebih langsung mengisolasi kebijakan persiapan/batching.

## Bukti kesetaraan

Replay memakai koordinat, cuaca dan oracle distance/time v1 yang sama dengan benchmark kompleks sebelumnya. A memakai package/orchestration asli; B/C memakai adapter lab. Acuan clock 6 November 2026, itinerary 7 November, katalog sumber tidak dimajukan tanggalnya.

CLI final dan simulator masing-masing: 51/51 outcome didukung auditor, 28 pembanding objective terhadap A identik. Pengujian unit juga menjalankan kembali 35 tes aturan/source/weather/storage dari package asli dengan import diarahkan ke salinan engine. Source dan data asli tetap terpisah; tidak ada backend Node/LLM lama yang menggantikan hybrid.

Bukti live lama 53 request N5 tidak otomatis harus sama dengan replay N3: oracle berbeda dapat mengubah urutan/keputusan pencarian. Hanya pembanding dalam oracle yang sama dipakai untuk parity.

## Tambahan D,6November2026

`LabFastPlanner.swift` adalah jalur lab baru; IntegrationPipeline hanya memilih hook D bila varian D dipilih. B/C tetap memakai hybrid sebelumnya. Semua finalis D melewati NativeTripEngine.evaluate dan PlanAudit yang sama. NativeTripEngine, NativeTripTimeAwarePlanner dan katalog/source acuan tidak diubah untuk D. LabVariant/Campaign/harness menambahkan C/D; server menyediakan batas budget yang dapat dikonfigurasi. Manifest runtime dibekukan sebelum live; hasil dan keterbatasan dicatat di [laporan D](FAST_D_RESULTS_2026-11-06.md).
