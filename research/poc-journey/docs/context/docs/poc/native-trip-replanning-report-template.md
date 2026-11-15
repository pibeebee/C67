# Laporan PoC itinerary native — [tahap / tanggal]

> Template. Ganti seluruh placeholder dan jangan mengisi Passed sebelum bukti tersedia. Saat menyalin template ke direktori hasil, sesuaikan tautan rencana/matriks dan artefak terhadap lokasi laporan tersebut.

**Rencana induk:** [masterplan](native-trip-replanning-masterplan-2026-11-03.md).  
**Kasus penerimaan:** [matriks](native-trip-replanning-test-matrix-2026-11-03.md).  
**Tahap/gerbang:** [P0/P1/P2A/P2B/P3/P4; G…].  
**Waktu pelaksanaan:** [tanggal, jam, zona].  
**Keputusan:** [lanjut / revisi / persempit / investigasi kembali / belum cukup bukti].

## 1. Pertanyaan dan hasil utama

- Hipotesis yang diuji: [H-…].
- Kemampuan yang diperiksa: […].
- Hasil paling penting beserta angka/jumlah kasus: […].
- Batas hasil yang memengaruhi keputusan: […].
- Hal yang belum diuji: […].

## 2. Sumber dan lingkungan yang benar-benar diuji

| Field | Nilai aktual |
| --- | --- |
| Repository/branch | […] |
| Base commit | […] |
| Working tree dan source manifest | […] |
| Perubahan sejak basis sebelumnya | […] |
| Xcode/Swift/SDK | […] |
| Host OS / Simulator OS | […] |
| iPhone model/OS | [… / Not run] |
| Konfigurasi mode/provider | [replay/live; provider; tanpa menyalin key] |
| Internet / akses backend tim | [diizinkan/diblokir/bagaimana dibuktikan] |
| Jam/zona trip dan clock eksperimen | […] |
| Cache awal, seed, request/eval/CPU/wall budget | […] |
| App/build ID | […] |

## 3. Input, oracle, dan pembanding

- Fixture/brief dan versi/hash: […].
- Provenance ETA: [sintetis / rekaman / live; waktu pengambilan].
- Sumber jam operasional dan tanggal berlaku: […].
- Provider cuaca, retrievedAt, interval berlaku: […].
- Actual state: [kunjungan selesai/current/pending/skip; asOf].
- Deadline dan endpoint: […].
- Pembanding: [urutan diterima yang divalidasi ulang / cara biasa pengguna / lainnya].
- Kesetaraan input/oracle/budget/cache dan urutan eksekusi: […].
- Auditor independen dan toleransi: […].

## 4. Ringkasan pengujian

| Tingkat bukti | Kasus | Pengulangan | Passed | Failed | Blocked | Not run | Inconclusive |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Domain/unit | | | | | | | |
| Storage lintas proses | | | | | | | |
| Pipeline/replay | | | | | | | |
| UI Simulator | | | | | | | |
| Layanan live/iPhone | | | | | | | |
| Walkthrough/perjalanan | | | | | | | |

Build lulus dicatat terpisah: […]. Jangan menggabungkan build, harness, XCTest, run benchmark dan sesi pengguna menjadi satu jumlah tes tanpa penjelasan.

| ID kasus | Harapan | Hasil aktual | Status | Bukti | Keputusan/fix |
| --- | --- | --- | --- | --- | --- |
| […] | | | Not run | | |

## 5. Contoh sebelum/sesudah

| Elemen | Rencana diterima sebelum perubahan | Baseline setelah konteks diperbarui | Proposal |
| --- | --- | --- | --- |
| AsOf/anchor | | | |
| Urutan sisa | | | |
| Waktu keluar current stop | | | |
| Selesai di endpoint | | | |
| Perjalanan/menunggu/singgah tersisa | | | |
| Deadline/conflict/unknown | | | |
| Request/cache | | | |

- Prefix aktual sebelum/sesudah: [identik/tidak; field yang diperiksa].
- Delta karena perubahan pengguna: […].
- Perbaikan terhadap baseline pada konteks yang sama: […].
- Keputusan pengguna/apply: […].
- Revision/receipt/hasil restore: […].

## 6. Kinerja dan availability

| Kelompok input/mode/cache | n operasi | Sukses | Gagal/partial/cancelled | Median | p90 | Request ETA/map/weather/search |
| --- | ---: | ---: | --- | --- | --- | --- |
| […] | | | | | | |

Catat seluruh run, ukuran sampel, status cache dan konteks trafik; p90 sampel kecil bersifat deskriptif. Pisahkan CPU, waktu jaringan, dan waktu menunggu pengguna. Perubahan target/budget setelah pilot: [alasan + hasil pengukuran ulang].

## 7. Temuan gagal dan perubahan iterasi

| Temuan | Bukti | Dampak | Perubahan | Kasus regresi | Hasil setelah perubahan |
| --- | --- | --- | --- | --- | --- |
| […] | | | | | |

Jelaskan apakah kebijakan disetel menggunakan kasus yang sama. Sebutkan himpunan tambahan yang belum dipakai menyetel implementasi. Pertahankan artefak awal yang gagal.

## 8. Observasi pengguna/lapangan bila dilakukan

- Jumlah dan kriteria peserta/perjalanan: […].
- Persetujuan, data yang dikumpulkan, retensi dan anonimisasi: […].
- Tugas dan urutan pembanding: […].
- Yang peserta lakukan: […].
- Yang peserta katakan: […].
- Interpretasi tim dan alternatif penjelasan: […].
- Penyelesaian tanpa pengambilalihan moderator: [x/n].
- Pemahaman dampak perubahan: [x/n].
- Waktu/koreksi berpasangan: […].
- ETA versus aktual dan akses tempat: […].
- Klaim yang didukung / belum didukung: […].

## 9. Keputusan dan langkah berikutnya

- Gerbang [G…]: [lulus / belum lulus; alasan].
- Keputusan lingkup: […].
- Masalah kritis yang masih terbuka: […].
- Kebutuhan bukti berikutnya dan pemiliknya: […].
- Kesiapan integrasi Foundation Models bila relevan: [belum dievaluasi / hasil terpisah; inti tetap dapat dipakai].
- Tautan artefak dan cara reproduksi: […].

## 10. Daftar artefak

Manifest source/config, input fixture, accepted snapshot, event/perubahan, proposal, hasil apply/restore, hasil auditor, log pengujian, metrik semua run, bukti UI/device, dan observasi anonim sesuai lingkup. Jangan menyertakan credential atau koordinat pribadi pada paket bersama.
