# Pocket catalog and Luna advice

The maintained Python service supplies independent place evidence and bounded schedule-choice advice. The iOS app performs preference matching, route estimation, schedule validation, and local trip storage. See the [wire contract](../../contracts/api/openapi.json) and [native integration](../../docs/guides/pocket-engine-integration.md).

## Configure and run

Python 3.11+ is sufficient for the standard-library server. Live Luna advice also uses `curl` and system TLS trust. The Docker image includes both.

```sh
cp server/pocket/.env.example server/pocket/.env
# Set private tokens and provider settings before starting.
python3 server/pocket/src/server.py
```

The process loads `server/pocket/.env` and defaults to loopback port 8792. Its default SQLite directory is `server/pocket/.local/server/`. Generate different read/write tokens of at least 24 characters. Set the provider HTTPS base including `/v1`, its API key, and the daily advice cap. Failed upstream attempts consume a reservation. Keep `.env` readable only by its owner.

From the repository root, the local Docker recipe uses a persistent volume and host loopback.

```sh
docker compose -f server/pocket/compose.yml up -d --build
```

Use the [homelab deployment](../deploy/pocket/README.md) for Cloudflare Tunnel ingress. Preserve the SQLite volume across updates. Seed initialization inserts missing identities and preserves stored evidence.

## Resources and endpoints

The canonical seed and 62-label taxonomy live in `packages/PocketEngine/Sources/PocketEngine/Resources/`. Native execution resolves these files from the checkout independently of the working directory. Docker copies them into `/app/resources` and sets `POCKET_RESOURCE_DIR`. `POCKET_SEED_CATALOG` can point to a separate reviewed seed file.

| Endpoint | Access |
| --- | --- |
| `GET /health` | Public health status |
| `GET /v1/catalog` | Read bearer token |
| `POST /v1/advice/visits` | Read bearer token, bounded quota/concurrency |
| `POST /v1/evidence/import` | Write bearer token, local administration |
| `POST /v1/providers/tomtom/search` | Optional provider configuration, excluded from the beta ingress |

The beta ingress publishes only health, catalog, and advice. It limits request bodies to 80 KB and uses a timeout above the upstream time budget. Authorization headers, request bodies, and provider keys must stay out of logs. Import reviewed evidence locally with `--import-evidence`; use `--import-identities` for reviewed catalog identities.

A shared read token serves invited beta testers. It is separate from the write token and provider key. The app stores it in Keychain through Account > Pocket settings.

## Verification

```sh
python3 -m unittest discover -s server/pocket/tests
```

The suite checks resource relocation, the real local HTTP entry point, read authorization, and persistence without external providers. See [repository verification](../../docs/testing/verification.md) for Docker and client checks.

The original experimental service remains a preserved [Pocket Lab snapshot](../../research/poc-journey/apps/c67-pocket-engine-lab/Server/). Product changes belong here.
