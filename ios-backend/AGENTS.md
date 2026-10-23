# On-device backend instructions

Apply the [root instructions](../AGENTS.md). Scope: `ios-backend/`.

- This is a local Swift package running on the device. Follow [the package README](README.md) and `Package.swift`.
- `C67Domain` owns entities, domain errors and repository protocols; it must not import Data, SwiftUI or provider SDKs. `C67Data` depends on Domain. Reserved Application/Platform folders are not compiler targets yet.
- Keep wire DTOs, mapping and transport details in Data. Preserve the contract's UUIDs, zero-based stop ordering and offset-bearing timestamps.
- Maintain matching repository behavior across mock and live adapters. Mock trips remain memory-only until a persistence task explicitly changes that boundary.
- Preserve request IDs across retries of the same operation, reject changed input with a reused ID, and distinguish uncertain responses from confirmed writes.
- Get authenticated access tokens through the injected session provider. Implement storage/refresh/cancellation deliberately in Auth work; do not hardcode tokens or use Studio credentials.
- Keep opaque client keys in `apikey`; only actual traveller JWTs belong in the bearer header. Do not weaken transport configuration to make a remote endpoint work over plain HTTP.
- Fixture source: `../contracts/fixtures/`. Run `python3 scripts/sync_fixtures.py` from the root to update the bundled copy and SQL seed; do not hand-edit those copies.

## Verification

Run `swift test --package-path ios-backend` from the root. Tests are under `Tests/Starter/`. Add meaningful behavior or wire-boundary checks for changed behavior, including relevant error/retry/session cases. Run contract validation for payload/fixture changes. A URLProtocol stub verifies adapter behavior, not a real Supabase connection.
