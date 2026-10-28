# Native Auth setup and verification

The app implements email/password sign-in, registration, confirmation resend and password recovery
against the existing Supabase Auth service. See [the task](tasks/ios-auth-api.md) for Simulator,
real-provider verification and remaining device/delivery limits.

Native Sign in with Apple is also implemented; [Apple setup](apple-auth.md) records its active homelab
provider and remaining Apple Developer provisioning/real-authorization gates.

## Run the app

Open `ios-ui/C67.xcodeproj`, scheme C67, Debug. Keep client settings in the ignored
`ios-ui/Configuration/Development.local.xcconfig`. For shared development use live mode,
HTTPS and `supabase.mrt.qzz.io` with its anon client key. Never use Studio or service-role credentials.

Open Account from Discover. Choose Sign in, Create account or Forgot password. New passwords need
at least 8 characters and matching confirmation. Existing shorter passwords can still be used to
sign in. Registration requires the email's confirmation link; pending signup exposes Resend
confirmation. Recovery returns to Set a new password before private app requests are enabled.
Open the newest link on the device that requested it. Pending requests/verifiers survive an app
restart and expire after one hour. Cancel email request removes the local pending flow.

A real physical iPhone can receive system email callbacks after the app is installed and signing is
configured. A desktop email link does not automatically target an iOS Simulator. System-opened
callback routing and missing-flow rejection passed on Simulator; physical email-to-app routing
remains a verification step on the intended device.

## Release configuration

Debug.xcconfig includes Base.xcconfig and Development.local.xcconfig. Release.xcconfig includes
Base.xcconfig and a separate optional Production.local.xcconfig. Copy Production.example.xcconfig
to that ignored file and choose the intended backend before distributing a build. Its default live
host/client key are empty so a missing setup presents configuration failure. Base remains safe to commit.

## Repeat tests

Package: `swift test --package-path ios-backend`.
Simulator C67 tests use `CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- C67_DATA_MODE=mock`.
The native Keychain test creates/deletes unique synthetic items. Integration and live keyboard
checks are opt-in and otherwise skip; default CI does not access the shared backend or send email.

For isolated email verification, copy `server/scripts/native_auth_fixture.py` to the homelab and
run `python3 <copied-script> provision --approved-auth-verification` only within an approved scope.
It uses existing image IDs, separate PostgreSQL/Auth, a mail sink and host-loopback port 18081.
It starts no Mac Docker and sends no external email. Forward that loopback port over SSH. Run only
`C67AppTests/AuthLifecycleIntegrationTests` with test-runner `C67_AUTH_INTEGRATION=1`. The test uses
actual Simulator Keychain, signup, confirmation/resend, PKCE, restart, recovery, update and refresh
revocation. Remove the exact fixture using the script's cleanup action and close its SSH tunnel.

For shared verification, run `server/scripts/test_native_auth_homelab.py prepare --env-file
<private-server-env> --approved-auth-verification`. This creates two confirmed synthetic accounts
without sending email and a private `/private/tmp/c67-native-auth-shared/cohort.json` on the Mac.
Run `C67AppTests/SharedAuthIntegrationTests` on that Mac's Simulator with test-runner
`C67_SHARED_AUTH_INTEGRATION=1`. It imports no admin key into the app. Always run the helper's cleanup
action afterward; it checks exact identities, owner trip cleanup and preservation of baseline accounts.
If interrupted, inspect its private state file and resume exact cleanup; never reset the shared DB.

Live UI: build with the intended Debug client and select
`C67UITests/StarterUITests/testLiveRegistrationAndRecoveryFormValidation`, test-runner
`C67_TEST_LIVE=1`. It types only synthetic values and does not submit any shared email request.
This case dismisses the native strong-password suggestion before synthetic typing. It and
`testAccountUsesConfiguredMode` support `C67_TEST_LARGE_TEXT=1` for Accessibility XXXL text and
scrolling checks. `testLiveSystemCallbackWithoutPendingFlow` opens a synthetic URL through the
system and checks rejection feedback without a token exchange. With the xcodebuild CLI, prefix
these environment flags with `TEST_RUNNER_` so they reach the UI test runner. Dark appearance must
be verified separately; the AppleInterfaceStyle launch argument did not change it on this runtime.
Do not run the mock trip-save smoke test in live mode.

## Backend operations

The shared Auth image remains v2.197.0. Configuration uses the C67 callback, required confirmation,
minimum password 8, refresh rotation with a 10-second reuse interval and 3600-second JWTs. SMTP
secrets are unchanged. Backup/rollback evidence and the exact deployed helper are linked in the task.
`server/scripts/configure_native_auth.py` is a guarded deployment tool, not a routine startup command.
