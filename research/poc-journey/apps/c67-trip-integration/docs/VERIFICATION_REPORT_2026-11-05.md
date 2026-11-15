# Hasil verifikasi prioritas 3 — 5 November 2026

**Integrasi teknis berhasil pada skenario dan perangkat yang diuji.** C67 Trip Integration **v0.1 build 3** sudah dibangun, ditandatangani, dipasang, dan dijalankan di iPhone Giovan. Preferensi → tempat → jam layanan → ETA → cuaca → penjelasan menghasilkan draf yang konsisten; revisi durasi dan penolakan jadwal tidak layak juga bekerja. Ini belum membuktikan kualitas personalisasi terhadap pengguna nyata atau kesiapan produksi.

## Ringkasan bukti

| Pemeriksaan | Hasil | Bukti |
| --- | --- | --- |
| Build iOS bertanda tangan, WeatherKit entitlement | Berhasil; build 3, Bundle ID `giovanchristoffel.c67-trip-integration`, Team `DP5XP7C2AM` | [Log build](../artifacts/build3.log), [metadata hasil](../artifacts/verification-summary.json) |
| Unit/integrasi package | **35/35 lulus**, 4 suite, sekitar 3,25 detik pada run akhir | [Log lengkap](../artifacts/unit-final.log), [inventaris kasus](test-inventory.json) |
| Simulator UI | **2/2 lulus**, iPhone 18 Pro / iOS 27.2 | [Ringkasan xcresult](../artifacts/ui-final-summary.json), [tangkapan layar](../artifacts/ui-final-attachments/705160B2-52AE-411F-A1F3-B716E06084A4.png) |
| Provider asli di iPhone | **7/7 skenario otomatis lulus**, iPhone 17 / iOS 27.0.1 | [Status perangkat](../artifacts/iphone-build3-final/status.json), [console](../artifacts/iphone-live-final-console.log) |
| Pencarian MapKit Mac | **6/6 identitas terpilih** pada policy akhir | [Respons MapKit asli](../artifacts/mac-mapkit-probe-final.json) |
| Kecocokan data lintas ekspor | Jumlah request, set tujuan, referensi sumber, metadata Apple dan raw report cocok; bukan simulasi | [Audit ekspor](../artifacts/cross-artifact-audit.json) |
| Source routing lama | Sepuluh file asli tetap identik dengan hash sebelum penyalinan | Audit di atas dan [manifest](vendor-manifest.json) |

Simulator menjalankan replay sintetis. Bukti provider asli berasal dari iPhone dan probe Mac; keduanya tidak disamakan dengan replay. Pengujian dimulai setelah Giovan mengonfirmasi kapabilitas WeatherKit sudah ditambahkan. Peluncuran iPhone sempat tertahan oleh kunci perangkat dan berhasil dilanjutkan setelah dibuka.

## Hasil iPhone per kemampuan

| Kasus | Hasil aktual | Durasi skenario |
| --- | --- | --- |
| L01 · WeatherKit langsung | Data hourly asli dan metadata tersedia; legal attribution serta URL mark Apple dikembalikan. **Fallback mati**, tanpa Open-Meteo | 0,16 dtk |
| L02 · Tanpa profil | Label general; tiga venue unik dipertahankan, rute selesai, accepted plan disimpan, dibaca ulang dan diekspor | 29,47 dtk |
| L03 · Wajib membaca + kopi | BDT RBBJ lolos dengan fakta dari area yang sama; lokasi dan ETA asli; jam Jumat 12.30 dihormati | 2,32 dtk |
| L04 · Outdoor / hujan lebih rendah | GBK dan Ragunan tetap ada; sesi layanan dan seluruh durasi kunjungan valid; dua hasil waktu berstatus `context_ranked` | 7,35 dtk |
| L05 · Kategori vs E5 | Inferensi lokal ONNX CPU/int8 berhasil; hard gate tetap sama pada kategori dan E5 | 0,80 dtk untuk rangkaian perbandingan |
| L06 · Durasi +30 menit | Seluruh tiga tujuan dipertahankan, rute dan interval cuaca dihitung ulang. Proposal lalu ditolak; accepted baseline tetap tersimpan | 29,15 dtk |
| L07 · Deadline terlalu pendek | Hasil `conflicted`; tidak ada waktu mulai valid setelah tiba dan batas pulang terlewati. Tujuan tidak dihapus agar terlihat muat | 2,70 dtk |

