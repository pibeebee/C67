# ADR-0009 — Independent personal planning aggregate and bounded orchestration

Status: Accepted and implemented in the local repository; new shared deployment and real-provider acceptance pending.
Date: 30 October 2026.

## Context

Giovan authorized end-to-end C67 repository changes for the AI direction, delegated routine decisions and explicitly requested no iOS tests for this task. Existing creator/version creation and planned-only journal guards cannot safely represent arbitrary user-selected destinations and active remaining-trip recalculation.

## Decision

Add an independent personal-planning aggregate alongside the existing catalog/trip model. The MVP supports one day, one to six selected places, explicit origin/dwell/departure/finish-by/zone, walking or driving, optional suggestions, reviewed proposals and manually reported trip events. Finish-by excludes an implicit return-home leg. The user controls selected destinations; infeasible proposals cannot apply.

Keep SwiftUI/VIPER and Domain/Data separation. Use a separate Node/TypeScript Planning HTTP API plus durable PostgreSQL job worker. The worker calls an explicitly selected OpenAI-compatible hosted model, Apple Maps Server API, WeatherKit REST and a bounded public HTTPS text reader. There is no self-hosted model or browser on the phone.

The model proposes orders and chooses/explains an evaluated candidate. Application code enumerates bounded orders, refreshes shortlisted ETAs and checks time arithmetic, place preservation and feasibility. Missing evidence remains explicit. The model has no database-write tool. This does not guarantee factual correctness or globally optimal time-dependent routing.

Use additive SQL with session-derived ownership, explicit grants/RLS, private jobs/events/receipts, worker-only leases, expected revisions and atomic application. No external I/O occurs while holding trip locks. Replanning preserves completed visits and holds a manually confirmed current stop first; new proposals require review/apply. Existing creator, media and journal contracts retain their guards.

Persist one exact pending planning command per endpoint/account on device for safe resume; retain apply/event retry identities in memory. Auth tickets bind requests/results to the current login. This is not full offline synchronization. Source/provider credentials remain server-only.

## Consequences and limits

This isolates new semantics and preserves old API meanings, at the cost of two trip aggregates until a later migration/convergence decision. Personal trips do not automatically inherit journal/album behavior. Manual arrival does not certify presence. Automatic recalculation, undo, skip, destination edits within an existing trip, multi-day/transit and retention policy remain separate work.

Dependencies, local examples, CI configuration and setup are checked in; no paid model is selected, shared service deployed or real Apple/model call made. Embedded PostgreSQL tests use simulated claims on PostgreSQL 18, not matching-image PostgreSQL 17/PostgREST/GoTrue acceptance. The user's verification exclusion covers iOS tests; compilation alone is recorded as build evidence.

See [planning design](../ai-trip-planning.md), [backend setup](../../server/planning/README.md), [contract](../../contracts/README.md) and [task evidence](../tasks/ai-trip-planning-implementation.md).
