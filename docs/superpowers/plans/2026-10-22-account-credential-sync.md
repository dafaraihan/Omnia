# Account Credential Sync Implementation Plan

> **For agentic workers:** Use the approved spec and this plan. Independent cloud and local-adapter work may run in parallel; the coordinator owns integration. Repository validation policy supersedes automated-test steps.

**Goal:** Restore user-owned credentials, PIN protection, media-server connections and Live TV sources after Omnia sign-in.
**Architecture:** Dedicated authenticated Edge Function encrypts typed entries and playlist chunks; private tables enforce atomic revisions. A serialized account-owned Swift coordinator restores through existing stores and persists pending edits encrypted locally.
**Tech Stack:** SwiftUI, CryptoKit, Keychain, existing Supabase Swift/TypeScript dependencies, Deno Web Crypto, Postgres.
**Spec:** docs/superpowers/specs/2026-10-22-account-credential-sync-design.md (approved).

## Global constraints

- Preserve existing unrelated edits; work on current feature branch and canonical DerivedData, no duplicate app products.
- No automated tests, fixtures, suites or test scripts. No hosted mutations or deployment.
- 256 KiB decoded entry, 1,000 entries/account; 1 MiB wire request, 512 KiB playlist chunks, 64 MiB playlist, 256 MiB attachment quota/account.
- Device copies in Keychain or device-key-encrypted local vault; never log credentials or extend ordinary profile_data with secrets.
- Do not commit or push as part of this task.

## Review focus

- Stale callbacks after A→B account switching must never write A's values into B.
- Missing PIN verifier must remain locked; PIN removal must be explicit.
- Empty fresh install must pull before upload and cannot delete remote entries.
- Failed Keychain apply and partially restored playlist must retain the previous entry.
- Concurrent edits and tombstones must retain local conflicts without resurrecting deletions.

## Interfaces

Wire operations use POST JSON with no-store responses:
- list -> { entries: [{ id, revision, deleted, payload? }] }; payload is base64-encoded entry JSON.
- write { id, expectedRevision, deleted, payload? } -> { entry }; HTTP 409 -> { entry }.
- attachment operations and exact manifest fields are agreed between cloud worker and integrator before integration.

Local adapter `@MainActor CredentialVaultLocalStore(profiles: ProfileStore)` exposes
`capture() throws -> [String: Data]`, `apply(id: String, payload: Data?) throws`,
`clear() throws`, and playlist bytes access for attachments. IDs are
provider.mdblist, provider.anilist, provider.plugin-tmdb, pin.<UUID>,
server.<connectionID>, livetv.configuration, livetv.secrets, playlist.<UUID>.
Posting Notification.Name.credentialVaultDidChange schedules a serialized capture;
remote applies suppress the notification in the coordinator. Values are validated
before mutation; callers own encrypted persistence and account association.

### Task 1: Cloud vault (independent)
- [x] Read approved design, existing function config/locks and migration policies.
- [x] Add private ciphertext tables/RPC with server-only grants, atomic revision CAS, quota/ownership checks and account-delete cascade.
- [x] Add dedicated credential-vault function with verified Auth identity, bounded input/schema, AES-GCM/AAD/key versions and chunk integrity/cleanup.
- [ ] Check with frozen Deno typecheck and local SQL lint when local stack is available. Record unperformed runtime checks honestly.

### Task 2: Native store adapters (independent)
- [x] Add capture/apply/clear API for provider keys, PIN verifiers, media-server connections, Live TV settings/secrets and local playlist data.
- [x] Validate remote types/origins/bounds; rollback partial writes; notify on successful user changes; PIN verifier missing fails closed.
- [ ] Verify with affected platform builds during integration; manual restore/revoke/missing-PIN checks remain required.

### Task 3: Account coordinator and UI
- [x] Add bounded native vault client, wire models and device-key-encrypted account state (revisions, baselines, pending changes, conflicts).
- [x] Add single serialized coordinator with account-generation guards, pull-first/guest adoption, explicit tombstones, CAS conflict handling, attachments and sign-out detachment.
- [x] Integrate startup/account transitions/foreground/edit notifications; restore PINs before locked-profile access; expose progress/errors/retry/conflict choice and sign-out pending warning.
- [ ] Verify stale account completions, offline pending changes, initial restoration and error states manually where runtime access permits.

### Task 4: Review, validation and operations documentation
- [x] Update SECURITY.md, supabase/README.md and INFRASTRUCTURE.md for the new trust boundary, separate secrets, rotation/rollback/deploy gate and old-client limitations.
- [ ] Run Mac and iOS affected builds, frozen Deno checks, local DB lint if available, git diff --check; retain only canonical Mac app product.
- [x] Fresh security/correctness review; fix material findings and repeat affected checks.
- [x] Record evidence and pending device/hosted/accessibility checks. Do not represent local build success as production availability.

## Execution rulings and evidence

- User approved implementation; execute continuously without another plan-approval round.
- Existing branch contains prior user work and the installed canonical build points here; keep this checkout to preserve it. No worktree creation.
- Parallel work is limited to disjoint cloud and native-adapter files with the interface above; integrator owns models/client/coordinator/app/UI/docs.

## Verification record

See [local validation](../../research/account-credential-sync-validation.md).
Mac signed build, frozen Deno and diff checks pass. iOS destination is unavailable
under current macOS-only project settings. SQL lint cannot connect local Postgres.
Native runtime/manual steps above remain unchecked until actually performed.
Subsequent authorized backend activation, rollback-scoped SQL rehearsal and
focused live API/isolation checks are in
[the deployment record](../../research/account-credential-vault-deployment-2026-10-22.md).
Native and backend source review findings were addressed.
