# Probe live Jakarta

Jalankan dari root repo dengan output baru:

~~~sh
bash scripts/test-native-trip-jakarta-live.sh /tmp/c67-jakarta-live-new
python3 scripts/audit-native-trip-jakarta-live.py /tmp/c67-jakarta-live-new
~~~

Ini memanggil MapKit automobile ETA/search dan Open-Meteo sungguhan melalui source produksi di executable macOS. Lima pin publik berasal dari kasus log; tanggal besok08.00–18.00 WIB. Hasil provider dapat berubah. Tidak memakai API key model/cloud atau backend tim.

Probe menghasilkan initial-report,replan-report,end-only-report,snapshot restore/selesai,search results,trace provider,summary dan manifest hash. Kunjungan aktual dalam skenario adalah fakta uji yang diskenariokan untuk tanggal tersebut, bukan kehadiran pengguna/GPS. Binary dan module cache sementara dibersihkan. Auditor Python memeriksa aritmetika/ID/deadline/prefix/counter tanpa memanggil validator Swift.

Tidak menggantikan tes iPhone atau walkthrough UI. [Hasil dan batas bukti](../../docs/verification/JAKARTA_ROUTING_FIX_2026-11-04.md).
