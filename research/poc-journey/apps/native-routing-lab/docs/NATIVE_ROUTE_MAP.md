# Peta seluruh itinerary — PoC iOS C67

Implementasi 3 November 2026, minimum iOS 18. Fitur ada pada perencana native di `<LOCAL_HOME>/Programming/software/ios/poc-c67`.

## Cara memakai

1. Isi rencana dan pilih lokasi seperti biasa, lalu **Hitung itinerary**.
2. Buka **Lihat itinerary → Peta seluruh itinerary**. Aplikasi mengambil garis jalur hanya untuk ruas kandidat terpilih, termasuk ruas ke titik akhir/kembali.
3. Nomor dan warna menunjukkan urutan ruas; pin bernomor menunjukkan urutan kunjungan. Badge di sepanjang jalur memuat nomor ruas dan ikon moda. Warna berulang setelah delapan ruas, sehingga nomor tetap menjadi identitas utama.
4. Pilih ruas di daftar atau ketuk badge pada peta. Garis terpilih ditebalkan, garis lain diredupkan dan kamera diarahkan ke ruas tersebut. Tombol **Seluruh rute** mengembalikan tampilan keseluruhan.
5. Periksa legenda, status pemuatan dan rincian tiap ruas. Jika terjadi kegagalan, ruas yang berhasil tetap terlihat; **Coba lagi jalur gagal** hanya mengulang ruas yang belum tersedia dan tetap mengikuti batas request.

Peta juga dapat dibuka melalui **Rincian kandidat → Peta kandidat ini**, termasuk kandidat alternatif cuaca dan kandidat parsial yang tersedia. Rencana parsial diberi penanda dan hanya menampilkan ruas yang sudah dihitung.

## Pembeda visual

| Unsur | Arti |
|---|---|
| Warna + nomor ruas | Urutan perpindahan; warna yang sama digunakan pada garis, badge dan nomor daftar. |
| Pin 1, 2, 3, … | Urutan kunjungan, mengikuti kandidat yang dipilih. |
| Pin Awal / Akhir | Awal dan akhir pada koordinat yang sama digabung. Kunjungan berulang di koordinat sama juga digabung labelnya, tetapi occurrence/ruas tetap terpisah. |
| Ikon mobil + garis penuh | Moda mobil. |
| Ikon jalan kaki + garis putus-putus | Moda jalan kaki. |
| Transit | Status geometri belum tersedia dan akses **Periksa di Apple Maps**; tidak menggambar jalur transit pengganti. |

Pemilihan melalui daftar dan badge mendukung aksesibilitas. Nomor, teks moda, ikon, gaya garis dan status terpilih menjadi pendamping warna. Ruas yang berimpit dapat saling menutupi pada overview; memilih ruas akan menggambarnya paling atas dan menampilkan badge ruas itu saja. Belum melakukan audit VoiceOver atau seluruh ukuran Dynamic Type di perangkat fisik.

## Data jalur dan ETA

Pencarian itinerary tetap memakai evaluator/ETA yang sudah ada. Setelah pengguna membuka peta, `NativeTripMapDirectionsProvider` meminta `MKDirections.calculate()` untuk pasangan awal–akhir, moda terpilih dan jam keberangkatan masing-masing ruas. Respons `MKRoute.polyline` menjadi `MapPolyline`.

Pengambilan geometri adalah permintaan baru. Jalur yang diperoleh adalah jalur MapKit untuk konteks permintaan tersebut; ETA sebelumnya tidak menyimpan identitas jalur jalan yang bisa direkonstruksi persis. Karena itu rincian memisahkan **ETA itinerary** dari durasi/jarak **Jalur peta**. Memuat geometri tidak mengganti urutan, moda, waktu singgah, jadwal atau hasil optimasi. Fitur ini bukan rekaman perjalanan GPS dan belum menambahkan navigasi belokan demi belokan.

Transit di API MapKit hanya mendukung estimasi waktu tiba. Geometri mobil/jalan kaki dapat diminta jika tersedia di wilayah tersebut. Kegagalan atau geometri yang belum tersedia tidak diganti dengan garis lurus. Titik dengan koordinat sama tidak memerlukan request atau garis tambahan.

Referensi Apple: [MKRoute](https://developer.apple.com/documentation/mapkit/mkroute), [MapPolyline](https://developer.apple.com/documentation/mapkit/mappolyline), [batasan transit](https://developer.apple.com/documentation/mapkit/mkdirectionstransporttype/transit).

## State, cache dan pembatalan

- Store `@MainActor @Observable` dimiliki layar laporan dan dibagi ke peta kandidat dalam laporan tersebut. Cache bersifat sementara di memori, bukan penyimpanan jalur lintas peluncuran aplikasi.
- Kunci cache berisi koordinat kedua titik, moda dan waktu berangkat. ID ruas yang sama dengan konteks berbeda tidak menggunakan geometri lama. Cache geometri bersama dibatasi 128 entri.
- Status per ruas: pending, loading, available, failed, unsupported, stationary atau missingInput. Hasil per ruas yang berhasil tetap tersedia selama laporan hidup.
- Request berjalan berurutan, dengan pacing minimum 1,2 detik dan timeout 25 detik. Maksimum 64 upaya pengambilan per laporan; anggaran ini terpisah dari anggaran ETA itinerary. Pembatalan saat menunggu slot tetap dapat menghabiskan satu upaya yang sudah dicatat.
- Tidak melakukan retry otomatis tanpa batas. Tombol retry hanya mencoba kegagalan yang belum tercakup cache. Saat throttled, request baru ditolak selama sedikitnya 15 detik; pengguna dapat mencoba lagi sesudahnya.
- Meninggalkan layar atau aplikasi tidak aktif membatalkan pemuatan. Token generasi mencegah respons lama menimpa pemuatan baru; hasil yang sudah berhasil tidak dihapus. Kembali ke layar memakai cache dan melanjutkan ruas pending.
- Canvas membaca state geometri sebelum closure `MapContent`, sehingga hasil async memperbarui garis dan badge tanpa perlu tap tambahan.

## Log

Kategori `route_map` ditulis melalui penyimpanan log lokal yang sudah ada. Event:

- `map.routes_started`, `map.routes_completed`, `map.routes_cancelled`;
- `map.route_requested`, `map.route_result`, `map.route_failed`, `map.route_skipped`, `map.route_cache_hit`;
- `map.leg_selected` untuk pemilihan ruas atau keseluruhan peta.

Field mencakup ID ruas, nama awal/akhir, moda, jam berangkat, jumlah upaya, jumlah titik polyline, jarak/durasi geometri, ETA itinerary, elapsed serta domain/kode error bila gagal. Seluruh titik polyline tidak disalin ke log. Ekspor tersedia melalui **Rencana → Log**, mengikuti retensi yang sudah ada.

## Verifikasi

Build iOS Simulator dan pemeriksaan lokal state/cache telah dijalankan. Lihat [bukti verifikasi UI dan batas pengujian](verification/NATIVE_ROUTE_MAP_2026-11-03.md).

Pemeriksaan lokal memakai provider sintetis tanpa jaringan; berbeda dari uji MapKit nyata melalui UI:

```sh
bash scripts/check-native-trip-map.sh
```

Enam kelompok memeriksa cache lintas pembukaan/ID, pemisahan koordinat-moda-waktu, kegagalan parsial dan retry, status non-geometri tanpa request, batas upaya, serta balapan respons setelah pembatalan. Pemeriksaan tidak menyatakan bahwa provider transit tersedia atau bahwa jalur dunia nyata sudah akurat di seluruh wilayah.
