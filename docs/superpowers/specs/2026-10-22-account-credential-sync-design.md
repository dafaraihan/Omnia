# Account credential restoration

Status: approved by user; source implemented and backend deployed with explicit
owner authorization on 2026-10-22. Native/device validation remains pending; see
the validation and deployment records.

## Intent and chosen approach

After signing into the same Omnia account on a fresh Mac, iPhone, or iPad,
restore provider credentials, profile PIN protection, media-server connections
and tokens, and Live TV sources and credentials. No additional vault password,
recovery key, or existing-device approval is required.

The user selected sign-in-only restoration. The proposed implementation uses a
server-managed encrypted vault. Omnia's authorized backend can decrypt it;
this is not end-to-end encryption. Account compromise also grants access to
restorable credentials. App copies remain in device Keychain.

Alternatives considered:

- End-to-end encrypted vault: hides secrets from the backend, but requires
  recovery material or another device. User chose sign-in-only restoration.
- Plain JSON in existing profile_data: simpler, but exposes secrets through
  ordinary table access and database exports. Rejected in favor of a dedicated
  encrypted boundary.

## Current evidence and boundaries

ProfileDataSync already syncs settings, layout, collections, add-ons, plugins,
library and watch statistics through owner-scoped profile_data. Provider keys,
profile PIN verifiers, media-server tokens and Live TV secrets are Keychain-only.
Live TV configuration is local. ProfileStore currently accepts a locked profile
when its local PIN verifier is missing; the new restoration flow must fail closed.
OmniaApp currently ignores sign-out for sync and launches independent sync tasks;
credential sync needs explicit account ownership and cancellation.

Existing add-on payloads may contain private URLs. This change must not add new
credential values to profile_data or silently broaden unrelated payloads. Shared
TMDB/TVDB backend secrets, Auth refresh tokens, signing keys and local encryption
keys are never part of the new vault.

## Vault contents and ownership

One logical vault belongs to the authenticated Omnia account. It contains versioned
entries, each with a stable typed identifier and revision:

- User-entered provider secrets: MDBList, AniList, and the plugin TMDB key.
  The plugin key is user-owned, distinct from the server's TMDB credential.
- Profile PIN salt and verifier, keyed by viewer-profile UUID. Never the PIN text.
- Media-server connection configuration and its bearer token, keyed by connection ID.
- Live TV configuration, playlist/guide URLs, Xtream credentials and Stalker portal
  settings. Imported local M3U file bytes sync as a bounded source attachment;
  device paths and security-scoped bookmarks do not. Remote URLs re-fetch normally.

Provider credentials, media servers and Live TV retain their current device-wide
semantics within one signed-in account. PINs remain per profile. Account switching
must swap these values; it must not merge account A's credentials into account B.
No cached channels, EPG, artwork, downloaded media or playback caches are uploaded.

## Cloud boundary

Add a dedicated credential-vault Edge Function, separate from metadata, and a
forward-only migration for a private ciphertext table. The function validates
an authenticated user session against Supabase Auth and derives ownership from
that identity; a request cannot choose an owner. Anonymous and publishable-key-only
calls are rejected. Use the existing pinned Supabase dependency where compatible;
no new external crypto dependency is proposed.

Use authenticated encryption through Web Crypto AES-256-GCM, a fresh random
96-bit nonce for each write, and additional authenticated data binding account ID,
entry ID, schema version and revision. Store ciphertext, nonce, key version,
revision and server timestamps; do not store plaintext credential payloads.
The encryption key is supplied only as a dedicated versioned Edge Function secret,
with a documented rotation and backup procedure. It never reaches clients.

The ciphertext table has RLS enabled and no anon/authenticated grants or direct
client policies. Narrow server-only operations always filter by the verified user.
A database operation enforces revision comparison atomically. The account foreign
key cascades deletion. Do not expose a general-purpose decrypt API or request-
selected database identifiers. Bound request sizes, item counts, attachment sizes
and per-user storage; streamed size enforcement precedes JSON parsing.
Use a 256 KiB decoded limit for an ordinary entry, 1,000 active entries per account,
and a 1 MiB raw request limit. Preserve the existing 64 MiB local-playlist import
limit using a separate private ciphertext attachment store, with 512 KiB plaintext
chunks and a 256 MiB attachment quota per account. Each chunk has a fresh nonce and
AAD also binding attachment ID, generation and chunk index. The same authenticated
function mediates bounded chunk access; clients have no direct storage grants.
Publish a manifest only after every chunk is present; restore and validate every
chunk before atomically replacing the local file. Retain the prior complete
attachment on failure. Garbage-collect orphaned uploads after a bounded retention
period; tombstones invalidate manifests before blob cleanup. Limits include encoded
size overhead. Attachments use per-entry revisions with their owning source.

