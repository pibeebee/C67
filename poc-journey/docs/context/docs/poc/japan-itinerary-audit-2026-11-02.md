# Audit PoC Jepang — Funabashi, Kamakura, Enoshima

Pengguna memberikan 24 baris jadwal dan meminta pengujian PoC, reasoning tetap on, serta plafon total 1.000.000 token. Tanggal diklarifikasi sebagai tiga hari setelah 2 November 2026: **5 November 2026**, dengan zona waktu **Asia/Tokyo / JST**. Pengguna meminta melanjutkan setelah limit sebelumnya habis; data dikumpulkan dan disimpan agar bisa dipakai ulang.

## Implementasi dan batas eksperimen

- [Input lengkap](../../../../apps/ai-trip-planner/examples/funabashi-enoshima-2026-11-05.json) mempertahankan 24 baris, urutan dan jam baseline. Oiwayamichi tetap ditandai opsional.
- Command `npm run audit:itinerary` mengaudit jadwal panjang dan leg WALK/TRANSIT. Penjadwal lama 1–5 tujuan tidak dipaksa memproses permutasi 24 baris.
- Apartment, restoran siang/malam, toko suvenir tertentu, posisi clock tower dan titik pantai depan sekolah tidak ditetapkan sebagai lokasi presisi tanpa data pengguna. Cuaca memakai empat titik regional yang disebut sebagai pendekatan.
- Semua waktu prompt/jadwal baru sudah JST `+09:00`, bukan WIB. Provider transit diminta tanpa parameter traffic khusus mobil.
- Snapshot pengumpulan disimpan sebelum AI, termasuk respons kosong. `--reuse` mengulangi AI saja tanpa mengambil Google/cuaca ulang.
- Saran AI belum diterapkan. Ini pemeriksaan baseline secara berurutan, bukan optimasi ulang atau simulasi keterlambatan yang dipropagasikan sepanjang hari.

## Konfigurasi dan batas token

Model `nvidia/nemotron-3.5-super-vl:free`, reasoning `on`, reserve completion 16.384 token, timeout AI 180 detik, plafon total konteks 1.000.000 token.

Preflight konteks menggunakan estimasi konservatif ukuran request UTF-8 plus 8.192 cadangan overhead; ini bukan hasil tokenizer model yang persis. Nilai aktual diverifikasi dari `prompt_tokens + completion_tokens`, dengan reasoning sudah termasuk completion. Batas konteks aktual provider tetap berlaku. API key dipertahankan dan tidak dimasukkan ke artefak hasil.

## Bukti pengujian nyata

Hasil utama: `poc/ai-trip-planner/results/japan-2026-11-05-run1/`.

| Bagian | Hasil |
|---|---|
| Baris baseline | 24/24 dipertahankan |
| Leg yang dimodelkan | 18; lima interval lain adalah aktivitas pada area yang sama |
| WALK tersedia | 7 |
| TRANSIT tanpa rute | 6 query; hasil kosong tidak membuktikan perjalanan kereta mustahil |
| Lokasi belum spesifik | 5 leg tidak dimintakan rute; nilai durasi tetap null |
| Cuaca | 4 area × 24 jam, tanpa peringatan adapter |
| Panggilan pengumpulan | 13 Google Routes, 4 Open-Meteo |
| Kontrol transit tambahan | 1 Google request memakai Place ID dan tanpa preferensi moda, tetap tanpa rute |
| AI | Selesai normal, JSON dan referensi sumber lulus |
| Input token | 25.044 |
| Reasoning token | 6.555 |
| Jawaban akhir token | 2.841 |
| Total token | 34.440 dari plafon 1.000.000 |
| Waktu AI | 53,97 detik |
| Pemeriksaan lokal | 37/37 lulus; TypeScript dan format lulus |

## Temuan yang dapat ditelusuri ke data

1. **Illumination perlu diperjelas.** Pengumuman operator terbaru menyebut Shonan no Hoseki 2026–2027 mulai **1 Desember 2026** sampai **28 Februari 2027**. Shonan Candle 2026 berakhir **3 November 2026**. Kedua acara musiman itu tidak berlangsung pada 5 November; ini tidak membuktikan semua pencahayaan malam biasa tidak tersedia. [Hoseki](https://enoshima-seacandle.com/information/post-4136/), [Candle](https://enoshima-seacandle.com/information/post-4039/).
2. **Coastal walk terlalu ketat pada titik yang dipetakan.** Google memberi sekitar 17,6 menit untuk Shichirigahama → Kamakurakokomae, sedangkan slot pengguna 15 menit. Titik pantai depan sekolah belum dipatok presisi, sehingga angka ini tetap estimasi untuk titik hasil pemetaan, bukan pengukuran rute jalan kaki pengguna.
3. **Sea Candle pukul 17:00 berada setelah sunset regional.** Forecast memberi sunset Enoshima sekitar **16:44 JST**. Ini relevan untuk ekspektasi pemandangan sore; tidak membuktikan ketersediaan acara malam.
4. **Peluang hujan regional tinggi pada sebagian kunjungan luar ruang.** Pada snapshot yang diambil 2 November, forecast Kamakura sekitar 73% pukul 12:00 dan 72% pukul 13:00; Enoshima sekitar 65% pukul 16:00 dan 58% pukul 17:00. Angka adalah probabilitas prakiraan, bukan jaminan atau prediksi menit hujan.
5. **Kereta dan tiba apartment pukul 22:00 belum terverifikasi.** Keenam request transit tidak memberi rute. Return memakai Funabashi Station sebagai proxy; transfer ke apartment belum diketahui. Tidak mengganti data tersebut dengan angka dari pengetahuan model.
6. **Tourist Center pukul 15:15 masuk jam umum yang dipublikasikan**, 08:30–17:00, dengan penutupan khusus tanggal tetap belum diperiksa. [Sumber resmi kota](https://www.fujisawa-kanko.jp/info/tourist_Information.html).

## Review jawaban AI

AI mengenali ketidakpastian rute kereta, lokasi makan/apartment, konflik coastal walk, serta perbedaan musim illumination. Namun:

- Beberapa saran menempatkan sisa waktu slot pada lokasi tujuan berikutnya. Contohnya E15→E16 (15:15–15:45): perjalanan dari Tourist Center ke jembatan diperkirakan lima menit. Sisa 25 menit secara baseline adalah untuk kunjungan Tourist Center sebelum tiba di jembatan pada 15:45, sedangkan narasi menyebut aktivitas di jembatan. Pola serupa muncul pada E03→E04 dan E16→E17.
- Walaupun prompt meminta prioritas maksimal 12 temuan, model memberi 16; validator menerima rentang struktural 1–20. Tidak menganggap semua instruksi gaya telah dipatuhi.
- Cuaca serta sunset disertakan pada data dan tabel kode, tetapi tidak dibahas secara memadai dalam temuan utama AI. Konteks lebih besar tidak otomatis menjamin variabel produk yang paling penting mendapat prioritas.
- Validasi referensi mengecek ID, bukan kebenaran seluruh hubungan fakta dalam narasi.

Kesimpulan: pipeline dapat mengaudit skenario nyata yang lebih panjang, menangani JST serta data yang hilang, dan mempertahankan sumber. Jadwal belum dapat dinyatakan layak utuh; mutu penalaran naratif masih memerlukan perbaikan/evaluasi. Tidak ada perubahan pada aplikasi iOS C67 atau deployment.
