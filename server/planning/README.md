# Planning API and worker

Node 22.18+ (Node 24 used for this batch), erasable TypeScript and no production npm dependencies. This is a separate service from Supabase and the media worker. See [ADR-0009](../../docs/decisions/0009-personal-planning-implementation.md), [semantics/bounds](../../docs/ai-trip-planning.md), [contract](../../contracts/README.md) and [implementation evidence](../../docs/tasks/ai-trip-planning-implementation.md).

## Synthetic local server

From this directory:

```sh
npm ci --ignore-scripts
npm run check
npm run format:check
npm test
PLANNING_DATA_MODE=mock npm start
```

Mock binds only to `127.0.0.1:8788`, uses in-memory jobs/trips and accepts a synthetic UUID as its bearer identity. It never calls real providers. This mock token policy is for local development only. The native app's default mock uses its own Swift in-memory repository and does not need this HTTP server.

`GET /health` reports service mode without credentials. The Planning paths are `POST /v1/planning/jobs`, `GET /v1/planning/jobs/{id}`, `GET /v1/planning/trips`, `POST /v1/planning/proposals/{id}/apply` and `POST /v1/planning/trips/{id}/events`. All require a bearer token. A request returns a job immediately; poll until succeeded/failed. The in-process worker claims one job at a time; durable leases allow another service instance to recover abandoned jobs. No model/provider request runs in an HTTP request transaction.

## Live configuration

1. Review the additive migration `../supabase/migrations/20261029235123_add_personal_ai_planning.sql` against the target's current migrations. Test the complete stack/matching PostgreSQL image and prepare backup/recovery before a separately scoped shared deployment. This implementation has not deployed it.
2. Copy `.env.example` to a private ignored file, restrict its permissions, and fill server-only values. Node can load it with `node --env-file=.env.local --experimental-strip-types src/main.ts`; `npm start` does not implicitly read a dotenv file.
3. Set `PLANNING_DATA_MODE=live`, Supabase HTTPS origin/client key/service-role key, Apple team/Maps key/Weather key and Weather service ID, and an explicitly chosen model plus API key. The model endpoint defaults to OpenRouter's OpenAI-compatible chat-completions endpoint. OpenRouter requests require supported JSON output and disallow data-collection providers. Different compatible endpoints need their own capability/data-policy validation.
4. Use a private listener/reverse proxy with HTTPS for shared access. The prepared [Compose example](../deploy/planning-api.compose.yml) binds only host loopback and reads a private env path; no gateway, DNS or shared service is changed automatically. Its container build/runtime has not been run in this batch.
5. In the native app's ignored local configuration, set live Supabase client configuration and `PLANNING_SCHEME=https` / `PLANNING_HOST=<API host>`. For same-Mac Simulator development only, loopback HTTP is accepted. Physical-device networking is separate. The app sends traveller JWTs, never server/model/Apple keys.

Live HTTP forwards each traveller JWT to Supabase owner RPCs, which verify the session and derive ownership. Worker RPCs use only the private service key and current lease. Live mode never accepts synthetic UUID tokens or substitutes fake routes/weather/model output. Logs contain fixed operation names, mode/port and generic failure events; they do not include commands, locations, model content or credentials.

## Source and model boundary

Apple Maps ETAs/search and WeatherKit REST are adapters, not a raw traffic feed or guaranteed venue/weather coverage. The website tool reads only an explicitly supplied public HTTPS site, with DNS/IP and redirect checks, an 8-second connection/inactivity timeout, an overall job signal, 128 KiB response limit and a 6,000-character text extract. It does not execute JavaScript or log into sites. Missing evidence remains explicit. Real source freshness, opening hours, model support and data-sharing/attribution terms require acceptance before distribution.

The model proposes up to three complete orders and chooses/explains only evaluated candidates. The deterministic scheduler handles time arithmetic, directed travel, soft preferred windows and destination preservation. Its bounded shortlist is not a proof of global time-dependent optimality. Provider calls time out after 20 seconds; processing has a nine-minute budget and database leases expire within ten minutes. Queue admission is ten jobs/hour and at most two outstanding jobs per owner. Proposal application expires after 15 minutes unless already applied; receipts replay the original response.

No credentials were configured and no real model/Maps/Weather call was made for this task. Tests stub the live-adapter HTTP responses with generated signing keys.

## Verification scope

`npm run check` checks both source and test types. `npm test` covers scheduler/provider/HTTP/retry behavior and applies the new migration to disposable in-memory PostgreSQL via PGlite. The database checks simulate `auth.uid()` / `auth.role()` and role grants; they cover ownership, leases, changed-input retries, arithmetic rejection, single application, active extension/revision conflicts and preservation of completed visits. They need no Docker, shared data, Auth credentials or paid providers.

PGlite in the lockfile runs PostgreSQL 18.6; the shared homelab uses PostgreSQL 17. This narrow check does not replace the complete migration history, pgTAP suite, matching-image execution, actual PostgREST/GoTrue sessions or concurrent multi-connection acceptance. The existing database CI job remains responsible for its full disposable stack; a separate planning CI job runs the new checks. Adding CI configuration does not claim that GitHub Actions has run it.

Provider references: [Maps ETA endpoint](https://developer.apple.com/documentation/applemapsserverapi/-v1-etas), [Maps token exchange](https://developer.apple.com/documentation/applemapsserverapi/-v1-token), [Weather REST](https://developer.apple.com/documentation/weatherkitrestapi), [Weather attribution](https://developer.apple.com/documentation/weatherkitrestapi/attribution), [Weather display requirements](https://developer.apple.com/weatherkit/), [PGlite API](https://pglite.dev/docs/api).
