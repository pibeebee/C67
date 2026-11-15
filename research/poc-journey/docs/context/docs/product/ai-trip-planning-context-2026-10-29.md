# Konteks produk — rekomendasi AI untuk trip personal

**Tanggal:** 29 Oktober 2026, WIB. **Audiens:** tim produk, desain, mentor dan pengembang. **Status:** keputusan pengguna dan penjelasan konsep; belum hasil validasi atau fitur berjalan.

[CBL](../../../source-records/CBL.md) · [Alur pengguna](ai-trip-planning-user-flow-2026-10-29.md) · [Engine target](../technology/11-ai-planning-engine.md) · [Validasi](ai-trip-planning-validation-plan-2026-10-29.md)

## 1. Pengalaman dan engine

Pengguna mempunyai tujuan awal, memilih rekomendasi tambahan bila dibutuhkan, memperoleh rencana, mengunjungi tempat dan menyesuaikan perjalanan. Pengalaman ini melanjutkan konsep sebelumnya. Engine rekomendasi kini mengandalkan AI dengan data pendukung, tanpa prasyarat rundown dari orang yang pernah berkunjung.

“Full AI” menjelaskan siapa yang menghasilkan rekomendasi. Fakta cuaca, estimasi perjalanan dan informasi tempat tetap dibedakan dari interpretasi AI. Browser yang menemukan halaman tidak otomatis menjadikan seluruh isinya benar atau mutakhir.

| Sudah dikonfirmasi pengguna | Belum ditentukan |
|---|---|
| AI menghasilkan rekomendasi; model dipanggil melalui API backend | Provider, model, versi, routing provider dan kebijakan datanya |
| Pengguna menentukan tujuan dan memilih tempat tambahan | Format personalisasi/onboarding, field wajib dan penyimpanan preferensi |
| Pengguna memasukkan tanggal, jam berangkat dan batas selesai | Makna batas selesai terhadap perjalanan pulang; durasi default tiap stop |
| Urutan mempertimbangkan preferensi, waktu, cuaca dan konteks tempat | Formula/bobot “terbaik”, prioritas konflik dan aturan moda |
| Recalculation dapat berlangsung selama trip | Pemicu, cadence, review/apply dan pembaruan otomatis yang diizinkan |
| Backend mempunyai browser untuk mencari konteks tempat | Runtime, penyedia pencarian, sumber dan cara verifikasi |
| MapKit, Core Location dan WeatherKit menjadi fokus | Bukti kemampuan traffic/transit, cakupan wilayah dan kontrak transfer data |

Aplikasi merekomendasikan. Pengguna menentukan penggantian, penambahan atau pelewatan tujuan. Ketika rencana tidak muat, hasil harus menjelaskan benturannya dan menawarkan pilihan; daftar tujuan tidak dipangkas diam-diam.

## 2. Johan

Johan berasal dari Jogja, pindah ke Jakarta untuk Academy, dan suka ngopi sambil membaca. Pada contoh baru ia sudah tahu kafe/toko kopi di Cipete yang ingin dikunjungi. Ia dapat meminta kandidat kegiatan tambahan, memilihnya sendiri, lalu meminta urutan dan jadwal yang sesuai.

Informasi daring dapat membantu menjelaskan karakter tempat dan alasan suatu waktu kunjungan disarankan. Sumber, tanggal pemeriksaan dan ketidakpastiannya perlu terlihat pada informasi yang memengaruhi rencana. Cerita ini tidak menyatakan kafe tertentu sudah diverifikasi atau Johan telah mengalami manfaat produk.

## 3. Fixture A/B/C/D dari pengguna

Data berikut ditranskripsikan dari gambar tabel pengguna untuk menjelaskan konsep. Simetri dan hubungan jaraknya diterima sebagai ilustrasi. Ini bukan data geografi, routing/traffic live atau hasil WeatherKit.

| Asal / tujuan | A | B | C | D |
|---|---|---|---|---|
| A | — | 10 km / 20 menit | 5 km / 15 menit | 2 km / 8 menit |
| B | 10 km / 20 menit | — | 12 km / 30 menit | 18 km / 45 menit |
| C | 5 km / 15 menit | 12 km / 30 menit | — | 1 km / 10 menit |
| D | 2 km / 8 menit | 18 km / 45 menit | 1 km / 10 menit | — |

Asumsi pembanding: mulai di A, mengunjungi B/C/D masing-masing sekali, tanpa kembali ke A, tanpa waktu tunggu atau durasi menikmati tempat, dan estimasi perpindahan tetap.

| Urutan | Waktu perpindahan |
|---|---|
| A → B → C → D | 60 menit |
| A → B → D → C | 75 menit |
| A → C → B → D | 90 menit |
| A → C → D → B | 70 menit |
| A → D → B → C | 83 menit |
| A → D → C → B | 48 menit |

A → D → C → B paling singkat untuk asumsi fixture ini. Urutan yang paling sesuai pengalaman pengguna belum dapat ditentukan dari tabel saja. Waktu berangkat, durasi kunjungan, batas selesai, moda, kondisi pada waktu tiba dan informasi tempat masih diperlukan. Data nyata tidak boleh diasumsikan simetris atau tetap sepanjang hari.

## 4. D lebih lama, C mempunyai kesempatan golden hour

Johan masih di D dan ingin tinggal lebih lama. Sistem memperbarui durasi atau waktu keberangkatan dari D, menghitung perkiraan tiba di C dan dampaknya ke sisa rencana, lalu menjelaskan pilihan.

- Jika masih terkejar, jelaskan rekomendasi waktu meninggalkan D dan asumsi ETA.
- Jika berpotensi terlewat, jelaskan ketidakpastian serta konsekuensi tinggal lebih lama.
- Jika tidak terkejar, jelaskan bahwa pengalaman golden hour berkurang/terlewat; kunjungan C tetap menjadi pilihan Johan.
- Jika perubahan membuat batas selesai terlampaui, tampilkan benturan dan opsi penyesuaian untuk dipilih pengguna.

Tidak ada jam sunrise/sunset atau prakiraan aktual dalam fixture. Golden hour bukan sinonim sunset; definisi jendela dan pengaruh awan/penghalang harus diselesaikan pada rancangan integrasi.

## 5. Cakupan yang belum diaktifkan ulang

Album/journaling, kewajiban foto/GPS, kontribusi publik, merge rundown, HealthKit/MusicKit dan gamifikasi belum ditetapkan ulang untuk engine baru. Riwayat fitur tersebut bukan keputusan penghapusan maupun kewajiban otomatis. Walkable dan non-mainstream tidak membatasi seluruh trip.

## 6. Keberhasilan yang ingin diuji

Pengguna memahami mengapa urutan disarankan, dapat mengikuti rencana dalam rentang waktunya atau memahami alasan ketidaklayakannya, dan tetap mengendalikan perubahan tujuan. Mutu dibanding AI umum/Maps, manfaat personalisasi dan kenyamanan recalculation harus dibuktikan melalui [rencana validasi](ai-trip-planning-validation-plan-2026-10-29.md).
