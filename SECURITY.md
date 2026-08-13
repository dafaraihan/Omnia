# Omnia Security Guide

This document is the authoritative security model, release checklist, and
hardening register for Omnia. It covers the native SwiftUI client, its
AVPlayer/libmpv playback boundary, Supabase Auth and data access, the metadata
Edge Function, user-configured playback resolvers, and untrusted
Stremio-compatible add-ons.

The findings below are from a static repository audit performed on 2026-08-10;
they are not a penetration test or an attestation about the deployed Supabase
project. Reassess this document whenever authentication, entitlements, playback,
add-on networking, dependencies, or the backend contract changes.

## Evidence labels and priority

- **Confirmed** means the cited behavior is present in this repository snapshot.
- **Production verification required** means migrations or local configuration
  express an intent, but the deployed control cannot be proved from source.
- **Proposed hardening** means the control is a requirement or recommendation,
  not a claim about current behavior.
- **P0** blocks a production release; **P1** should be resolved before the next
  release; **P2** is defense in depth or an operational maturity improvement.

## Security objectives

Omnia must prevent one user from reading or changing another user's identity,
library, or viewing history; keep user and provider credentials out of the app
bundle, logs, URLs, and cloud-sync payloads; prevent untrusted add-ons and
resolvers from broadening where credentials or media URLs are sent; and ship
only reviewed, reproducible, signed native code. Availability and provider-cost
abuse are also security concerns because the metadata function is callable with
the deliberately public publishable key.

## Assets and actors

| Asset | Sensitivity and required owner |
| --- | --- |
| Supabase user identity and OAuth session | Private account data. Supabase Auth owns the session; only the signed-in user may act with it. |
| Library entries and playback history | Private behavioral data. RLS must bind every client operation to `auth.uid()`. |
| User-owned provider credentials | MDBList API keys and AniList tokens belong to the local user and must remain in Keychain. |
| Add-on manifest URLs and enabled state | User-selected configuration that can reveal interests and causes requests to an untrusted origin. It must not contain credentials. |
| Resolver endpoint, token, and allow-lists | The endpoint and allow-lists are local configuration; the bearer token is a Keychain-only secret. |
| Backend provider and operational secrets | TMDB/TVDB credentials, the metadata seed token, and the Supabase service-role key are server-only secrets. |
| Supabase URL and publishable key | Public client configuration, not a secret. Its exposure must never grant authorization or unmetered privileged work. |
| Third-party payloads | Add-on manifests/catalogs/streams, provider JSON, artwork, subtitles, and resolver responses are untrusted input. |
| Final media URLs and request headers | Potentially signed or identifying capabilities. Do not persist or log them; send them only to the selected player. |
| Embedded native libraries | libmpv and its dynamic-library closure execute in the app process and inherit the app's privileges. |

Relevant actors are the signed-in user, an unauthenticated client holding the
publishable key, a malicious or compromised add-on, a user-operated or
compromised resolver, metadata providers, Supabase services and operators, an
attacker able to register the custom URL scheme, and a compromised build or
dependency source.

## Trust boundaries

1. **Device to Supabase Auth/Data API.** The app crosses the public network with
   a publishable key and, when signed in, a user access token. The database must
   treat both as untrusted and enforce ownership with RLS. The publishable key
   identifies the project; it does not authorize access.
2. **Edge Function to providers and Postgres.** The metadata function holds
   provider credentials and a service-role key. Because service-role access
   bypasses RLS, request validation, narrow queries, and isolation in the
   function are the authorization boundary.
3. **Device to add-on.** An installed add-on controls its HTTPS origin and all
   returned JSON. Its text, identifiers, artwork, headers, and URLs remain data,
   never executable configuration. Installing an add-on is not permission to
   receive other credentials.
4. **Device to optional resolver.** Only a resolver-required candidate from an
   explicitly approved add-on may cross this boundary. The token goes only in an
   authorization header to the configured HTTPS endpoint. The returned media
   URL must use HTTPS and match an exact approved host.
5. **Playback engine.** AVPlayer or libmpv consumes attacker-influenced media,
   container metadata, subtitles, URLs, and selected headers. This is a native
   parser boundary with memory-safety and supply-chain risk; no scripts,
   external configuration, or downloader integrations should be enabled.
6. **OAuth callback.** The operating system dispatches the custom `omnia` URL
   scheme. Treat every callback URL as attacker-controlled until its routing
   components and the SDK's PKCE/state transaction are verified.
