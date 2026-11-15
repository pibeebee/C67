# Cadangan cuaca native — WeatherKit → Open-Meteo

Berlaku pada PoC iOS `poc-c67`, untuk **Hitung itinerary** dan akuisisi snapshot **Bandingkan algoritme → Tempat saya · MapKit**. Tidak ada pengaturan baru; WeatherKit tetap didahulukan.

## Perilaku

1. Di dalam horizon sekitar 10 hari, minta atribusi dan prakiraan WeatherKit.
2. Bila atribusi gagal, request gagal/timeout dari provider, prakiraan untuk trip kosong, atau tanggal di luar horizon WeatherKit, coba Open-Meteo per area yang belum terselesaikan.
3. Titik berdekatan berbagi hasil sementara per pembulatan 0,01 derajat, termasuk provider dan status. Kegagalan satu titik tidak mengganti prakiraan WeatherKit yang berhasil di area lain.
4. Pembatalan pengguna/task tidak memulai fallback. Pembatalan saat Open-Meteo sedang berjalan diteruskan ke URLSession. Request Open-Meteo memakai timeout request 25 detik/resource 30 detik, tanpa retry otomatis.
5. Jika keduanya gagal, tidak mengisi peluang presipitasi nol. Data tetap `unavailable`/`outside_forecast_horizon`; evaluasi paparan mempertahankan interval unknown.

Open-Meteo mendokumentasikan prakiraan hingga 16 hari. Rentang di luar cakupan tidak diminta sebagai data historis. Bagian hari yang tidak terjangkau tetap unknown. Contoh 1 Desember 2026 berada di luar kedua horizon pada 3 November 2026; fallback bukan cara memprediksi cuaca sebulan ke depan.

## Request dan pemetaan

- HTTPS `https://api.open-meteo.com/v1/forecast`, tanpa API key untuk endpoint PoC nonkomersial.
- Dikirim: koordinat titik terpilih, tanggal UTC yang relevan, `hourly=precipitation_probability,temperature_2m`, Celsius, GMT dan timestamp Unix. Nama tempat, daftar itinerary, kredensial Apple dan lokasi GPS perangkat tidak dikirim.
- Timestamp absolut UTC dipakai agar zona waktu trip/DST tidak menggeser jam prakiraan.
- `precipitation_probability` adalah persen untuk **satu jam sebelumnya**. Saat dipetakan ke model interval aplikasi, timestamp dikurangi satu jam dan nilai dibagi 100. Presipitasi mencakup hujan maupun salju; ini bukan data intensitas hujan atau tambahan durasi perjalanan.
- Nilai null/tidak valid tidak diubah menjadi nol. Respons dengan unit salah, panjang array tidak cocok atau interval duplikat/tidak berurutan ditolak. Suhu opsional, tidak menggantikan peluang presipitasi yang hilang.
- Waktu pengambilan dicatat sebagai `retrievedAt`. Endpoint Open-Meteo ini tidak memberikan waktu penerbitan model; field metadata `fetchedAt` dibiarkan kosong.

## Hasil, atribusi dan log

Detail cuaca menampilkan Apple Weather atau Open-Meteo per titik, alasan fallback, dan waktu pengambilan. Open-Meteo diberi tautan sumber serta CC BY 4.0 di tampilan data dan laporan teks. Ekspor kasus pembanding menyertakan `weatherSources` dan `weatherAttribution` sebagai field opsional yang kompatibel dengan kasus lama.

Log lokal yang sudah ada menerima `weather.failed` per provider, `weather.fallback_requested`, serta `weather.result` dengan sumber/provider, status, waktu dan jumlah jam. Alur log/ekspor sebelumnya tetap berlaku. Jangan menafsirkan `source=cache` sebagai provider cuaca; lihat field `provider`.

Endpoint gratis ditujukan untuk penggunaan nonkomersial; kebutuhan produk komersial perlu memakai paket yang sesuai. Implementasi ini untuk PoC, tanpa akun atau subscription baru.

## Verifikasi

- Pemeriksaan logika macOS secara offline: `./scripts/check-native-trip-weather.sh`. Menggunakan closure dan URLProtocol lokal untuk respons sukses/gagal; tidak meminta cuaca live.
- Pemeriksaan routing macOS yang sudah ada memverifikasi kompatibilitas evaluator/kasus setelah metadata sumber ditambahkan.
- Build generic iOS unsigned dan pemeriksaan format. Tidak menjalankan tes iOS, Simulator, install/launch iPhone atau request WeatherKit/Open-Meteo live. Autentikasi WeatherKit dan ketersediaan fallback pada jaringan iPhone masih memerlukan uji perangkat.

Bukti hasil pemeriksaan dicatat pada [verification/NATIVE_WEATHER_FALLBACK_2026-11-03.json](verification/NATIVE_WEATHER_FALLBACK_2026-11-03.json).

Rujukan resmi: [Forecast API](https://open-meteo.com/en/docs), [lisensi dan atribusi](https://open-meteo.com/en/licence), [syarat penggunaan](https://open-meteo.com/en/terms).
