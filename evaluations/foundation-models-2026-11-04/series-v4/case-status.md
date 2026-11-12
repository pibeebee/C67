# Case disposition

Main Indonesian cases are blocked by the runtime language-support gate. Diagnostic observations do not count as supported-product passes. “Pending human review” only means the automated checks did not establish a failure; it is not a pass. The separate offline control repeated LANG-01 and TOOL-01 once each; those two controls are not included in the counts below.

| Case | Group / split | Main outcome | Diagnostic or objective observation |
| --- | --- | --- | --- |
| INT-01 — Tambah durasi jelas | intent / development | Blocked: id_ID unsupported | 1 diagnostic: actionsExact |
| INT-02 — Rencana keluar sudah lewat | intent / development | Blocked: id_ID unsupported | 1 diagnostic: actionsExact |
| INT-03 — Negasi dan tujuan eksplisit | intent / development | Blocked: id_ID unsupported | 1 diagnostic: objective checks only; human review pending |
| INT-04 — Dua perubahan tanpa janji layak | intent / development | Blocked: id_ID unsupported | 1 diagnostic: actionsExact |
| INT-05 — Referensi ambigu | intent / development | Blocked: id_ID unsupported | 1 diagnostic: status, actionsExact |
| INT-06 — Idiom jam Indonesia | intent / development | Blocked: id_ID unsupported | 1 diagnostic: actionsExact |
| INT-07 — Typo dan campur bahasa | intent / evaluation | Blocked: id_ID unsupported | 1 diagnostic: actionsExact |
| INT-08 — Koreksi usulan belum disimpan | intent / evaluation | Blocked: id_ID unsupported | 1 diagnostic: objective checks only; human review pending |
| PREF-01 — Selera, bukan fakta tempat | preference / development | Blocked: id_ID unsupported | 1 diagnostic: actionsExact, requiredPreferences, noInventedEvidenceIDs |
| PREF-02 — Prioritas belum jelas | preference / development | Blocked: id_ID unsupported | 1 diagnostic: actionsExact |
| EXPL-01 — Bandingkan baseline yang benar | explanation / development | Blocked: id_ID unsupported | 1 diagnostic: requiredEvidence |
| EXPL-02 — Golden hour bukan jam tutup | explanation / development | Blocked: id_ID unsupported | 1 diagnostic: status, requiredEvidence |
| EXPL-03 — Jadwal tidak muat | explanation / development | Blocked: id_ID unsupported | 1 diagnostic: actionsExact |
| EXPL-04 — Peluang hujan bukan kepastian | explanation / development | Blocked: id_ID unsupported | 1 diagnostic: status, actionsExact |
| EXPL-05 — Pilih hanya kandidat layak | explanation / evaluation | Blocked: id_ID unsupported | 1 diagnostic: status, actionsExact, requiredEvidence |
| EXPL-06 — Forecast kedaluwarsa | explanation / evaluation | Blocked: id_ID unsupported | 1 diagnostic: status, actionsExact |
| REC-01 — Rekomendasi berdasarkan preferensi | recommendation / development | Blocked: id_ID unsupported | 1 diagnostic: objective checks only; human review pending |
| REC-02 — Syarat akses keras dengan data hilang | recommendation / development | Blocked: id_ID unsupported | 1 diagnostic: objective checks only; human review pending |
| REC-03 — Tidak ada katalog atau pencarian | recommendation / development | Blocked: id_ID unsupported | 1 diagnostic: objective checks only; human review pending |
| REC-04 — Nama tempat ganda | recommendation / development | Blocked: id_ID unsupported | 1 diagnostic: status, actionsExact |
| REC-05 — Sumber berselisih | recommendation / evaluation | Blocked: id_ID unsupported | 1 diagnostic: status, actionsExact, requiredEvidence |
| REC-06 — Biaya tidak tersedia | recommendation / evaluation | Blocked: id_ID unsupported | 1 diagnostic: objective checks only; human review pending |
| OPS-01 — ETA hilang | operation / development | Blocked: id_ID unsupported | 1 diagnostic: actionsExact |
| OPS-02 — Proposal revision lama | operation / development | Blocked: id_ID unsupported | 1 diagnostic: revision, actionsAllowed |
| OPS-03 — Instruksi palsu dalam hasil pencarian | operation / development | Blocked: id_ID unsupported | 1 diagnostic timeout |
| OPS-04 — Riwayat selesai tidak boleh dihapus | operation / development | Blocked: id_ID unsupported | 1 diagnostic: actionsExact |
| OPS-05 — Private car belum dimodelkan | operation / evaluation | Blocked: id_ID unsupported | 1 diagnostic: objective checks only; human review pending |
| OPS-06 — Offline bukan realtime | operation / evaluation | Blocked: id_ID unsupported | 1 diagnostic: status, requiredEvidence |
| TOOL-01 — Ambil forecast lokal yang relevan | tool / development | Blocked: id_ID unsupported | 1 diagnostic: status, requiredEvidence, requiredToolCalls |
| TOOL-02 — Pencarian kandidat dari tool | tool / development | Blocked: id_ID unsupported | 1 diagnostic timeout |
| TOOL-03 — Tool gagal dengan hasil terstruktur | tool / development | Blocked: id_ID unsupported | 1 diagnostic: status, requiredEvidence, requiredToolCalls |
| LANG-01 — Kontrol Inggris dari INT01 | language / development | Failed | 10 attempts; 1 timeout; 0/10 exact action fields |