7. **Build and distribution.** Swift packages, Deno modules, Homebrew artifacts,
   signing identities, and release automation cross into trusted application or
   server code. Locks, provenance, review, hardened runtime, signing, and
   notarization are required.

## Confirmed repository controls

- User-owned provider credentials and the resolver bearer token use
  `KeychainStore`; mobile items use `WhenUnlockedThisDeviceOnly`, and no
  synchronizable Keychain attribute is enabled. The resolver endpoint and exact
  add-on/stream-host allow-lists are separate local settings.
- The resolver requires an HTTPS endpoint without URL user information, checks
  the add-on ID before sending data, uses a 20-second request timeout, and checks
  that its returned HTTPS URL has an exact approved host.
- Add-on manifest/resource requests require HTTPS and specify 15- or 20-second
  request timeouts. The app hands final HTTPS media sources to AVPlayer/libmpv;
  magnet and handoff links are not treated as final native playback URLs.
- The plist contains no App Transport Security exception. The built products
  still need release verification because generated or dependency settings can
  alter effective behavior.
- Migrations enable RLS on all application tables. User tables use
  `auth.uid()` ownership predicates; server-managed metadata and discovery
  tables revoke client access and grant access to `service_role`.
- The metadata function reads provider credentials and the service-role key
  from its environment. They are not included in client configuration. It
  returns generic provider failures to ordinary callers and does not return
  upstream response bodies.
- The macOS target enables App Sandbox and hardened runtime. libmpv configuration,
  scripts, console input, auto-profiles, and downloader integration are disabled
  in the player wrapper.
- Swift Package Manager and Deno lockfiles record resolved revisions. This does
  not make the locally copied libmpv dependency reproducible.

## Required controls

### Credentials and authorization

- Store user-owned provider and resolver secrets only in Keychain. Never put
  them in `UserDefaults`, Swift source, plist files, add-on configuration,
  analytics, crash reports, or sync payloads. Do not treat the publishable key
  as confidential or as an authorization check.
- Keep provider credentials, the seed token, and the service-role key only in
  managed Edge Function secrets. The native app must never receive them. Rotate
  a secret after suspected exposure and invalidate affected sessions where
  applicable.
- Enable RLS on every exposed table. Client policies must name the intended role
  and enforce ownership, including both `USING` and `WITH CHECK` for updates.
  Keep service-role operations in a small server-only module and never use them
  on request-selected tables or arbitrary filters.
- Validate an OAuth callback's exact scheme, host, port, user information, and
  path before passing it to the Auth SDK. Require the SDK to validate the active
  PKCE/state transaction. Prefer a claimed HTTPS universal link when deployment
  support makes that possible.

### Network and untrusted input

- Require HTTPS and normal ATS validation for Supabase, providers, add-ons,
  artwork, resolver calls, and final media. Any exception requires a documented,
  host-scoped review; never allow arbitrary HTTP or disable certificate checks.
- Before sending a credential, compare a normalized host to an exact allow-list.
  Do not use suffix or substring matching. Reject URL user information,
  unexpected ports, non-public/local targets where applicable, and credentialed
  redirects to a different origin. Revalidate the final URL after redirects.
- Apply explicit request and response byte limits before JSON decoding. Also
  bound strings, arrays, nesting, image dimensions, concurrent provider/add-on
  requests, redirect count, and decompressed content. Reject unexpected content
  types. Stream large media; do not buffer it as metadata.
- Every request needs a deadline and cooperative cancellation. Edge provider
  calls must use abort signals; UI navigation and playback changes must cancel
  obsolete tasks. A timeout does not replace response-size and concurrency
  limits.
- Keep operational tokens out of URLs, shell history, process arguments, and
  request/response logs. Prefer an authorization header on a separate
  admin-only route over a field in a general-purpose JSON request.

### Diagnostics, dependencies, and distribution

- Diagnostics may record an operation name, status class, provider identifier,
  correlation ID, duration, and bounded counts. Redact authorization headers,
  cookies, OAuth callbacks, query strings, provider payloads, email addresses,
  resolver endpoints, final media URLs, and signed headers. User-facing errors
  must not reveal database or provider details.
- Pin and lock Swift and Deno dependencies; review lockfile changes and run
  dependency/vulnerability scans. libmpv and every bundled dylib require a
  declared version, source, license, cryptographic digest, and reproducible
  acquisition process. Generate an SBOM for release artifacts.
- Ship the minimum entitlements. Verify App Sandbox, hardened runtime, library
  validation, signing identity, nested-code signing, and the absence of debug
  entitlements on the archived app. Notarize and staple macOS distribution
  artifacts, then validate them on a clean machine.
