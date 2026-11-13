# UI minimal dan log persisten — perencana native C67

Pembaruan **3 November 2026** pada `<LOCAL_HOME>/Programming/software/ios/poc-c67`.

## UI

Tampilan default membuka **Rencana** tanpa tab tambahan. Tab Jejak dihapus dari alur default; eksperimen diary tetap dapat dibuka dengan `--diary-demo`/`--diary-ui-testing`, dan lab lama melalui `--legacy-poc`. Modul serta datanya dipertahankan.

Form utama hanya memuat titik awal/akhir, waktu berangkat beserta zona waktu, daftar tujuan, akses **Pengaturan**, serta **Temukan lokasi** dan **Hitung itinerary**. Tambah satu tempat atau banyak tempat lewat **Tambah tempat → Satu tempat / Tempel daftar**. Nama dapat disimpan dengan **Simpan nama dulu**. Contoh Jepang dan rencana baru tetap tersedia pada menu tiga titik.

Durasi default, zona waktu, konteks kota/negara, moda dan batas preferensi ada di **Pengaturan**. Peran/durasi/paparan/jam operasional per tempat tetap ada pada detail tujuan. Hasil memakai rincian yang dapat dibuka; peta, cuaca dan penjelasan panjang ditutup secara default. Kode error teknis berpindah ke layar **Log**.

## Penyimpanan otomatis

Log aktif otomatis pada perencana native. Tombol ekspor tidak diperlukan untuk memulai perekaman. Setiap event masuk antrean berurutan, ditulis ke berkas lalu disinkronkan melalui `FileHandle.synchronize()`. I/O dilakukan pada actor terpisah dari UI. Ekspor menunggu antrean yang sudah terjadwal selesai sebelum membaca berkas.

Lokasi lokal: **Application Support/NativeTripLogs/log-*.jsonl** dalam sandbox aplikasi. Folder log dikecualikan dari backup sistem dan tidak dikirim ke backend/CloudKit oleh fitur ini. Draf UI tetap dalam memori; isi snapshot yang tercatat pada log adalah data debugging, bukan fitur pemulihan draf.

Format **JSON Lines**, satu event JSON per baris. Metadata meliputi schema version, timestamp UTC, ID event/sesi, urutan sesi, ID operasi, level, kategori, nama event dan field. Event pembuka sesi mencatat versi/build aplikasi dan versi OS. Log tidak mengambil semua pesan Console iOS atau log modul rombongan/diary lama secara otomatis.

Event yang dicatat:

- Input daftar dan perubahan titik/pilihan lokasi, sumber MapKit atau pin pengguna, serta snapshot input sebelum pencarian/perhitungan, termasuk tanggal, zona waktu, koordinat, durasi, moda dan batas yang dipakai.
- Pencarian: query, petunjuk area, batas waktu, ID request, durasi, kandidat hasil, status dan domain/code/underlying error. Timeout, pembatalan, kosong dan throttling tetap dibedakan.
- ETA: asal/tujuan/koordinat, moda, waktu permintaan, cache, respons waktu provider sebelum validasi, durasi/jarak, status, serta opsi yang dikecualikan oleh batas berjalan.
- WeatherKit: permintaan, cache/horizon, jumlah jam cakupan, metadata waktu, status dan error. Log tidak menyimpan dump seluruh respons WeatherKit/prakiraan per jam sebagai dataset.
- Penyusunan kandidat: urutan, status lengkap/layak, total perjalanan/menunggu/durasi trip, baseline dan kandidat validasi, model refinement, jumlah request/budget, paparan cuaca yang diketahui/tidak diketahui, konflik, keputusan cuaca, hasil teks dan kegagalan validasi/perhitungan.
- Pembatalan, perubahan fase aplikasi, dan permintaan/hasil ekspor.

Nama tempat, alamat/query dan koordinat pilihan **termasuk dalam log** untuk debugging. File hanya dibagikan ketika pengguna mengekspornya. Tidak mencatat API key atau meminta izin GPS baru.

Retensi: maksimal **10 berkas × 2.000.000 byte**, sekitar 20 MB. Berkas tertua dirotasi saat membuat berkas baru. Field panjang dibatasi dan diberi penanda pemotongan; record yang terlalu besar memakai preview bertanda `truncated`. Snapshot menampilkan 80 event terakhir; ekspor memuat semua isi berkas yang masih disimpan, termasuk baris mentah yang tidak dapat didekode.

Jika menulis gagal, UI menampilkan **Sebagian log gagal disimpan**; kegagalan tidak dianggap sebagai sukses dan tidak menghentikan perhitungan itinerary. Jika terjadi partial write, event berikutnya memakai berkas baru. Berkas log yang sudah berhasil ditulis dapat dibaca sesi berikutnya. Penghentian proses mendadak dapat menghilangkan event terakhir yang masih dalam antrean; ini breadcrumb aplikasi, bukan penangkap crash/stack trace iOS.

## Membaca dan mengekspor

1. Buka **Log** di kanan atas layar Rencana atau pemilih lokasi.
2. Ketuk event untuk melihat field dan kode error; tarik layar untuk memuat ulang.
3. Tekan **Ekspor log (.txt)**, lalu pilih tujuan melalui dialog sistem Files. Isi file tetap JSON Lines agar mudah diproses dengan alat debugging.

File ekspor merekam kondisi sampai `log.export_requested`. `log.export_completed`, kegagalan atau pembatalan ekspor dicatat setelah dialog selesai dan akan muncul pada ekspor berikutnya. Membuka layar Log tidak membatalkan pekerjaan yang sedang berjalan; aplikasi yang tidak aktif tetap membatalkan operasi sesuai kebijakan sebelumnya.

## Verifikasi

- Build generic iOS unsigned, minimum iOS 18.
- Sembilan pemeriksaan macOS tanpa jaringan: append/JSON, urutan/flush, sesi baru, batas record, rotasi ukuran/jumlah, baris rusak, kegagalan disk, underlying error, serta data yang ditulis satu proses dan dibaca proses lain setelah proses penulis berhenti.
- Pemeriksaan input dan kebijakan pencarian lokal yang sudah ada dijalankan kembali untuk perubahan model terkait.
- Format Swift strict dan `git diff --check`.
- Tidak menjalankan aplikasi iOS, Simulator, tes iOS, instalasi iPhone, atau request layanan Apple. UI/export Files, suspend/kill iOS dan hasil MapKit/WeatherKit masih belum diverifikasi pada perangkat.

Ulangi pemeriksaan log lokal dengan `./scripts/check-native-trip-logs.sh`. Bukti hasil ada di [catatan verifikasi](verification/NATIVE_MINIMAL_UI_LOGGING_2026-11-03.json).

## Provider cuaca cadangan

Event `weather.failed`, `weather.fallback_requested` dan `weather.result` mencatat `provider` (`weatherkit`, `open_meteo`, atau `none`), point ID, alasan error, jumlah jam dan penggunaan cache. `fetchedAt` adalah waktu metadata sumber bila tersedia; `retrievedAt` adalah waktu pengambilan. Open-Meteo tidak memberi waktu penerbitan model pada endpoint ini, sehingga tidak dibuatkan nilai metadata palsu. Fallback hanya mengirim koordinat pilihan dan rentang tanggal cuaca ke Open-Meteo; nama tempat dan seluruh itinerary tidak disertakan pada request.
