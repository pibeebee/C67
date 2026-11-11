# Itinerary stop reordering

Status: Locally implemented; live-service rollout and acceptance pending.

## Outcome and scope

The Balaraja Sketch Hi-Fi itinerary uses a three-line drag handle for changing visit order. In the editable review, drag a handle onto another stop; the proposal is recalculated and must be reviewed before saving. Visit-time editing remains available from the stop summary. Saved itinerary views stay read-only. VoiceOver users can use the handle's Move up and Move down actions.

Manual ordering is represented by the optional `preserve_place_order` planning input field. The mock repository and local planning service recalculate travel and visit times in the requested order; the input and returned proposal are checked before the client permits saving. The client rejects a service response that drops the flag or returns a different stop order, protecting users when an older service does not support this field. Original optimized planning remains the default. No shared service was deployed or database changed in this task.

## Local verification

- iPhone 18 Pro / iOS 27.0 Simulator, mock mode: the UI test dragged the first stop below the second, verified the new order, saved the recalculated itinerary, and verified the saved order. The standard-size screenshot was compared with the Sketch handle.
- C67 app test run including the drag UI test: 89 passed, 2 skipped; the unit suite includes cases rejecting services that ignore or strip the order request.
- Shared Swift package: 36 tests passed, including mock schedule arithmetic and backward-compatible wire encoding.
- Planning service: 22 tests passed, including ordered scheduling and updated route times; TypeScript and Prettier checks passed.
- OpenAPI and fixture checks, Swift formatting and generic Simulator build passed.

Live provider acceptance requires deploying the updated planning service and testing against the intended environment separately. This local result does not establish live-provider operation, iOS 18 runtime behavior, physical-device drag interaction, or manual VoiceOver acceptance.
