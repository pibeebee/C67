# ADR-0008 — AI-generated personal trip recommendations

Status: Accepted product direction. The 30 October implementation is recorded separately in [ADR-0009](0009-personal-planning-implementation.md); the scope statements below describe the original documentation decision.
Date: 29 October 2026.

## Context

The user reported mentor feedback that the concept depended too heavily on other people's recommendations. The user clarified that the underlying trip experience remains similar while the recommendation/planning engine changes. Recommendations are now AI-generated rather than dependent on creator-authored rundowns.

## Confirmed decisions

- The traveller brings initial places and preferences and sets a date, departure time and finish-by time.
- AI may suggest optional additional places; the traveller chooses which to include.
- Recommendations include visit order and timing based on route, weather and place context.
- Recommendations can be recalculated during the trip, including a longer stay at one stop.
- Destination replacement/omission remains the traveller's decision.
- MapKit, Core Location and WeatherKit are the selected framework focus.
- Models are accessed through backend APIs, not self-hosted; a backend browser is intended to research place context.

## Consequences and open decisions

Creator-catalog assumptions no longer define the target recommendation engine. Existing source/version IDs, migrations, RPCs, fixtures and data still describe the implemented baseline and retain their meanings.

[ADR-0005](0005-backend-mvp.md) remains the record of the implemented planned-only edit/media slice. Supporting active-trip replanning needs new contracts and compatibility work; this ADR does not remove guards or claim a migration. Prior source manifests and verification records are preserved.

Provider/model/version, runtime/browser tools, personalization fields, visit durations, return endpoint, scoring priorities, data capabilities/terms, recalculation cadence, review/apply/undo, budget and retention remain open. Photo/album/completion and other prior features have not been re-scoped.

The implementation split between model recommendation and numerical/contract validation is an engineering proposal, not a finalized algorithm. No globally optimal ordering or hallucination-free output is promised.

## Scope of this change

This ADR authorizes no runtime transition by itself. The current work updates documentation only. No application code, API schema, fixtures, migrations, provider configuration, service or deployment is changed.

Follow-up: [ADR-0009](0009-personal-planning-implementation.md) records the subsequent authorized implementation and its evidence boundaries.

See [product context](../../product/product-context.md), [target design](../ai-trip-planning.md), [architecture](../architecture.md) and [roadmap](../server-roadmap.md).
