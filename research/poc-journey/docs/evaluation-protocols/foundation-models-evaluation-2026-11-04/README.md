# Paket evaluasi Foundation Models untuk C67

4 November 2026, Asia/Jakarta. **Status: prompt, fixture dan protokol siap diuji; belum ada inferensi Foundation Models atau hasil performa baru pada paket ini.**

Keputusan yang ingin diambil: apakah model on-device dapat mengisi pemahaman bahasa, preferensi, penjelasan dan rekomendasi berbasis konteks yang belum ada pada core native P2? Ini tidak mengasumsikan seluruh backend AI dapat diganti. Pembandingnya form/tombol native dan penjelasan template, yang tetap tersedia ketika model tidak dapat dipakai.

Basis: [CBL](../../source-records/CBL.md), [masterplan](../../context/docs/poc/native-trip-replanning-masterplan-2026-11-03.md), [laporan P2](../../../apps/native-routing-lab/docs/verification/NATIVE_TRIP_REPLANNING_P2_2026-11-04.md). Routing hybrid adaptif, jadwal, actual history, revision, validator dan commit tetap milik aplikasi. Field JSON paket ini merupakan **kontrak eksperimen baru, belum adapter yang terpasang di app**.

## Cara menyerahkan

Berikan seluruh folder/ZIP, lalu minta teman atau coding agent membaca [PROMPT-UNTUK-PENGUJI.md](PROMPT-UNTUK-PENGUJI.md). Isinya instruksi kerja lengkap. Penguji memakai [model-instructions.txt](model-instructions.txt) sebagai instructions model, kontrak terstruktur dan satu payload kasus per sesi.

| Berkas | Penerima/kegunaan |
| --- | --- |
| PROMPT-UNTUK-PENGUJI.md | Teman/coding agent: konteks, tugas eksperimen dan laporan |
| model-instructions.txt | Model: ganti placeholder LOCALE dan OUTPUT_LANGUAGE |
| output-contract.json | Kontrak hasil; petakan ke tipe/schema yang tersedia pada framework |
| inputs.jsonl | Model: satu context, history, userMessage per request |
| local-tool-fixtures.json | Wrapper tool; hasil baru diberikan setelah pemanggilan aktual |
| evaluator-only.jsonl | Penguji saja: kunci semantik/tindakan |
| cases-and-rubric.md | Penguji saja: katalog prompt dan harapan |

Seluruh lokasi, ETA, jam, karakter tempat, probabilitas dan sumber adalah **sintetis**. Nama Cipete tidak membuat kandidat fiktif menjadi venue nyata. INT-01 hanya menguji intent extend30; EXPL-01 memasok angka hasil engine untuk menguji penjelasannya. Jangan meminta model menebak hasil engine pada INT-01.

## Cakupan

| Kelompok | Jumlah | Kasus |
| --- | ---: | --- |
| INT | 8 | +30, overdue, negasi, multi-command, ambigu, jam setengah sebelas, typo, koreksi |
| PREF | 2 | Ngopi/membaca/tenang dan prioritas yang belum diputuskan |
| EXPL | 6 | Baseline, golden hour, deadline, probabilitas, kandidat tidak layak, forecast stale |
| REC | 6 | Kandidat bersumber, aksesibilitas unknown, katalog kosong, nama ganda, sumber berselisih, biaya unknown |
| OPS | 6 | ETA hilang, proposal stale, instruksi palsu dalam sumber, riwayat immutable, private car, offline |
| TOOL | 3 | Forecast, pencarian, jam buka dari tool lokal dan error |
| LANG | 1 | Kontrol Inggris yang sepadan dengan INT-01 |
| **Total** | **32** | **29 context +3 local tools; 24 development +8 evaluation** |

## Mode dan dependensi

M1 hanya context; M2 tool baca lokal. Keduanya secara eksplisit memilih model Apple on-device, tanpa jaringan sesudah model siap. Ini memisahkan kualitas model dari kualitas provider. Jangan menyamakan offline inference dengan ETA/cuaca/search terbaru secara offline.

