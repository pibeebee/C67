# Task: Connect reasonable Luna ordering to the existing native UI

Date: 2026-11-15. Status: Implemented locally; successful live acceptance pending (upstream HTTP 524). Owner: Codex. Reviewer: Giovan.
Branch: existing `gi/pocket-ui`; preserve unrelated work.

## Authorized outcome and scope

Connect selected places/preferences to live Luna ordering and the existing
itinerary review/save/My Trips screens. Keep the visual structure; later Hi-Fi
adjustments are a separate request. No catalog, geographic allowlist, stop-count
cutoff, operational-hour prerequisite or ETA dependency for the new proposal.
Unknown venue facts remain unknown. Open-Meteo is the authorized current weather
fallback; unavailable weather must not prevent ordering. Solar windows are code
calculations. No Google API, provider secret in the app, deployment, commit/push
or unrelated Discovery/preference-ranking redesign.

## Implementation and acceptance

- Add authenticated asynchronous order jobs, immutable request identity and
  persisted results. Repeated reads/reconnection must not regenerate a completed
  answer. Failed generation is visible and retry is explicit.
- Validate exact selected IDs, nullable estimates, model identity/completion and
  source references. Use optional schedule timestamps for untimed proposals.
- Carry activities/duration ranges/dayparts/weather/light into existing cards;
  do not display invented arrival/departure/ETA values. Save the proposal locally.
- Keep established timed trips and their legacy planning path compatible.
- Use replay/stub checks for failures and at most one initial live five-place
  end-to-end acceptance request, with no blind provider experiment loop.
- Run Python/source/contract tests, Swift package tests, Simulator compilation
  and targeted native UI verification. Record each actual layer and any gap.

## Evidence

Local implementation and checks are recorded in [the integration evidence](../evidence/pocket-order-integration-2026-11-15/README.md).
Python: 39 tests passed; Swift backend: 63 passed; Simulator: 44 app unit and
3 synthetic UI cases passed. API contracts, pinned formatting and whitespace passed.
The one actual five-place request obtained real weather/light context but Luna
returned HTTP 524 after about 125 seconds; all selections remained visible and
no substitute answer or automatic model retry was used. Successful actual
provider → native review → save remains pending. No shared deployment occurred.

Research and bounded capability evidence:
[contextual outputs](../evidence/pocket-contextual-order-2026-11-14/README.md),
[real weather fallback](../evidence/pocket-open-meteo-2026-11-15/README.md).
