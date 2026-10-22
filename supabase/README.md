# Omnia Supabase contract

This directory is the deployment boundary for Omnia's cloud data. The Swift app
must never contain a TMDB read token, TVDB API key, TVDB subscriber PIN, or a
Supabase `service_role` key.

## Credential boundary

TMDB and TVDB are shared Omnia services. Their credentials live only in the
Supabase Edge Function secrets (`TMDB_READ_ACCESS_TOKEN`, `TVDB_API_KEY`, and
any required TVDB subscriber PIN); the Apple apps receive only the project's
publishable key.

MDBList and AniList credentials belong to the user, along with any plugin-specific
TMDB key they enter. Live values remain in device Keychain. The dedicated
`credential-vault` function can back them up encrypted for sign-in-only account
restoration; they never enter `metadata` or ordinary `profile_data`. User-facing
provider requests still send keys only to the intended provider origin.

The same vault backs up profile PIN **salted verifiers**, media-server connection
configuration/tokens, Live TV source configuration and credentials, and bounded
imported M3U files. PIN text, Supabase session tokens, shared backend secrets and
local encryption keys never sync. Server-managed encryption means the authorized
Omnia backend can decrypt the vault; account compromise grants access to its
contents. No additional recovery password is required.

The new migration creates private ciphertext entry/upload/chunk tables and a
service-only invoker RPC. There are no anon/authenticated table grants or policies.
The function derives the owner from `auth.getUser`, rejects anonymous sessions,
and uses AES-GCM with account/entry/revision/chunk AAD. Requests are bounded before
JSON parsing; responses are no-store. `verify_jwt=false` relies on this explicit
Auth verification and must never be paired with an unverified JWT decode.

Required **server-only secret names**, never values in repository files:
`CREDENTIAL_VAULT_KEYS` (JSON key-version → base64 32-byte key) and
`CREDENTIAL_VAULT_ACTIVE_KEY` (the version to encrypt new writes). Keep old key
versions while any encrypted entry, attachment or retained backup references them.

The migration requires Supabase's built-in `pg_cron` for hourly bounded orphan/
retired attachment cleanup. Source limits: 256 KiB ordinary entry, 1 MiB request,
1,000 active entries, 2,000 total IDs including retained tombstones, 512 KiB playlist
chunks, 64 MiB per imported playlist, 256 MiB account attachment quota including
ciphertext/base64 overhead. Deleted IDs remain reserved to prevent stale clients
resurrecting entries. Large imports can consume more quota than their plaintext
size. Older apps neither upload nor propagate edits/deletions to this new vault.

**Deployed to Omnia on 2026-10-22:** `credential-vault` version 1 and migration
`20261022140828` are active. See the [deployment evidence](../docs/research/account-credential-vault-deployment-2026-10-22.md).
Future changes still follow the separate
[credential-vault release gate](../INFRASTRUCTURE.md#account-credential-vault-release-gate)
for migration, secrets, deployment, validation and rollback. The existing pending
`metadata` function deployment remains a separate operation.

## Add-on stream boundary

Omnia accepts declarative HTTPS add-on manifests and preserves the documented
stream response data returned for a selected title or episode. That includes a
direct URL, an `infoHash` with optional `fileIdx`, an external URL, filename,
file size, and playback behavior hints.

Only a final HTTPS media URL is passed to AVPlayer. An `infoHash` identifies a
torrent package rather than media bytes, while `fileIdx` selects a file inside
that package; neither is playable by AVPlayer on its own. Omnia can use an
opt-in, user-configured resolver only after the user supplies all of the
following locally: an HTTPS resolver endpoint, a Keychain-only bearer token,
the specific add-on IDs allowed to use it, and exact approved HTTPS stream
hosts. The resolver receives a versioned JSON request with the approved
candidate's add-on ID, stream identifier, info hash, optional file index, and
filename. It must respond with `{ "url": "https://approved-host/..." }`.
Omnia rejects non-HTTPS, credential-bearing, or non-allow-listed final URLs and
does not forward resolver authorization to AVPlayer. Resolver secrets and
settings are not part of cloud library sync.

## What the first migration creates

| Resource | Client access | Purpose |
| --- | --- | --- |
| `profiles` | Own row only | Account identity presented by Omnia. |
| `library_entries` | Own rows only | Cross-device saved, watching, and completed states. |
| `playback_progress` | Own rows only | Resumable playback position, including episode-specific progress. |
| `metadata_records` | None | Shared TMDB/TVDB cache written by the Edge Function only. |

The library and progress tables are added to Realtime for signed-in device sync.
Every table in `public` has RLS enabled; policies use the authenticated user ID
as the ownership boundary.

## Metadata function contract

The authenticated `metadata` Edge Function accepts only POST requests:

```json
{ "action": "search", "query": "The Bear", "type": "series", "language": "en-US" }
```

```json
{ "action": "details", "provider": "tmdb", "id": "136311", "type": "series", "language": "en-US" }
```

Search returns normalized records from TMDB and TVDB. Details reads the server
cache first, refreshes an expired record from the selected provider, and returns
the normalized record plus a `cached` flag.

## Deployment sequence

1. Create or select the Supabase project and link this directory with `supabase link`.
2. In the Dashboard, expose only `profiles`, `library_entries`, and `playback_progress` through the Data API.
3. Configure Apple, Google, and Facebook providers under Auth. Add the exact native URL `omnia://auth-callback` to the Redirect URLs allow list, and keep the `omnia` URL scheme registered in the Apple target's Info.plist. Configure each provider's callback URL from the Supabase Auth provider page; it is not the app's native redirect.
4. Set the server-only secrets with `supabase secrets set --env-file supabase/.env` after creating a local file from `.env.example`. Required: `TMDB_READ_ACCESS_TOKEN`, `TVDB_API_KEY`, and a random `METADATA_SEED_TOKEN`. `TVDB_SUBSCRIBER_PIN` is optional. The hosted runtime supplies `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`; do not place either in the app or `.env`.
5. Run `supabase db push`, then `supabase functions deploy metadata`.
6. Configure the app with the project URL and publishable key only, then manually verify each account provider, a metadata search, a detail request, and a second-device progress update.

Local verification requires Docker because `supabase start`, `supabase db lint --local`, and `supabase functions serve` run the local Supabase stack in containers.
