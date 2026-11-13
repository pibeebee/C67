# Johan — illustrative Jakarta itinerary

**Mode:** fixture · **Date:** 2026-11-03 · **Time zone:** WIB

**Evidence status:** Fixture only; AI was NOT executed. Not evidence of AI quality.

**AI called:** NO — deterministic simulation

**Visited:** none · **Departure now:** 14:00 · **Finish by:** 19:00

**Recommended:** B → D → C · **Feasible:** yes, against supplied constraints

SIMULATION ONLY — selected by the transparent scoring function; OpenRouter was not called.

| Stop | Arrival | Visit | Leave | Travel (min) | Wait (min) | Rain probability during visit |
|---|---|---|---|---:|---:|---|
| B — coffee stop (example coordinate) | 14:20 | 14:20 | 15:20 | 20.0 | 0.0 | 10.0% (forecast) |
| D — reading stop (example coordinate) | 16:05 | 16:05 | 16:50 | 45.0 | 0.0 | 10.0% (forecast) |
| C — outdoor stop (example coordinate) | 17:00 | 17:00 | 17:45 | 10.0 | 0.0 | 10.0% (forecast) |

## Comparison

| Plan | Order | Feasible | Travel (min) | Wait (min) | Rain exposure proxy (min) | Missed preferred overlap (min) | Finish | Score |
|---|---|---|---:|---:|---:|---:|---|---:|
| AI / selected | B → D → C | true | 75.0 | 0.0 | 4.5 | 0.0 | 17:45 | 84.0 |
| Original order | B → C → D | true | 60.0 | 0.0 | 12.5 | 30.0 | 17:30 | 175.0 |
| Travel-only baseline | D → C → B | true | 48.0 | 0.0 | 40.5 | 30.0 | 17:18 | 219.0 |

## Rationale

- **B:** Synthetic route, timing and weather were evaluated by code. This is not an AI explanation. Sources: `input:B`, `fixture-route:A/B@1793689200`, `weather:B`.
- **D:** Synthetic route, timing and weather were evaluated by code. This is not an AI explanation. Sources: `input:D`, `fixture-route:B/D@1793694000`, `weather:D`.
- **C:** Synthetic route, timing and weather were evaluated by code. This is not an AI explanation. Sources: `input:C`, `fixture-route:D/C@1793699400`, `weather:C`.

## Tradeoffs and uncertainties

- This fixture run checks plumbing and arithmetic, not AI quality or real travel feasibility.
- All provider data in this mode is synthetic.

## Warnings and constraints

- Routing, forecast and sunset are synthetic fixtures.
- OpenRouter was not called. This run is only a local pipeline demonstration.
- Place context, exposure and opening hours are user-supplied assumptions; no web research was performed.
- Finish time means the end of the final visit. No journey home is included.
- Before-sunset preference does not establish golden hour, cloud visibility or venue suitability.
- Rain exposure is a scoring proxy, not a forecast of how many minutes it will rain. Waiting and journey weather are not scored.
- Weights, shortlist quality and AI reasoning need evaluation. No global optimality or user benefit is established.

## Experiment diagnostics

- 12 initial candidates; 5 refined candidates. Global optimality: not established.
- HTTP calls: {}. Elapsed: 6 ms.
- AI usage (as returned by provider): null.
- Inspect report.json for all alternatives, constraints, normalized input and evidence. Evidence IDs validate references, not the truth of every sentence.
