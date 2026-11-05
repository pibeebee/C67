# PoC itinerary AI tanpa UI — 2 November 2026

Chat ini mengembangkan eksperimen CLI terpisah; pekerjaan aplikasi C67 di chat lain tetap terpisah. Instruksi terbaru pengguna membuka pilihan non-Apple untuk memudahkan PoC dan memilih OpenRouter sebagai akses model AI.

Implementasi berada di [poc/ai-trip-planner](../../../../apps/ai-trip-planner/README.md). Pekerjaan PoC ini tidak mengubah kode iOS, server, kontrak atau database pada repository `<LOCAL_HOME>/Programming/software/ios/C67`.

## Alur dan keputusan

- Input JSON berisi tujuan, koordinat, preferensi, tanggal, waktu, durasi dan asumsi karakter tempat.
- Google Routes memberikan matriks terarah dan ETA ulang berdasarkan waktu keberangkatan tiap leg. Open-Meteo memberikan prakiraan per jam serta sunrise/sunset. OpenRouter memilih kandidat yang sudah dihitung dan menjelaskan tradeoff.
- Kode memeriksa jadwal, ID tujuan dan referensi bukti. Penjelasan AI tetap memerlukan review fakta/manusia.
- Mode `live` wajib menggunakan ketiga provider; `fixture-ai` menggunakan AI nyata dengan data tetap; `fixture` adalah demonstrasi tanpa AI yang ditandai eksplisit.
- Replan menerima snapshot manual kunjungan selesai, posisi saat ini dan waktu siap berangkat. Destinasi tersisa dipertahankan; ketidaklayakan dilaporkan.
- Satu hari WIB, 1–5 tujuan, satu moda DRIVE/WALK. Batas selesai berarti selesai kunjungan terakhir tanpa perjalanan pulang. Tidak ada UI, pencarian/rekomendasi tempat, web research, auth, GPS tracking atau deployment baru.

Pilihan non-Apple ini adalah batas eksperimen, bukan penggantian otomatis framework aplikasi final. Layanan Apple membutuhkan validasi tersendiri ketika integrasi dilanjutkan.

## Contoh hasil sintetis

Dengan fixture A/B/C/D pengguna, durasi kunjungan contoh dan forecast buatan, pilihan skor kontekstual adalah `B → D → C` (75 menit perpindahan; C 17:00–17:45), sementara pembanding perjalanan terpendek `D → C → B` menggunakan 48 menit tetapi melewatkan preferensi waktu dan terkena peluang hujan buatan yang lebih tinggi. Perpanjangan di D sampai 17:20 dengan B/C belum dikunjungi menghasilkan konflik batas selesai 19:00; keduanya tetap berada dalam hasil.

Hasil tersebut tidak berasal dari Google, Open-Meteo atau AI nyata. Ini demonstrasi konsekuensi input dan bobot penjadwal, bukan bukti perjalanan lapangan.

## Bukti dan batas validasi

Verifikasi lokal pada 2 November 2026, menggunakan Node 24.14.0:

- TypeScript (`npm run check`) dan format kode (`npm run format:check`) lulus.
- **27/27 pemeriksaan backend lulus**, termasuk alur CLI live dan fixture-ai dengan HTTP tiruan, preservasi tujuan, jadwal asimetris, data hilang serta keluaran model yang tidak sah. Respons AI pada pemeriksaan tersebut adalah stub; tidak ada inferensi model nyata.
- CLI fixture, replan konflik dan replan satu tujuan tersisa berhasil dijalankan. Contoh konflik melampaui batas selesai sebanyak 45 menit, dengan B dan C tetap dijadwalkan.
- **Satu request Open-Meteo nyata berhasil** melalui adapter: 24 sampel per jam untuk tanggal 3 November 2026 dan sunset `2026-11-03T10:46:43Z` (17:46:43 WIB), tanpa peringatan adapter. Ini bukti konektivitas/format respons pada titik contoh, bukan verifikasi akurasi prakiraan lapangan.
- Pemeriksaan konfigurasi dan percobaan mode live/fixture-ai berhenti dengan pesan konfigurasi yang belum lengkap, sebelum pemanggilan Google/AI. Tidak ada fallback AI diam-diam.
- Tidak menjalankan tes iOS, Simulator, deployment, commit atau push.

