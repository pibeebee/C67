# 01 — Arsitektur, domain dan aturan bisnis AI trip planning

**Diperbarui:** 29 Oktober 2026, WIB. **Status:** rancangan 0.2; keputusan produk dipisahkan dari usulan implementasi.

[Indeks](README.md) · [Engine AI](11-ai-planning-engine.md) · [Database](03-database.md) · [API](04-backend-api.md) · [Keputusan](10-decisions-sources.md)

## 1. Batas produk

Pengguna membawa tujuan awal dan preferensi, menentukan tanggal/jam berangkat/batas selesai, lalu menerima rekomendasi AI mengenai tambahan opsional, urutan dan jadwal. Rekomendasi dapat diperbarui selama trip. AI dipanggil melalui API backend dengan kemampuan browser; model tidak di-self-host. MapKit, Core Location dan WeatherKit menjadi fokus integrasi.

Ketergantungan pada rundown kreator dilepas. Istilah atau tabel kreator yang masih ada pada kode/kontrak merepresentasikan baseline implementasi; perubahan semantiknya memerlukan desain kompatibilitas tersendiri.

## 2. Tanggung jawab target — usulan

| Lapisan | Tanggung jawab |
|---|---|
| Domain iOS | Input tujuan/preferensi/waktu, snapshot rencana/proposal dan keadaan perjalanan. |
| Application/data iOS | Mengelola request, persistensi yang dipilih, akun, pemulihan dan hasil yang sudah superseded. |
| Adapter native | Konteks lokasi dan layanan tempat/rute/cuaca yang kemampuannya telah dibuktikan. |
| Backend | Otorisasi, orchestration model API/browser/tools, status request dan pengelolaan proposal. |
| Validasi/perencanaan | Memeriksa identitas tempat, sumber, aritmetika jadwal dan benturan; pembagian pencarian urutan antara model/kode belum final. |
| Penyimpanan | Memisahkan input pengguna, proposal, rencana diterima dan fakta kejadian dengan revision/ownership. |

Fondasi Supabase/VIPER/Auth yang sudah ada dicatat dalam repository C67. Rancangan ini tidak menetapkan vendor model, runtime server/browser, package, tabel atau endpoint baru sebagai sesuatu yang sudah tersedia.

## 3. Istilah domain aktif

| Istilah | Makna |
|---|---|
| Tujuan pilihan | Tempat yang dipilih pengguna untuk dipertimbangkan dalam trip. |
| Kandidat tambahan | Rekomendasi AI yang belum menjadi pilihan pengguna. |
| Place | Identitas tempat, dibedakan dari satu kejadian kunjungan. |
| Stop | Kemunculan kunjungan di rencana. |
| Leg | Perpindahan dari asal atau antarkunjungan dengan estimasi dan sumber. |
| Preferensi | Minat/prioritas yang diberikan atau dikonfirmasi pengguna. |
| Konteks | Data tempat, perjalanan, cuaca dan waktu yang berlaku untuk input tertentu. |
| Proposal | Usulan AI yang belum otomatis menjadi fakta atau rencana tersimpan. |
| Trip plan | Rencana personal yang dipakai pengguna; tidak wajib berasal dari versi kreator. |
| Recalculation | Penyusunan ulang rekomendasi berdasarkan masukan atau keadaan terbaru. |
| Actual event | Kejadian yang tercatat, dengan sumber/waktu sendiri; tidak diisi dari ETA atau teks model. |

## 4. Batas yang diturunkan dari keputusan pengguna

- Tujuan awal dan preferensi pengguna merupakan dasar perencanaan.
- Tempat tambahan bersifat pilihan; keputusan mengganti/melewati tujuan tetap milik pengguna.
- Tanggal, jam berangkat dan batas selesai dari pengguna menjadi acuan rekomendasi.
- Recalculation dapat terjadi saat trip berjalan, termasuk karena pengguna tinggal lebih lama di suatu tempat.
- AI menjadi penghasil rekomendasi dengan data pendukung; pengalaman kreator tidak menjadi prasyarat.

## 5. Aturan engineering yang diusulkan

- Pisahkan input, prakiraan, estimasi, interpretasi AI dan kejadian aktual.
- Bedakan proposal dari perubahan yang sudah disimpan. Kebijakan review/penerapan otomatis masih perlu dipilih.
- Data yang hilang tidak menjadi nol atau fakta rekaan. Provenance mencakup sumber, waktu fetch dan waktu relevansi.
- Lindungi kepemilikan/revision dan cegah hasil request lama menimpa input/rencana terbaru.
- Replanning mempertahankan fakta kunjungan serta dokumentasi yang sudah diterima.
- Request retry tidak mengulang efek penyimpanan; concurrency dan idempotency perlu kontrak baru yang kompatibel.
- Browser membaca sumber dengan batas tool; isi halaman tidak menjadi instruksi untuk mengambil alih rencana atau mutasi.

Usulan di atas memerlukan kontrak dan pengujian sebelum menjadi invariant implementasi baru. Auth/otorisasi yang sudah ada tetap mengikuti kontrak repository.

## 6. Waktu dan lifecycle

Gunakan tanggal/zona tujuan, waktu berangkat, durasi kunjungan dan perpindahan untuk menilai waktu tiba/selesai. Makna batas selesai terhadap perjalanan pulang, waktu tunggu dan prioritas benturan belum final. Kesempatan cahaya adalah rekomendasi pengalaman kecuali pengguna menetapkan batas lain.

Fase konseptual adalah input → proposal → rencana dipakai → perjalanan berlangsung → usulan perubahan. Ini bukan enum database baru. Definisi start/arrival/completion/skip/berhenti dini dan hubungannya dengan foto/album perlu ditentukan ulang.

## 7. Hubungan dengan baseline 0.1 dan kode yang ada

Model lama memisahkan versi kreator dan salinan trip; pemisahan tersebut masih harus dijaga untuk data/API lama. Rencana baru membutuhkan jalur input tujuan sendiri dan provenance AI/tools. Rancangan baru tidak mengubah arti `source_version_id` atau menempelkan identitas kreator palsu pada hasil AI.

Backend lama memakai planned-only edits dan melindungi topology/time terkait jurnal. Dukungan recalculation aktif perlu definisi kunjungan yang tetap, sisa rencana yang dapat diubah, serta migration/compatibility. Jangan membuka guard lama hanya dengan mengganti dokumen.

Protokol media/presence, angka parameter, lifecycle kreator dan kewajiban foto pada spesifikasi 0.1 adalah referensi bertanggal. Cakupan journaling pada engine baru belum diputuskan. [Snapshot 0.1](../../../missing-evidence.md#missing-e4ef2b63f729) menyimpan rincian lama tanpa mengaktifkannya kembali.
