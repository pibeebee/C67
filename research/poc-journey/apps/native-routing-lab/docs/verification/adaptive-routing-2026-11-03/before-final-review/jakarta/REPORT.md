# Unit test routing Jakarta — PoC C67

Hasil: **25/25 lulus**, 0 gagal, 0 dilewati. Exit code XCTest: `0`.

Suite XCTest dijalankan melalui SwiftPM pada macOS, tanpa jaringan dan tanpa membuka aplikasi/Simulator. Kode evaluator, solver, engine dan planner produksi dikompilasi tanpa perubahan; lapisan layanan memakai adapter replay yang sudah ada. Suite mencakup unit evaluator/optimizer serta integrasi pipeline dengan adapter.

Source aplikasi: commit `712f036b222839173d7ea82bb736dd57aaeed6f5`. Hash berkas fixture, source, test dan runner tercatat pada [manifest](manifest.json).

## Tempat dan data

- Pergi/pulang **Stasiun Sudirman**, 5 November 2026, mulai **07.00 WIB**.
- Tujuan: **Monas, Grand Indonesia, Kota Tua, dan Summarecon Mall Kelapa Gading**; juga diuji dua subset dengan masing-masing dua tujuan.
- Default singgah **30 menit**. Moda memakai ETA walking/transit/automobile yang terekam; konteks mobil taksi/ride-hailing. Tidak menambahkan waktu pesan/tunggu taksi atau parkir.
- ETA berasal dari rekaman MapKit yang dipakai pada benchmark sebelumnya, dibekukan untuk pengujian. Ini bukan prakiraan trafik terbaru.
- Fixture asli hanya memiliki jam buka Kelapa Gading **10.00**, berasal dari input pengguna; jam operasional tujuan lain dan jam tutup belum diketahui. Hasil fixture asli tidak membuktikan tempat sungguh buka pada jadwalnya.
- Kasus tambahan jam buka semua tujuan, jam tutup sempit dan perubahan ETA adalah **asumsi sintetis untuk unit test**, bukan informasi operasional nyata. Tidak ada data cuaca pada suite ini.

## Hasil test