- Audit required-reason APIs and third-party SDK manifests for each Apple
  platform. Include and validate `PrivacyInfo.xcprivacy` when required, and keep
  App Store privacy declarations aligned with actual identity, history, and
  network behavior.

## Hardening register

| Priority | Finding and evidence state | Risk | Required disposition | Exit criterion |
| --- | --- | --- | --- | --- |
| P0 | **OAuth callback validation — Confirmed.** `OmniaAccount.handle(callback:)` accepts any URL whose scheme matches `omnia`; `AppInfo.plist` and local Supabase config identify the intended callback as `omnia://auth-callback`. | Another route using the same scheme, or another app claiming the custom scheme, can feed attacker-controlled callback material to the Auth SDK. | Require the exact normalized routing tuple (`omnia`, `auth-callback`, no user information/port, expected empty path) before SDK parsing, retain PKCE/state validation, add negative tests, and evaluate universal links. | Automated tests on every supported platform accept the canonical route only during an active valid PKCE/state transaction and reject a wrong host, scheme, path, port, user information, missing transaction, or replayed callback. |
| P0 | **Production Auth and data policy — Production verification required.** Migrations contain ownership RLS and local config uses exact redirect URLs, one-hour JWTs, refresh-token rotation, and no anonymous sign-in. No repository evidence proves deployed policies, grants, provider callback allow-lists, or Auth settings match. | Drift can expose identity/history rows or enable callback/session behavior not reviewed here. | Before release, compare the linked production schema and grants with migrations; test cross-user CRUD denial; verify allowed redirects, providers, signup/anonymous policy, token lifetime/rotation, abuse protections, and leaked-password/CAPTCHA controls as applicable. Record dated evidence. | A dated production export matches the reviewed migrations and Auth settings, and an automated two-user/anon test proves each role receives the intended CRUD result while all cross-user and server-table access attempts are denied. |
| P0 | **libmpv supply-chain reproducibility — Partially remediated, release evidence pending.** A pinned HTTPS/digest manifest, confined extractor, deterministic arm64/x86_64 source builder, universal artifact verifier, exact license staging, and SPDX 2.3 SBOM are present. Release staging rejects pending manifest review and does not use the Debug Homebrew fallback. A second clean builder, independent provenance/license approval, vulnerability scan, reproducibility comparison, archive inspection, and legal approval are not yet recorded. | Different or compromised builders can still ship unsafe native code if the human/CI review gates are bypassed or falsely approved. | Independently review every pinned source and license, build the same inputs on two clean controlled builders, compare the complete pre-signing artifact inventory, scan the SBOM, and inspect the signed archive. Keep strict manifest review fail-closed. | Two clean CI builds from the same pinned inputs produce the same recorded hashes for libmpv and every bundled dylib; the release SBOM lists that closure and the vulnerability scan has no unaccepted applicable critical/high finding. |
| P1 | **`allow-jit` entitlement — Removed in source; archive verification pending.** The pinned mpv profile disables Lua, JavaScript, external scripts, and C plugins. The source entitlement no longer grants JIT or executable-memory exceptions, and a release verifier rejects JIT, unsigned executable memory, disabled page protection/library validation, dyld environment variables, and `get-task-allow`. | A signing/configuration override could still reintroduce a forbidden entitlement in the effective archived app. | Keep the source and strict release gate, run the supported playback suite, then inspect the effective entitlements extracted from the signed archive. | The removal branch closes when the archived app's extracted entitlements omit `com.apple.security.cs.allow-jit` and all other forbidden executable-memory/library-validation exceptions, and the release playback suite passes. |
| P1 | **User-script build sandbox — Confirmed.** `ENABLE_USER_SCRIPT_SANDBOXING = NO` is set for Debug and Release on the app target to run the libmpv embedding phase. | The build script has broader access during builds, increasing dependency and CI compromise impact. | Make script inputs/outputs complete and enable sandboxing, or isolate native-library packaging in a separately reviewed, least-privileged build job with immutable inputs. Do not silently retain the exception. | `xcodebuild -showBuildSettings` reports `ENABLE_USER_SCRIPT_SANDBOXING = YES` for Debug and Release and a clean archive succeeds, or CI evidence proves the isolated packaging job can read only declared immutable inputs and write only its declared artifact. |
| P1 | **Publishable-key endpoint abuse and rate limiting — Production verification required.** The metadata function intentionally accepts user or publishable authentication and can trigger provider requests and service-role cache writes. No application-level quota is present; gateway/WAF limits are not repository-verifiable. | Anyone can extract the key and amplify provider cost, exhaust quotas, or cause avoidable database writes. | Enforce per-IP/device/account and global budgets at the gateway, cap concurrency and expensive actions, cache/coalesce requests, monitor cost/error anomalies, and test 429/fail-closed behavior. Never attempt to solve this by hiding the publishable key. | A production-equivalent load test using only the publishable key crosses every configured per-client and global threshold, receives bounded `429` responses, causes no provider/cache work after rejection, and triggers the documented alert. |
| P1 | **Operational seed-token transport — Confirmed.** Seed, status, and reindex actions accept `seed_token` inside the JSON body of the same publishable function and compare it with an environment secret. Invocation tooling and log redaction are not documented. | General endpoint exposure and unsafe operator tooling can leak a high-impact operational capability; detailed seed errors can reveal internals. | Move operations to a separate admin-only function, accept short-lived authorization in a header, use timing-safe verification where supported, prohibit URL/CLI-argument transport, redact logs, return generic external errors, rotate the current token during rollout, and audit use. | Publishable/user requests and invalid or expired admin credentials cannot invoke any operational action; a valid short-lived admin header can, and captured commands, URLs, responses, platform logs, and audit records contain no token value. |
| P1 | **Query-string provider credential — Confirmed.** The MDBList client sends the user's API key as the `apikey` query item because of the provider API contract. | Full URLs commonly appear in proxy, cache, metrics, crash, and diagnostic records even over HTTPS. | Use an authorization header if the provider supports it. Otherwise use an ephemeral URL only for the request, disable caching, never persist or log it, redact query strings everywhere, and document the provider constraint. | An instrumented request test proves the credential is sent in a header with no secret query item when supported; otherwise cache, proxy, application, analytics, and crash-log tests show the ephemeral URL is not retained and every recorded URL has its query redacted. |
| P1 | **Response-size bounds — Confirmed gap.** Add-on, resolver, Supabase metadata, and user-managed provider clients use whole-body `URLSession` APIs without explicit byte caps. The Edge Function calls `req.json()` and provider `response.json()` without explicit body limits or abort deadlines. Some add-on/resolver requests have timeouts, but metadata/provider clients and Edge fetches rely on defaults. | A malicious or oversized response can consume memory/CPU; slow requests and unbounded fan-out can degrade availability and cost. | Add shared bounded loaders, preflight `Content-Length` when trustworthy, enforce streaming byte ceilings and decode limits, add deadlines/abort signals, bound concurrency, and test oversized, compressed, deeply nested, slow, and cancelled responses. | Automated client and Edge tests reject bodies above each documented compressed/decompressed limit, excessive nesting/collections, too many redirects, and slow responses within the deadline; cancellation tests end the underlying work while valid boundary-size responses succeed. |
| P1 | **Privacy manifest and API-use audit — Confirmed gap / production verification required.** No `PrivacyInfo.xcprivacy` is present in the repository. Whether current code and resolved dependencies require declarations must be checked against the release SDK and App Store requirements. | Missing or inaccurate declarations can block release and obscure sensitive-data/API use. | Inventory required-reason APIs and SDK manifests on every release archive; add/merge a valid manifest when required; verify privacy labels cover account data, library/history, and third-party network requests. | Each platform's release archive passes the current Xcode privacy report/validation with no unexplained API or SDK entry, and a dated review maps the effective manifest and store disclosures to the recorded data/network inventory. |
| P1 | **Root ignore coverage — Confirmed gap.** The root `.gitignore` ignores only `.worktrees/`; Supabase-local rules ignore its `.env` variants, but root and other feature directories lack equivalent secret/config patterns. | A developer can accidentally stage credentials outside `supabase/`. | Add narrow repository-wide ignores for local environment files, signing material, generated secret configs, and credential exports while preserving reviewed examples. Add secret scanning in pre-commit/CI; do not rely on ignore rules as the only control. | `git check-ignore -v` matches a documented fixture for every prohibited secret/signing pattern without hiding reviewed examples, the tracked-tree scan is clear, and a CI test containing a synthetic secret is rejected. |
| P1 | **Dependency scanning — Confirmed gap.** Swift and Deno lockfiles exist, but no repository dependency-update or vulnerability-scanning workflow was found. Deno import constraints permit compatible upgrades before lock resolution. | Known vulnerable or unexpectedly updated dependencies can reach trusted client/server code. | Add automated Swift/Deno/native dependency review and vulnerability scanning, fail release on unresolved applicable critical/high findings, and require human review for lockfile and native binary changes. | CI scans Swift, Deno, and native SBOM inputs on every dependency change, a synthetic known-vulnerable fixture makes the gate fail, and the release report contains no unaccepted applicable critical/high finding. |
| P0 | **Private vulnerability reporting — Production verification required.** This guide designates GitHub **Security > Advisories > Report a vulnerability** as the required private route, but repository-setting enablement and unauthenticated external availability were not verified by this audit. | Without a working private route, reporters may disclose credentials or exploitable detail publicly, and maintainers cannot reliably coordinate containment. | Before any public distribution, enable private vulnerability reporting and GitHub Security Advisories, assign an owner and backup, rehearse secret/session rotation, and publish the process below. | From an external account with no repository access, a reporter can open **Security > Advisories > Report a vulnerability**, submit a synthetic report, and the assigned maintainers receive it privately; dated evidence records the test and a second maintainer confirms ownership. |

