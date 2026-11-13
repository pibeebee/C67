# Pemeriksaan P0–P2 native lokal

Jalankan dari root repo:

```sh
bash scripts/test-native-trip-local.sh /tmp/c67-local-new
```

Gunakan direktori output baru dan Xcode command-line tools. Suite berisi 77 XCTest (24 planned/storage + 35 trip aktif +18 profil/tempat Jakarta) pada kode produksi untuk launch policy, deadline, penyimpanan/pemulihan, validasi itinerary dan kegagalan simpan. Adapter ETA dibekukan; dependensi model UI diganti adapter test tanpa transport. Tidak memakai kredensial atau provider live.

Runner menyalin source ke package sementara, mencatat hash, menjalankan XCTest, membandingkan event console dengan jumlah/failure suite, lalu menghasilkan JUnit/ringkasan jika SwiftPM tidak menulis xUnit. Probe executable menulis snapshot, berhenti, lalu proses lain membaca ulang data. Direktori package sementara dibersihkan; hasil/log/manifest tetap di direktori output.

[Laporan dan bukti](../../docs/verification/NATIVE_LOCAL_P0_P1_2026-11-03.md). [Laporan replanning P2](../../docs/verification/NATIVE_TRIP_REPLANNING_P2_2026-11-04.md) memuat hasil tes aktif. Tes host ini tidak menggantikan pengujian iPhone fisik atau layanan live.

[Hasil perbaikan Jakarta build 9](../../docs/verification/JAKARTA_ROUTING_FIX_2026-11-04.md) mencakup profil, boundary, konversi data lama, provider cuaca dan pencarian nama/cabang. Tes lama untuk save failure memakai perubahan konteks yang berbeda dari default Jakarta agar dirty-state benar-benar diuji.
