# Evaluasi PoC

**Pertanyaan:** apakah AI yang diberi kandidat berbasis data dapat memilih dan menjelaskan itinerary yang masuk akal, serta membantu memahami konsekuensi perubahan?

**Given:** tujuan dipilih pengguna; AI wajib membantu pada PoC nyata; tanpa UI; Google Routes + Open-Meteo + OpenRouter.

**Assumed:** maksimal lima tujuan; WIB; satu moda; durasi/jam buka/karakter tempat dimasukkan manual; batas selesai adalah akhir kunjungan terakhir; bobot skor sementara.

**Needs validation:** cakupan dan akurasi ETA/cuaca Jakarta, identitas/tempat/jam buka, mutu penjelasan AI, nilai personalisasi, latensi dan biaya aktual, serta manfaat dibanding baseline.

## Hubungan requirement dan bukti

| Kebutuhan | Hipotesis | Artefak | Bukti yang diperlukan |
|---|---|---|---|
| Urutan mempertimbangkan waktu/cuaca | Kunjungan C dapat ditempatkan saat kondisi/jendela lebih sesuai | Skor kandidat + penjelasan AI + baseline | Review alasan serta forecast/ETA yang benar-benar digunakan |
| Destinasi tetap di tangan pengguna | Keterlambatan tidak menghapus tempat diam-diam | Snapshot replan dan laporan infeasible | Semua ID tersisa terjaga, konflik dinyatakan |
| AI membantu secara berarti | Pilihan/penjelasan AI memperjelas tradeoff preferensi | `fixture-ai` untuk data tetap, kemudian `live` | Penilaian manusia terhadap baseline; bukan hanya respons 200 |
| Kemampuan dapat dibawa ke aplikasi | Logika dapat memakai penyedia data berbeda | Pemisahan `DataProvider` dan penjadwal | Uji layanan Apple tersendiri pada tahap berikutnya |

## Syarat teknis minimum

- Tidak ada tujuan ditambah/dihapus atau durasi diubah tanpa instruksi pengguna.
- Semua waktu konsisten dengan leg dan kunjungan sebelumnya.
- Pelanggaran jam buka/batas selesai ditampilkan; kandidat tidak layak tidak dipilih jika kandidat layak tersedia dalam hasil refinement.
- Mode AI benar-benar menghubungi OpenRouter dan mencatat model/usage; tidak boleh menganggap fixture sebagai AI.
- Data tidak tersedia tetap unknown. Fakta angka ditelusuri ke bukti; konteks manual dilabeli asumsi.

Syarat ini dapat diperiksa otomatis, tetapi belum membuktikan jadwal nyaman dijalani atau penjelasan bebas klaim keliru.

## Rubrik review manusia

Untuk masing-masing lima skenario di README, simpan input dan laporan pada direktori run terpisah. Gunakan data fixture yang sama ketika membandingkan model. Provider live berubah sepanjang waktu; catat tanggal pengambilan serta model aktual.

| Dimensi | Pertanyaan reviewer | Catatan / hasil |
|---|---|---|
| Dukungan fakta | Apakah setiap klaim penting sesuai data, tanpa mengarang tempat, jam buka, kondisi atau sumber? | Belum dievaluasi |
| Preferensi | Apakah pilihan mempertimbangkan preferensi pengguna dan menjelaskan konflik? | Belum dievaluasi |
| Jadwal | Apakah durasi, menunggu dan perpindahannya masuk akal untuk perjalanan tersebut? | Belum dievaluasi |
| Ketidakpastian | Apakah kekurangan data dan peluang terlewat disampaikan secara jujur? | Belum dievaluasi |
| Perubahan | Apakah replan mempertahankan kunjungan selesai dan semua tujuan tersisa? | Belum dievaluasi |
| Nilai tambah AI | Dibanding skor kode/urutan awal/rute terpendek, apa yang menjadi lebih berguna? | Belum dievaluasi |

**Keputusan berikutnya:** lanjutkan integrasi aplikasi bila tidak ada pelanggaran syarat teknis dan reviewer menilai rencana serta alasan berguna pada skenario yang diuji. Jika AI hanya mengulang skor, mengarang fakta, atau melewatkan konflik penting, revisi prompt/kandidat/sumber data lalu ulangi. Ini kriteria kerja PoC, bukan bukti user value yang sudah tervalidasi.

## Catatan run

