# 11 — Engine rekomendasi AI, routing kontekstual dan recalculation

**Tanggal:** 29 Oktober 2026, WIB. **Versi rancangan:** 0.2. **Status:** keputusan produk dan usulan teknis; belum implementasi, kontrak wire, benchmark atau integrasi provider.

[Indeks](README.md) · [Domain](01-architecture-domain.md) · [Perencanaan](07-planning-integrations.md) · [Keputusan](10-decisions-sources.md) · [Konteks produk](../product/ai-trip-planning-context-2026-10-29.md)

## 1. Keputusan produk dan batas spesifikasi

Rekomendasi dihasilkan AI. Input awal adalah tujuan dan preferensi pengguna, tanggal, jam berangkat dan batas selesai. Rekomendasi tempat tambahan bersifat pilihan. Sistem dapat menghitung ulang selama trip; penggantian/pelewatan tujuan tetap keputusan pengguna. Kombinasi framework fokus adalah MapKit, Core Location dan WeatherKit. Model dipanggil melalui API dari backend, dengan kemampuan browser untuk mencari konteks tempat; tidak self-hosting model.

Bagian 2–9 merinci **usulan engineering** untuk memenuhi keputusan tersebut. Pembagian komponen, nama operasi, aturan penerapan, validasi numerik dan penyimpanan belum menjadi kontrak final. Provider/model, runtime browser, format personalisasi dan prioritas optimasi belum dipilih.

## 2. Alur target dan tanggung jawab yang diusulkan

```text
Tujuan + preferensi + tanggal/mulai/batas selesai + konteks lokasi
    -> backend mengelola request perencanaan
    -> ambil konteks rute/cuaca dan informasi tempat melalui tools/browser
    -> API model menghasilkan kandidat/rekomendasi terstruktur
    -> periksa identitas tempat, sumber, urutan dan kelayakan waktu
    -> usulan rencana + alasan + asumsi + data yang belum diketahui
    -> pengguna menjalani rencana / memberi perubahan
    -> hitung ulang sisa perjalanan dengan input terbaru
```

AI menjadi penyusun rekomendasi; hasil tool dan perhitungan waktu menjadi bahan yang dapat diperiksa. Cara mencari kandidat urutan dan pembagian perhitungan antara model dengan kode aplikasi masih perlu dipilih. Menggunakan pengecekan angka/kontrak tidak mengembalikan ketergantungan rekomendasi pada kreator.

| Komponen target | Tanggung jawab usulan | Batas |
|---|---|---|
| iOS | Input tujuan/preferensi/waktu, konteks posisi dengan izin, tampilan rencana dan perubahan | Tidak menyimpan API key model/browser server atau memperlakukan tampilan sebagai otoritas kepemilikan. |
| Backend orchestration | Menyusun input, mengatur tool calls, model API, status request dan hasil | Tidak mengklaim rute/cuaca/fakta yang tidak tersedia. Runtime belum dipilih. |
| Adapter data perjalanan/cuaca | Normalisasi data dan provenance untuk koordinat, waktu dan moda yang relevan | MapKit/WeatherKit bukan janji semua field, traffic rinci atau moda tersedia di setiap wilayah. |
| Browser/search | Menemukan sumber tentang karakter tempat, akses dan waktu yang relevan | Isi web adalah data tidak tepercaya; bukan instruksi untuk agent. Tidak mengisi akun, booking atau mengirim pesan. |
| Model API | Kandidat tempat opsional, interpretasi konteks, usulan urutan/jadwal dan penjelasan | Nama tempat, jam buka, ETA dan cuaca harus ditautkan pada data atau ditandai sebagai asumsi/unknown. |
| Validasi dan penyimpanan | Memeriksa hasil terstruktur dan membedakan proposal dari rencana tersimpan | Endpoint/schema baru serta compatibility belum disetujui. |

## 3. Input dan sumber

