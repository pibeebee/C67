# Johan — illustrative Jakarta itinerary

**Mode:** fixture · **Date:** 2026-11-03 · **Time zone:** WIB

**Evidence status:** Fixture only; AI was NOT executed. Not evidence of AI quality.

**AI called:** NO — deterministic simulation

**Visited:** B, D · **Departure now:** 17:20 · **Finish by:** 19:00

**Recommended:** C · **Feasible:** yes, against supplied constraints

SIMULATION ONLY — selected by the transparent scoring function; OpenRouter was not called.

| Stop | Arrival | Visit | Leave | Travel (min) | Wait (min) | Rain probability during visit |
|---|---|---|---|---:|---:|---|
| C — outdoor stop (example coordinate) | 17:30 | 17:30 | 18:15 | 10.0 | 0.0 | 10.0% (forecast) |

## Comparison

| Plan | Order | Feasible | Travel (min) | Wait (min) | Rain exposure proxy (min) | Missed preferred overlap (min) | Finish | Score |
|---|---|---|---:|---:|---:|---:|---|---:|
| AI / selected | C | true | 10.0 | 0.0 | 4.5 | 0.0 | 18:15 | 19.0 |
| Original order | C | true | 10.0 | 0.0 | 4.5 | 0.0 | 18:15 | 19.0 |
| Travel-only baseline | C | true | 10.0 | 0.0 | 4.5 | 0.0 | 18:15 | 19.0 |

## Rationale

- **C:** Synthetic route, timing and weather were evaluated by code. This is not an AI explanation. Sources: `input:C`, `fixture-route:D/C@1793701200`, `weather:C`.

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

- 2 initial candidates; 1 refined candidates. Global optimality: not established.
- HTTP calls: {}. Elapsed: 5 ms.
- AI usage (as returned by provider): null.
- Inspect report.json for all alternatives, constraints, normalized input and evidence. Evidence IDs validate references, not the truth of every sentence.
