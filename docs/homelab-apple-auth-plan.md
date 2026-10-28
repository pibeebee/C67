# Homelab native Apple provider plan

Status: Explicitly approved, applied and verified on 28 October 2026
Date: 28 October 2026

## Exact scope

Read-only preflight identified healthy `supabase-auth`, image `supabase/gotrue:v2.197.0`, external
Compose project `supabase` with files `/home/giovan/apps/supabase/docker-compose.yml` and
`docker-compose.cf-tunnel.yml`. Apple provider/client IDs were unset at preflight; no Apple secret was configured. The public settings endpoint
also returned HTTP 200 with Apple disabled before deployment (certificate validation enabled using system CA roots).
The native app's existing bundle is `io.pibeebee.c67.starter`.

Edit only the main Compose Auth environment to add Apple enabled=true, client ID equal to that
bundle, and skip-nonce-check=false. Recreate only `auth` using both existing Compose files:
`up -d --no-deps --pull never auth`. No schema, other provider, SMTP, callback, gateway, Cloudflare,
port, image or other service change is part of this plan. Expected interruption: a brief Auth
restart. Existing JWTs retain standard validity until expiry; new login/refresh may briefly fail.

## Reviewed helper and drift gate

[configure_apple_auth.py](../server/scripts/configure_apple_auth.py) defaults to read-only `plan`.
It validates exact Compose ownership, image and health, rejects existing Apple configuration,
and produces a configuration fingerprint. The inspected fingerprint was:

`48d1dec80679a2768b40d7ef600e161c4ee4412fb2d242882aa68948f19e74db`

Before applying, rerun plan and compare its result with this reviewed scope. A changed fingerprint
requires review of drift. After approval, copy the reviewed helper to a private temporary directory
on the homelab and run `python3 <helper> apply --fingerprint <reviewed-fingerprint>
--approved-apple-auth`. Never apply by piping an unreviewed remote download to a shell.

## Backup, rollback and verification

The helper creates a private timestamped directory under `/home/giovan/backups/c67/` containing
`.env`, both Compose files, checksums and sibling container IDs/start times. It changes only the main Compose
file, compares resolved service configuration, then restarts Auth. It checks health and exact
runtime settings, and verifies unchanged sibling lifecycle identifiers. On failure it restores
the main Compose file and recreates Auth; raw Compose diagnostics are not printed because they can
contain configuration secrets. Keep the backup for recovery.

Manual rollback: restore `docker-compose.yml` from that exact backup, validate the same two Compose
files and recreate only Auth with `--no-deps --pull never`; verify health and previous provider
settings. No database restore is needed because this operation does not write application rows.

After deployment, verify `/auth/v1/settings` exposes Apple enabled and a real signed-device Apple
login succeeds. A healthy provider setting alone does not prove Apple signing, audience, nonce,
real token verification or device authorization. The user must complete Apple's authorization.

## Deployment evidence

Giovan explicitly authorized activation of this exact plan on 28 October 2026. Immediate preflight
returned the same fingerprint. The reviewed local helper was executed over SSH via stdin with its
apply/fingerprint/approval arguments; no downloaded remote code was executed or helper left behind.
Backup: `/home/giovan/backups/c67/before-apple-auth-2026-10-28T061902Z` (06:19:02 UTC / 13:19:02 WIB).

Only the three reviewed environment keys changed and only Auth was recreated. Auth is healthy;
ten sibling service container IDs/start times are unchanged. `.env` and tunnel Compose remain
byte-identical to backup. All backup checksums and 0700 directory/0600 file permissions passed.
TLS-verified public `/auth/v1/settings` returned HTTP 200 with Apple=true and email=true.
No rollback was needed and no database operation was issued. Real Apple authorization/signing
acceptance remains pending; provider activation does not establish it.
