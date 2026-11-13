# ADR 0010: Connect the native UI to Pocket Engine

Status: Accepted — user requested pulling origin and connecting the existing UI on 12 November 2026.

## Context

The Hi-Fi UI uses C67Domain planning interfaces. Its earlier live adapter calls the Node Planning API. The separate Pocket Engine Lab implements the Apple-first replacement: local matching/validation, an independent catalog, Apple routing/weather and constrained Luna advice. Integration must not silently invoke the earlier planner or treat missing evidence as known.

## Decision

Extract the Foundation-only core into `packages/PocketEngine`, preserving provenance/tests. C67Domain stays independent of provider SDKs; C67Data implements `PocketPlanningRepository` and platform/transport adapters. Views/Presenters retain their planning interfaces with structured preference and connection capabilities. Default Debug/Release mode is `pocket`; explicit `mock` and legacy `live` remain available.

Seven themes map to the existing 62 labels. Structured values drive matching; prose budget/popularity wishes remain unverified wishes. Recommendations require at least three eligible matches and representation of every chosen interest. Missing coverage asks users to change area/preferences instead of silently dropping an interest.

The solver checks sourced availability or personal confirmation for the trip date, full durations, waiting, timing, deadline, last stop and optional return leg. Reordering preserves order. After consent, Luna selects from immutable local options and its choice is revalidated. Invalid IDs/models and transport errors never fall back to an invented itinerary. Explicitly disabling Luna selects the local planner.

Trips/receipts are written atomically to protected local storage. Pocket does not claim account sync or Supabase persistence. Provider/write keys stay on the server and the read token stays in Keychain. Release connections require HTTPS; redirects are refused. No shared deployment or TestFlight upload is part of this change.

## Consequences

Default UI planning no longer depends on the Node Planning API. Pocket read/advice endpoints use separate server/auth scope in the authoritative OpenAPI document. Legacy HTTP rejects Pocket-only options rather than stripping them. Bundled identities do not establish current opening/access facts. Real server connectivity, coverage, WeatherKit provisioning, oldest supported runtime and physical-device/release acceptance remain separate verification layers.