Kredensial Google/OpenRouter belum tersedia pada verifikasi awal tersebut. Lihat hasil smoke test lanjutan di bawah, [README](../../../../apps/ai-trip-planner/README.md) untuk perintah dan [rubrik evaluasi](../../../../apps/ai-trip-planner/EVALUATION.md) untuk keputusan eksperimen selanjutnya.

## Smoke test setelah pengguna mengisi `.env` — 2 November 2026

- Semua variabel wajib terbaca `set`; nilai API key tidak ditampilkan atau disalin ke laporan.
- Model terpilih `nvidia/nemotron-3-ultra-550b-a55b:free` mengembalikan HTTP 404 pada request itinerary. Katalog publik OpenRouter mengonfirmasi model tersebut ada, tetapi daftar parameter yang didukung tidak mencantumkan `response_format` atau `structured_outputs`, yang dibutuhkan request PoC.
- Satu model gratis pembanding, `liquid/lfm-2.5-2.6b:free`, dicoba melalui override environment sementara. Respons itinerary tidak selesai normal; tes JSON minimal terpisah dengan reasoning dinonaktifkan mendapat HTTP 400. Tidak ada hasil AI yang diterima sebagai itinerary berhasil; `.env` pengguna tetap dipertahankan.
- Google `computeRoutes` dasar berhasil, HTTP 200, untuk titik contoh A/B: 3.131 meter dan 647 detik. Ini bukan verifikasi identitas atau karakter tempat contoh.
- Google `computeRouteMatrix` mengembalikan HTTP 403 dengan alasan eksplisit **`BILLING_DISABLED`**. API meminta billing diaktifkan pada project yang terkait key. Keberhasilan rute dasar tidak membuktikan akses matriks sudah tersedia.
- Pipeline live lengkap belum lulus. Tidak ada deployment atau perubahan konfigurasi akun, billing, maupun file `.env` oleh pekerjaan pengujian ini. Bukti lokal tersimpan di `poc/ai-trip-planner/results/smoke-2026-11-02-diagnostics.json` dan log smoke; folder hasil tetap diabaikan Git.

Langkah berikutnya: pengguna mengaktifkan billing Google dan menentukan model/endpoint OpenRouter yang kompatibel, lalu ulangi smoke test sebelum menilai mutu itinerary.

### Pengulangan pukul 17:04 WIB

- Matriks Google kini **berhasil, HTTP 200**, dengan request `DRIVE`/`TRAFFIC_AWARE` untuk satu pasangan titik contoh: 3.131 meter, 656 detik. Kendala matriks Google pada percobaan sebelumnya sudah tidak muncul.
- Model di `.env` masih `nvidia/nemotron-3-ultra-550b-a55b:free`. Tes JSON kecil mendapat **HTTP 404** dengan pesan `No endpoints found that can handle the requested parameters.` Request memakai JSON Schema dan `provider.require_parameters: true`, sesuai kebutuhan PoC.
- Tidak melanjutkan panggilan itinerary lengkap karena pemeriksaan kompatibilitas AI belum lolos. Tidak mengubah `.env`. Bukti tersimpan di `poc/ai-trip-planner/results/retry-2026-11-02T10-04-30-904Z.json`.

Kendala yang tersisa pada pengulangan ini adalah pemilihan model/endpoint OpenRouter yang dapat menerima parameter structured output PoC.

### Model pilihan pengguna: Nemotron 3.5 Super VL

Pengguna meminta `nvidia/nemotron-3.5-super-vl:free`. Hasil pengujian lanjutan:

