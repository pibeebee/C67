# Protokol evaluasi final

Tanggal pelaksanaan 6 November 2026 WIB. Tiga pertanyaan dipisahkan: kesetaraan semantik, pengurangan waktu live, dan kelayakan resource satu Mac. Source/policy dibekukan dalam manifest sebelum replay; perubahan presentasi UI dan penambahan test setelah pengukuran dicatat dalam verifikasi akhir.

## Acuan dan varian

A menggunakan source/orchestration asli. B menggunakan HTTP Mac dan adapter single-pair. C menggunakan engine yang sama dengan batch snapshot, dedup satu akuisisi, precomputed passage dan lower bound yang diumumkan. Semua mengembalikan seluruh pilihan atau alasan belum lengkap; tidak ada penghapusan tujuan diam-diam. Objective elapsed_v2 dan deadline kembali Bundaran HI dipertahankan. Server tidak memakai LLM judge.

C mengelompokkan hanya query dengan koordinat asal, moda dan **departure instant sama**, maksimal 10 tujuan. Respons REST dipetakan berdasarkan koordinat/identitas, bukan posisi array. Sel final divalidasi pada departure setelah kunjungan sebelumnya. Budget logis engine tetap 512, seed 67 dan konfigurasi hybrid asal. Provider concurrency 1; REST B/C memakai pacing ETA 1,2 detik, tidak memakai concurrency 2. Native A live mempertahankan pacing asal.

## Replay utama

Clock evaluasi 2026-11-06T00:00:00Z; itinerary 7 November WIB. Search/cuaca adalah fixture berlabel. Oracle travel memakai jarak CoreLocation, durasi `(300 + distance/8) * factor`; factor 1,35 untuk jam WIB 07–10 dan 16–19, selain itu 1. E5 asli/model yang sama benar-benar dieksekusi. Batching mengemas query, bukan mengubah jawaban oracle.

| Kasus | Input | Harapan |
| --- | --- | --- |
| N1 ×3 | Cikini, 09–19, 60 menit | Ready |
| N3 ×3 | Cikini, BDT RBBJ, Erasmus, 09–19, 60 menit | Ready |
| N4 ×3 | N3 + Ragunan, 07–19, 60 menit | Ready |
| N5 ×3 | N4 + GBK, 07–19, 60 menit | Ready |
| REV5 | Final stop N5 +30; baseline diterima sebelumnya | Ready, accepted sebelumnya dipertahankan |
| MIX5 | Durasi Cikini45/BDT90/Erasmus45/Ragunan60/GBK30 | Ready pada oracle |
| TIGHT5 | 5×90 menit, 07–13 | Penolakan yang benar; C menyimpan proof 450>360 menit |
| SIX | Enam tempat unik pada katalog lima tempat layak | Needs places |
| UNKNOWN | Cikini + Wi-Fi wajib tanpa bukti | Needs places |

Setiap kasus dijalankan pada A/B/C: 17×3 =51 observasi. Urutan Latin ABC/BCA/CAB bergantian per kasus. Pipeline baru untuk kasus utama; REV memakai baseline N5 varian masing-masing. Penerimaan baseline berada di luar timer pembuatan. Mac CLI dan simulator merupakan run terpisah, tidak digabung menjadi sampel live. Tidak ada cache respons provider lintas-job; C passage disk index merupakan persiapan yang diumumkan.

Timer monotonic client mulai create/revise sampai result lengkap tersimpan atomik. Untuk B/C termasuk submit, queue, polling 100 ms, fetch result, dan penyimpanan. Job ID/202 bukan hasil. Timeout 240 detik dicatat censored. Server outcome elapsed mencakup engine orchestration; metrik warisan memisahkan preference/search/weather/routing. SQLite/serialization dan solver/audit belum dipecah menjadi stopwatch tersendiri; jangan menjumlahkan stage sebagai dekomposisi CPU yang lengkap.

## Audit independen

