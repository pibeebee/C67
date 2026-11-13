# Perbaikan pencarian tempat native — 3 November 2026

## Masalah dan bukti

Pengguna melaporkan timeout di iPhone sesudah **Temukan lokasi yang belum dipilih**, termasuk untuk **Inamuragasaki Station**. Pemeriksaan read-only menemukan aplikasi `giovanchristoffel.poc-c67` versi 0.6 build 8 terpasang pada iPhone pengguna. Aplikasi tidak diganti, diluncurkan ulang, atau dihapus selama diagnosis ini.

Yang terkonfirmasi dari kode sebelumnya:

- Satu error `MKLocalSearch` keluar dari seluruh loop bulk. Tujuan berikutnya tidak dicari dan tetap tampak belum dipilih.
- Error pencarian hanya ditampilkan sebagai `localizedDescription`, tanpa pemisahan timeout, offline, pembatasan request, dan tidak ada hasil.
- Query Jepang belum diberi petunjuk `MKLocalSearch.Request.region`.
- Pencarian manual dapat dipicu kembali lewat keyboard saat request masih berlangsung.

Penyebab jaringan/layanan dari timeout asli di iPhone **belum dapat dipastikan**. Tidak ada bukti bahwa nama tempat tersebut tidak valid, dan petunjuk area tidak dijanjikan dapat menyelesaikan timeout layanan. Apple mendokumentasikan `region` sebagai petunjuk relevansi, bukan pembatas hasil atau perbaikan koneksi.

## Perubahan

1. **Status per tempat:** sedang dicari, sudah dipilih, perlu memilih kandidat, tidak ada hasil, timeout, offline, throttled, gagal, dan ditunda dibedakan. Lokasi tanpa koordinat memakai label belum dipilih, bukan ikon lokasi tidak valid.
2. **Kelanjutan bulk:** satu timeout tidak menghentikan tempat berikutnya. Dua kegagalan layanan berturut-turut menjeda sisanya; offline/throttling menjeda langsung. Tujuan yang belum diminta ditandai ditunda, bukan dianggap tidak ada.
3. **Pelestarian hasil:** lokasi yang sudah dipilih dilewati. Kandidat ambigu yang sudah diterima tidak dicari lagi sampai pengguna memilih/mengubah query. Satu query yang dipakai beberapa aktivitas memakai cache dalam run tersebut.
4. **Petunjuk area:** contoh Jepang diberi area Funabashi atau Kamakura–Enoshima. Ini bukan koordinat tujuan yang sudah dikonfirmasi. Pengguna dapat mematikan prioritas area di pemilih lokasi.
5. **Nama alternatif:** contoh menyediakan query Inggris yang lebih ringkas, termasuk `Inamuragasaki Station, Kamakura, Japan`. Bulk mencoba satu alias hanya jika layanan benar-benar mengembalikan tidak ada hasil. Timeout tidak memicu percobaan semua nama secara otomatis.
6. **Pembatasan request:** jarak awal minimum 1,2 detik antarrequest pencarian fitur ini; cooldown 60 detik saat throttling terdeteksi. Deadline aplikasi 35 detik membatalkan request dan dicatat sebagai timeout. Angka ini kebijakan PoC, bukan limit resmi Apple.
7. **Pembatalan dan hasil lama:** request keyboard ganda dicegah; perubahan query/area membatalkan hasil lama; pembatalan pengguna tidak diubah menjadi timeout/no-results.
8. **Diagnostik:** durasi, query, area, kategori hasil, domain/code error dan underlying code disediakan pada layar dan laporan yang dapat dibagikan. Log OS kategori `NativePlaceSearch` mencatat status/kode tanpa menuliskan query sebagai data publik.
9. **Pin manual:** pemilih lokasi memiliki **Pilih titik pada peta**. Pengguna menggeser peta dan mengonfirmasi titik tengah. Sumber koordinat diberi label pin manual; tidak diklaim sebagai hasil pencarian nama. Titik tengah awal tidak dipakai otomatis sebagai lokasi tujuan.

Data tetap hanya berada dalam memori pada fitur ini, sesuai versi sebelumnya. Hasil dipertahankan sepanjang percobaan ulang dalam sesi yang sama; pekerjaan ini tidak menambahkan penyimpanan draft permanen.

## Coba pada iPhone setelah build baru dipasang

1. Buka Rencana → menu tiga titik **Kelola rencana** → **Muat contoh Jepang** → konfirmasi → detail **Stasiun Inamuragasaki** → pilih lokasi. Pada versi input bebas, contoh ini tidak dimuat otomatis.
2. Gunakan query `Inamuragasaki Station, Kamakura, Japan`, dengan prioritas area Kamakura–Enoshima aktif, lalu **Cari di MapKit**.
3. Jika request tetap timeout, gunakan **Bagikan diagnostik pencarian ini** pada layar tersebut. Diagnostik harus bertanda `native-search-v2-20261103` agar versi kode dapat dibedakan.
4. Bandingkan nama yang sama di aplikasi Apple Maps pada iPhone yang sama. Jika diperlukan, bandingkan Wi-Fi dan seluler serta pengaturan VPN/filter jaringan. Ini langkah diagnosis, bukan kesimpulan penyebab.
5. Untuk melanjutkan pengujian perhitungan saat pencarian bermasalah, pilih **Pilih titik pada peta**, geser ke lokasi yang dimaksud, lalu konfirmasi. Titik tersebut tetap diberi provenance manual.

Jangan menekan pencarian berulang-ulang saat masih berjalan atau sedang cooldown. Hasil tidak ada tetap dapat dicoba dengan nama/area lain; timeout sendiri tidak membuktikan tempat tidak ada.

## Verifikasi

- Build generic iOS unsigned berhasil, Xcode 27.2, target minimum tetap iOS 18.
- Tujuh pemeriksaan sintetis berjalan **di macOS**, bukan tes iOS/Simulator. Pemeriksaan meliputi klasifikasi error, melanjutkan antrean setelah satu timeout, jeda setelah dua error, hasil kosong, throttling, offline, serta pembatalan tanpa hasil lama.
- `swift-format lint --strict` untuk fitur dan check: lolos.
- Tidak menjalankan Simulator, tes iOS, atau mengganti aplikasi di iPhone. Keberhasilan pencarian live sesudah patch belum dibuktikan.

Jalankan pemeriksaan kebijakan dengan:

```sh
bash scripts/check-native-place-search.sh
```

Pemeriksaan ini menggunakan error/respons buatan, tidak memanggil layanan Apple. Build log lokal: `/private/tmp/c67-mapkit-search-fix-20261103/build-ios.log`. Snapshot file sebelum perbaikan: `/private/tmp/c67-mapkit-search-fix-20261103/originals/`.

Rujukan resmi: [MKLocalSearch.Request.region](https://developer.apple.com/documentation/mapkit/mklocalsearch/request/region), [MKError.loadingThrottled](https://developer.apple.com/documentation/mapkit/mkerror/code/loadingthrottled).
