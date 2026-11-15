# Full-page trip creation

- Outcome: show the creation flow as a full-screen page with its own navigation stack, while preserving the My Places sheet, draft recovery and Pocket settings. Home is restored when the flow is dismissed; saved trips open after saving.
- Scope: Home routing and creation presentation; no change to preference, planning, provider or storage rules. Reduce Motion disables the page transition.
- Verification: iPhone 18 Pro Max / iOS 27.2, mock and synthetic Pocket fixture: selected quick pick UI test passed; focused tests for itinerary generation/reorder/save, review back/cancel, and selected-places sheet passed. The full-page preferences screen was visually inspected. Live Luna, recovery after a real interrupted request, and a physical iPhone were not tested.
