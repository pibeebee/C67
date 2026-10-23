# iOS Backend (on-device code)

This is a local Swift package, not a remote server. It exports two products:

| Target | Responsibility |
|---|---|
| `C67Domain` | Rundown/stop/trip entities, repository protocol, domain-facing errors |
| `C67Data` | Mock actor with bundled fixtures; URLSession Supabase RPC adapter |

Run `swift test --package-path ios-backend` from the repository root. Tests cover snapshot copying, retry identity, configuration validation, authentication boundaries and the RPC wire adapter.

The package has no external Swift dependencies. Domain cannot import Data. Reserved Application/Platform directories are not compiler targets yet. Introduce them when shared use cases or native services need a stable boundary.

`MockRundownRepository` is memory-only. Its bundled fixture is a checked copy of `contracts/fixtures/rundowns.json`; update it with `scripts/sync_fixtures.py`. `SupabaseRundownRepository` accepts a URL, client key, injectable URLSession and async access-token provider. It adds a bearer header only for an actual traveller JWT; client API keys stay in the `apikey` header.

Implement secure session persistence and refresh before wiring authenticated live writes. No SMTP, Studio password or service-role key belongs in the client. Offline persistence, synchronization and Apple platform adapters remain follow-up tasks.
