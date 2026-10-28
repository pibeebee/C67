# iOS Backend (on-device code)

This is a local Swift package, not a remote server. It exports two products:

| Target | Responsibility |
|---|---|
| `C67Domain` | Rundown/stop/trip entities, repository protocol, domain-facing errors |
| `C67Data` | Mock actor with bundled fixtures; URLSession Supabase RPC adapter |

Run `swift test --package-path ios-backend` from the repository root. Tests cover snapshot copying, retry identity, configuration validation, authentication boundaries and the RPC wire adapter.

The package has no external Swift dependencies. Domain cannot import Data. Reserved Application/Platform directories are not compiler targets yet. Introduce them when shared use cases or native services need a stable boundary.

`MockRundownRepository` is memory-only. Its bundled fixture is a checked copy of `contracts/fixtures/rundowns.json`; update it with `scripts/sync_fixtures.py`. `SupabaseRundownRepository` accepts a URL, client key, injectable URLSession and async access-token provider. It adds a bearer header only for an actual traveller JWT; client API keys stay in the `apikey` header.

`SupabaseAuthentication` implements email/password login for an existing traveller account,
Keychain restore, demand-driven refresh within 60 seconds of expiry, and local-scope logout.
The composition root injects its throwing access-token provider into private RPCs and invalidates
only the matching session after a 401. Concurrent refresh callers share one persisted result;
logout and account changes invalidate late responses. Temporary network/429/5xx failures retain
refresh credentials for retry; a rejected refresh clears them. A failed server logout clears local
credentials and reports that remote revocation was not confirmed. No background timer runs while
the app is suspended. Refresh also runs on foreground activation.

`KeychainSessionStore` uses an atomic generic-password item scoped by app namespace and backend URL,
with `WhenUnlockedThisDeviceOnly` accessibility and iCloud synchronization disabled. Storage errors
are surfaced, not replaced by an insecure fallback. Passwords are submitted, never persisted.
Session tokens stay in Data; Domain/presentation receive `TravellerAccount` identity only.

The repository adds `searchRundowns`, `listMyTrips` and `tripGraph`. Domain graph values preserve
occurrence identities and unknown locations/time/durations; provider DTO mapping stays in Data.
Cursors pass unchanged and belong to their original query/account. On 401, commands are not
silently replayed. The caller retains its original request UUID when explicitly retrying a write.
The mock provides synthetic keyset pages and stable in-memory graphs with unknown route facts;
its minted root IDs are synthetic, distinct from version IDs, and are not server catalog IDs.

See [the Auth/API task](../docs/tasks/ios-auth-api.md) for evidence and remaining boundaries.
Registration, confirmation/resend and recovery/password update now use native PKCE callbacks
with a separately persisted Keychain verifier. Session streams update presentation state, recovery
blocks private app requests until reset, and authenticated response tickets reject stale login results.
See [native Auth setup](../docs/native-auth.md) and [ADR-0006](../docs/decisions/0006-native-auth-session.md).
Apple/OAuth, MFA and other server RPCs remain separate slices. Interactive registration keyboard
acceptance is still pending; do not infer it from successful method/API tests.

No SMTP, Studio password or service-role key belongs in the client. Offline persistence, synchronization and Apple platform adapters remain follow-up tasks.
