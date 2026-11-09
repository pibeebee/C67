# Eksperimen D: cari lokal, validasi finalis

User mengizinkan implementasi ide pencarian kandidat murah dengan sedikit validasi provider pada6 November2026. Implementasi terbatas pada lab; source PoC/aplikasi asli dipertahankan. Tidak ada LLM atau homelab.

## Kebijakan D v1

D memakai fakta, preference gate, E5, jam layanan, durasi, deadline dan auditor final yang sama dengan C. Perubahan hanya pada pencarian kandidat routing. Maksimal6 tujuan on-demand automobile, sehingga≤720 urutan dienumerasi secara lokal. Prior tetap: `(300 + jarakCoreLocation/8) × faktor`, faktor1,35 pada07–10/16–19 WIB dan1 di luar itu. Ini perkiraan engineering belum dilatih dari data jalan, bukan ETA Apple.

Urutan diperingkat menurut jumlah konflik perkiraan, waktu selesai+paparan hujan perkiraan, waktu travel perkiraan, lalu tie-break ID. Slot15menit dan policy full-stay/session dipakai saat estimasi. Estimasi tidak pernah dimasukkan ke cache ETA provider atau ruas final.

Finalis pertama divalidasi berurutan dengan ETA Apple pada departure yang diperoleh setelah kunjungan aktual sebelumnya. Engine NativeTripEngine.evaluate dan audit akhir tidak dilonggarkan. Jika validasi menemukan konflik jadwal, observasi edge hanya mengkalibrasi ranking spekulatif, lalu urutan yang belum diperiksa dicoba lagi. Maksimal3 validasi. Jika provider tidak memberi ETA, hentikan; unknown tidak diubah menjadi nol atau global infeasible. Cache provider tetap exact departure sesuai engine. Hasil layak pertama dikembalikan; tidak ada klaim optimum.

Local rank mengutamakan feasibility dan memakai prior hujan sebagai soft score. Kualitas hasil dapat berbeda dari C; cuaca akhir tetap dilaporkan dan diaudit, tidak dijadikan jaminan kenyamanan. Inferensi ulang/asimetris memerlukan validasi final, bukan memperlakukan pengamatan pagi sebagai ETA sore.

## Yang belum diimplementasikan dari ide awal

Belum ada prefetch saat pengguna mengisi form, model waktu jalan terlatih, atau optimasi lanjutan di background dengan tawaran perubahan. D v1 menguji inti paling kecil: local shortlist, bounded repair, first valid result. Tidak ada hasil parsial yang diberi label itinerary siap.

## Matriks dan pembanding

Pembanding live **C vs D** pada17kasus masing-masing=34observasi. N1/N3/N4/N5 tiga pengulangan fresh, plusREV5/MIX5/TIGHT5/SIX/UNKNOWN. Urutan bergantian CD/DC per kasus; kondisi sama dengan benchmark simulator terkontrol sebelumnya: pin native MapKit nyata identik, tanggal itinerary7November2026, WeatherKit/ETA live, E5 aktual, fallback dimatikan, HTTP loopback. Identity search/branch di luar timer; tidak mengklaim discovery E2E.

C tidak diubah: bulk snapshot, sequential final validation, pacing1,2detik dan provider concurrency1. D memakai pacing yang sama, satu runtime E5 dan passage cache seperti C. Tidak memakai data hasil C untuk fitting prior D atau memanaskan cache ETA D; cache provider lintasjob tetap off. Weather grouping tetap seperti engine.

Timer monotonic client create/revise→result lengkap diterima+persist; acceptance baseline dan precompute di luar timer. D timeout240detik, tiga validasi; tidak diberi evaluasi lebih banyak daripada C. Maks1500providerHTTPcalls dan2000ETAcells pada kampanye baru. Account quota remainder tidak diketahui; 429 menghentikan operasi dan tidak diulang. Policy/hash dibekukan di artifacts/fast-d-live-2026-11-06 sebelum live. Keep-awake sementara menghindari gangguan idle sleep yang ditemukan sebelumnya.

Target eksploratif D median N5<10detik. Hard constraints harus nol pelanggaran. Objective tiap pasangan, travel, waiting, order dan rain exposure dilaporkan; selisih elapsed>5menit **atau**>5% diberi quality flag, bukan disembunyikan oleh kecepatan. Provider live dapat berubah antarrequest; selisih bukan ukuran regret kausal/optimum.

## Pengujian sebelum live

Replay oracle C/D:34outcome,14pasangan ready, objective sama dalam1detik. Oracle replay jarak/time serupa prior D, sehingga equality bukan bukti kualitas generalisasi. Uji adversarial wajib: salah estimasi edge menyebabkan deadline conflict→repair; provider unavailable→no ready; semua kandidat gagal→stop3; full-stay gate tetap menolak; returned ETA harus nilai provider sintetis yang sengaja berbeda dari prior; exact departure mengikuti visit; seluruh720urutan unik; dan contoh eksplisit first-feasible layak tetapi objective lebih buruk dari urutan lain.

Auditor independen memakai katalog mentah, source/session/full-stay, deadline, provider queries, rain coverage, revision baseline, call/cell accounting. Tidak mempercayai boolean runner. Semua kegagalan tersimpan. Tidak ada pemilihan ulang hanya run buruk.

## Reproduksi

Build/test Debug. CLI `planner-bench fast-replay OUTPUT` terhadap server replay menjalankan matriks C/D yang sama. Simulator live memakai `comparison: CD` dalam manifest dan helper simulator-run.py. Tool XcodeBuildMCP tidak tersedia pada sesi D, sehingga build/install/launch menggunakan xcodebuild/simctl. App memakai bundleID PoC yang sama; export bukti lalu restore binary asli tanpa uninstall. Filekey dan env tetap di Mac dan diabaikan Git.
