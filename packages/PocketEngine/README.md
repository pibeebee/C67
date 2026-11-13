# Pocket Engine core

Maintained extraction of the pure-Foundation recommender, taxonomy, area polygons, bounded itinerary solver and schedule-advice envelope from the separate C67 Pocket Engine Lab. `UPSTREAM.json` records original snapshot checksums, not a claim that maintained files remain byte-identical.

There is no SwiftUI app, Foundation Models dependency, credential, HTTP server, Google API integration or old 982-place dataset here. The Foundation-only core targets iOS 18/macOS 14; this does not lower the standalone PoC app's iOS 26 requirement. C67Data injects platform and server services.

Integration changes: Swift formatting; expose the 13 existing feature labels alongside 49 venue/subtype labels (62 selectable labels plus four compatibility aliases in `Interests.all`); preserve requested manual order and an optional first stop; revalidate both after model selection. Original test scenarios are retained, with the taxonomy count expanded for the existing features.

Run `swift test --package-path packages/PocketEngine`. Adapter tests are in `packages/C67Backend/Tests/Starter/PocketPlanningRepositoryTests.swift`. See [integration boundaries](../../docs/guides/pocket-engine-integration.md).
