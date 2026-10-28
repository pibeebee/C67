# Task: Native Sign in with Apple

Status: Implemented; live Apple sign-in recorded; device lifecycle acceptance remains
Owner: Giovan
Branch: gi/trip-graph (consolidated from gi/ios-auth-api)
Updated: 28 October 2026

## Scope

Giovan requested Apple Account authentication on top of the existing email/password session work.
Use native AuthenticationServices and the same Supabase session actor, Keychain, refresh, logout
and private-response isolation. Keep the existing bundle identifier `io.pibeebee.c67.starter`.
The initial request authorized implementation. On 28 October Giovan separately authorized
committing, pushing and opening a review PR; merging remains a separate action.

## Implemented

- The official SignInWithAppleButton on the live Account form; hidden in mock mode. Native black/
  white styles follow the environment. Email scope only; names are not requested or stored.
- A fresh cryptographically random nonce and request state per attempt. Apple receives SHA-256
  hex of the nonce; GoTrue receives the original nonce with the identity token. Completion checks
  state, a five-minute lifetime, nonempty user/token and UTF-8; consumes the attempt before exchange.
  Dismissal clears the attempt, cancellation is quiet, duplicate/late callbacks are ignored.
- `POST /auth/v1/token?grant_type=id_token` with provider=apple. GoTrue is responsible for Apple
  signature, issuer, audience and nonce verification. No client-side JWT decoding establishes trust.
- Sessions use the existing Keychain and generation guards. Apple identity token/nonce are not
  persisted. An optional Apple user identifier survives refresh for local credential-state checks;
  old email-only session records remain decodable. Server ownership remains the Supabase user UUID.
- Restore/foreground and Apple's credential-revoked notification check credential state. Definitive
  revoked/not-found/transferred results clear only the matching Apple session and revoke its local
  refresh session. Temporary Apple errors preserve the session. Email sessions are unaffected.
- Typed provider-disabled/invalid-credential errors, plus existing rate-limit/server behavior.
- The Apple entitlement and Xcode capability in project.yml and regenerated project.

## Verification

Package HTTP-stub tests: **34 passed**, including Apple wire payload, session persistence without
identity token/nonce, refresh identity, matching/foreign revocation, email-session isolation,
provider error mapping and late-exchange-after-logout rejection. These are adapter tests, not a
real Apple identity-token signature/nonce acceptance test.

Simulator: iPhone 18 Pro / iOS 27.0, Xcode 27.1. Full mock scheme: **15 passed, 4 intentionally
skipped** (isolated provider, shared cohort and two live UI opt-ins). It includes native SHA-256/
state/expiry/token-validation tests and revoked-vs-temporary-error session checks.
Final live UI run: **3/3 passed** with Accessibility XXXL text. It verifies the official Apple
button is present and email signup/recovery plus system callback rejection remain functional.
Screenshots were exported and inspected. The UI tests do not press the Apple authorization button,
exchange a real Apple token or submit email. See [verification](../verification.md).

Read-only homelab preflight: GoTrue v2.197.0 healthy, external Compose project `supabase`, Apple
provider/client IDs were unset at preflight. After explicit approval, the three reviewed settings
were applied and only Auth restarted. Public settings HTTP 200 confirms Apple and email enabled.
Auth is healthy and ten sibling service IDs/start times are unchanged. Backup checksums and private
permissions passed; .env and tunnel Compose are byte-identical to their backups.
Backup: `/home/giovan/backups/c67/before-apple-auth-2026-10-28T061902Z`. No database operation was issued.
No matching local provisioning profile
for the C67 bundle was found; no Apple Developer portal registration/permission change was made.
The [deployment record](../homelab-apple-auth-plan.md) retains the approved scope and rollback steps.

## Remaining acceptance

1. Confirm distribution provisioning for the intended Apple Developer Program team. Xcode now
   shows the selected team and Sign In with Apple capability; the portal itself was not inspected.
2. Provider configuration and `/auth/v1/settings`/Auth health verification are complete.
3. Record device/OS and complete Hide My Email, relaunch, refresh, private-trip access, logout
   and credential revocation acceptance on a signed supported device. Do not supply Apple
   passwords, verification codes or identity tokens to agents/logs. The user completes authorization.

Account linking follows GoTrue's verified identity policy. Hide My Email can create a distinct
Supabase account from an existing email/password account; no custom merge or trip migration is
implemented. Native Apple sign-in does not require a web Services ID, `.p8` key or six-month OAuth
client-secret rotation. Web OAuth, account deletion and transfer migration are separate scopes.

See [Apple setup](../apple-auth.md) and [ADR-0007](../decisions/0007-native-apple-auth.md).

## Subsequent live observation and review authorization

After Giovan reported signing in, a read-only transaction on the primary homelab database at
14:56 WIB on 28 October confirmed an Apple identity with a 14:49 WIB sign-in, one session and
one trip owned by that account. No password, token or complete email was inspected or recorded.
This confirms backend acceptance of the user-driven sign-in, not a complete device lifecycle test.
The user subsequently authorized commit, push and a review PR for the consolidated changes.
