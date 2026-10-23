# Getting started

## 1. Run the mock app

Requirements: macOS, Xcode 16+ with an iOS Simulator runtime, Swift 6 language support. The app targets iOS 18+. The initial verification uses Xcode 27.1; test your team's chosen Xcode version before standardizing it. Signing is unnecessary for Simulator; choose your own development team for a physical device.

```sh
git clone https://github.com/pibeebee/C67.git
cd C67
open ios-ui/C67.xcodeproj
```

Select **C67**, choose an iPhone Simulator, and Run. You should see **Mock • memory only** and one synthetic rundown. Open its detail, choose a start time, and save a personal trip. Relaunching clears mock trips.

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

Requirements: Node.js 22+ / npm and a running Docker-compatible engine. Run from `server/`:

```sh
npm ci
npm run start
npm run db:reset
npm run db:test
npm run supabase -- status
```

**`db:reset` deletes and rebuilds the local development database.** Use it only for disposable local data. The npm script explicitly passes `--local`; do not add remote connection flags. Initial image downloads may take several minutes.

Default ports: API `54321`, database `54322`, Studio `54323`, local mail inbox `54324`. Close an older stack using these ports first. Local Auth emails stay in the local inbox; no Brevo credentials are needed. PostgreSQL 17 is the generated local baseline; verify the actual homelab version and migration compatibility before any future deployment.

## 5. Try the live local catalog

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

Live mode reads the synthetic catalog through RPC. **Saving a live trip requires a verified traveller access token.** The repository accepts an async token provider, but the starter composition root deliberately has no real session or sign-in UI. The app reports that sign-in is needed. Implement secure session storage and refresh as the Account task; do not substitute Studio Basic Auth credentials.

For a later homelab integration use HTTPS and the homelab client key, after reviewing and deploying the schema separately. Setting a URL does not install the RPCs there. Never point reset commands at the homelab.

## 6. UI smoke test

Run the **C67** scheme's Test action in Xcode. The UI test opens the rundown and saves a mock trip. Keep data mode set to `mock` for this test.

CI also runs package tests, contract validation, the Simulator smoke test, and local Supabase database tests. See [Verification](verification.md) for what has actually run locally.