Each row's exit criterion is independent and mandatory. Closing a register item
requires the specified observable result, a code/config change where applicable,
fresh release evidence, and an update to this table. Do not mark
production-verification items complete from local configuration alone.

## Pre-release security verification

Record the date, release commit, operator, environment, commands, and unredacted
evidence location for each release. Keep evidence access restricted; do not paste
tokens or user data into tickets.

- Run the full application build and test suite for every supported Apple
  destination. Exercise sign-in/callback rejection, sign-out, add-on installation,
  hostile/oversized add-on JSON, resolver host denial, request cancellation, and
  AVPlayer/libmpv playback with malformed media.
- Inspect the archived entitlements and signature with `codesign`; verify App
  Sandbox, hardened runtime, library validation, and least privilege. Test removal
  of `allow-jit`. Validate every nested dylib, run `spctl` assessment, notarize,
  staple, and test the packaged artifact rather than only the build-directory app.
- Generate a release SBOM; verify Swift/Deno locks and pinned libmpv/dylib hashes;
  run dependency and native-binary vulnerability scans; review every new license
  and dependency diff.
- Apply migrations to an isolated environment, run database lint/advisors, and
  test as anon, user A, user B, and service role. Confirm user A cannot read or
  mutate user B's profile, library, or progress, and clients cannot access
  server-managed tables. Then repeat the configuration checks against production.
