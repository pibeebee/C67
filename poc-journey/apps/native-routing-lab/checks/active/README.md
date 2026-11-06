# Pemeriksaan perjalanan aktif P2

Jalankan dari root checkout:

```sh
bash scripts/test-native-trip-local.sh /tmp/c67-p2-local-new
python3 scripts/benchmark-active-trip.py . /tmp/c67-p2-replay-new
```

Runner lokal menjalankan 24 tes planned/storage lama dan 35 XCTest trip aktif. Source domain, planner dan controller produksi dikompilasi tanpa perubahan; adapter ETA beku menggantikan transport. Tes menguji lifecycle, history, replan, deadline, skip/end-only, revision, cancellation, watchdog, idempotensi dan kegagalan simpan. Ini tes host macOS, bukan UI/device.

Replay membandingkan urutan tersisa diterima yang dihitung ulang dengan hybrid adaptif: 24 kasus, 3 seed, 2 alur. Output mencakup input, setiap run, hash source, trace request, counter solver, ringkasan dan audit Python independen. Binary/module-cache hanya output lokal; tidak disalin ke paket bukti. Semua ETA/window sintetis atau oracle beku; cuaca unknown, tanpa jaringan. Setup awal itinerary mempunyai budget terpisah.

Gunakan output baru. Memerlukan Xcode command-line tools dan Python3. [Laporan P2](../../docs/verification/NATIVE_TRIP_REPLANNING_P2_2026-11-04.md) menjelaskan hasil, kasus matriks dan batas validasi.
