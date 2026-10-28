# Native Sign in with Apple setup

The app contains a native Apple authorization button and Supabase ID-token adapter. On 28 October
2026, after Giovan reported signing in, a read-only database check confirmed a recent Apple identity
sign-in, a session and an owned trip. This establishes server-side sign-in acceptance; device-specific
relaunch, refresh, logout, Hide My Email and revocation acceptance remain to be recorded.
[Task evidence](tasks/apple-auth.md) separates implementation, HTTP stubs, Simulator UI and live evidence.

## Apple Developer and Xcode

Use the Apple Developer Program team intended for C67. In Certificates, Identifiers & Profiles,
select the App ID whose bundle identifier is `io.pibeebee.c67.starter` and enable Sign in with Apple.
If that identifier does not belong to the intended team, resolve ownership before changing either
the app's bundle ID or the server's accepted audiences. Do not invent a new ID as a signing workaround.

The XcodeGen source already declares the capability and
`C67.entitlements` with `com.apple.developer.applesignin = [Default]`. Open C67,
select that team under Signing & Capabilities, and refresh its development provisioning profile.
The project currently retains the signing team selected in Xcode. Put developer-specific
`DEVELOPMENT_TEAM` overrides in ignored Development.local.xcconfig or Production.local.xcconfig. No `.p8` key, Apple password or service-role key belongs in the app.
A successful ad-hoc Simulator build does not prove an Apple-issued signing capability is enabled.

This is the native ID-token flow. A web Services ID, website return URL and OAuth client secret
are not required for it. If adding web OAuth later, configure and maintain that separate flow.

## Supabase on the homelab

The existing service is external Compose `/home/giovan/apps/supabase`, GoTrue v2.197.0. Its Apple
provider was enabled after explicit approval on 28 October 2026. The
[deployment record](homelab-apple-auth-plan.md) covers only:

```yaml
GOTRUE_EXTERNAL_APPLE_ENABLED: "true"
GOTRUE_EXTERNAL_APPLE_CLIENT_ID: "io.pibeebee.c67.starter"
GOTRUE_EXTERNAL_APPLE_SKIP_NONCE_CHECK: "false"
```

The audience must match the signed native bundle. Keep nonce checking enabled. Do not add arbitrary
ID-token issuers or relax audience/signature verification. No schema migration is needed; GoTrue
issues the same authenticated sessions used by existing RLS/RPCs. The approved helper created a private backup and restarted only Auth. Its public settings
endpoint confirms Apple enabled; the ten sibling service lifecycles are unchanged. Do not reapply
the initial helper to an already configured provider; future changes need a new drift review.

## Runtime behavior

Open Account in live mode and choose Sign in with Apple. The user completes Apple's system UI;
passwords and two-factor codes stay with Apple. The app requests email only and supports the private
relay email returned by Supabase. A first Apple login may create an account without a password;
it does not require the email/password confirmation step. The existing email flow remains available.

The Apple nonce and identity token exist only for the current exchange. Supabase access/refresh
credentials use the existing backend-scoped, device-only Keychain store. Apple's user identifier
is stored with that session only for credential-state checks; it is never an RPC owner_id.
Cancellation leaves no error. Invalid/expired/foreign completions fail before exchange. Network or
provider failures show a safe error. Revoked credentials clear the matching local session; transient
credential-state lookup errors do not sign the user out. Standard JWT expiry limitations remain.

Apple Hide My Email may identify a different account from an existing email/password login.
Do not promise automatic trip merging or manually equate accounts based on a claimed email.
No full name is collected because the current traveller model has no profile-name feature.

## Verify

- `swift test --package-path ios-backend`: adapter/session tests use HTTP stubs, not Apple tokens.
- Run the C67 scheme in mock with signed Simulator tests as documented in [native Auth](native-auth.md).
  Apple attempt unit tests cover nonce/state/expiry and missing/invalid token data.
- Live UI opt-in `C67_TEST_LIVE=1` verifies that the native button exists and the email/recovery/
  system callback regressions still work. `C67_TEST_LARGE_TEXT=1` exercises scrolling. The tests
  never press Apple's authorization button or create an Apple account.
- After provisioning, the user verifies real authorization, Hide My Email,
  relaunch/refresh/private data/logout, then revocation in Apple Account settings. Verify session
  clearing on return to the app. Record device/OS, not credentials or tokens.

Sources: [Supabase Apple authentication](https://supabase.com/docs/guides/auth/social-sign-in/auth-apple),
[Supabase native token API](https://supabase.com/docs/reference/swift/auth-signinwithidtoken),
[GoTrue v2.197.0 token verification](https://github.com/supabase/auth/blob/v2.197.0/internal/api/token_oidc.go),
[Apple button](https://developer.apple.com/documentation/authenticationservices/signinwithapplebutton),
[Apple credential-state API](https://developer.apple.com/documentation/authenticationservices/asauthorizationappleidprovider/getcredentialstate(foruserid:completion:)).
