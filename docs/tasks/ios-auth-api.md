# Task: Native email/password Auth, session lifecycle and API queries

Status: Implemented and verified for the scoped native email/password flow on Simulator
Owner: Giovan
Reviewers: iOS UI and on-device backend owners
Branch: gi/trip-graph (consolidated from gi/ios-auth-api, originally based on main 5e2d943)
Updated: 28 October 2026

## Outcome and authorization

Giovan authorized completing Auth/session while away: global session changes, safe logout/account
transitions, registration/confirmation/resend, recovery/password reset, meaningful errors,
PKCE callbacks, backend configuration and verification. The earlier search/owner-trip/graph query
adapters remain included. On 28 October the work was consolidated into the primary C67 checkout
on gi/trip-graph at Giovan's request, preserving the existing Xcode signing team and Apple capability.
The original working trees, Git indexes, local overrides and branch history were privately backed up
and verified before consolidation. project.yml remains the generated project's source of truth.
No commit, push, PR or merge was performed at the initial implementation checkpoint.
Giovan subsequently authorized commit, push and a review PR on 28 October; no merge is included.

## Implemented

- Domain account/session snapshots and an observable stream from one Data actor.
- Keychain session and separate pending email-flow storage, both scoped to app/backend and
  WhenUnlockedThisDeviceOnly. Passwords are ephemeral form input, never persisted.
- Email/password login, signup, confirmation resend, recovery, code exchange and password update.
  PKCE S256 plus random callback state, exact callback shape validation and one-hour pending expiry.
  Verifiers survive app replacement; callback replay/foreign/implicit-token URLs are rejected.
- Shared refresh requests, local-scope logout, matching-token 401 invalidation and typed errors,
  including GoTrue's numeric HTTP code alongside its machine-readable error_code.
- The app blocks private RPCs while finishing password recovery. Private response tickets and
  presentation resets prevent a late response from appearing under a different login.
  This is an app restriction; the server's standard authenticated recovery JWT is not a separate RLS role.
- Account forms for sign-in, registration, confirmation status, recovery and new password; native
  secure fields and explicit validation state. Queued callbacks are handled after foreground restore.
- Search/owner trip pagination and graph adapters preserve wire identity and unknown values.
- Debug loads Development.local.xcconfig. Release uses a separate optional Production.local.xcconfig;
  missing Release credentials fail configuration instead of inheriting the development endpoint.

## Shared homelab changes and recovery

Preflight identified external Compose `/home/giovan/apps/supabase`, GoTrue v2.197.0, configured SMTP,
confirmation required, and a localhost callback fallback. Only Auth settings were changed:
SITE_URL=c67://auth/callback, additive exact/query callback allowlist, minimum password 8,
refresh rotation enabled with a 10-second reuse interval. JWT lifetime remains 3600 seconds;
SMTP credentials, email-confirmation requirement, gateway/Cloudflare and schema were preserved.

Private configuration backup: `/home/giovan/backups/c67/before-native-auth-2026-10-28T010039Z`.
The checked helper [configure_native_auth.py](../../server/scripts/configure_native_auth.py)
validates manager/files/config drift, backs up config, recreates only Auth, checks health and
unchanged sibling lifecycles, and automatically rolls back its config on failure. It is intentionally
not a repeatable overwrite command; inspect drift before any future application. To roll back this
specific deployment, restore `.env` and `docker-compose.yml` from the private backup, validate the
same two Compose files, and run `up -d --no-deps --pull never auth`; then recheck health/callbacks.

Final remote check: Auth healthy, 10 other Supabase service IDs/start times unchanged, one original
Auth account and zero trips. Two exact synthetic shared accounts and their owned graph/trip data
were removed. Temporary isolated Auth/PostgreSQL/SMTP containers, anonymous database volume,
both fixture networks, private files and the task SSH tunnel were removed.

## Evidence

- `swift test --package-path ios-backend`: **29 passed** after the final Auth changes.
- Earlier native unit/integration checkpoint, iPhone 18 Pro / iOS 27.0: **9 passed, 1 skipped**. It includes
  actual Keychain operations, form validation, Account state, private-state reset and real GoTrue
  signup/email/resend/PKCE/relaunch/refresh/recovery/password change/logout against the isolated
  fixture. Shared verification was skipped only because its cohort had already been cleaned.
- Earlier combined C67 run: **9 passed, 0 skipped**, including the real shared-homelab native test:
  two-account login/refresh, Keychain recreation, private create/list/graph, bidirectional foreign
  graph denial, account switching, local logout, rejected revoked refresh token and preservation
  of a separate session. The two mock UI smoke paths also passed in that run.
- Shared SMTP accepted certificate-verified STARTTLS and authentication. No external email was
  sent for verification. Real email delivery was exercised only against the isolated SMTP sink;
  actual inbox placement/provider delivery remains unverified.
- Final clean mock C67 run after cleanup: **11 passed, 4 intentionally skipped** (isolated/shared/live-input/callback opt-ins disabled).
- Contract/fixture/seed validation passed. Operational scripts compile, formatting/whitespace and
  ignored-config/secret checks are recorded in the final handoff. Release Simulator build passed.

## UI diagnosis and acceptance

The earlier registration typing failure was reproduced after unlocking the Mac. XCTest's hierarchy
and a desktop screenshot exposed the native “Use Strong Password?” suggestion over the secure field.
Dismissing its Close button before typing the synthetic password made the same test pass. The
production SecureField and newPassword semantics remain intact; no AutoFill setting was disabled.
The test scrolls controls into view for the largest accessibility text size. No signup/recovery submit
is performed against shared SMTP.

A system-opened synthetic callback exposed a separate presentation bug: a passive restore when
Account opened cleared the callback error. Passive restore now preserves that feedback; explicit
Check session again clears it after success. A native regression test covers both transitions.

The targeted run passed **9/9** tests: six Account/Keychain/state tests and three live UI cases,
on iPhone 18 Pro / iOS 27.0 using Xcode 27.1. The Account and registration/recovery forms were exercised
with Accessibility XXXL text, including scrolling to the submit control. Opening a synthetic callback
through XCUIDevice.shared.system from the Home screen reopened Account and displayed the missing
pending-flow error. This establishes OS routing and rejection feedback; real PKCE exchange evidence
comes from the isolated integration checkpoint above. Exported screenshots were inspected. A separate final standard-text run passed all three live UI cases.
The attempted AppleInterfaceStyle launch argument did not produce Dark appearance in screenshots;
it was removed from the tests. Dark appearance remains unverified, with no claim based on that flag.

Physical-device/iOS 18 runtime, external SMTP inbox delivery and a full accessibility audit are
unverified. Web OAuth, MFA, account deletion, native My Trips/search/graph screens and journal
integration are separate scopes. See [native Auth guide](../native-auth.md) and
[ADR-0006](../decisions/0006-native-auth-session.md).

Native Apple authentication was subsequently implemented alongside this uncommitted work.
[Apple task](apple-auth.md) tracks its separate provider/signing/real-authorization acceptance gates.

## Consolidated checkout verification

On 28 October, build/install/launch from `gi/trip-graph` passed on iPhone 18 Pro / iOS 27.0.
The shared Swift package passed 34/34 tests and the live Account UI test passed 1/1, verifying
the Apple button and email form. Formatting and whitespace checks passed. Xcode was opened
on the primary checkout and showed the retained signing team and Sign In with Apple capability.
Both auxiliary worktrees were removed after backup and destination-content verification.
See [verification](../verification.md) for the consolidation record. Commit/push/PR were authorized
after that checkpoint.
