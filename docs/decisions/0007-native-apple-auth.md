# ADR-0007: Native Apple credentials reuse the Supabase session actor

Status: Accepted implementation; homelab provider active; real Apple authorization pending
Date: 28 October 2026

C67 already owns email/password, PKCE email flows and sessions in one SupabaseAuthentication actor.
Apple login uses AuthenticationServices' official native button rather than a web OAuth redirect.
The platform bridge creates an ephemeral nonce/state, sends SHA-256 hex nonce to Apple and passes
the original nonce plus returned identity token to the domain authentication protocol. GoTrue
verifies Apple signature/issuer/audience/nonce and returns the standard Supabase session.

Keep SDK objects in the platform adapter, transport in Data, presentation actions in Presenter,
and shared credential values in Domain. Reuse Keychain persistence, refresh, local logout,
generation guards and server RLS ownership. Store only Apple's user identifier alongside the
Supabase session for credential-state checks; never persist Apple's identity token or raw nonce.
A definitive revocation affects only its matching Apple session; temporary system errors preserve
it, and an old Apple revocation cannot clear a newer email login.

Native-only Apple uses the app's bundle audience and does not require an OAuth client secret,
Services ID or `.p8` signing key. A web flow would require a separate configuration decision.
The app requests email only, so there is no first-authorization name/profile synchronization.
Hide My Email identities and existing email/password users follow GoTrue's verified linking policy;
there is no custom account merge or trip migration.

Capability/entitlement source is XcodeGen. Actual Apple Developer provisioning, shared provider
activation and user authorization are separate gates; source/UI/stub tests do not establish them.
See [setup](../apple-auth.md), [task](../tasks/apple-auth.md) and [deployment plan](../homelab-apple-auth-plan.md).
