# Kontrak katalog dan pengayaan v1

Server menerima hasil pengayaan yang sudah diperiksa dan menyediakan proxy saran Luna yang dibatasi pilihan dari perangkat. Server tidak menjalankan crawler. Kunci provider tetap di server.

## Endpoint

| Method/path | Otorisasi | Perilaku |
| --- | --- | --- |
| `GET /health` | Tidak ada | Identitas service, tanpa membaca provider |
| `GET /v1/catalog` | Bearer `POCKET_READ_TOKEN` | Envelope `schemaVersion`, `generatedAt`, `attribution`, `venues` |
| `POST /v1/evidence/import` | Bearer `POCKET_WRITE_TOKEN` | Impor atomik 1–1000 cabang yang sudah ditinjau; field segar dilewati |
| `POST /v1/advice/visits` | Bearer `POCKET_READ_TOKEN` | Memilih satu ID dari 1–6 jadwal yang telah disusun perangkat; Luna Max, tanpa fallback |
| `POST /v1/providers/tomtom/search` | Bearer `POCKET_READ_TOKEN` | Satu Discover v3, maksimum lima hasil; opsional, tanpa persistensi hasil |

Respons memakai `Cache-Control: no-store`. Ranking tempat, pemeriksaan kelayakan, optimasi urutan, dan ETA tetap di perangkat. Endpoint saran menerima minat, refinements, preferensi, tanggal dan ringkasan pilihan kunjungan; tidak menerima kunci provider atau titik awal pengguna. Server tidak menerapkan TLS sendiri; untuk akses publik gunakan terminasi HTTPS dan batas akses yang sesuai.

## Impor bukti

Envelope:

```text
schemaVersion: 1
reviewed: true
records: [
  venueID: ID independen yang sudah ada dalam katalog
  facts: [Fact, ...]           # opsional; maksimum satu per field dalam impor
  hours: HoursEvidence | null # opsional; null tidak menghapus bukti
]
```

`Fact`:

| Properti | Kontrak |
| --- | --- |
| `field` | 62 ID dalam [taksonomi Pocket](../Sources/PocketEngine/Resources/preference-labels.json) serta `publicAccess`, `reading`, `coffee`, `quiet`, `children`, `wheelchair`, `noMembership` |
| `status` | `supported`, `contradicted`, `unknown` |
| `value` | Ringkasan pendek, maksimum 500 karakter |
| `sourceURL` | HTTPS operator/sumber yang sudah dikenal untuk cabang, atau domain resmi `jakarta.go.id` |
| `quote` | Kutipan fakta, 8–2000 karakter |
| `branchQuote` | Kutipan yang memuat nama/alias cabang yang dikenal, 5–500 karakter |
| `checkedAt` | ISO 8601 UTC (`...Z`); waktu pemeriksaan nyata, bukan waktu impor |
| `expiresAt` | ISO 8601 UTC; setelah pemeriksaan dan paling lama 30 hari sesudahnya |

Status contradicted berarti bukti secara eksplisit membantah atribut tersebut. Contoh makna field outdoor contradicted: bukti mengatakan kegiatan berada di dalam ruang. Tidak adanya kata outdoor tidak membuktikan indoor. Field publicAccess tidak boleh disimpulkan dari kategori bisnis saja. Konflik fakta segar pada klien menjadi unknown.

`HoursEvidence` memakai properti sumber/waktu/kutipan di atas, tanpa `field/status/value`, dan `intervals`:

```text
intervals: [
  weekday: 1...7               # Minggu = 1
  startMinute: 0...1439
  endMinute: start+1...2880    # >1440 hanya bila sumber menyatakan lewat tengah malam
  date: YYYY-MM-DD | null     # opsional; tanggal eksplisit harus cocok weekday
]
```

Jangan mengubah jam untuk tujuh hari mendatang menjadi jam mingguan tanpa dukungan. Hari tanpa interval tetap unknown untuk perencanaan. Hari dengan pengecualian tutup yang belum dapat dinyatakan oleh kontrak ini harus ditahan lewat masa berlaku atau sumber yang lebih jelas; jangan mengandalkan jam reguler untuk hari itu. Data jam kosong tidak dipakai planner.

Peninjau harus memeriksa nama fisik, cabang, hubungan kutipan dengan cabang, status akses, masa berlaku, syarat masuk, dan hak penggunaan sumber. `reviewed: true` adalah pernyataan peninjau, bukan sertifikasi otomatis. Pemeriksaan server terhadap quote/name tidak membuktikan bahwa kutipan benar-benar ada pada halaman. Output mentah LLM tidak boleh langsung ditandai reviewed.

Seluruh impor dibatalkan jika satu record tidak valid. Transaksi SQLite mencegah dua impor cabang menimpa fakta segar pada saat bersamaan. Field segar, termasuk unknown yang sudah diperiksa, dilewati hingga expiresAt/maksimum 30 hari. Masalah transport tidak diubah menjadi fakta unknown.

Alternatif impor lokal setelah peninjauan, tanpa membuka service HTTP:

```sh
python3 Server/server.py --import-evidence /absolute/path/reviewed-evidence.json
```

Perintah ini menulis database, sehingga tidak dijalankan pada tahap build-only.

## Pencarian TomTom