Durasi merupakan observasi satu run, bukan SLA. Framework Apple dapat memakai cache internal. L03/L06/L07 juga memakai cache aplikasi untuk prakiraan yang masih mencakup rentang yang diminta. Jumlah `weather_groups` adalah operasi fetch grup, bukan hitungan panggilan internal hourly/daily/attribution atau HTTP server.

### Contoh jadwal nyata yang dihitung

Tanggal trip **Jumat, 6 November 2026**, seluruh waktu di bawah **WIB**. Ini rencana berdasarkan ETA/prakiraan yang diambil pada 5 November, bukan observasi perjalanan atau kondisi lapangan pada 6 November.

| Tempat | Baseline | Setelah durasi BDT +30 menit |
| --- | --- | --- |
| Perpustakaan Jakarta, Cikini | 09.15–10.15 | 09.15–10.15 |
| Erasmus Huis Library | 10.45–11.45 | 10.45–11.45 |
| Baca Di Tebet, RBBJ | 12.30–13.30 | 12.30–14.00 |
| Kembali ke titik MapKit Bundaran HI | **13.55.21** | **14.29.46** |

Return berubah **34 menit 25 detik**: durasi kunjung bertambah 30 menit dan estimasi perjalanan kembali berubah pada waktu berangkat baru. Waktu perjalanan total berubah 67,47 → 71,88 menit, sedangkan waktu tunggu tetap sekitar 47,88 menit. Deadline 19.00 tetap dipenuhi. Peluang hujan maksimum pada interval BDT tetap 4% pada forecast ini; nilainya sama tidak berarti interval kunjungannya diabaikan. [Baseline asli](../artifacts/iphone-build3-final/L02-plan.json), [revisi asli](../artifacts/iphone-build3-final/L06-plan.json).

Skenario outdoor menghasilkan GBK **07.30–08.30**, Ragunan **09.15–10.15**, kembali **10.55.55**. GBK berada di sesi pagi sebelum tutup 10.00; tidak menyeberangi jeda 10.00–15.00. [Data outdoor](../artifacts/iphone-build3-final/L04-plan.json).

### Request dan waktu proses

| Kasus | Search MapKit | ETA MapKit | Fetch grup cuaca baru | Waktu routing |
| --- | --- | --- | --- | --- |
| Tiga tempat, baseline | 4 | 24 | 2 | 27,82 dtk |
| BDT saja | 2 | 2 | 0; cache | 1,74 dtk |
| GBK + Ragunan | 3 | 6 | 3 | 6,18 dtk |
| Tiga tempat, +30 menit | 4 | 24 | 0; cache | 27,78 dtk |
| Deadline singkat | 2 | 2 | 0; cache | 2,06 dtk |

Pada contoh tiga tempat, sebagian besar waktu proses berada pada routing, bukan embeddings. Engine mempertahankan pacing ETA 1,2 detik dan melakukan validasi alternatif. Metode hybrid adaptif tidak diganti untuk mempercepat benchmark ini. Batas 512 request tidak tercapai pada run tersebut; perilaku live 4–6 tujuan belum dibuktikan.

Perbandingan preferensi menggunakan **13 kartu area**, 10 eligible untuk profil kasus L05. Waktu tahap preferensi kategori sekitar **0,53 ms**; E5 panggilan pertama dalam proses **0,778 dtk**, pengulangan dengan cache **1,31 ms**. Pengulangan memakai cache query/passage, sehingga angka 1,31 ms bukan benchmark inferensi model baru. E5 memakai `intfloat/multilingual-e5-small`, revisi `614241f622f53c4eeff9890bdc4f31cfecc418b3`, 384 dimensi, ONNX Runtime 1.24.2 / CPU / int8. Ranking berubah sementara hard gate tetap sama. Kandidat tanpa jam layanan tetap tidak bisa langsung dijadwalkan, meskipun skor semantiknya tinggi. Tidak ada label penilaian manusia atau klaim akurasi personal dari perbandingan ini.

## Temuan yang diperbaiki selama verifikasi

