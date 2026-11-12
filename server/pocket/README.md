# Pocket catalog and Luna advice

This beta service is separate from Supabase and the old Node planner. It serves the independent catalog and sends bounded, consented schedule-choice requests to Luna. The app chooses places, estimates Apple routes and validates the final schedule. See the [HTTP contract](../../contracts/api/openapi.json) and [maintained server source](../../poc-journey/apps/c67-pocket-engine-lab/Server/CONTRACT.md).

1. On the intended host, copy the provided env template into the ignored `.env`. Generate distinct random read/write tokens (at least 24 characters each). Set the provider HTTPS base including `/v1` and its key. Never embed the write token or provider key in the app. Keep the daily Luna cap small for internal beta; failed attempts also consume a reservation.
2. From the repo root, run `docker compose -f server/pocket/compose.yml up -d --build`. The HTTP service binds to host loopback. It uses a persistent SQLite volume. Preserve the volume across upgrades; the bundled seed initializes missing IDs, it does not overwrite evidence.
3. Put a trusted HTTPS reverse proxy in front. Expose only GET `/health`, GET `/v1/catalog` and POST `/v1/advice/visits`; default deny all other routes. Limit request body size to 80 KB and provider concurrency; set the proxy timeout above 95 seconds. Do not log Authorization or bodies. Import reviewed evidence locally with the server CLI.
4. Verify public HTTPS health, 401 without a read token, a catalog schema check with one, and a single authorized Luna request. Use an invited-tester token in Account → Pocket settings. A shared read token is not a public multi-tenant authorization model.

The host's SQLite volume and the signing account are independent. Local loopback testing does not show that a TestFlight install can reach the server. This deployment recipe has no host names or credentials committed.
