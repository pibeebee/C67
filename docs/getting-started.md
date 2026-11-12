# Getting started

**Current native flow — 12 November 2026:** Pocket Engine is the default on-device planner. Configure catalog/Luna connectivity in Account and use [Pocket setup](pocket-engine-integration.md). Synthetic mock and legacy HTTP live modes remain explicit options; the older Supabase setup below does not configure the Pocket service.

## 1. Run the mock app

Requirements: macOS, Xcode 16+ with an iOS Simulator runtime, Swift 6 language support. The app targets iOS 18+. The initial verification uses Xcode 27.1; test your team's chosen Xcode version before standardizing it. Signing is unnecessary for Simulator; choose your own development team for a physical device.

```sh
git clone https://github.com/pibeebee/C67.git
cd C67
git switch dev
open ios-ui/C67.xcodeproj
```

Select **C67**, choose an iPhone Simulator and Run. Pocket mode opens the existing trip UI; choose an origin, preferences and destinations, review availability and advice consent, then save locally. For synthetic UI work, build with `C67_DATA_MODE=mock`. Mock trips remain memory-only. `--legacy-catalog` still opens the earlier sample, not Pocket discovery.

The committed Xcode project is ready to open. XcodeGen is only needed when changing targets or source groups:

```sh
xcodegen generate --spec ios-ui/project.yml
```

`project.yml` is the build-configuration source. Commit the regenerated `.xcodeproj` with configuration changes. XcodeGen 2.44+ is required; the current checked-in project was generated with the version recorded in [Verification](verification.md).

## 2. Run the shared package tests

From the repository root:

```sh
swift test --package-path ios-backend
```

No network SDK dependency is required. Domain and Data are separate compiler targets. Application/Platform folders are reserved; they are not empty compiler targets.

## 3. Validate the API contract

Use Python 3.11+:

```sh
python3 -m venv .venv
.venv/bin/pip install -r scripts/requirements.txt
.venv/bin/python scripts/check_contracts.py
```

Edit fixtures in `contracts/fixtures/`, then run `python3 scripts/sync_fixtures.py` to update the package resource and SQL seed. Validation rejects a stale package copy.

## 4. Start local Supabase (server developers)

Requirements: Node.js 22+ / npm, Python 3.11+ for HTTP checks, and a running Docker-compatible engine. Run from `server/`:

```sh
npm ci
npm run start
npm run db:reset
npm run db:test
npm run db:lint
npm run api:test
npm run supabase -- status
```

**`db:reset` deletes and rebuilds the local development database.** Use it only for disposable local data. The npm script explicitly passes `--local`; do not add remote connection flags. Initial image downloads may take several minutes. The HTTP suite creates two temporary local accounts, tests real login/refresh and private trip access, and verifies cleanup. It does not accept a remote URL or reset data. See [the server guide](../server/README.md) for scope and recovery limits. CLI status output contains local credentials; keep it private.

Default ports: API `54321`, database `54322`, Studio `54323`, local mail inbox `54324`. Close an older stack using these ports first. Local Auth emails stay in the local inbox; no Brevo credentials are needed. PostgreSQL 17 is the generated local baseline; verify the actual homelab version and migration compatibility before any future deployment.

## 5. Configure live mode

```sh
cp ios-ui/Configuration/Development.example.xcconfig ios-ui/Configuration/Development.local.xcconfig
```

Edit the ignored local file:

```text
C67_DATA_MODE = live
SUPABASE_SCHEME = http
SUPABASE_HOST = 127.0.0.1:54321
SUPABASE_CLIENT_KEY = <local publishable or legacy anon client key>
```

Get the local client key from local Studio or the local CLI status output. Never commit CLI status output or copy a service-role key into the app. Rebuild the app after changing `.xcconfig` values. Loopback works for the iOS Simulator on the same Mac; physical-device networking is a separate setup task.

For personal planning, also set `PLANNING_SCHEME` / `PLANNING_HOST` to the configured API (loopback HTTP on the same Mac Simulator or HTTPS for shared access). If omitted, Account remains available and planning reports configuration required. The API forwards traveller JWTs to the new owner RPCs; it never accepts an app service-role key.

The legacy catalog still reads synthetic sources through RPC. Open **Account** from the app toolbar to
sign in with an existing traveller email/password account. The app stores its session in Keychain,
refreshes before private requests/foreground activation, and supports local-scope logout. Saving a
live trip uses the injected traveller JWT. Studio Basic Auth credentials cannot sign in here.
Account also includes Create account, confirmation resend, Forgot password and Set new password
using PKCE links on the requesting device. See [native Auth setup and current UI acceptance issue](native-auth.md).
Apple/OAuth remains a separate setup.

For the existing shared homelab, use `SUPABASE_SCHEME = https`,
`SUPABASE_HOST = supabase.mrt.qzz.io` and its anon client key in the ignored override; no Mac-local
Supabase is needed. The server RPCs are already deployed as recorded in the server handoff.
Configuration defaults remain mock. Debug includes the development override; Release requires its own ignored
Production.local.xcconfig before distributing a build. Never point reset commands at the homelab.

## 6. UI smoke test

Run the **C67** scheme's Test action in Xcode. The legacy UI smoke test launches `--legacy-catalog`, opens the rundown and saves a mock trip. A new planning walkthrough has not been run in this implementation batch. Keep data mode set to `mock` for these tests. For command-line Simulator tests, use
`CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- C67_DATA_MODE=mock`; ad hoc signing permits the
native Keychain test to run without an Apple development team. Disabling signing causes Keychain
access to fail in the test host. Ordinary build-only checks can still disable signing.

CI also runs package tests, contract validation, the Simulator smoke test, and local Supabase database tests. See [Verification](verification.md) for what has actually run locally.

## 7. Team conventions and formatting

Read [Coding conventions](coding-conventions.md), then run `python3 scripts/swift_format.py --check`. The runner downloads the pinned macOS formatter on first use and verifies its archive checksum. Use `--write` when formatting your Swift changes. Complete [the onboarding checklist](onboarding-checklist.md) before your first merge.
