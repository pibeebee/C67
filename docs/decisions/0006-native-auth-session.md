# ADR-0006: Native email/password sessions and PKCE email links

Status: Accepted; scoped Simulator and provider verification is recorded in the task.
Date: 28 October 2026

## Decision

Use the existing self-hosted Supabase Auth REST service with the dependency-free URLSession Data
adapter. One actor owns session persistence, refresh, pending email state and session-change events.
Domain exposes account identity and local session snapshots; provider DTOs and tokens stay in Data.

Email/password is the implemented method. Native registration/confirmation/resend and recovery use
PKCE S256, a cryptographically random verifier, random local state and `c67://auth/callback`.
Register this scheme in the app and add its callback/query entries to Auth. The app enforces the exact path/state; GoTrue also permits its configured site origin. Retain
pending verifiers in a separate backend-scoped Keychain item so a newly opened app can complete a
link. Reject unexpected origins/paths, duplicates, implicit bearer fragments, missing/wrong state,
expired local requests and replays. A link is completed on the device that requested it.

Session and pending-flow Keychain items use WhenUnlockedThisDeviceOnly and do not sync to iCloud.
Passwords are held only while entering/submitting the form. Refresh callers share one operation;
token rotation retains local session identity. Login/logout/recovery transitions change that identity.
Requests already sent may commit on the server; response tickets and UI resets discard results
under a different login. Client cancellation is not database rollback.

Recovery remains limited in the app until password update succeeds. Supabase's recovery JWT retains
its standard server role; no new RLS policy or claim-based recovery role is asserted here. Local
logout clears device credentials and revokes that refresh session; already issued JWTs can remain
valid until expiry under Supabase's standard behavior. A failed remote logout is reported explicitly.

Debug and Release use separate local override files. Missing production configuration fails visibly;
development client settings cannot silently flow into Release. No server secrets or traveller JWTs
belong in either bundle configuration.

## Verification and limits

See the [task evidence](../tasks/ios-auth-api.md). Real native Auth/Keychain flows passed against the
matching isolated GoTrue and local mail sink; real owner isolation passed on the shared homelab.
Native registration input and system callback rejection passed on Simulator. No physical-device, external-email
inbox, web OAuth, MFA or production readiness claim follows from those checks.

Provider references: [GoTrue v2.197.0](https://github.com/supabase/auth/tree/v2.197.0),
[Supabase sessions](https://supabase.com/docs/guides/auth/sessions),
[password authentication](https://supabase.com/docs/guides/auth/passwords).

Native Apple credentials now reuse this actor; [ADR-0007](0007-native-apple-auth.md) records the extension
and the remaining live Apple activation/authorization gates.