HTTPS requests use cancellation, finite timeouts and no credential-bearing
redirects. Vault responses use no-store caching headers. Logs contain operation
and generic error categories only, never payloads, tokens, PIN verifiers or URLs.

## Native restoration and conflict behavior

A single account-scoped coordinator owns fetch, apply, edits and upload, rather
than independent UI tasks. Capture account ID and generation before each request;
recheck them before every local write. Serialize apply and local changes.

On sign-in, pull first. Remote entries win for matching IDs on a newly bound
device; local entries absent remotely are uploaded only when they belong to that
same account or to a first-time guest setup adopted by signing in. Signing in itself
authorizes this initial backup; explain it in the account screen rather than adding
another import prompt. For an existing account, remote values win matching IDs.
A previously bound account's data is never adopted by another account. An empty
fresh install cannot erase remote data. Missing data and explicit deletion are
different: deletion creates a revisioned tombstone. An offline edit remembers its
base revision; stale writes are rejected and refreshed, never blindly retried as
an overwrite. Preserve the rejected local entry as an encrypted pending conflict,
continue with the remote value, and show a category-level conflict in account sync.
The user can keep the account copy (discard the pending local change) or keep this
device's edit (submit it against the freshly fetched revision). Never silently
throw away the pending edit. Unrelated entries can still sync independently.

Persist pending changes locally under account identity using device-only encryption.
After success, write secrets into Keychain and configuration into existing stores;
validate decoded payloads and connection origins before accepting them. Stage and
validate a complete entry before applying it, retain the prior local entry if
Keychain or disk persistence fails, and suppress change observers during remote apply.

On sign-out or account change, cancel requests and detach the outgoing account's
live credentials/configuration before activating guest or another account. Preserve
its encrypted local snapshot and pending edits for that account only. Reuse existing
local vault facilities where possible; never place decrypted secrets in defaults.

Restore profile PIN verifiers before allowing locked-profile entry. Missing or
failed restoration leaves the profile locked with retry/account recovery. Sync the
existing salted verifier in v1; PINs protect profile selection, not the Omnia account,
and are low-entropy even when salted. PIN changes and removal propagate explicitly.

## User-visible states

Show account restoration progress and success/failure in the existing account/sync
surface. During initial restoration, dependent credential actions remain disabled.
Empty remote vault means no saved credentials, not an error. A provider's rejected
or expired token affects that connection only and offers reconnect. Offline startup
uses this account's validated local copy; a fresh offline install offers retry.
Partial entry failures preserve successful entries and identify categories needing
retry without exposing secrets. Sign-out warns if pending edits have not uploaded.
A locked profile never becomes accessible just because its verifier is unavailable.

## Compatibility and rollout

Retain existing non-secret profile sync and Keychain account names where safe.
Update SECURITY.md, the Supabase contract and infrastructure guidance to distinguish
local Keychain storage from encrypted account backup. Older apps keep their current
behavior and do not write the new vault; deletions and secret edits made only in an
older app are not synchronized and must be documented as a version limitation.

Prepare source, migration, dedicated secret-name documentation and a local validation
record first. No hosted mutation is authorized by this feature request. Migration,
secret installation and function deployment require the explicit release gate in
INFRASTRUCTURE.md. Keep the existing pending metadata deployment separate.
Rollback disables vault sync and returns to device-local credentials, retaining
ciphertext and encryption keys for recovery; never drop vault data or lose key
versions as part of rollback. A new DMG is a separate release step.

## Acceptance and validation

Follow AGENTS.md: no automated tests, fixtures, suites or test scripts. Use affected
Mac and iOS builds, frozen Deno checks, local database lint and focused manual flows.
Verify fresh sign-in restoration on two devices, every secret category, local M3U
restoration, PIN lock/change/removal, revocation/reconnect, offline pending edits,
concurrent edits/deletions, partial Keychain failure, sign-out during requests,
A-to-B account switching, oversized/malformed requests and two-account isolation.
Inspect ciphertext and grants without printing secret values. Confirm logs and
ordinary profile_data contain no newly introduced secrets. Verify changed UI with
the accessibility and platform checks in DESIGN.md. Production availability and
real-device evidence remain explicitly pending until performed.

Builder choices: exact entry schema, coordinator seams, UI wording and rotation tooling.
Initial guest adoption and conflict policy above are implementation proposals, not
additional user-selected requirements. Preserve stable entry
identities and revision semantics across those choices.

References: SECURITY.md, supabase/README.md, INFRASTRUCTURE.md and DESIGN.md;
Supabase [function authentication](https://supabase.com/docs/guides/functions/auth)
and [function secrets](https://supabase.com/docs/guides/functions/secrets).

Design review: a fresh builder review identified guest adoption and conflict
resolution as the two missing decisions. Both are now specified above. No product
code, migration, secret or hosted state was changed during the design step.
Implementation and evidence are recorded separately in
[the validation record](../../research/account-credential-sync-validation.md).