- Verify production OAuth redirect allow-lists and providers, PKCE/state failure
  cases, signup/anonymous settings, token expiry/rotation, session revocation,
  and any account-deletion flow. Do not assume `supabase/config.toml` is deployed.
- Exercise metadata quotas and concurrency limits with publishable and user
  authentication; verify bounded 429 responses, provider/cache cost controls,
  generic errors, alerting, and that operational routes reject ordinary clients.
- Search tracked files and release artifacts for credentials, private keys,
  authorization headers, signed URLs, OAuth callbacks, and query-string API keys.
  Inspect symbols, plist files, logs, crash reports, source maps, and build output;
  allow only the documented Supabase URL and publishable key.
- Validate ATS, redirect handling, exact resolver/callback host checks, response
  size/decompression limits, content-type rejection, redacted diagnostics, and
  the effective privacy manifests in each release archive.

## Reporting a vulnerability

Do **not** open a public issue containing credentials, personal data, working
exploit details, private add-on/resolver URLs, signed media URLs, or provider
payloads.

The required private mechanism is GitHub **Security > Advisories > Report a
vulnerability**. Its enablement is **unverified and P0 before public
distribution**. Maintainers must enable private vulnerability reporting and
verify the route from an external account before release.

If the **Report a vulnerability** button is absent, do not send sensitive details
through an issue, discussion, pull request, commit, or other public channel. A
reporter may post only a generic request that private reporting be enabled, with
no vulnerability details or identifying artifacts. Maintainers must enable and
verify the required GitHub route before asking the reporter to continue; there
is no approved public fallback for sensitive material.

Include the affected commit/version and platform, impact, minimal reproduction,
prerequisites, and suggested mitigation. Redact all real tokens and personal
data; use test accounts and synthetic URLs. Maintainers should acknowledge the
report within three business days, establish a private remediation channel,
rotate or revoke exposed credentials/sessions immediately, preserve restricted
evidence, coordinate a release and disclosure timeline, and credit the reporter
if requested. Public disclosure should wait until affected users can update and
must never include live secrets.
