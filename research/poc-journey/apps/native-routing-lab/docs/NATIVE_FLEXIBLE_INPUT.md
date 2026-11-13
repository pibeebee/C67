# Input itinerary bebas — PoC iOS C67

Tanggal pekerjaan: **3 November 2026**. Proyek: `<LOCAL_HOME>/Programming/software/ios/poc-c67`.

## Perubahan alur

Sebelumnya layar dibuka dengan fixture Funabashi–Kamakura–Enoshima, zona waktu hanya Jepang/Jakarta, dan penambahan tempat bergantung pemilih lokasi. Sekarang nama tempat bisa dikumpulkan terlebih dahulu, terpisah dari pencarian koordinat.

1. Mulai dengan rencana kosong; tanggal/jam dan zona waktu awal mengikuti perangkat.
2. Isi titik awal dan titik akhir, atau kembali ke titik awal.
3. Gunakan **Tambah tempat → Tempel daftar** untuk input satu tempat per baris, atau **Satu tempat** untuk input satu per satu. **Simpan nama dulu** tidak memanggil MapKit.
4. Pilih tanggal/jam, zona waktu trip (semua identifier yang disediakan sistem), durasi singgah dan moda. Kota/negara pencarian opsional diterapkan ke pencarian nama, termasuk titik awal/akhir. Kosongkan konteks bila daftar melintasi area dan tulis alamat/kota pada tiap nama bila perlu.
5. Cari/pilih koordinat melalui MapKit atau pin manual. Nama saja belum cukup untuk menghitung rute; hasil ambigu perlu pilihan pengguna. Pencarian massal melewati titik yang namanya masih kosong dan titik yang sudah dipilih.
6. Hitung itinerary menggunakan algoritme ETA/cuaca yang sudah ada.

Nama baru dimulai sebagai **kunjungan**, singgah default **30 menit**, paparan **belum diketahui**, dan jam operasional belum diisi. PoC tidak menebak peran stasiun, jam buka atau durasi berdasarkan fixture lama. Ubah peran transfer/durasi/paparan pada detail tempat.

List mendukung teks biasa, `1. Nama`, `1) Nama`, `- Nama`, `* Nama`, dan `• Nama`. Baris kosong diabaikan; satu baris selalu satu tempat. Alamat dengan koma, Unicode dan nama yang berulang dipertahankan. Belum ada parsing rundown/jam bebas, CSV atau pemisahan beberapa tempat dalam satu baris. Maksimum **20 tujuan** tetap berlaku untuk batas PoC; daftar melebihi sisa kapasitas ditolak seluruhnya, tidak dipotong.

Menu tiga titik **Kelola rencana** → **Rencana baru** mengosongkan input. **Muat contoh Jepang** mengembalikan fixture sebelumnya secara eksplisit. Keduanya meminta konfirmasi. Draf tetap hanya dalam memori; menutup proses aplikasi dapat menghilangkannya.

## Peta dan status data

Input pengguna tidak mewarisi petunjuk area atau alias Jepang. Peta manual tanpa koordinat/area referensi dimulai dari tampilan dunia dan meminta ketukan sebelum konfirmasi. Pin manual tetap diberi sumber pengguna; bukan pengesahan kecocokan nama oleh MapKit. Mengganti query tidak membawa hasil koordinat lama sebagai hasil baru.

Konteks kota/negara ditambahkan secara transparan pada query detail maupun massal. Perubahan konteks membersihkan kandidat pencarian yang belum dipilih. Titik yang sudah dipilih dipertahankan. Mengganti zona waktu mempertahankan tanggal dan jam dinding yang diisi sebagai waktu lokal trip; instant keberangkatan menyesuaikan zona baru.

Perubahan ini membuat input fleksibel, **bukan bukti timeout MapKit di iPhone teratasi**. Pencarian dan ETA tetap bergantung layanan Apple. Alur status, jeda/cooldown, diagnostik dan pin manual dari [perbaikan pencarian](NATIVE_PLACE_SEARCH_FIX.md) tetap digunakan. Transit masih ETA saja; WeatherKit tetap mengikuti ketersediaan dan horizon prakiraan. Tidak ada provider/AI/backend baru.

## Verifikasi

- Build generic iOS unsigned: berhasil; minimum iOS tetap 18.
- Delapan pemeriksaan logika input dijalankan sebagai executable **macOS**, tanpa jaringan: draf kosong, parsing, append/ID/default, batas kapasitas tanpa perubahan parsial, konteks query, zona waktu, fixture opsional, validasi titik awal/akhir manual.
- Format Swift strict, whitespace diff, dan sintaks shell diperiksa.
- Tidak menjalankan tes iOS, Simulator, instalasi atau pengujian aplikasi di iPhone. Kesesuaian UI, gesture peta dan hasil layanan nyata masih memerlukan pengamatan perangkat.

Pemeriksaan lokal dapat diulang dengan `./scripts/check-native-trip-input.sh`. Bukti build dan hash kode tersimpan di [catatan verifikasi](verification/NATIVE_FLEXIBLE_INPUT_2026-11-03.json).

## Pembaruan UI minimal

Pengaturan rinci sekarang dibuka melalui **Pengaturan**; tampilan default hanya Rencana. Log persisten dan ekspor Files tersedia melalui **Log**. Lihat [panduan log](NATIVE_LOGGING.md). Catatan verifikasi di atas merupakan hasil tahap input bebas; verifikasi perubahan UI/log dicatat terpisah.
