# Trip processing Hi-Fi

- Outcome: show the supplied loading and completion designs during itinerary creation, while retaining the existing continue-later action.
- Scope: iOS trip creation and processing presentation; no provider or routing changes.
- Completion is shown for 1.5 seconds only after a successful result; cancellation and session changes prevent navigation during that interval.
- Verification: Debug mock-mode build and launch succeeded on iPhone 18 Pro Max / iOS 27.2. A synthetic three-place creation reached itinerary review. Both visual states were inspected separately using a temporary debug preview; this does not verify a live Luna request or the continue-later recovery path. The final loading line break was adjusted after that visual inspection.
- Pinned SwiftFormat could not be downloaded because network DNS was unavailable; run `python3 scripts/swift_format.py --check` when available.
