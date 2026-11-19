# Pocket on the homelab

This recipe connects an ingress proxy to the existing external Docker network `cf-tunnel`. Pocket and SQLite use the project network. The service and proxy publish no host ports.

Prepare `server/pocket/.env` using [Pocket setup](../../pocket/README.md). From the repository root, after the exact deployment has been reviewed, run the project-specific Compose file.

```sh
docker compose -p c67-pocket-beta -f server/deploy/pocket/compose.yml config --quiet
docker compose -p c67-pocket-beta -f server/deploy/pocket/compose.yml up -d --build --wait
```

The expected Cloudflare Tunnel service URL is `http://pocket-beta-ingress:8080`. Configure the published hostname manually in the Cloudflare dashboard. The existing connector must already join `cf-tunnel`. Network and connector ownership stay with their current manager.

The proxy serves `GET /health`, `POST /v1/order`, `GET /v1/order/jobs/{id}`, `POST /v1/hours/lookup`, `POST /v1/visits/resolve`, `GET /v1/visits/jobs/{id}`, `POST /v1/advice/visits`, and `POST /v1/account/deletion`. Other paths return 404. The body limit is 200 KiB, except account deletion which is limited to 4 KiB. The upstream read timeout is 320 seconds. Automatic proxy retries are disabled to avoid repeating a paid request.

When updating an existing ingress, preserve the hours lookup route. Add the account deletion route to the active ingress after the [migration and Apple credentials](../../pocket/README.md#account-deletion) are ready and the worker passes isolated verification. An order-only rollout can keep its current ingress while those prerequisites are pending.

Before updating an existing service, inspect its Compose owner, release path, environment file and volume. Preserve the volume name and credentials. The first reviewed deployment uses project `c67-pocket-beta`; changing the project name creates a different default volume. Follow the local homelab operational approval procedure before applying any shared change.

After deployment, verify container health, read-only filesystems, the data mount, network membership, no host port bindings, public HTTPS, ordering endpoint authorization and job polling with synthetic inputs. An explicitly authorized advice call verifies provider connectivity. Keep tokens out of commands and logs.

Rollback uses the previous reviewed release with the same persistent volume. Stop only this project if needed. Do not remove its volume during rollback.