Tool M2 mencatat argumen, hasil dan evidence ID. Query pencarian dinilai semantik kopi/membaca dalam Indonesia atau Inggris, bukan string persis. ID/waktu pada forecast dan jam buka harus tepat. Maksimal **2 tool call/request**, **20 detik total/request**, termasuk tools; tanpa retry otomatis pada pengukuran utama. Ini budget eksperimen, bukan batas framework. TOOL-03 mengembalikan objek unavailable agar model dapat menjelaskan; exception tool diuji terpisah.

Tool tidak menulis storage. Tool tak dikenal, argumen invalid atau budget habis ditolak/dihentikan wrapper dan dicatat. Gunakan API SDK yang benar-benar tersedia. Jangan memaksa tool calling tanpa exit condition.

## Kontrak dan oracle

basedOnRevision menyalin state terbaru. actions adalah intent usulan, bukan commit. requiresConfirmation=true untuk actions/perubahan preference. Tidak ada tindakan otomatis add-place: rekomendasi berupa candidateIDs untuk dipilih pengguna dan dievaluasi engine. Waktu eksplisit ISO-8601 +07:00; field tak relevan null. Confidence model tidak dipakai sebagai probabilitas benar.

Periksa status yang diizinkan, field semantik dan pantangan pada oracle:

- expectedActions: tepat himpunan tindakan itu; urutan boleh berbeda bila actionOrderMatters=false.
- allowedActions: boleh kosong atau subset yang tercantum, dengan status/message sesuai.
- Kasus lain: actions kosong, kecuali oracle menyebut expectedActions/allowedActions.
- requiredEvidence: ID harus ada dan benar-benar mendukung klaim. Menempelkan ID tanpa hubungan belum grounding.
- mustMention: konsep semantik, bukan kalimat yang harus disalin.
- mustNot: perilaku yang tidak boleh muncul. Jangan menyamakan klarifikasi aman tetapi berlebihan dengan aksi salah.

Kritis: target/angka/tanggal perubahan salah, tujuan hilang, fakta aktual diubah, data/ID/sumber dikarang, konflik dianggap layak, mengaku sudah save/apply, atau cloud/network fallback tersembunyi. Decode failure tetap kegagalan, bukan keluaran yang boleh diperbaiki lalu dihitung berhasil. Refusal/unsupported language dipisahkan dari salah memahami intent.

Dua reviewer menilai semantik/rekomendasi dan mencatat ketidaksepakatan sebelum konsensus. Jangan gunakan model lain sebagai satu-satunya hakim. Kunci jawaban dan ID kasus tidak dikirim ke model.

## Protokol hasil minimum

1. Audit availability, locale dan identitas on-device; sanity check dahulu. Jika unavailable, Blocked dan fallback tetap bekerja.
2. Tuning pada 24 development; bekukan prompt/schema/settings sebelum 8 evaluation. Pembagian ini bukan blind holdout karena penguji menerima seluruh paket.
3. Jika eligible, jalankan32×10=320 percobaan.Sesi baru per kasus/pengulangan.INT-08 memakai history user/assistant yang belum commit.Ukur token terhadap batas SDK/runtime; tidak ada asumsi context window universal.
4. Catat scheduled, eligible, attempted, success, error, timeout, refusal, blocked, canceled.Unsupported locale pada preflight tidak dimasukkan sebagai jawaban salah semantic accuracy; tetap menghalangi klaim kesiapan locale.Error setelah request dimulai tetap dalam denominator attempted.
5. Laporkan per kelompok/locale dan platform.Kontrol Inggris satu kasus bukan validasi lengkap Inggris.Tiga kasus tool hanya smoke test orchestration.
6. p50/p90/max untuk kelompok sebanding, cold/warm dan M1/M2 terpisah.Sepuluh keluaran greedy yang identik bukan observasi independen.Jangan meminta chain-of-thought; raw jawaban, field dan tool trace cukup.
7. Simpan semua percobaan, prompt/version/hash dan contoh gagal.Jangan memilih keluaran terbaik atau memperbaiki dengan cloud diam-diam.

