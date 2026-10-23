# ADR-0002 — Supabase backend foundation

**Status:** accepted for starter development, 23 October 2026. Replaces the earlier provider-undecided proposal after the user's approval of the Supabase starter.

Use the existing self-hosted Supabase as the backend foundation. Author schema/SQL RPC migrations in this repository through the pinned Supabase CLI. The homelab is the shared development environment; mutation/reset tests run in an isolated homelab container/database. Mac-local Supabase is optional, while CI uses a disposable local stack. The first slice uses PostgreSQL transactions, RLS and Data API RPCs; no custom Node HTTP server is introduced. Node/npm here manages the CLI only.

Use `server/supabase/migrations/` as the single migration history. The initial starter stores ordered stops as JSON snapshots; the complete proposed relational/PostGIS design is not implemented. Edge Functions and media workers are reserved for later orchestration and processing needs.

Local development permits reads of published synthetic catalog entries. Trips are owner-scoped and creation is a verified-session command. This development access policy does not finalize production catalog access, creator publishing or media distribution.

The homelab installation and its SMTP/Studio configuration remain external operational state. The reviewed starter migration was applied and verified on 23 October; see [execution evidence](../homelab-verification.md). No automatic deployment or shared reset is configured. Before each later deployment, verify PostgreSQL/runtime compatibility, review migrations against existing data and approve the concrete operational scope. See [Server guide](../../server/README.md).
