# Product context

Updated 23 October 2026 from the workspace CBL record and explicit team decisions. The original source manifest remains a historical provenance record; it is not a claim that later starter code appeared in those source files.

## Core journey

A traveller discovers an area or browses a map, selects a creator's travel rundown, understands its stops and context, chooses a suitable start time, follows the trip, documents visits and obtains an album. Social export is optional.

Athar's design scenario goes from Agora Mall Thamrin to Kota Tua: discover, select, reach the landing point, visit stops, add photos and view an album. The landing point can differ from the first stop. The Tokyo A/B scenario adds another creator's rundown to an existing plan; overlap resolution and rescheduling remain open decisions.

## Constraints to preserve

- Creator rundowns are the primary product; photos/GPS support execution and journaling.
- Creator times are recommendations, not mandatory traveller start times.
- Published creator versions and independently editable personal trips are different objects.
- Best-case journaling includes photos per stop. Skip/partial completion and early ending remain unresolved.
- Camera/gallery/selfie/edited photos are possible inputs. Device location is not proof of image authenticity; arrival is not a permanent upload permission.
- Weather supports preparation and decisions; missing ETA, opening hours or forecasts must not be invented.
- Chat, booking, payments, gamification and tracking other people are not requirements of this starter.

## Technical decisions and evidence

The team agreed on one repo with iOS UI, on-device iOS Backend and Server areas, using VIPER as the iOS direction. Self-hosted Supabase is the backend foundation; the current repo supplies local development assets and does not deploy to that host.

The starter implements synthetic discovery/detail and memory-only mock trip creation, plus an authenticated RPC adapter and SQL development baseline. The full product specification, native journaling PoC and HTML wireframe remain separate artifacts. None establishes product adoption or field validation.

Guest/catalog access, creator distribution, merge, presence policy, photo audiences, moderation, retention, transit and detailed offline behavior still need decisions. Public synthetic catalog access in local development does not settle production access policy. App sign-in is a follow-up; Studio access is a developer concern.