Python membaca output numerik dan katalog mentah. Memeriksa set tujuan/venue, required/desired count, durasi utuh, published sessions, last entry/entry pause, slot 15 menit, urutan departure/arrival/visit/leave, return deadline, sumber dan freshness, metadata model, final ETA query persis waktu/koordinatnya, call/cell dan batch compatibility. Tidak mempercayai `passed` atau `feasible` milik runner.

Parity: B/C tidak lebih buruk dari objective A lebih dari 1 detik pada oracle yang sama; hard constraints tanpa slack. Enam negative controls merusak dwell, source, departure, return leg, outcome dan accounting; auditor harus menolak semuanya. Tes terpisah memeriksa 384 elemen vektor runtime terhadap E5 asli, identity area dan cache query.

Kasus gagal/terputus disimpan. Final proposal valid dapat memiliki kegagalan alternatif; provider outage tidak menjadi proof infeasible. Tidak ada p95 atau klaim optimum global dari sampel ini.

## Kegagalan dan kontrak

Tes lokal: aturan sumber/jam/cuaca/storage; batching/time identity; budget; signature JWT; 401/expiry, 429/Retry-After, 5xx, timeout; missing REST config; all ETA unavailable; queue capacity; idempotency; restart; cancellation dan late result; stale base/apply ulang; jadwal kampanye.

Pemeriksaan HTTP nyata: health, auth, malformed JSON, payload cap, enqueue, idempotency, konflik, complete result, invalid apply hash, cancellation, no result setelah cancel dan missing job. UI simulator: autostart/progres/selesai, relaunch 51 hasil, start dan cancel melalui Device Hub. Input helper tap XcodeBuildMCP tidak mengaktifkan tombol pada runtime ini; hasil interaksi hanya dikreditkan setelah diamati melalui Device Hub.

## Live: disiapkan, belum dijalankan

Mode REST memerlukan kredensial dan minimum probe. Server tidak fallback ke native atau mock. A native →B REST adalah perubahan sistem termasuk platform/SDK; B→C lebih langsung mengukur kebijakan. Fakta yang kedaluwarsa harus diverifikasi ulang bersama, bukan sekadar memajukan checkedAt.

Jadwal penuh: fresh 36, priming 12, warm 12, edge 15 =75; sampai tiga baseline tambahan bila diperlukan. `prepare-live.py` menghitung ulang anggaran dari replay dan membekukan subset sebelum observasi. Jika full melebihi batas 3.000 call/6.000 ETA cells, warm/priming dikeluarkan seluruhnya menjadi fresh+edges 51; tidak dipilih berdasarkan hasil. Current dry estimate subset: 2.284 call termasuk allowance overhead20/job, 1.431 cells. Ini perkiraan perencanaan, bukan sisa quota resmi maupun jaminan pola query live identik.

Sisa allowance provider harus dikonfirmasi, manifest live berlaku15 menit dan script menolak jika keys/fakta/quota/budget belum siap. Client juga menyisakan worst-case reserve542 call/512cells sebelum setiap job; server mempunyai guard REST. Dua job berurutan unavailable menghentikan kampanye; resume butuh manifest baru. Seluruh status dan kegagalan tetap masuk laporan.

Target live: minimal tiga pasangan fresh lengkap masing-masing N3/N4/N5; median rasio paired C/A ≤0,70 per keluarga, seluruh ready valid. Warm tidak menggantikan fresh gagal. `audit.py --live` memisahkan perbandingan objective karena drift provider dan menghitung paired ratios. Jalur ini belum divalidasi dengan respons live aktual; hasil replay tidak meluluskan target waktu.

## Resource dan penutupan

Sampling RSS/%CPU proses server memakai `ps`, interval1 detik,120 sampel. Window mencakup bagian run simulator dan idle sesudahnya; `%CPU` merupakan angka yang dilaporkan ps, bukan profil CPU per tahap. Tidak mengukur RAM/baterai iPhone atau energi produk.

Simpan raw result, status, source manifests, audit JSON/CSV, negative controls, resource CSV dan log verifikasi. Pulihkan app asli pada iPhone tanpa uninstall, cocokkan data, hentikan hanya server lab dan cabut token. Tidak ada homelab/deploy/commit/push.
