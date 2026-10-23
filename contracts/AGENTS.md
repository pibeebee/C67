# Shared-contract instructions

Apply the [root instructions](../AGENTS.md). Scope: `contracts/`.

- `api/openapi.json` is the authoritative OpenAPI 3.1 wire contract. Keep reusable schemas there; the reserved `schemas/` directory is not a duplicate source. Follow [the contract README](README.md).
- Specify request/result/error shapes, access requirements, nullability, UUIDs, timestamp offsets, ordering and retry behavior for changed operations.
- `Rundown.id` currently means a published version ID. Do not silently change its meaning or return database rows as a new public contract.
- Coordinate breaking changes with UI, on-device backend and server owners. Identify affected callers and migration/compatibility work in the task and PR. Do not silently activate a product policy while changing a schema.
- Use synthetic fixtures without real account IDs, tokens, private media or credentials. Keep fixture values labelled as example content rather than verified travel facts.
- Update authoritative fixtures here, then run `python3 scripts/sync_fixtures.py` from the root. It regenerates both the Swift resource and SQL seed; do not hand-edit the copies.

## Verification

From the root run `.venv/bin/python scripts/check_contracts.py` after the documented environment setup. It validates OpenAPI, JSON fixtures and generated-copy consistency. Also run affected package and database checks for behavioral changes. Contract validation alone does not prove adapter/server conformance or deployed compatibility.
