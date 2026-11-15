# 07 — Perencanaan urutan, waktu dan integrasi eksternal

**Diperbarui:** 29 Oktober 2026, WIB. **Status:** target 0.2; belum integrasi atau algoritme yang teruji.

[Indeks](README.md) · [Engine AI](11-ai-planning-engine.md) · [Domain](01-architecture-domain.md) · [Keputusan](10-decisions-sources.md)

## 1. Sasaran perencanaan

AI menyusun rekomendasi urutan dan jadwal dari tujuan/preferensi serta tanggal, jam berangkat dan batas selesai pengguna. Konteks tempat, rute dan cuaca memberi dasar untuk rekomendasi. Sistem dapat mengevaluasi ulang sisa perjalanan saat input atau keadaan berubah.

Ini menggantikan batas rancangan lama yang hanya menjadwalkan urutan tetap dan tidak memerlukan LLM. Cara mengeksplorasi urutan, memilih skor dan membagi perhitungan antara model/kode masih terbuka. Rekomendasi tidak diberi jaminan optimum global.

## 2. Kontrak provenance — usulan

Setiap fakta/estimasi yang memengaruhi rencana membawa sumber (`user`, provider, browser/source atau calculation), URL/reference bila sesuai, waktu pengambilan, interval relevansi, availability dan ketidakpastian. Interpretasi AI dibedakan dari data sumber.

Informasi “terkenal karena …” dapat menjadi karakterisasi dari sumber, bukan fakta objektif tanpa bukti. Jam buka, akses dan event yang ditemukan perlu waktu pemeriksaan. Halaman yang berhasil dibaca tidak otomatis memverifikasi seluruh klaimnya.

## 3. Waktu dan evaluasi urutan

Input tambahan yang perlu dipastikan: asal, zona waktu, moda, durasi tiap stop, aturan menunggu dan titik akhir/pulang. Jangan mengunci asumsi tersebut tanpa label yang dapat ditinjau pengguna.

```text
tujuan pilihan + preferensi + tanggal/mulai/batas selesai
    -> konteks tempat, estimasi leg dan cuaca pada interval relevan
    -> kandidat urutan dan jadwal dari engine AI
    -> evaluasi waktu tiba, durasi, jendela pengalaman dan konflik
    -> rekomendasi + alasan + alternatif + unknown
```

Waktu tiba memengaruhi konteks cuaca dan kesempatan pengalaman yang dinilai. Bila urutan atau waktu tinggal berubah, estimasi leg dan interval cuaca yang relevan mungkin perlu diperbarui. Unknown tidak menjadi durasi nol. Rencana yang tidak muat harus dinyatakan, dengan opsi untuk pengguna.

Pisahkan waktu pilihan pengguna, waktu rencana, interval prakiraan dan kejadian aktual. Zona dan offset harus jelas; waktu lokal ambigu/lintas hari perlu kontrak tersendiri. Batas selesai belum otomatis berarti tiba di rumah.

## 4. Place lookup, rute, moda dan traffic

MapKit/Core Location adalah arah integrasi tempat, perjalanan dan posisi yang dipilih pengguna. Identitas/alamat yang ambigu perlu diselesaikan sebelum menjadi dasar rencana. Cara distribusi request antara app/server dan bentuk DTO harus dirancang serta diuji.

Verifikasi kemampuan dan ketersediaan untuk wilayah/moda sasaran. ETA, rute rinci, informasi transportasi umum dan data traffic mentah merupakan kebutuhan berbeda; tidak ada klaim semuanya tersedia hanya karena memakai MapKit. Jika sumber gagal, jangan mengganti moda/durasi tanpa label.

Usulan identitas estimasi: pasangan endpoint, waktu berangkat, moda, provider, waktu fetch dan parameter relevan. Estimasi kedaluwarsa atau untuk pasangan lama tidak dipakai setelah reorder. Rute nyata tidak diasumsikan simetris.

## 5. WeatherKit dan kesempatan cahaya

Rencana memakai WeatherKit untuk prakiraan dan solar events yang tersedia. Evaluasi konteks lokasi/waktu kunjungan dan perpindahan, bukan hanya cuaca kota secara umum. Availability, horizon, timestamp dan atribut kosong perlu dibuktikan pada destinasi; tidak ada query API baru pada pekerjaan dokumen ini.

Sunrise/sunset berbeda dari jendela golden hour. Definisi/perhitungan jendela, tanggal/zona, penghalang dan pengaruh awan perlu ditinjau. Aplikasi tidak menjamin kualitas cahaya atau foto. Jika kesempatan terlewat, kunjungan tetap pilihan pengguna.

Atribusi, cache, penyimpanan dan transfer data provider ke layanan AI memerlukan pemeriksaan ketentuan sebelum integrasi. [Riset WeatherKit 21 Oktober](../research/weatherkit-traveller-experience-research-2026-10-21.md) dan [hubungan cahaya/cuaca/moda 22 Oktober](../research/keterkaitan-cahaya-cuaca-moda-rundown-2026-10-22.md) tetap referensi bertanggal; bukan bukti live response saat ini.

## 6. Browser dan API model

Backend menghubungkan API model dengan pencarian informasi tempat. Provider/model dan runtime browser belum dipilih. Perlu batas tool/read, sumber yang dapat ditelusuri, penanganan halaman gagal/bertentangan dan pemeriksaan input/output.

Browser tidak menggantikan layanan cuaca/routing dengan teks rekaan, dan instruksi halaman bukan instruksi pengguna. Detail orchestration, privasi, budget dan kegagalan ada pada [spesifikasi engine](11-ai-planning-engine.md).

## 7. Recalculation dan penyimpanan

Saat Johan tinggal lebih lama di D, perbarui perkiraan keluar D dan tiba di C, kesempatan golden hour, sisa tujuan dan batas selesai. Jelaskan perbedaan dan pilihannya. Pengguna memutuskan perubahan tujuan.

Usulan teknis adalah mengikat proposal ke input/preferensi/revision saat dibuat, menjaga fakta yang sudah terjadi dan menolak hasil stale. Pemicu, cadence, review/apply, undo dan background behavior belum ditentukan. Kontrak backend planned-only perlu pengembangan tersendiri sebelum perubahan pada perjalanan aktif dapat disimpan.

## 8. Riwayat

Merge rundown A/B, ranking library kreator dan scheduler urutan tetap adalah rancangan 0.1, tersimpan dalam [snapshot](../../../missing-evidence.md#missing-e4ef2b63f729). Data/API yang sudah memakainya tidak diubah oleh dokumentasi ini. Feature foto/album serta framework di luar kombinasi fokus belum ditetapkan ulang untuk engine baru.