- Request pertama diterima HTTP 200, tetapi `finish_reason=length`: seluruh 2.500 completion token digunakan sebagai reasoning, tanpa jawaban akhir. Tidak menerima keluaran tersebut sebagai itinerary.
- Menambahkan konfigurasi opsional `OPENROUTER_REASONING=auto|off`. Dengan `off`, request mengirim `reasoning.enabled=false`; budget tetap 2.500 token. Konfigurasi dan budget ikut tersimpan pada laporan.
- **Fixture + AI nyata berhasil**: HTTP 200, `finish_reason=stop`, 1.120 completion token, nol reasoning token; tujuan dan referensi bukti lolos pemeriksaan.
- **Satu pipeline live lengkap berhasil**: satu matriks Google, sepuluh request leg, tiga request Open-Meteo dan satu request OpenRouter. Semua tujuan dipertahankan, jadwal terstruktur layak terhadap input, cakupan prakiraan lengkap; durasi run sekitar 10,4 detik. Hasil tersimpan di `poc/ai-trip-planner/results/super-vl-live/report.json`.
- Review manusia awal menemukan AI salah mengonversi jam dalam prosa. Memperbarui konteks model agar semua timestamp sudah berupa WIB `+07:00`, menjelaskan arah skor dan membedakan rain-exposure proxy dari durasi hujan.
- Satu replay AI pada kandidat live yang sudah tersimpan berhasil menggunakan konteks WIB baru; tidak mengambil rute/cuaca lagi. Keluaran ada di `poc/ai-trip-planner/results/super-vl-readable-replay/report.md`. Jam yang disebut pada replay sesuai tabel, tetapi satu narasi masih menyebut kunjungan D berdurasi 60 menit padahal input/tabel 45 menit. **Kualitas prosa belum lulus penuh.** Tabel jadwal tetap dihitung kode dan tidak berubah mengikuti narasi AI.
- Menyetel `.env` lokal ke model pilihan pengguna dan reasoning `off`, dengan mempertahankan nilai API key. Menambahkan pemeriksaan request reasoning dan timestamp prompt; **28/28 pemeriksaan lokal**, TypeScript dan format lulus.

Kesimpulan teknis: model dapat digunakan pada pipeline PoC. Kesimpulan kualitas: koneksi, JSON dan konsistensi tabel sudah terbukti pada smoke ini; akurasi seluruh alasan serta manfaat itinerary masih perlu dievaluasi, khususnya klaim angka dalam narasi.

### Perbandingan reasoning off/on dengan budget lebih besar

Pengguna meminta reasoning diaktifkan dan ruang token diperbesar. Implementasi menambahkan mode eksplisit `on`, batas completion sampai 32.768 token, timeout AI yang dapat diatur sampai 180 detik, dan command `npm run compare:reasoning`.

Eksperimen memakai data kandidat Google/cuaca yang sama, tanpa lookup provider tersebut lagi. Hash prompt dan JSON Schema identik di kedua konfigurasi dan di kedua pengulangan; masing-masing request memakai 6.775 input token. Model memiliki kapasitas konteks 1.000.000 token menurut katalog, tetapi memperbesar `max_tokens` mengubah budget reasoning/jawaban, bukan menambahkan konteks/fakta input.

| Ukuran pada pengulangan kedua | Off | On |
|---|---:|---:|
| Batas completion | 2.500 | 16.384 |
| Reasoning terpakai | 0 | 2.805 |
| Token jawaban akhir | 924 | 998 |
| Waktu request AI | 7,86 detik | 30,03 detik |
| Lolos validasi struktur/referensi | Ya | Tidak |

Percobaan pertama juga dipertahankan: off 58,23 detik (gagal kelengkapan alasan); on 39,81 detik dengan 2.102 reasoning token (gagal kelengkapan alasan). Secara keseluruhan off lolos 1/2 dan on 0/2; ini sampel eksplorasi kecil, bukan benchmark keunggulan atau estimasi latensi yang stabil.

Pada pengulangan kedua, on menghasilkan enam entri alasan untuk tiga tujuan karena menambahkan entri referensi terpisah untuk D/B/C. Validator menolak respons tersebut. Review prosa juga menemukan on menyebut menunggu di B, sedangkan kandidat menghitung menunggu di C. Off menyamaratakan peluang hujan C menjadi 100% pada semua kandidat, meskipun kandidat direct tertentu sekitar 94,64%.

Budget yang lebih besar mengatasi kehabisan token, tetapi belum menunjukkan peningkatan keandalan pada sampel ini. Teks reasoning internal tidak disimpan atau ditampilkan; perbandingan memakai jawaban akhir dan counter token. Ringkasan lengkap tersimpan di `poc/ai-trip-planner/results/reasoning-comparison-summary.md`.

Sesuai permintaan pengguna, `.env` aktif sekarang memakai reasoning `on`, completion 16.384 dan timeout 180.000 ms. Model serta API key dipertahankan. **29/29 pemeriksaan lokal**, TypeScript dan format lulus setelah perubahan.
