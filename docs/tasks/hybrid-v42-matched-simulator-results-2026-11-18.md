# Hybrid v4.2 matched Simulator comparison — 18 November 2026

The controlled comparison ran on iPhone 18 Pro Max Simulator, iOS 27.2, with two scenarios and two repetitions each. The Swift Testing test failed with four issues: Luna produced four structurally accepted proposals; Foundation Models produced none. There are no complete successful pairs, so this run cannot establish a paired speed or itinerary-quality comparison.

Both arms received matching English prompts and scenario context, shared validation and the same v4.2 planner, synthetic directed ETA matrix, unavailable opening hours, no weather or light context, and one generation attempt. Provider token caps and execution environments differ. The Foundation arm uses plain JSON generation for comparability, not the production guided-generation adapter. Timings cover the test planner, not the complete app, real MapKit travel, or end-user wait.

| Scenario | Repetition | Luna provider (s) | Luna planner (s) | Foundation provider (s) | Foundation outcome |
| --- | ---: | ---: | ---: | ---: | --- |
| Manual day | 1 | 12.982 | 13.005 | 1.723 | Provider error: Simulator safety inference not supported |
| Manual day | 2 | 19.072 | 19.080 | 7.263 | Invalid JSON and response contract |
| Two candidate days | 1 | 16.650 | 16.933 | 3.969 | Invalid JSON and response contract |
| Two candidate days | 2 | 20.142 | 20.147 | 4.059 | Invalid JSON and response contract |

Foundation's failed call timings do not measure time to a valid itinerary. The malformed responses included extra closing characters; the two-day responses also had unquoted values and did not follow the requested day-bound schema. The failure at the simulator safety inference layer does not establish how an iPhone behaves. Likewise, a successful `isAvailable` check did not guarantee a successful request in this simulator session.

For both one-day Luna runs, the selected order was Museum Nasional Indonesia, M Bloc Space, then Taman Literasi, with the first visit fixed at 45 minutes. For both two-day runs, the planner selected Thursday 14 January and that same order. The generated Thursday park estimate was shorter than Wednesday's, reflecting the fixture's day-specific preference. This is a limited qualitative inspection, not a factual verification of venues, opening hours or actual travel feasibility.

Artifacts: `/tmp/c67-v42-matched-20261118-1908.xcresult` and `/tmp/c67-v42-matched-20261118-1908.log`. These temporary files may be removed by the system. The initial launch failed before model calls because Xcode did not match the lowercased simulator UUID; the launcher was corrected to preserve Xcode's uppercase UUID convention before this recorded run.