| Run / mode | Model aktual | Data / waktu pengambilan | Hasil teknis | Hasil review manusia | Keputusan |
|---|---|---|---|---|---|
| Fixture lokal | Tidak ada AI | Matriks ilustrasi + cuaca sintetis | Lihat catatan implementasi | Bukan evaluasi kualitas AI | Siap menjalankan eksperimen dengan kredensial |
| `fixture-ai`, smoke 2 November 2026 | `nvidia/nemotron-3-ultra-550b-a55b:free` | Fixture tetap | HTTP 404; katalog model tidak mencantumkan `structured_outputs` | Belum dapat dievaluasi | Pilih model/endpoint yang kompatibel |
| Pembanding sementara, smoke 2 November 2026 | `liquid/lfm-2.5-2.6b:free` | Fixture tetap | Respons itinerary tidak selesai normal; tes JSON minimal terpisah mendapat HTTP 400 | Belum lulus | Tidak direkomendasikan sebagai model yang sudah terverifikasi; `.env` tidak diubah |
| Google terisolasi, smoke 2 November 2026 | Tidak ada AI | Titik contoh A/B | Rute dasar HTTP 200; matriks HTTP 403 `BILLING_DISABLED` | Bukan evaluasi mutu itinerary | Aktifkan billing pada project Google yang terkait key |
| Pipeline `live` lengkap | Belum dijalankan sampai selesai | — | Terhalang konfigurasi matriks/kompatibilitas model | — | Ulangi sesudah dua kendala tersebut diperbaiki |

Pengulangan 2 November 2026 pukul 17:04 WIB: matriks Google sudah HTTP 200 (3.131 meter/656 detik pada titik contoh). Model aktif masih sama dan tes JSON terstruktur tetap HTTP 404 dengan pesan `No endpoints found that can handle the requested parameters.` Pipeline lengkap belum dapat dievaluasi sampai kompatibilitas model diperbaiki; `.env` tidak diubah oleh pengujian.

Pengujian berikutnya menggunakan model yang diminta pengguna, `nvidia/nemotron-3.5-super-vl:free`:

| Run | Hasil teknis | Hasil review awal | Keputusan |
|---|---|---|---|
| Default reasoning, 2.500 token | HTTP 200 tetapi seluruh budget habis untuk reasoning; tidak ada jawaban akhir | Tidak ada itinerary yang diterima | Uji reasoning off |
| Fixture-ai, reasoning off | HTTP 200, JSON valid; 1.120 token keluaran | Narasi salah mengonversi beberapa jam dari epoch | Perjelas timestamp WIB pada konteks model |
| Live, reasoning off | Google + Open-Meteo + AI berhasil; sekitar 10,4 detik, tujuan/tabel terjaga | Prosa masih mengandung jam yang tidak sesuai tabel | Tidak menganggap kualitas prosa lulus |
| Replay atas kandidat live dengan konteks WIB | AI berhasil; jam yang disebut sesuai tabel, tanpa request Google/cuaca baru | Masih menyebut durasi D 60 menit padahal tabel/input 45 menit | Pertahankan tabel dari kode sebagai otoritas; lanjutkan evaluasi/validasi prosa |

Konfigurasi lokal model dan reasoning diperbarui sesuai percobaan yang berhasil; API key dipertahankan. Smoke ini membuktikan konektivitas dan pipeline pada contoh, bukan kebenaran semua penjelasan atau kelayakan pengalaman perjalanan nyata.

## Eksperimen reasoning dan budget yang diperbesar

Model dan data sama; hash prompt/schema sama. Dua percobaan per konfigurasi memakai input 6.775 token, off 2.500 completion token versus on 16.384 completion token. Tidak ada pengambilan data Google/cuaca baru. Reasoning internal tidak disimpan.

| Percobaan | Off | On |
|---|---|---|
| 1 | 58,23 detik; 0 reasoning + 1.059 token akhir; ditolak | 39,81 detik; 2.102 reasoning + 719 token akhir; ditolak |
| 2 | 7,86 detik; 0 reasoning + 924 token akhir; lolos struktur/referensi | 30,03 detik; 2.805 reasoning + 998 token akhir; ditolak karena 6 alasan untuk 3 tempat |

Review pengulangan kedua: off menyamaratakan peluang hujan C sebagai 100% pada semua kandidat; ada kandidat direct dengan sekitar 94,64%. On menyebut menunggu di B, sedangkan perhitungan menempatkan waktu menunggu di C, serta menduplikasi alasan tujuan. Tidak ada hasil yang dianggap bebas kesalahan semantik hanya karena JSON valid.

Keputusan eksperimen: budget tambahan memungkinkan reasoning selesai, tetapi belum ada bukti kualitas lebih andal pada sampel kecil ini. Konfigurasi on/16.384 disimpan sesuai permintaan pengguna untuk eksplorasi berikutnya, dengan validator tetap aktif. Lihat `results/reasoning-comparison-summary.md` untuk jawaban, fakta acuan dan seluruh kegagalan yang dipertahankan.
