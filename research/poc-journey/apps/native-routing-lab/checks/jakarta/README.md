# Unit test Jakarta

Jalankan dari root repo:

```sh
./scripts/test-native-trip-jakarta.sh /tmp/c67-jakarta-unit-results
```

Gunakan direktori output baru. Memerlukan Xcode command-line tools, Swift 6+ dan Python 3; tidak mengunduh dependency. Runner membuat package SwiftPM sementara, menyalin enam berkas routing produksi tanpa perubahan, dan mengompilasinya bersama adapter deterministik yang sudah dipakai benchmark. Test berjalan dengan XCTest pada macOS, mode bahasa Swift 5, Debug, secara serial. Tidak membuka aplikasi atau Simulator dan tidak menghubungi MapKit/WeatherKit.

Fixture berasal dari rekaman Jakarta pada `docs/verification/routing-time-aware-2026-11-03/final/cases/jakarta-recorded-static.json`, disalin tanpa perubahan. Provenance rekaman dan hash source diperiksa serta dicatat. Tempat: Sudirman pergi/pulang; Monas, Grand Indonesia, Kota Tua dan Kelapa Gading. Input asli hanya mengetahui jam buka Kelapa Gading 10.00; waktu tempat lainnya belum diverifikasi. Skenario jam operasional lengkap dan perubahan ETA ditandai sintetis.

Suite mencakup 26 test: evaluator, tujuh algoritme, pipeline baseline/hybrid, subset tujuan, input acak, durasi singgah, jam buka/tutup, tanggal berubah, ETA hilang, moda tidak tersedia, propagasi ETA dinamis dan batas satu hari. Assertion memakai acuan angka tetap dari enumerasi independen empat tujuan dan perhitungan subset, bukan hanya membandingkan dua fungsi yang sama.

Output: `REPORT.md`, `summary.json`, `junit.xml`, `test.log`, `itineraries.jsonl`, dan `manifest.json`. Pada host yang tidak menghasilkan xUnit dari SwiftPM, reporter mengonversi event console XCTest menjadi JUnit, memeriksa jumlah kasus/kegagalan terhadap ringkasan suite, dan mencatat asal konversinya. Exit nonzero, test hilang, test gagal atau test dilewati tidak dianggap lulus.

Waktu test adalah komputasi host tanpa jaringan. Kolom request adalah pemanggilan adapter yang tidak terpenuhi cache. Estimasi pacing pada laporan bukan pengukuran waktu layanan live. Hasil tidak membuktikan jam tempat benar, rute tercepat dunia nyata atau ketersediaan layanan pada iPhone.
