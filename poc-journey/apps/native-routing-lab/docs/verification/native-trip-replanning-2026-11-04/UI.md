# Observasi Simulator P2

4 November 2026 WIB, iPhone 18 Pro iOS 27.0, bundle `giovanchristoffel.poc-c67`. Sesi memakai `--active-ui-testing`; snapshot biasa tidak direset. Seluruh lokasi/ETA/jam contoh ini sintetis.

Urutan diamati lewat XcodeBuildMCP:

1. Muat simulasi trip aktif dari menu, simpan itinerary, buka layar trip, mulai 08.00.
2. Jam +10, tiba/mulai A 08.10. Jam +30, selesai A 08.40. Jam +10, tiba/mulai B 08.50. Jam +10 →09.00.
3. Tambah30; dialog menyebut09.50. Simpan, konfirmasi anchor B, hitung ulang. Review menunjukkan awal11.00, baseline baru/proposal11.30, C→D, travel40, dwell60, total sisa150 menit.
4. Terapkan. Hentikan app, launch ulang, lanjutkan trip aktif: B keluar09.50 dan estimasi11.30 bertahan.
5. Scroll riwayat: A08.10–08.40 dan B08.50 tetap. Konfirmasi skip C dan skip D satu per satu; keduanya berlabel Dilewati pengguna.
6. Hitung ulang dengan anchor B: hanya endpoint, selesai10.50; ruas B→O60 menit sesuai fixture. Abaikan usulan; rencana terakhir11.30 tetap, perlu dihitung ulang.
7. Build/relaunch source hasil review. Riwayat skip dan durasi B pulih. Jam +30,+10,+10 →09.50, selesai B. Jam +30,+30 →10.50, konfirmasi sudah tiba endpoint.
8. Build/relaunch terakhir sesudah koreksi teks status selesai. Buka trip: pesan perjalanan selesai, tiba aktual10.50, A/B completed, C/D skipped. Source akhir berhasil dibangun.

`tool-observations.json` menyimpan capture milestone yang sempat dikumpulkan, bukan rekaman video setiap tap. Screenshot proposal/end-only dibuat sebelum perbaikan teks status selesai; screenshot finished-restored memakai build akhir. Snapshot schema2 `ui-final-session.json` berasal dari folder uji sintetis setelah selesai.

Kasus save failure/stale request/proposal pending saat restart mempunyai bukti harness; tidak semuanya diulang lewat UI. Tidak ada iPhone fisik, provider live, GPS, VoiceOver, atau stress rapid tap pada sesi ini.
