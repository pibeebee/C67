# Prompt lengkap untuk teman atau coding agent penguji

Salin seluruh blok berikut ke coding agent yang membantu eksplorasi dan lampirkan paket ini. Ini **instruksi kerja penguji**, bukan seluruhnya untuk dikirim ke Foundation Models.

~~~text
Saya ingin menguji apakah Apple on-device Foundation Models dapat melengkapi aplikasi itinerary native kami tanpa ketergantungan backend AI tim/OpenRouter.

KONTEKS
Pengguna memilih tujuan, waktu berangkat, batas tiba di endpoint dan preferensi. Aplikasi menyusun itinerary satu hari dan memperbarui sisa perjalanan ketika pengguna tinggal lebih lama, skip tujuan atau mengubah deadline. Model diharapkan membantu memahami bahasa pengguna, mengekstrak preferensi, menjelaskan konsekuensi, dan merekomendasikan kandidat tempat berdasarkan data.

Contoh produk penting: pengguna suka ngopi sambil membaca; pengguna ingin lebih lama di D tetapi C memiliki kesempatan golden hour. Golden hour adalah preferensi lunak, bukan jam tutup.

PoC native sudah mempunyai routing hybrid adaptif, deadline, storage, lifecycle manual, extend, skip, review/apply/reject, revision dan cancellation. Timestamp aktual tidak boleh diubah oleh replan. Semua pending stop yang tidak di-skip tetap wajib. Endpoint asal dan deadline absolut dipertahankan. Anchor dikonfirmasi manual. Lingkup aktif satu hari dan satu moda walking atau on-demand automobile; private car/transit belum didukung. Model tidak perlu menggantikan solver yang sudah ada untuk membuktikan manfaatnya.

PERTANYAAN EKSPERIMEN
1. Apakah model memahami Bahasa Indonesia sehari-hari, negasi, jam lokal, typo dan koreksi multi-turn menjadi intent yang benar?
2. Apakah ia menjelaskan hasil solver, konflik dan ketidakpastian tanpa mengarang fakta atau mengklaim perubahan sudah diterapkan?
3. Apakah ia memberi rekomendasi personal dari kandidat bersumber, dengan tradeoff dan unknown yang jelas?
4. Apakah ia menggunakan tool baca lokal untuk mengambil konteks dan menangani kegagalannya?
5. Bagian mana tetap membutuhkan kode native, sumber data/provider, atau keputusan pengguna?

Jangan simpulkan seluruh backend tergantikan hanya karena model dapat mengobrol atau menghasilkan JSON.

BAHAN
- README.md: protokol, batas dan gerbang keputusan.
- model-instructions.txt: instruksi runtime; ganti locale/outputLanguage per kasus.
- output-contract.json: kontrak hasil; petakan ke tipe @Generable/enum atau schema yang benar-benar tersedia pada SDK.
- inputs.jsonl:32 kasus. Kirim hanya context, history, userMessage untuk SATU kasus per sesi.
- local-tool-fixtures.json: hasil tool lokal untuk 3 kasus. Jangan memasukkan hasil tool ke prompt sebelum model benar-benar memanggil tool.
- evaluator-only.jsonl dan cases-and-rubric.md: kunci penilaian. JANGAN kirim ke model, termasuk case ID/nama skenario/expected output.

PELAKSANAAN
Bangun harness kecil terpisah; tidak perlu UI produk baru. Pertahankan source/data lama. Jika checkout PoC tersedia, baca dokumentasi aktual dahulu. Jangan mengubah atau mengimplementasikan ulang solver untuk membuat model terlihat berhasil. Kontrak paket ini adapter evaluasi baru, belum terintegrasi ke app.

Pilih secara eksplisit model Apple ON-DEVICE. Nama framework Foundation Models bukan bukti inferensi lokal karena pilihan model pada SDK dapat berbeda. Tidak ada fallback diam-diam ke Private Cloud Compute, OpenRouter, ChatGPT atau model cloud. Catat kategori/identitas model dan cara memastikannya. Hasil mock atau build berhasil bukan inferensi berhasil.

Catat perangkat, OS/build, Xcode/SDK, availability, region, locale app, bahasa didukung menurut runtime, opsi generation dan versi prompt/schema. Cek id_ID dan en_US melalui API yang tersedia. Jika Indonesia tidak didukung atau model unavailable, catat Blocked dan sediakan form/template. Jangan translate lewat cloud atau mengubah bahasa diam-diam. Tes Indonesia di luar dukungan resmi boleh menjadi diagnostik terpisah, bukan Passed dukungan produk.

Jalankan mode terpisah:
M1: model on-device dengan context, tanpa tools/jaringan; 29 kasus context.
M2: model on-device dengan tool baca fixture lokal, tanpa jaringan; 3 kasus local_tools.
Catat transcript tool, input, output dan jumlah panggil. Tidak ada tool mutasi.

