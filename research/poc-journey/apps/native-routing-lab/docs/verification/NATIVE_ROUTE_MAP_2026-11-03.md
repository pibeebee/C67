# Verifikasi peta seluruh itinerary — 3 November 2026

**Fitur berhasil dibangun dan diamati di Simulator.** Peta Jakarta menampilkan kelima ruas mobil, termasuk perjalanan pulang, dengan warna dan nomor ruas. Pemilihan daftar/badge menyorot ruas dan mengarahkan kamera. Peta yang dibuka ulang menggunakan lima hasil cache tanpa request jalur tambahan. Contoh jalan kaki menampilkan dua garis putus-putus dan badge moda yang benar, termasuk ketika ruas pulang dipilih di atas jalur pergi yang berimpit.

## Lingkungan dan cakupan

- Repo: `<LOCAL_HOME>/Programming/software/ios/poc-c67`.
- Simulator: iPhone 18 Pro, iOS 27.0, UUID `B774448D-6569-46E0-9833-669540D094D0`; target minimum tetap iOS 18.
- Build final berhasil dalam 14,3 detik melalui XcodeBuildMCP. Interaksi UI melalui `cua_repl` pada Device Hub; bukan injeksi state aplikasi.
- Tidak mengubah algoritme pemilihan itinerary atau kebijakan jam operasional. Pengambilan geometri dilakukan saat layar peta dibuka.
- Pemeriksaan lokal enam kelompok menggunakan provider sintetis tanpa jaringan; tidak menjalankan target XCTest atau pengujian iPhone fisik.

## Pengujian Jakarta

Input sama dengan kasus sebelumnya: Sudirman pergi/pulang, Monas, Grand Indonesia, Kelapa Gading, Kota Tua Jakarta; **5 November 2026 pukul 07.00 Asia/Jakarta**, singgah 30 menit dan Kelapa Gading buka 10.00 berdasarkan input pengguna. Jam operasional lainnya tetap belum diisi. Ini pengujian visualisasi, bukan validasi kelayakan itinerary wisata.

Sesudah **Hitung itinerary → Lihat itinerary → Peta seluruh itinerary**, kelima geometri diterima dan garis muncul otomatis. Seluruh ruas terpilih memakai mobil.

| Ruas | Warna | Titik polyline | Jarak jalur | ETA itinerary | Durasi jalur yang diambil ulang |
|---|---|---:|---:|---:|---:|
| Sudirman → Grand Indonesia | Biru | 27 | 1,171 km | 237 detik | 237 detik |
| Grand Indonesia → Monas | Oranye | 136 | 5,559 km | 1.260 detik | 1.260 detik |
| Monas → Kota Tua | Ungu | 72 | 5,751 km | 1.088 detik | 1.116 detik |
| Kota Tua → Kelapa Gading | Hijau | 236 | 16,073 km | 2.136 detik | 2.078 detik |
| Kelapa Gading → Sudirman | Merah | 233 | 14,833 km | 2.620 detik | 2.499 detik |

Perbedaan durasi dicatat dan tampil terpisah; pemuatan jalur tidak menulis ulang jadwal. Pin Sudirman menampilkan **Awal / Akhir** pada satu koordinat. Setiap ruas tetap memiliki ID/nomor sendiri.

Pengujian interaksi:

- Memilih ruas 2 melalui daftar menebalkan garis oranye, meredupkan garis lain, menandai baris **Disorot**, serta mengarahkan kamera ke Grand Indonesia–Monas.
- Tombol **Seluruh rute** mengembalikan framing overview.
- Badge ruas 4 pada peta memilih ruas Kota Tua–Kelapa Gading.
- Keluar dan membuka ulang peta menghasilkan **5 cache hit**, tanpa `map.route_requested` tambahan. Counter tetap **5/64**, dan status tetap **5/5**.

Bukti: [overview](native-route-map-2026-11-03/jakarta-overview.jpg), [ruas 2 dipilih](native-route-map-2026-11-03/jakarta-selected-leg-2.jpg), [log geometri/cache/selection](native-route-map-2026-11-03/jakarta-map-events.json), [input Jakarta](native-route-map-2026-11-03/jakarta-input.json).

## Pengujian jalan kaki

Contoh terpisah: Sudirman → Grand Indonesia → Sudirman, tanggal/jam sama, hanya moda jalan kaki diaktifkan. Itinerary menggunakan dua request ETA, lalu peta mengambil dua geometri: **44 dan 47 titik**. UI menampilkan **2/2 ruas** dan ikon jalan kaki.

Ruas pulang yang berimpit dipilih dari daftar. Pada build final, garis oranye tetap putus-putus meskipun lebih tebal, dan badge yang ditampilkan adalah **nomor 2 + ikon jalan kaki**. Ruas lain diredupkan. Ini menghindari badge ruas pergi menutupi badge ruas pulang ketika dipilih.

Bukti: [screenshot final](native-route-map-2026-11-03/walking-selected-leg-2.jpg), [log dua jalur jalan kaki](native-route-map-2026-11-03/walking-map-events.json), [input](native-route-map-2026-11-03/walking-input.json), [laporan itinerary](native-route-map-2026-11-03/walking-itinerary.txt).

## Pemeriksaan lokal dan source

`bash scripts/check-native-trip-map.sh`: **6 kelompok lulus**:

1. Cache lintas pembukaan dan ID ruas, tanpa mengubah ETA itinerary.
2. Koordinat, moda dan jam berangkat berbeda tidak menggunakan cache yang salah.
3. Kegagalan parsial mempertahankan geometri berhasil; retry eksplisit hanya mengambil geometri yang hilang.
4. Transit, koordinat sama, moda belum dipilih dan koordinat tidak lengkap tidak memanggil provider atau mengarang garis.
5. Retry tetap mematuhi batas upaya per laporan.
6. Respons terlambat setelah pembatalan tidak menimpa geometri/kondisi pemuatan baru.

Compiler macro Swift awalnya tidak dapat berjalan dalam sandbox; perintah yang sama kemudian dijalankan dengan izin eksekusi yang disetujui dan lulus. Pemeriksaan format Swift, sintaks shell dan `git diff --check` juga lulus.

Bukti: [output pemeriksaan lokal](native-route-map-2026-11-03/local-map-checks.log), [build final](native-route-map-2026-11-03/build-final.log), [metadata dan hash source](native-route-map-2026-11-03/verification.json).

## Batas verifikasi

Pengujian Jakarta dilakukan pada build sesudah perbaikan pembaruan async MapContent. Build final berikutnya memperjelas dash jalan kaki dan badge terpilih; build ini diverifikasi ulang dengan geometri jalan kaki nyata. Overview mobil pada screenshot tetap berasal dari pengujian Jakarta sebelumnya dalam rangkaian task yang sama.

Kegagalan parsial, retry, kuota dan respons setelah pembatalan diperiksa menggunakan provider sintetis. Belum menguji offline/retry melalui UI perangkat, satu itinerary campuran mobil–jalan kaki, seluruh variasi 20 tujuan, VoiceOver, Dynamic Type besar, atau iPhone fisik. Transit memang tidak memiliki geometri dari API MapKit yang digunakan dan ditampilkan sebagai status unsupported dengan akses ke Apple Maps.

Ruas yang berimpit dapat saling menutupi ketika semua jalur ditampilkan; pemilihan ruas digunakan untuk membacanya. Tampilan peta bukan rekaman GPS atau bukti bahwa jalur yang dihitung ulang identik dengan jalur internal yang menghasilkan ETA sebelumnya.