| Test | Hasil | Yang diperiksa |
|---|---|---|
| 1. `testAdaptiveJakartaSkipsExtraRequestsWithoutChangingSchedule` | PASSED | Adaptif memakai 30 request; jadwal tetap sama dan perkiraan tidak menjadi data provider. |
| 2. `testAdaptiveLargeWaitingTriggersOptimization` | PASSED | Waktu tunggu besar tetap memicu pencarian tambahan. |
| 3. `testAdaptiveNoWaitingDoesNotHideUnknownRoadShortcuts` | PASSED | Biaya ruas yang belum diketahui tetap memicu pencarian ketika tidak ada waktu tunggu penyangga. |
| 4. `testAdaptiveOneAndTwoDestinationsCoverAllOrdersWithoutSnapshot` | PASSED | Satu/dua tujuan selesai setelah semua urutan sudah divalidasi. |
| 5. `testAdaptiveScreeningPreservesWeatherAndPrivateCarSearch` | PASSED | Cuaca/mobil pribadi tetap dicari; screening tidak mengambil ETA baru. |
| 6. `testAdaptiveTightClosingMarginStillRunsOptimization` | PASSED | Margin jam tutup sempit tetap menjalankan optimizer. |
| 7. `testAdaptiveTinyScreeningBudgetFallsBackToSearch` | PASSED | Budget screening yang tidak cukup tidak dianggap bukti baseline memadai. |
| 8. `testAllSevenNativeMethodsPreserveStopsAndReachTheKnownFourStopReference` | PASSED | Tujuh algoritme mempertahankan semua tujuan dan mencapai acuan empat tujuan ini. |
| 9. `testCentralJakartaSubsetReturnsToSudirman` | PASSED | Subset Monas–Grand Indonesia kembali ke Sudirman. |
| 10. `testChangedDateRejectsStaleOpeningHoursBeforeAnyETARequest` | PASSED | Perubahan tanggal menolak jam operasional lama sebelum request ETA. |
| 11. `testCompleteDwellAtClosingBoundaryIsAcceptedButOneMinuteEarlierIsNot` | PASSED | Akhir singgah tepat saat tutup diterima; melewati satu menit ditolak. |
| 12. `testCurrentBaselinePipelineUsesElapsedObjective` | PASSED | Baseline versi sekarang menggunakan tujuan elapsed. |
| 13. `testForcedFullHybridRemainsAvailableForComparison` | PASSED | Override hybrid penuh tetap memakai 88 request dengan itinerary acuan yang sama. |
| 14. `testHybridPipelineKeepsValidatedBaselineAndRequestBudget` | PASSED | Hybrid mempertahankan baseline, membatasi request dan tidak mengarang rekomendasi cuaca. |
| 15. `testImpossibleOpeningWindowDoesNotProduceAFeasibleItinerary` | PASSED | Singgah 30 menit dalam jendela buka 15 menit tidak dinyatakan layak. |
| 16. `testLessTravelDoesNotBeatAnEarlierTripFinish` | PASSED | Perjalanan lebih pendek tidak mengalahkan total trip lebih singkat. |
| 17. `testLongerDwellPropagatesAndCanReplaceOpeningWait` | PASSED | Durasi singgah 60 menit menggantikan sebagian waktu menunggu buka. |
| 18. `testMissingAllRoutesIntoKelapaGadingRemainsUnknown` | PASSED | ETA hilang tetap unknown, tanpa durasi nol atau klaim optimum. |
| 19. `testNorthJakartaSubsetWaitsUntilKelapaGadingOpens` | PASSED | Subset Kota Tua–Kelapa Gading menunggu sampai 10.00. |
| 20. `testRecordedFourStopScheduleHasExpectedTravelWaitAndReturn` | PASSED | Empat tujuan: ETA, tunggu buka, singgah dan ruas kembali cocok dengan acuan tetap. |
| 21. `testShuffledInputStillVisitsEveryPlaceAndRespectsOpening` | PASSED | Input acak tetap menghasilkan urutan yang layak pada fixture. |
| 22. `testSyntheticHoursForEveryStopAreAllRespected` | PASSED | Semua jam buka/tutup asumsi sintetis diterapkan pada empat tujuan. |
| 23. `testSyntheticPeakETAUsesActualDepartureAfterDwell` | PASSED | ETA sintetis naik setelah +120 menit; waktu keberangkatan aktual digunakan. |
| 24. `testTripCrossingMidnightIsNotSilentlyShortened` | PASSED | Trip melewati tengah malam ditandai tidak lengkap tanpa membuang input. |
| 25. `testUnavailableTransitAndWalkingLimitDoNotInventTransport` | PASSED | Tanpa mobil, transit tidak tersedia dan batas berjalan tidak dilewati diam-diam. |

## Itinerary dengan fixture ETA asli

Baseline di tabel ini adalah **baseline versi sekarang yang sudah memakai elapsed**, bukan default lama sebelum commit perubahan.

| Skenario | Urutan setelah Sudirman | Perjalanan | Tunggu | Singgah | Total | Selesai WIB | Request adapter |
|---|---|---:|---:|---:|---:|---|---:|
| Baseline sekarang · 4 tujuan | Grand Indonesia → Monas → Kota Tua → Kelapa Gading → Sudirman | 121,02 | 16,77 | 120,00 | 257,78 | 11:17:47 | 30 |
| Hybrid sekarang · 4 tujuan | Grand Indonesia → Monas → Kota Tua → Kelapa Gading → Sudirman | 121,02 | 16,77 | 120,00 | 257,78 | 11:17:47 | 30 |
| Hybrid · Monas + Grand Indonesia | Monas → Grand Indonesia → Sudirman | 32,85 | 0,00 | 60,00 | 92,85 | 08:32:51 | 18 |
| Hybrid · Kota Tua + Kelapa Gading | Kota Tua → Kelapa Gading → Sudirman | 107,20 | 90,58 | 60,00 | 257,78 | 11:17:47 | 18 |