1. **Batas actor pada Swift:** closure task-group bertanda `@MainActor` memicu error region-based isolation checker Xcode 27.2; actor hop kini melalui protocol `Sendable`. Callback async pada salinan bulk search juga dibuat eksplisit `@MainActor`. Original routing source tidak diedit.
2. **Kasus uji cache:** percobaan awal menghitung usia cache dari fetch pertama, padahal rentang yang diperluas sudah diambil lagi 120 detik kemudian. Test kini membuktikan cache masih valid pada usia781 detik dan refetch setelah usia901 detik dari fetch terbaru. Policy cache tidak dilonggarkan untuk meluluskan test.
3. **Helper UI:** `Form` membuat baris secara lazy. Assertion sebelum scrolling salah menganggap kontrol tidak ada. Helper kini mencari sambil scrolling; alur review/accept benar-benar berjalan, dengan screenshot pada hasil.
4. **Nama nyata Cikini:** MapKit mengembalikan **“Jakarta Provincial Library”**, alamat **Jalan Cikini Raya No.73**. Predicate Indonesia terlalu ketat dan awalnya menghentikan L02/L07 serta memblokir L06. Alias Inggris kini khusus untuk identitas Cikini dan tetap mewajibkan alamat cabang Cikini. Dua regression test membuktikan alias benar diterima dan cabang Nyi Ageng Serang tetap ditolak. Bukti awal [Mac](../artifacts/mac-mapkit-probe.json) dan [iPhone build2](../artifacts/iphone-build2-first/status.json) dipertahankan.

Jadi hasil akhir bukan sekadar mengulang happy path; pengujian live menemukan masalah yang tidak terlihat dalam fixture, lalu fix diuji ulang pada Mac, unit, Simulator dan iPhone.

## Penyimpanan, ekspor dan isolasi

Eval memakai direktori `Documents/P3LiveEval/Session`, terpisah dari session normal aplikasi. Baseline diterima, dipulihkan, diekspor, lalu proposal +30 menit ditolak tanpa mengganti baseline. [Ekspor fisik](../artifacts/iphone-build3-final/Session/exports/CE510818-1040-4C5A-830C-BC679699E63A/REPORT.md) menyertakan JSON eksperimen, native report dan provider log. Audit lintas file mencocokkan request count, set tujuan dan source ID yang dipakai, serta memastikan raw report tidak mempunyai `simulationKind`.

Source dan storage PoC lama dipertahankan. Setelah evaluasi selesai, iPhone dikembalikan ke layar normal C67 Trip Integration; tidak ada provider yang otomatis dipanggil saat layar normal pertama dibuka.

## Batas kesimpulan dan kasus yang belum diuji live

- **L08:** kegagalan/cuaca unknown, timeout dan pemulihan data rusak lulus pada fault injection. Jaringan iPhone tidak sengaja dimatikan untuk percobaan gangguan nyata.
- **L09:** cancellation kini diuji saat benar-benar menunggu ETA; epoch stale-result dan version guard lulus. Interaksi fisik mengganti input saat proses berjalan, background dan relaunch belum diobservasi manual. Simulator membuktikan happy path review/accept.
- **L10:** penyimpanan/pemulihan/ekspor di iPhone dan audit angka/sumber antarfile berhasil. Seluruh detail tampilan live dan pemuatan gambar mark Apple belum diperiksa manual di iPhone; URL atribusinya tersedia dan komponen UI sudah disiapkan.
- Runtime yang diuji adalah iOS27.0.1 pada iPhone17 dan Simulator iOS27.2. Minimum deployment iOS26 berhasil dikompilasi; runtime iOS26 belum dicoba.
- Katalog sengaja terbatas; ada lima venue unik dengan jam yang dapat dijadwalkan pada tanggal tersebut, sedangkan kartu tanpa bukti jam ditahan. Cakupan Jakarta secara luas, live4–6 tempat dan perubahan fakta setelah batas tujuh hari tetap membutuhkan bukti baru.
- Saran waktu tetap advisory. Ini tidak membuktikan optimizer global seluruh preferensi waktu, kenyamanan rute di lapangan, kapasitas, antrean, tiket atau pengecualian hari libur.
- Belum ada sesi pengguna, penilaian kepuasan, pengukuran RAM/energi, atau bukti pengurangan kontribusi pengguna. Lulus integrasi tidak otomatis menjawab manfaat produk.

**Keputusan:** prioritas 3 sudah mempunyai bukti integrasi teknis pada skenario yang diuji. Komponen rekomendasi lokal dapat berjalan tanpa backend AI tim; layanan MapKit/WeatherKit tetap memerlukan jaringan dan layanan Apple. Data tempat, validasi pengguna dan keandalan perjalanan aktif menjadi pekerjaan berikutnya, tanpa mengubah hasil P3 menjadi klaim produksi.
