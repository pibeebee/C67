# Interactive itinerary map — Context Lab v0.5 (5)

9 November 2026, Asia/Jakarta. The current map follows the earlier Native Routing Lab interaction pattern.

Tap **Jelajahi peta rute** in the itinerary to open **Peta itinerary** inside the app. Each leg has a colour, numbered badge and a row containing its endpoints, planned times and map distance. Selecting a row or badge highlights the same leg and frames it. **Seluruh rute** restores the overview. Closing the map returns to the itinerary.

Geometry is requested once for each missing leg. Successful lines are retained during retries. The plan and the geometry use separate Apple requests. A missing line has an explicit state, with the confirmed place pins still available.

## Observed verification

One live UI test passed on the iPhone 18 Pro Max / iOS 27.2 Simulator. The test completed onboarding, actual place acquisition, Apple confirmation, WeatherKit and ETA planning for Pantai Indah Ancol from Mercure Convention Center Ancol. It opened the detail map, selected the return leg from the list, reset the overview, selected the outward leg by its numbered badge, closed the sheet, and verified that the app remained in the foreground.

The build succeeded before this UI run. This map change did not run a new route-comparison benchmark. More destinations, partial-route failure/retry, restored sessions and physical-device interactions remain to be verified for this version.

- [All legs](../artifacts/interactive-route-map-2026-11-09/screenshots/peta-semua-ruas.png)
- [Return leg selected](../artifacts/interactive-route-map-2026-11-09/screenshots/peta-sorot-ruas-pulang.png)
- [Outward leg selected using its badge](../artifacts/interactive-route-map-2026-11-09/screenshots/peta-sorot-dari-nomor.png)

The original result bundle is retained locally as `artifacts/interactive-route-map-2026-11-09/route-map-live-v1.xcresult`. A public export can include reviewed screenshots and this summary without publishing the opaque test bundle.
