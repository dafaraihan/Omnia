# Credential vault deployment — 2026-10-22

## Authorization and verified target

The project owner explicitly authorized: “Deploy the credential vault to Omnia’s
Supabase project.” This covered the additive vault migration, its two new server
secrets, the dedicated function, focused verification and cleanup.

- Project: **Omnia**, `mjblatbeddetccidpogv`, Singapore (`ap-southeast-1`).
- Linked project ref matched the connected Supabase project inventory.
- Database: PostgreSQL 17.6, Supabase build `17.6.1.166`.
- Before deployment: vault tables/function absent; metadata bundle SHA256
  `9cf33ba4895e46d8088b4d9d68f8fecae59f8084ded452bb68b94999b7d506e1`.
- Supabase reported no physical backups and PITR disabled. No existing vault data
  needed restoring. This was an additive first release; existing application
  tables/data were not changed. Rollback retains the new empty/data-bearing
  tables and keys and disables only the new endpoint, rather than dropping data.

## Preflight and recovery evidence

The filename-only working-tree secret scan, frozen Deno check and diff check
passed. The previously recorded signed Mac build passed. No native source changed
in this deployment step. Existing iOS-destination and native UI/device-validation
limitations are in the [local validation record](account-credential-sync-validation.md).

Local Postgres remained unavailable. Instead, the reviewed complete migration was
executed on the verified target inside an explicit transaction with 2-second lock
and 30-second statement timeouts, checked with `plpgsql_check` and privilege/empty-
vault checks, then rolled back. A separate query confirmed both the vault tables
and the cron extension remained absent afterward. This is hosted rollback-scoped
rehearsal evidence, not a claim that local SQL lint passed.

Immutable source snapshots and SHA256 manifests are stored outside the repository
under the owner's private deployment-backup directory. The final deployment
manifest SHA256 is
`7fba79b7b68a4c33306c2a448add2b5537b518795fd89dce944082ffa3c9e6b7`.
The final import map uses exact versions already resolved in the reviewed lock:
`@supabase/functions-js` and `@supabase/supabase-js` at `2.110.9`.

A fresh 32-byte server encryption key was generated without displaying it. Its
AES-GCM-encrypted operational backup was written and decrypted for recovery
verification before any vault data was written. The sealed backup is at
`/Users/dafaraihan/.codex/deployment-backups/Omnia/credential-vault-20261022T140732Z/credential-vault-keys.sealed`.
The separate wrapping key is in the operator's login Keychain, service `Omnia.DeploymentBackups`, account
`mjblatbeddetccidpogv.credential-vault.wrap-v1`. Preserve both the sealed file and
that Keychain item; the file alone cannot recover the key. The dedicated service
is separate from device credential items cleared by an Omnia fresh start.
The temporary plaintext secret input was removed after installation. No secret,
user token, or decrypted credential was placed in repository/evidence files or
printed in tool output.

## Applied release

- Migration: `20261022140828_credential_vault.sql`, applied successfully through
  the connected migration tool. The tool generated its recorded version; the
  local file was renamed to match. SQL bytes match the reviewed snapshot originally
  named `20261022132415_credential_vault.sql`.
- New secret names verified present: `CREDENTIAL_VAULT_KEYS` and
  `CREDENTIAL_VAULT_ACTIVE_KEY`. No existing secret was replaced.
- Function: **credential-vault**, version **1**, **ACTIVE**.
- Function ID: `be0d54d7-d146-4a13-8d73-b3b814abe36b`.
- Activation: **2026-10-22 21:09:46 WIB** (14:09:46 UTC).
- Deployed bundle SHA256:
  `8648e0661b254c7312e74a5a141c8ce617c1ffd52be416ee221d138b7d0cf1aa`.
- Downloaded deployed `index.ts` and `deno.json` exactly match the frozen source.
- `pg_cron` 1.6.4 installed; hourly `credential-vault-expired-uploads` job active.
  A direct cleanup invocation completed successfully with zero rows to remove.
- Metadata code was **not deployed**. Its bundle SHA256, entrypoint and update
  timestamp remained unchanged. Supabase's later listing reported version 41
  (initially 40) after project secret installation; no metadata source was sent.

## Focused live API checks

Two temporary, email-confirmed isolated Auth accounts were created with synthetic
credentials; no email was sent and no existing account was used or modified.
Interactive calls inspected statuses/boolean outcomes without printing tokens,
provider values, PIN verifiers or playlist bytes. No automated test suite,
repository fixture or test script was created/run.

| Check | Observed outcome |
| --- | --- |
| Authenticated empty vault | 200, empty entries, `Cache-Control: no-store` |
| Invalid bearer / publishable-only bearer | 401 / 401 |
| Provider-string write and read | 200 / 200; exact payload round trip, revision 1 |
| Other account reading that entry | 404 |
| Stale expected revision | 409 |
| Authenticated direct table / RPC access | 403 / 403 |
| PIN salt/verifier string write | 200 |
| Playlist begin / chunk upload / commit / download | 200 for each; exact byte round trip |
| Other account fetching the attachment | 400; no data returned |
| Request-selected owner injection | 400 |
| Body larger than 1 MiB | 413 |
| Playlist deletion | 200; tombstone revision 2, no payload |
| Reading retired attachment bytes | 409 |
| Stale deletion | 409 |
| Deleted account's previously issued token | 401 |

Database checks confirmed RLS enabled and anon/authenticated SELECT denied on all
three vault tables; anon/authenticated RPC execution denied; live entries contained
ciphertext envelopes rather than payload fields. Both verification sessions were
revoked (204) and both temporary accounts removed (200). A final query showed zero
verification accounts and zero entries/uploads/chunks; account-delete cascades
removed the synthetic data.

The post-deploy security advisor returned an informational vault notice for RLS
without client policies. This is intentional for these service-only tables;
direct client grants/RPC checks above confirmed denial. No broader project
security settings were changed.

The sampled function-log attributes from the release window showed no server
errors or bearer/secret/synthetic-payload markers. This was an aggregate review of
visible log attributes, not proof about every platform/internal log sink.

## Remaining limits and rollback

Backend deployment and these API/security checks are complete. Real two-device
native restoration, interrupted app writes, Keychain failure/recovery, offline
conflict UX, accessibility and iPhone/iPad checks remain unperformed. No updated
DMG was built, committed or published; old releases lack the new sync client.

On a release regression, disable/remove **only** the new credential-vault endpoint
or deploy a reviewed denial-only replacement, leaving ciphertext, entry tombstones,
key versions and device snapshots intact. Do not drop vault tables, remove server
key versions or change metadata. Re-enable only from the frozen source after the
fault is corrected. The general operator gate remains in
[INFRASTRUCTURE.md](../../INFRASTRUCTURE.md#account-credential-vault-release-gate).