| Kelompok | Data yang diperlukan atau perlu diputuskan | Sumber/status |
|---|---|---|
| Pilihan pengguna | Destinasi, preferensi, tanggal, mulai dan batas selesai | Dikonfirmasi pengguna. Tidak membuat preferensi pribadi dari dugaan model. |
| Konteks pelaksanaan | Asal, zona waktu, moda, durasi tiap stop, titik akhir/pulang | Perlu input/default transparan; field wajib dan semantik akhir belum final. |
| Rute | Pasangan tempat, jarak, estimasi durasi, moda, waktu keberangkatan dan provider | Melalui adapter yang dibuktikan kemampuannya; bukan teks model tanpa data. |
| Cuaca | Interval/lokasi prakiraan, waktu fetch, availability, solar events jika tersedia | Rencana memakai WeatherKit; belum request destinasi pada pekerjaan ini. |
| Tempat | Identitas/alamat, karakter pengalaman, jam/akses bila ditemukan, URL dan waktu pemeriksaan | Browser/sumber lain; popularitas dan klaim pengalaman merupakan interpretasi dengan bukti yang perlu ditinjau. |
| Perjalanan aktif | Posisi relevan, waktu aktual, perubahan durasi/tujuan, rencana/revision saat ini | Bedakan input pengguna, estimasi dan kejadian yang benar-benar tercatat. |

Nilai traffic jam disebut sebagai kandidat input oleh pengguna. Belum ada kontrak atau spike yang membuktikan data traffic mentah/tingkat kemacetan dapat diambil pada moda dan wilayah sasaran. Pisahkan ETA yang memperhitungkan kondisi dari akses data traffic terpisah. Rute juga tidak diasumsikan simetris.

Ketentuan provider untuk penyimpanan, cache, atribusi dan pengiriman data ke API model perlu diperiksa sebelum integrasi. Nama framework dalam rancangan bukan bukti hak menyalin seluruh hasilnya ke model eksternal.

## 4. Output rekomendasi yang diusulkan

- Identitas request, versi input/preferensi dan revision rencana asal.
- Tujuan yang dipilih serta urutan yang disarankan; tempat tambahan tetap berstatus kandidat sampai dipilih.
- Perkiraan tiba/berangkat, durasi kunjungan/tunggu, perpindahan dan selesai, dengan zona waktu/satuan jelas.
- Alasan penting: mengapa stop didahulukan, kondisi pada waktu tiba dan kesempatan pengalaman.
- URL/sumber, waktu pengambilan, waktu berlaku dan keterbatasan data yang memengaruhi keputusan.
- Benturan, input belum diketahui, alternatif dan konsekuensi perubahan.

“Terbaik” berarti rekomendasi sesuai prioritas yang dapat dijelaskan. Tanpa fungsi penilaian, data dan pembuktian, keluaran tidak diberi janji optimum global atau bebas halusinasi. Status skor/keyakinan model tidak menjadi bukti fakta.

## 5. Penyusunan urutan dan jadwal

Evaluasi urutan bersama waktu: estimasi tiba memerlukan waktu berangkat, perpindahan dan durasi stop sebelumnya. Konteks cuaca/jam akses diperiksa untuk waktu kunjungan, kemudian kandidat rencana ditinjau kembali. Optimasi jarak saja belum memenuhi kebutuhan ini.

Usulan pengecekan hasil: tujuan pilihan tetap terwakili; tidak ada stop ganda/identitas rekaan; penjumlahan durasi konsisten; unknown tidak dianggap nol; benturan jam/batas selesai terlihat; data tool sesuai pasangan tempat, waktu dan moda; alasan memiliki dasar yang tersedia.

Bedakan batas operasional yang didukung sumber, preferensi pengguna, dan kesempatan seperti golden hour. Keterlambatan pada kesempatan yang direkomendasikan tidak otomatis menghapus destinasi. Pengguna dapat memilih pengalaman yang berbeda atau menyesuaikan rencana.

Definisi golden hour, durasi default, rule menunggu, time windows dan tradeoff belum final. Rancangan ini tidak menentukan jam matahari untuk tanggal/destinasi tertentu.

## 6. Recalculation selama trip