Usulan ambang awal berikut **belum requirement produk, bukan standar Apple, dan belum diuji**:

| Area | Sinyal awal untuk integrasi terbatas |
| --- | --- |
| Integritas | 0 critical violation teramati; app validator tetap wajib |
| Bentuk | ≥99% schema/decode success pada attempted utama, tanpa repair tersembunyi |
| Intent | ≥95% exact semantic match pada intent eligible; kasus kritis tetap dilaporkan satu per satu |
| Penjelasan/rekomendasi | ≥90% memenuhi seluruh butir semantik pada kelompoknya; 0 unsupported factual claim kritis |
| Interaksi | Target desain awal p90 warm M1 ≤5 detik pada iPhone target; M2 terpisah |
| Pengguna | Walkthrough melawan form/template; belum dibuktikan paket teknis |

Nilai tiap kemampuan terpisah.Misalnya explanation dapat layak untuk eksperimen meskipun parser perubahan belum layak.Nol kesalahan teramati tidak membuktikan risiko nol; kasus dan pengulangan berkorelasi.Sebelum integrasi, tambahkan paraphrase/skenario baru yang tidak dipakai tuning dan uji iPhone target.

## Kontrol runtime, terpisah dari 32 kasus

| ID | Trigger | Harapan/bukti |
| --- | --- | --- |
| ENV-01 | Device tidak eligible/model not ready/AI tidak aktif | Availability dicatat; form/template tersedia; Blocked bukan fake model success |
| ENV-02 | id_ID unsupported | Pesan dan fallback; tidak diam-diam translate/cloud; en_US kontrol terpisah |
| ENV-03 | Model siap lalu koneksi putus | M1/tool fixture M2 dapat diuji tanpa hosted model request; error apa adanya |
| ENV-04 | Total20detik atau cancel | Harness idle lagi; tidak mengaku aksi selesai; tanpa retry/cloud tersembunyi |
| ENV-05 | RequestA revision7 selesai sesudah state8 | Wrapper menolak hasil lama meskipun JSON valid; ini bukti wrapper |
| ENV-06 | Context panjang dan restart sesi | Batas/error dicatat; rebuild terkontrol mempertahankan constraint terbaru |

## Batas kesimpulan

Lulus INT/PREF membuktikan pemahaman input yang diuji.EXPL membuktikan penjelasan atas angka yang disediakan.REC membuktikan pemilihan dari katalog yang disediakan.TOOL membuktikan pemanggilan tool tertentu.Hasil itu belum membuktikan lokasi aktual, browser bawaan, ETA akurat, pengganti solver atau manfaat pengguna nyata.

Eksperimen jadwal buatan model boleh ditambah sesudah paket utama dengan oracle kecil lengkap dan auditor independen; laporkan kelayakan, tujuan hilang, deadline dan request secara terpisah.Untuk pengganti backend lebih luas, tetap uji sumber data/search/provider langsung, ketersediaan perangkat/bahasa dan failure end-to-end.

## Rujukan resmi yang diperiksa 4 November 2026

Gunakan SDK/runtime aktual, karena versi OS/model dapat mengubah perilaku:

- [Framework overview](https://developer.apple.com/foundation-models-framework/): bedakan on-device dan pilihan model lain.
- [Generation and availability](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models): availability, sesi dan fallback.
- [Languages/locales](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models): cek runtime dan handle unsupported language; template memakai locale instruction.
- [Guided generation](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation): bentuk terstruktur tidak sama dengan benar secara semantik.
- [Tool calling](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling): aplikasi menyediakan tool/sumber; trace/error perlu dicatat.
- [Prompt evaluation](https://developer.apple.com/documentation/foundationmodels/evaluating-prompts-to-measure-performance-and-improve-model-responses): kriteria eksplisit dan pengujian regresi.
- [Framework updates](https://developer.apple.com/documentation/updates/foundationmodels): bekukan versi model/OS pada laporan.
