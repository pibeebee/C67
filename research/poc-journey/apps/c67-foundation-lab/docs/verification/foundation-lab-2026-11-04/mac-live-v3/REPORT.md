# C67 Foundation Lab run 1AEC38A6-01EC-4980-9B2B-6A9D37E1CA8B
Date: 2026-11-04T09:37:43Z. Prompt: foundation-lab-v3.
Runtime: SystemLanguageModel.default (on-device), Version 27.0.1 (Build 26A434), available.
English supported: true. Indonesian supported: false.
Context: synthetic-jakarta-v1, revision 1, source Synthetic experiment fixture; all venue names, hours, travel and experience windows are illustrative.
Synthetic context: true. Search: MapKit live search; no route feasibility calculated.

| Capability | Display source | Status | Seconds |
| --- | --- | --- | ---: |
| preferences | Foundation Models | validated_shape_and_references | 1.551 |
| candidates | deterministic | rejected_or_error | 5.876 |
| windows | Foundation Models | validated_shape_and_references | 3.626 |
| explanation | Foundation Models | validated_shape_and_references | 2.729 |

The baseline schedule shows a sequence: O → A → B → C → O, with the museum opening at 09:00 and a finish at 12:15 against a 18:00 deadline (baseline ID). All venue details, hours, and travel windows are illustrative (baseline ID). The garden afternoon preference remains unfulfilled in the current setup.

## Deterministic comparison
Memenuhi batas yang diketahui pada snapshot. Example Museum (fictional) → Example Reading Cafe (fictional) → Example Garden (fictional). Selesai: 12:15. Deadline: 18:00. Sumber: Synthetic experiment fixture; all venue names, hours, travel and experience windows are illustrative. Informasi harga, suasana dan jam yang tidak diberikan tetap belum diketahui.

Input submissions: 0; corrections: 0; questions: 0.
Total processing: 14.700 seconds.
New schedule validated: false. All additions and time windows remain unvalidated suggestions.
Counts describe this UI session or runner input, not a user study. Semantic model quality requires human review.