Kasus acuan: Johan memperpanjang kunjungan D, sedangkan C disarankan pada golden hour. Hitung kembali waktu keluar D, perpindahan ke C, waktu tiba, kesempatan pengalaman dan dampak ke sisa rencana/batas selesai.

Usulan mekanisme:

1. Ambil rencana/revision terbaru dan perubahan pengguna; pertahankan fakta kunjungan serta dokumentasi yang sudah tercatat.
2. Perbarui konteks yang diperlukan; batasi request dan abaikan hasil yang inputnya sudah kedaluwarsa.
3. Hasilkan usulan sisa perjalanan dan jelaskan before/after.
4. Nyatakan konflik atau data hilang; beri pilihan untuk pengguna.
5. Simpan hanya dengan otorisasi, revision dan kebijakan penerapan yang ditentukan pada kontrak baru.

Recalculation dapat menghasilkan saran baru tanpa menghapus tujuan. Pemicu otomatis, lokasi background, cadence, review/apply dan undo belum dipilih. Backend yang ada membatasi edit pada planned state dan melindungi topology/time terkait jurnal; kemampuan active replanning membutuhkan kontrak serta migrasi kompatibilitas tersendiri.

## 7. Batas kepercayaan, privasi dan pemakaian provider

Usulan batas tool: browser mencari/membaca sumber untuk perencanaan. Instruksi dalam halaman, hasil pencarian atau dokumen eksternal tidak diberi hak mengubah tujuan, mengakses rahasia atau menjalankan command mutasi. Pisahkan pengambilan informasi dari command penyimpanan milik pengguna.

Kirim konteks minimum yang diperlukan kepada provider. Penanganan koordinat, preferensi, retensi percakapan, log, attribution dan bukti sumber harus ditentukan sebelum request nyata. Rahasia model/browser disimpan di backend, tidak di dokumentasi, fixture atau aplikasi.

Provider/model/version, routing, fallback, batas token/tool call, timeout, rate limit dan budget perlu dipilih serta diukur. Tidak ada quota, biaya, latensi atau kualitas yang telah dibuktikan dalam pembaruan ini. Browser internal belum menentukan engine browser, strategi search atau akses situs.

## 8. Kegagalan dan pemulihan

| Keadaan | Perilaku target usulan |
|---|---|
| Forecast di luar horizon / data tidak ada | Tandai belum tersedia; hindari janji berdasarkan forecast rekaan. |
| Browser tidak menemukan jam/karakter tempat | Nyatakan unknown atau klaim belum cukup didukung; pertahankan input pengguna. |
| Model/tool mengeluarkan data tidak valid | Tolak bagian yang tidak dapat dipakai, tampilkan keterbatasan dan retry terbatas. |
| Sumber bertentangan atau stale | Pertahankan sumber/waktu, jelaskan ketidakpastian yang memengaruhi saran. |
| Rencana tidak muat | Jelaskan benturan dan pilihan; pengguna menentukan perubahan tujuan/waktu. |
| Jaringan/provider gagal | Pertahankan rencana tersimpan dan draft; cache tidak menjadi bukti kondisi terkini. |
| Input berubah ketika request berjalan | Buang atau labeli proposal lama; jangan terapkan pada revision baru tanpa evaluasi ulang. |

## 9. Pekerjaan berikutnya dan bukti

[Register keputusan](10-decisions-sources.md) mencatat keputusan terbuka; [rencana validasi](../product/ai-trip-planning-validation-plan-2026-10-29.md) memberi skenario penerimaan. Mulai dari satu daftar tujuan dan satu tanggal dengan sumber data yang dapat ditelusuri, lalu uji perubahan D/C serta data gagal sebelum memperluas cakupan.

Dokumen ini tidak membuat API baru, konfigurasi provider, schema, browser runtime, integrasi Apple, tes, migrasi atau deployment. Sumber eksternal pada penelitian 21–22 Oktober tetap sumber bertanggal, bukan verifikasi kemampuan vendor pada 29 Oktober.