Setelah model siap/terunduh, ulangi sampel dengan koneksi diputus. Provider ETA/cuaca/tempat live tidak ikut diuji offline. Jangan melabeli fixture sebagai MapKit/WeatherKit live.

PROTOKOL
1. Sanity check1 kasus dahulu. Jika unavailable, jangan memalsukan hasil 32 kasus.
2. Tuning pada 24 development; simpan semua percobaan dan versi prompt. Bekukan prompt/kontrak/settings sebelum 8 evaluation dipakai. Ini pemisahan operasional, bukan studi blind.
3. Sesudah dibekukan, jalankan seluruh 32 kasus masing-masing10 kali:320 percobaan jika semua eligible. Sesi baru per kasus/pengulangan. INT-08 memakai history eksplisit sebagai turn user/assistant yang belum commit, bukan sebagai fakta perubahan sudah disimpan.
4. Catat sampling/temperature/seed jika tersedia; jangan mengarang API atau memaksa randomness. Keluaran greedy berulang bukan observasi independen.
5. Nilai field semantik, ID, target, angka, waktu, negasi dan evidence, bukan kesamaan wording. Schema valid tidak berarti isi benar. Nilai raw output sebelum repair; retry/repair menjadi metrik terpisah.
6. Ukur schema/decode success, intent exact-match, factual accuracy, unsupported claims, clarification tepat, rekomendasi/tool success, latency p50/p90/max, error/timeout/refusal. Denominator harus jelas. Pisahkan M1/M2, cold/warm dan platform.
7. Gunakan aturan deterministik serta dua reviewer manusia untuk semantik/rekomendasi. Catat ketidaksepakatan sebelum konsensus. Model lain bukan satu-satunya hakim; tidak perlu cloud. Simpan jawaban dan alasan singkat yang terlihat pengguna, bukan chain-of-thought.
8. Jalankan kontrol runtime tambahan pada README: unavailable, bahasa unsupported, offline, timeout/cancel, hasil lama setelah revision berubah, context panjang dan restart sesi. Keberhasilan wrapper menolak hasil lama adalah bukti wrapper, bukan intelligence model.
9. Hasil Mac/Simulator dan iPhone fisik dilaporkan terpisah. Mac tidak membuktikan latency/availability iPhone.

LARANGAN
- Jangan beri kunci jawaban ke model, hard-code jawaban dari case ID, atau menghapus gagal dari laporan.
- Jangan membiarkan model menulis storage, mengubah fakta aktual, memindahkan endpoint, menghapus tujuan, menggeser deadline atau apply tanpa validator dan konfirmasi.
- Jangan mengarang ETA, jam buka, harga, alamat, URL, cuaca atau klaim sudah browsing.
- Jangan menilai jawaban yang terdengar meyakinkan sebagai bukti routing benar.
- Jangan mencampur provider live, cloud, fine-tuning atau adapter training ke hasil on-device dasar.

DELIVERABLE
A. Harness yang dapat diulang dan instruksi menjalankannya.
B. Manifest perangkat/model/SDK/locale serta hash prompt/schema/source fixture.
C. Hasil setiap percobaan: runID, caseID, promptVersion, mode, latency, raw output, parsed fields, error, tool trace, semantic grade, critical violation.
D. Tabel32 kasus Passed/Failed/Blocked/Not run, jumlah pengulangan dan contoh gagal asli.
E. Ringkasan TERPISAH untuk Bahasa Indonesia, intent, explanation, recommendation, tool use, offline/runtime. Availability dan kualitas bukan metrik sama.
F. Perbandingan alur tanpa model: form/tombol/template sudah bisa menyelesaikan tugas. Tunjukkan apakah model mengurangi input/kebingungan atau memberi personalisasi; hasil teknis saja belum membuktikan manfaat pengguna.
G. Keputusan per kemampuan: integrasi terbatas, revisi, atau tunda. Pakai ambang PoC README sebagai hipotesis awal, bukan standar Apple/jaminan produksi.
H. Jawab tegas: bagian AI backend mana dapat diganti lokal, bagian mana tetap membutuhkan sumber data/provider/kode native, perangkat/bahasa mana belum terlayani, dan tes berikut paling penting.

Jika akses perangkat/runtime menghalangi, selesaikan harness/fixture yang dapat diperiksa dan laporan Blocked dengan alasan serta pekerjaan terverifikasi. Jangan sebut tes yang belum dieksekusi sebagai lulus.
~~~

Opsional sesudah paket utama: uji model menghasilkan urutan/jadwal pada oracle kecil lengkap lalu audit dengan solver independen. Pisahkan eksperimen itu dari language assistant dan jangan mengganti routing PoC hanya berdasarkan satu contoh berhasil.