Body dari aplikasi: `query` (1–200 karakter), `latitude`, `longitude` (angka atau teks numerik). Dibatasi wilayah Jakarta pilot. Token TomTom hanya dibaca di server dari `TOMTOM_API_KEY`; koneksi hanya menuju endpoint Discover v3 yang tetap. Redirect ditolak. Maksimal satu request provider aktif, maksimum 20 reservasi/hari UTC default, dan tidak ada retry/fallback otomatis.

Respons iPhone: `results` berisi `id`, `name`, `address`, `coordinate`, `hoursSummary`, serta `notice` atribusi. Data ini **tidak** diterima endpoint impor dan tidak otomatis membuktikan publicAccess. Penyesuaian cabang membutuhkan satu padanan nama/alias dan koordinat yang konsisten. Ketentuan penggunaan/retensi paket TomTom perlu diperiksa sebelum mengubah data sesi menjadi katalog tersimpan.

## Identitas sumber terbuka

Gunakan `Scripts/import-open-data.py` untuk mengubah JSON Overpass atau GeoJSON Overture menjadi katalog identitas. Kategori sumber tetap dibedakan dari fakta syarat wajib. Skrip menyimpan hash input serta atribusi per record.

Impor katalog melalui `python3 Server/server.py --data-dir /path/to/isolated-data --import-identities /path/to/identities.json`. Impor atomik menambah ID OSM/Overture baru, mempertahankan identitas yang diperiksa kurang dari 30 hari lalu, dan menolak fakta/jam pada jalur identitas. Identitas yang sudah 30 hari dapat diperbarui. Perubahan nama atau koordinat mengosongkan bukti lama agar fakta cabang sebelumnya perlu diperiksa kembali. Metadata yang tetap sama mempertahankan fakta dan jam yang sudah ada. Bukti tetap masuk melalui impor bukti ditinjau. `POCKET_SEED_CATALOG` dapat menunjuk katalog independen untuk inisialisasi lab terisolasi.

Field `noMembership` memerlukan bukti eksplisit bahwa kunjungan tidak membutuhkan keanggotaan. `publicAccess` sendiri menyatakan akses publik yang didukung sumber.


Untuk pengujian terisolasi, jalankan `Scripts/prepare-reviewed-catalog.py --identities identities.json --evidence reviewed.json --output catalog.json`. Skrip mengimpor kedua input melalui validator yang sama dengan server dan menghasilkan file katalog dari SQLite sementara. Katalog normal dapat disinkronkan melalui endpoint yang sama. Untuk mengukur kontribusi bukti, bandingkan dengan katalog identitas yang memakai ID, koordinat, dan kategori sumber yang sama.

Fakta bertipe label dapat menambah tipe atau subtipe dari sumber yang sudah ditinjau. Fakta segar yang bertentangan atau belum pasti menahan label tersebut pada tahap penilaian. Fitur seperti `rooftop` dan `children_play_area` masuk sebagai syarat berbasis bukti. Pemetaan kategori identitas dari OSM, Overture, dan Apple bergantung pada atribut yang memang disediakan tiap sumber.

## Saran jadwal Luna Max

`POST /v1/advice/visits` menerima `interests`, `refinements`, `preferences`, `preferredVisitMinutes` (key ID venue), `day`, dan `options`. Ada 1–6 pilihan dengan `slotID` berurutan S1–S6; setiap pilihan memiliki departure, finish dan 1–6 visits berisi venueID, name, start, end, categories, supportedAttributes, weather. Maksimum payload saran 80 KB. Respons hanya `slotID`, `requestedModel`, `reportedModel`, `elapsedMS`; server menolak JSON/ID/model yang tidak sesuai.

Endpoint provider dikonfigurasi pada server dengan `POCKET_LLM_BASE_URL`, model request `cx/gpt-6-luna(max)`, respons boleh melaporkan alias `gpt-6-luna(max)`. Identitas upstream internal tidak dapat dibuktikan dari alias ini. Satu request, maksimum 500 output tokens, koneksi 15 detik dan total upstream 85 detik. Tidak ada redirect, fallback, atau retry otomatis. Satu panggilan provider aktif pada server, bersama batas konkurensi TomTom.

Konfigurasikan `POCKET_LLM_ENV_FILE` ke file kredensial privat yang sudah ada (mendukung GIOVANC_API_KEY atau CATALOG_LLM_API_KEY dengan base URL yang sama dengan `POCKET_LLM_BASE_URL`), atau isi POCKET_LLM_API_KEY langsung pada server. Kunci tidak dikirim ke app. Transport memakai curl dan TLS sistem macOS, melalui stdin tanpa secret pada argv. Log hanya endpoint/status, jumlah pilihan, model yang dilaporkan dan durasi; tidak mencetak prompt, respons mentah, atau token. Tidak tersedia pencatatan biaya/provider billing otomatis.

App menyimpan pool jadwal asal, mengubah ID terpilih kembali ke objek asli, memeriksa ulang syarat dan masa berlaku bukti, serta menolak respons jika konfigurasi perjalanan berubah saat menunggu. Luna tidak dapat menambahkan tempat atau mengubah jam/rute. Jika koneksi/format gagal, jadwal tidak diterbitkan. Pengguna dapat mengulang, atau menonaktifkan saran Luna secara eksplisit pada Pengaturan untuk memakai planner Swift.

Publication build: set `POCKET_LLM_BASE_URL` explicitly. Luna reservations (including failed upstream attempts) are persisted separately from TomTom, capped at `POCKET_LUNA_DAILY_CAP` (default 20, maximum 100) per UTC day. A shared read token is for invited beta users.