Semua durasi tabel dalam menit. Dua tujuan di utara dapat selesai pada waktu yang sama dengan empat tujuan karena jam buka Kelapa Gading tetap 10.00; waktu yang tidak dipakai untuk kunjungan lain menjadi waktu tunggu.

## Waktu komputasi dan request

**Waktu di bawah adalah eksekusi host dengan adapter tanpa jaringan, bukan waktu tunggu pengguna pada MapKit live.** Request adapter menghitung permintaan baru yang tidak terpenuhi cache; tidak ada request ke Apple.

| Skenario | Komputasi pipeline di Mac | Request | Rentang minimum awal request berdasarkan pacing 1,2 detik |
|---|---:|---:|---:|
| Baseline sekarang · 4 tujuan | 1.92 ms | 30 | 34.8 detik |
| Hybrid sekarang · 4 tujuan | 0.58 ms | 30 | 34.8 detik |
| Hybrid · Monas + Grand Indonesia | 0.19 ms | 18 | 20.4 detik |
| Hybrid · Kota Tua + Kelapa Gading | 0.24 ms | 18 | 20.4 detik |

Kolom pacing dihitung sebagai `(jumlah request − 1) × 1,2`. Itu batas bawah rentang dari awal request pertama ke awal request terakhir jika semuanya dikirim berurutan sesuai kebijakan saat ini. Belum termasuk respons request terakhir, cuaca, pencarian lokasi atau penundaan provider. Bukan hasil pengukuran jaringan, dan tidak boleh dijumlahkan begitu saja dengan seluruh latensi tiap request karena pacing dapat bertumpang tindih dengan waktu respons.

## Skenario sintetis tambahan

- `synthetic_all_hours_four_stops`: Monas → Kota Tua → Kelapa Gading → Grand Indonesia → Sudirman; total **296,13 menit**, selesai **11:56:08 WIB**, 84 request adapter. Asumsi sintetis, tidak memvalidasi trafik atau jam operasional nyata.
- `synthetic_peak_four_stops`: Grand Indonesia → Monas → Kota Tua → Kelapa Gading → Sudirman; total **321,83 menit**, selesai **12:21:50 WIB**, 5 request adapter. Asumsi sintetis, tidak memvalidasi trafik atau jam operasional nyata.

## Tujuh algoritme pada model yang sama

| Metode | Total menit | Evaluasi | Klaim |
|---|---:|---:|---|
| `baseline` | 257,78 | 2 | `not_proven` |
| `hybrid` | 257,78 | 497 | `not_proven` |
| `local` | 257,78 | 476 | `not_proven` |
| `insertion` | 257,78 | 71 | `not_proven` |
| `beam` | 257,78 | 50 | `not_proven` |
| `alns` | 257,78 | 1653 | `not_proven` |
| `exact` | 257,78 | 26 | `exhaustive_fixed_evaluator` |

Acuan 15.467 detik pada empat tujuan ini diperoleh dari enumerasi independen pada benchmark sebelumnya. Hasil semua metode sama pada kasus kecil ini; bukan bukti bahwa kualitasnya selalu sama pada input lain. Acuan model tetap tidak membuktikan optimum kondisi dunia nyata.

## Bukti dan reproduksi

- [Hasil terstruktur dan rincian itinerary](summary.json)
- [JUnit XCTest](junit.xml) — Converted from actual XCTest console events; case count/failure count cross-checked against suite summary.
- [Log build dan test](test.log)
- [Metrik/ruas mentah](itineraries.jsonl)
- [Identitas source dan konfigurasi](manifest.json)

Dari root repo:

```sh
./scripts/test-native-trip-jakarta.sh /tmp/c67-jakarta-unit-results
```

Gunakan direktori output baru. Runner menghasilkan laporan ini dari hasil test sebenarnya, termasuk kegagalan. Tidak menjalankan benchmark seluruh suite sebelumnya, tidak mengubah kode aplikasi, dan tidak menguji layanan live atau iPhone fisik.
