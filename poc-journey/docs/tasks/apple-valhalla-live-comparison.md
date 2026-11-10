# Task: Compare Apple and Valhalla on matched live routes

Status: Complete for the matched live benchmark; field accuracy and full app integration remain out of scope
Owner: Hendra Irawan
Reviewers: Pending human assignment
Branch: codex/routing-access-benchmark

## Outcome and scope

Compare native Apple Maps and the existing pinned local Valhalla graph on identical sourced Jakarta origin/destination coordinates, transport mode and departure time. Retain the existing uncommitted routing POC and its evidence. Apple REST keys are absent; actual native MapKit server calls are labelled separately from REST. Google paid calls remain excluded.

## Acceptance

- [x] Probe actual Apple automobile/walking availability before the campaign.
- [x] Rotate provider order, repeat forward/reverse pairs three times and checkpoint failures as well as successes.
- [x] Separate deliberate request pacing from measured API/decoding latency.
- [x] Compare route availability, response time, estimated travel/distance ratios, endpoint snapping and sampled geometry disagreement without inventing ground truth.
- [x] Evaluate controlled 1/3/6-stop itinerary calculations and shared-TJ walking adapters where the request budget permits; distinguish controlled visit rules from live venue facts.
- [x] Test cancellation, no-callback timeout, stale callbacks, matched-input identity and output validation.
- [x] Write a fresh English report with a recommendation conditional on use case and field/provider limitations.

## Boundaries and verification

No Google live, field trip, production integration, default-provider change, commit/push/PR or deployment. No route geometry, raw Apple content or per-leg provider ETA is archived. Derived comparative metrics and timing/status metadata are exported. Live ETA differences cannot prove observed accuracy. Native MapKit can use Apple's managed caches; local Valhalla has static speeds and no traffic feed. Timing does not imply equivalent infrastructure or route quality.

Use a fresh directory under `.verification/apple-valhalla-20261110/`. Run targeted fixture tests, Context package regression, Python audit tests, formatter, evidence/portability and whitespace checks. Preserve the previous benchmark report as a dated checkpoint.

## Completion evidence

See the [live results report](../../apps/c67-local-server-lab/docs/APPLE_VALHALLA_LIVE_RESULTS_2026-11-10.md). New ignored evidence is in `.verification/apple-valhalla-20261110/`.

- 192 matched road pairs completed: Valhalla 192/192 validated; native Apple 190/192. Zero main-campaign audit errors.
- Six controlled 1/3/6-stop calculations succeeded on both providers. These are fixed-order live-route accumulations with authored dwell/arithmetic budgets, not full Context planner/editor or live venue-context acceptance.
- Four shared-TJ cases succeeded on both walking adapters: direct, reverse, one transfer 6A → 1 and non-BRT JAK.35. Feed scheduling is static, walking is live; station entrances remain unverified.
- Context final regression: 152 XCTest cases executed, 151 passed and one intentionally skipped; 35 Swift Testing cases passed. The seven new matched/native tests passed separately as well.
- Trip Integration: 81 Swift Testing cases passed. Python: 66 tests passed, including four new matched-auditor tests.
- Formatter: 0/392 Swift files require formatting. Evidence: 3,415 imported copies / 26 maintained entries pass. Portability/link/private-pattern scan: 3,581 publication files pass. Whitespace checks pass.
- No native UI changes; app builds/Simulator acceptance were not repeated for this CLI-only extension. Previous build results are historical, not new acceptance.
- Valhalla container and dedicated Colima profile stopped after the campaign; Docker context restored to `default`.
- Original checkout was not edited. Existing routing POC work remains uncommitted in the feature worktree; no default-provider change, Google request, commit/push/PR or deployment occurred.

Measured service speed favours local Valhalla; observed ETA accuracy and public-door connectivity remain unmeasured. The two transient Apple invalid-response rejections lack enough archived rejection detail for exact root-cause attribution.
