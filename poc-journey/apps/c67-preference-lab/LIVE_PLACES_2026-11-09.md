# Real place discovery in C67 Preference Lab

Version 0.2 build 2. Tested on the iPhone 18 Pro Max Simulator with iOS 27.2 on 9 November 2026.

The main screen now searches live places using the user's interests and explicit activity choices. Choosing coffee and reading at one venue creates one combined search. Choosing separate venues creates two search groups. Each card shows which needs apply to that venue and which apply elsewhere or to the trip. Opening hours can be checked against an optional visit time and duration. The app retains selections during a search change or pagination.

Google Places supplies identity, categories and operating status. The app requests selected details such as coffee service, price level or dated opening sessions when relevant. Missing values stay unknown. A library category alone cannot establish permission to sit and read for a given duration. If a venue's evidence conflicts with a mandatory requirement, its card shows the conflict. For separate activities, the app evaluates each venue against its assigned activity. The sequence of venues remains a planning decision.

Each query preserves the provider order, and duplicate IDs are removed when results are combined or appended. Only selected place IDs are saved locally. Provider responses are held in memory while displayed, with Google Maps attribution and source links. The LLM advisor handles optional clarification. The discovery benchmark made zero model calls. [Text Search (New)](https://developers.google.com/maps/documentation/places/web-service/text-search) · [Place resource](https://developers.google.com/maps/documentation/places/web-service/reference/rest/v1/places)

| Live scenario in Jakarta Pusat | Results | Requests | HTTP time |
| --- | ---: | ---: | ---: |
| Read at the venue | 6 | 1 | 0.46 s |
| Buy books | 6 | 1 | 0.39 s |
| Coffee and reading at one venue | 6 | 7 | 1.26 s |
| Coffee and reading at separate venues | 12 | 8 | 1.07 s |
| Shopping only | 6 | 1 | 0.49 s |
| Coffee with a preference for lower spending | 6 | 7 | 0.72 s |
| Coffee at 11.00 WIB, 60 minutes | 6 | 7 | 0.90 s |
| Coffee at 03.00 WIB, 60 minutes | 6 | 7 | 0.88 s |

All eight cases passed the checks for explicit requirements, result uniqueness and response context. The median client HTTP time was 0.80 s, with one observation per case. Pagination returned six additional unique results for the book search in 0.45 s with one request. These measurements cover live discovery and its evidence checks from the Mac. They exclude taps, debounce and route computation.

On 10 November 2026, the provider's dated opening sessions supported the full 11.00 WIB visit for six candidates. At 03.00 WIB, four had conflicting hours and two were unknown. For coffee plus reading at the same venue, all six still had at least one unknown mandatory requirement. This was a provider and rules verification. Evaluation of place suitability with users requires independent judgments and evidence about the actual experience.

The [final observations](artifacts/live-places-final-2026-11-09/observations.json) contain only experiment inputs, aggregate outcomes and timing. The earlier [integration run](artifacts/live-places-2026-11-09/observations.json) used a smaller detail lookup budget and preceded the per-activity evidence change.

The eight final scenarios and one continuation used 40 Places requests. During the later Simulator pass the lab reached its cumulative 100-request limit for the UTC day. For the targeted retests the running local service used a temporary 140-request ceiling. The project default remains 100. The pagination test was corrected to bring the header back into the viewport after tapping the footer. For the expanded evidence panel, the accessibility hierarchy showed that SwiftUI assigned the disclosure identifier to its descendants, so the test now matches the visible status label.

Verification on the final build included 12 Swift core tests, 24 Python tests, and five successful Simulator scenarios across the final pass and targeted retests. The Simulator scenarios covered save/restore/undo, trip reset, skip, live pagination with a saved place, and the combined preference with expanded evidence. Local XCTest result bundles are in the ignored `artifacts/*.xcresult` files.
