# Konteks produk untuk pengembang C67

**Ringkasan 22 Oktober 2026**, dari CBL dan dokumen teknologi workspace. Ini ringkasan mandiri untuk memulai repository; sumber lengkap, path lokal dan checksum dicatat pada [source-manifest.json](source-manifest.json). Klarifikasi pengguna terbaru mengungguli proposal lama.

## Pengalaman utama

Traveller mencari area atau menjelajah map → memilih rundown pengalaman kreator → memahami urutan spot, landing point, durasi, moda, tips dan konteks waktu → memilih waktu pelaksanaan yang fleksibel → mengikuti spot → mendokumentasikan foto → memperoleh album satu perjalanan. Ekspor ke media sosial opsional.

Contoh Athar: dari Agora Mall Thamrin mencari Kota Tua, memilih rundown, menuju titik awal, mengunjungi spot, menambahkan foto tiap spot, lalu membuka album. Landing point boleh berbeda dari spot pertama; bila sama, jangan membuat dua konfirmasi kedatangan identik.

Contoh Tokyo A/B tetap aktif: A berisi Chiyoda → Asakusa → Shibuya; B berisi Asakusa → Shibuya → Shinjuku. Traveller dapat melengkapi trip A dengan sumber B. Cara memilih sebagian, menyelesaikan overlap dan menjadwalkan ulang belum final.

## Batas yang perlu dipertahankan

- Rundown kreator adalah fitur utama. Foto/GPS mendukung pelaksanaan dan journaling, dengan album sebagai hasil perjalanan.
- Jam dalam template adalah rekomendasi; tidak mengunci waktu traveller.
- Foto setiap spot wajib dalam best-case Athar; pengecualian gagal/skip/berhenti dini masih terbuka.
- Foto boleh dari kamera, galeri, selfie, pemandangan atau editan. GPS perangkat diperiksa saat tindakan unggah; pernah tiba tidak cukup. Itu bukan bukti keaslian foto atau lokasi absolut.
- Cuaca membantu persiapan, moda dan penyesuaian. Availability, ETA, jam buka dan data tempat harus dibuktikan; tidak mengisi data kosong dengan angka simulasi tanpa label.
- Tidak ada keputusan baru tentang gamifikasi, chat, social graph, booking, pembayaran atau pelacakan orang lain.

## Keputusan yang masih terbuka

Provider/framework server; akses guest/library; makna default jam mulai; aturan merge/otomatisasi cuaca; skip/partial completion; presence saat transfer/finalisasi dan parameter GPS; audience/moderasi kontribusi; hak salinan dan penghapusan; retensi; provider transit serta dukungan offline terperinci.

Supabase/PostgreSQL/PostGIS/Storage/Edge Functions, worker media dan SwiftData adalah kandidat dari spesifikasi 0.1, bukan keputusan final tim. Kesepakatan monorepo dan arah VIPER dari percakapan 22 Oktober memperbarui pembagian kode; tidak mengesahkan seluruh proposal tersebut.

## Temuan audit yang memengaruhi implementasi

Model landing → stop pertama perlu dilengkapi; moderasi mencakup konten kreator; foto tambahan tidak boleh tanpa sengaja meregresi stop completed; kontrak media kreator perlu diperinci. Ketergantungan finalisasi presence pada antrean worker perlu diputuskan sebelum pilot foto. Detail keputusan tetap terbuka, bukan perilaku yang sudah diimplementasikan.

## Bukti yang sudah ada dan batasnya

Wireframe revisi 2 di workspace adalah simulasi HTML. PoC native terdahulu terpisah dan mencakup journaling satu pin dengan JSON lokal. Keduanya bukan implementasi monorepo ini. Foldering sekarang belum membangun aplikasi, menjalankan API, menguji GPS fisik, memvalidasi kebutuhan pengguna atau menyiapkan produksi.
