# Infrastructure and Operations

> **Automated-validation policy:** Follow the repository-root `AGENTS.md`. Instructions below that call for automated test targets, suites, fixtures, or scripts are historical and superseded; use builds, static checks, and focused manual evidence instead.

This document is the operational source of truth for Omnia's Apple clients and
Supabase backend. It describes the repository snapshot as of 2026-08-10. It is
not evidence that a setting exists in a hosted project or that a deployment has
run.

Some evidence below comes from the current working snapshot rather than this
documentation branch's committed history. In particular,
`Omnia/Platform/Playback/embed-libmpv.sh`, the TVDB identifier helper/tests,
`OmniaTests/`, and the modified metadata function are not all present in the
branch history. Final integration must ship those prerequisites together with
this guide and verify them from one reviewed commit; documentation must not be
used as evidence that uncommitted application work was integrated.

## Runtime topology

```text
+------------------+     +-------------------+
| SwiftUI clients  +---->+ Supabase Auth     |
| iOS / iPadOS /   |     +-------------------+
| macOS            |
| local library +  |     +------------------------+     +--------------+
| progress state   +---->+ metadata Edge Function +---->+ cache tables |
+---+-----------+--+     | service-role writes    |     | + RLS        |
    |           |        +-----------+------------+     +--------------+
    |           |                    |        |
    |           |                  TMDB     TVDB
    |
    +--> user-managed MDBList / AniList APIs (credentials stay in Keychain)
    +--> HTTPS Stremio-compatible add-ons
           |
           +--> direct HTTPS media --------------------+
           +--> HTTPS ISO -- explicit macOS prepare ---+
           +--> info hash --> macOS local resolver ----+--> completed cache input --> player
                                                         macOS: libmpv
                                                         iOS/iPadOS: AVPlayer

CloudLibrarySync (implemented, not composed into app state)
    +--> Postgres library/progress tables + RLS
           +--> Realtime publication in migrations (no app subscriber)
```

- The SwiftUI app currently uses the Supabase publishable configuration for
  Auth and the `metadata` Edge Function; library and progress state remain
  local. `CloudLibrarySync` implements reads and upserts for `library_entries`
  and `playback_progress`, but no composition root creates it, no client code
  accesses `profiles`, and no Realtime subscription is implemented. Migrations
  declare the user-table RLS and Realtime publication; hosted state remains
  unverified.
- The Edge Function is the shared-credential boundary for TMDB and TVDB. It
  normalizes provider data and writes the service-role-only metadata and
  discovery caches. The app must never call those providers with shared Omnia
  credentials.
- MDBList and optional AniList account access are user-managed, direct client
  integrations. AniList public discovery needs no credential. Personal tokens
  remain on the device in Keychain.
- Stremio-compatible add-ons are external HTTPS systems selected by the user.
  Direct HTTPS media can go to the platform player. An info hash is not media.
  On macOS Release, the opt-in local resolver validates the hash, tracker hints,
  selected index, filename, size, cache path, and capacity before peer activity.
  It downloads into the sandboxed cache and gives libmpv only a completed local
  regular file or a validated single-root BDMV directory. BDMV selection is
  bounded by the same quota and reserve, a 10,000-entry metadata ceiling, safe
  relative paths, exact aggregate bytes, and a completion manifest. Legacy
  remote-resolver credentials are inert and removable.
- An HTTPS ISO is never autoplayed. On macOS, explicit preparation requires a
  positive exact length within the configured resolver quota, accepts at most
  five same-origin HTTPS redirects, streams the image into an atomic cache job,
  validates the completed cache boundary, and gives libmpv only the typed local
  Blu-ray device plus `bd://longest`. An opaque extensionless HTTPS source may
  use the same explicit operation. Encrypted Blu-ray and DVD remain unsupported;
  the separately reviewed mobile phase is paused.
- macOS links and embeds libmpv; iOS and iPadOS use AVPlayer. The macOS build
  phase copies libmpv plus its non-system Homebrew dynamic-library closure,
  rewrites install names to `@rpath`, and signs the nested libraries before the
  app wrapper is signed. This describes the current working-snapshot
  `embed-libmpv.sh` and project changes, not a prerequisite already present in
  this documentation branch's history.

## Environment and configuration ownership

Omnia currently has one app configuration shape and no checked-in
per-environment build settings. Whether a worktree is linked to a hosted
project is operational state and is not inferred from source. Treat
`supabase/config.toml` as local CLI/emulator configuration only. Its ports,
Auth redirects, `verify_jwt`, database version, and other values do not prove
the corresponding hosted settings. Verify hosted configuration in the
Supabase Dashboard and CLI before every release.

| Configuration | Owner and location | Commit policy |
| --- | --- | --- |
| Supabase URL and publishable key | Release engineering; `AppInfo.plist` today | May be in the app because both values are public client configuration. Do not print the checked-in value in logs or operational docs. Use per-environment build settings before adding another environment. |
| App identity, versions, platforms, signing, entitlements, package requirement | Apple release engineering; `Omnia.xcodeproj/project.pbxproj`, `Omnia.entitlements`, and Xcode settings | Commit intentional project settings. Never commit signing certificates, private keys, or provisioning-profile material. Keep `Package.resolved` committed. |
| Local Supabase services | Backend engineering; `supabase/config.toml` | Commit reproducible local defaults. Do not treat them as hosted truth. |
| Database schema and access policy | Backend engineering; ordered files in `supabase/migrations/` | Commit migrations. Never edit a migration already applied to a shared environment; add a forward migration. Review RLS, grants, Realtime publication changes, and destructive SQL. |
| Edge Function dependencies | Backend engineering; `supabase/functions/metadata/deno.json` and `deno.lock` | Commit both. Update the lock intentionally and review dependency changes. |
| Shared provider and operational secrets | Backend operator; Supabase Edge Function secrets | Never commit values. Required names are `TMDB_READ_ACCESS_TOKEN`, `TVDB_API_KEY`, and `METADATA_SEED_TOKEN`; `TVDB_SUBSCRIBER_PIN` is optional. The hosted runtime supplies `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`. |
| Local secret input | Individual operator; `supabase/.env`, copied from `.env.example` | Never commit `supabase/.env`. Commit placeholder names only in `.env.example`; check staged changes before every commit. |
| User-owned provider credentials | User/device; Apple Keychain | Never commit, log, sync through Supabase, or store in UserDefaults. This includes the MDBList key, optional AniList token, and resolver bearer token. |
| Resolver endpoint and allow-lists | User/device preferences | Not secrets, but device-local by design. Do not promote them into shared cloud configuration without a separate security review. |

Before committing configuration, run a filename-only scanner over both the
staged index and the non-ignored working tree (including untracked files). The
scanner must never print matching values:

```bash
set -euo pipefail
secret_pattern='(SUPABASE_SERVICE_ROLE_KEY|TMDB_READ_ACCESS_TOKEN|TVDB_API_KEY|TVDB_SUBSCRIBER_PIN|METADATA_SEED_TOKEN)"?[[:space:]]*[:=][[:space:]]*"?[[:alnum:]/+_.-]{16,}|eyJ[[:alnum:]_-]{20,}\.[[:alnum:]_-]{20,}\.[[:alnum:]_-]{20,}|OMNIA_SECRET_SCAN_SENTINEL_[[:alnum:]_-]+'
scan_tmp="$(mktemp -d)"
scan_staged="$scan_tmp/staged-files"
scan_working="$scan_tmp/working-files"
scan_hits="$scan_tmp/suspect-files"

cleanup_scan() {
  rm -f -- "$scan_staged" "$scan_working" "$scan_hits"
  rmdir "$scan_tmp" 2>/dev/null || true
}
trap cleanup_scan EXIT

scan_staged_names() {
  local scan_status
  if git grep --cached -Il -E "$secret_pattern" -- \
    ':(exclude,glob)**/*.example' ':(exclude)INFRASTRUCTURE.md' \
    > "$scan_staged" 2>/dev/null; then
    return 0
  else
    scan_status=$?
  fi
  if [[ "$scan_status" -eq 1 ]]; then
    return 0
  fi
  printf '%s\n' 'Staged secret scan failed; aborting without displaying matches.' >&2
  return "$scan_status"
}

scan_working_names() {
  local scan_status
  if rg -l --hidden -e "$secret_pattern" \
    -g '!.git/**' -g '!.worktrees/**' -g '!.superpowers/**' \
    -g '!**/*.example' -g '!INFRASTRUCTURE.md' . \
    > "$scan_working" 2>/dev/null; then
    return 0
  else
    scan_status=$?
  fi
  if [[ "$scan_status" -eq 1 ]]; then
    return 0
  fi
  printf '%s\n' 'Working-tree secret scan failed; aborting without displaying matches.' >&2
  return "$scan_status"
}

scan_staged_names
scan_working_names
LC_ALL=C sort -u "$scan_staged" "$scan_working" > "$scan_hits"
if test -s "$scan_hits"; then
  printf '%s\n' 'Potential secret values detected in these files:'
  sed -n '1,200p' "$scan_hits"
  exit 1
fi
git status --short
```

The output above contains filenames only. Inspect each named file separately in
a secure local editor; do not rerun a value-emitting grep or paste suspected
content into a ticket, terminal transcript, or chat. Do not assume the scanner
makes a secret safe. If a secret is exposed, revoke or rotate it first, then
remove it from history using the repository owner's incident procedure.

Scanner acceptance test (for CI implementation in a disposable clean clone,
not for this active working snapshot): create a harmless file containing
`OMNIA_SECRET_SCAN_SENTINEL_harmless_test_value`, stage it, and run the scanner.
The test passes only when the scanner exits nonzero and its output contains the
sentinel filename but not the sentinel value. Then unstage and remove the test
file. This staged sentinel test is the exit evidence that index coverage works;
it must never use a real credential.

## Local development

Prerequisites are Xcode for the checked-in deployment targets, Docker, the
Supabase CLI, Deno 2, and Homebrew mpv for a macOS playback build. Start from
placeholders and supply real values only in the ignored local file. The setup
below is create-only: when `supabase/.env` exists, it records and rechecks its
checksum and leaves the file untouched.

```bash
set -euo pipefail

if test -e supabase/.env; then
  env_checksum_before="$(shasum -a 256 supabase/.env)"
  printf '%s\n' 'supabase/.env already exists; leaving it unchanged.'
  env_checksum_after="$(shasum -a 256 supabase/.env)"
  if [[ "$env_checksum_before" != "$env_checksum_after" ]]; then
    printf '%s\n' 'supabase/.env changed during bootstrap; refusing to start services.' >&2
    exit 1
  fi
else
  install -m 600 supabase/.env.example supabase/.env
fi
supabase start
supabase status
supabase db lint --local
git diff --quiet -- supabase/functions/metadata/deno.lock
git diff --cached --quiet -- supabase/functions/metadata/deno.lock
deno check --config supabase/functions/metadata/deno.json \
  --lock supabase/functions/metadata/deno.lock \
  --frozen \
  supabase/functions/metadata/index.ts
git diff --quiet -- supabase/functions/metadata/deno.lock
git diff --cached --quiet -- supabase/functions/metadata/deno.lock
supabase functions serve metadata --env-file supabase/.env
```

`supabase db reset` is destructive to the local database. It also currently
fails at the seed step because `supabase/config.toml` enables
`./seed.sql` but that file is absent. Until that finding is closed, use a
disposable local stack and either add the intended deterministic seed or obtain
explicit approval to disable seeding.

Build the Apple app after the backend checks:

```sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia \
  -destination 'platform=macOS' build
xcodebuild -project Omnia.xcodeproj -scheme Omnia \
  -destination 'generic/platform=iOS Simulator' build
```

The macOS app build requires a locally installed libmpv. A documentation-only
change need not mutate or rebuild the dirty application snapshot; release
candidates do.

## Database migration runbook

Migrations affect live data and authorization. Use a dedicated staging project
once one exists; until then, every remote command requires an explicit target
check and operator approval.

1. Confirm a clean release commit, select the intended project, and record the
   project reference without recording credentials.
2. Start Docker, reset a disposable local database after resolving the missing
   seed, then lint and run Edge Function tests.
3. Compare local and remote migration state and preview the push:

   ```sh
   supabase migration list
   supabase db lint --local
   supabase db push --dry-run
   ```

4. Review SQL for locks, table rewrites, data loss, RLS, grants, and Realtime
   publication changes. Capture a fresh managed backup or verify point-in-time
   recovery before destructive or irreversible work.
5. Apply only after the project reference, backup, review, and maintenance plan
   are confirmed:

   ```sh
   supabase db push
   supabase migration list
   ```

6. Verify that expected tables and policies exist, an authenticated user can
   access only their own rows, anonymous access is denied, service-only caches
   remain inaccessible to clients, and the Realtime publication matches the
   migration. After cloud sync is connected to app state, also verify Realtime
   convergence with two test users or devices.

Rollback database changes with a new, reviewed forward migration whenever
possible. Never delete a shared migration or rewrite its history. For data loss
or an unsafe irreversible migration, stop writes, preserve logs, and restore a
managed backup/PITR recovery into a new project first; validate it before
cutover. Record the incident timeline, recovery point, and any lost interval.

## Edge Function release runbook

### Pending metadata deployment

The current working snapshot contains the TVDB identifier improvement in the
modified `metadata` function and its uncommitted helper/tests; those files are
not all present in this documentation branch's history, and the improvement
**has not been deployed**. Final integration must ship the function, helper,
tests, import map, and lock from one reviewed commit. `supabase functions deploy
metadata` below is a pending live-state-changing step, not a record of work
performed.

Pre-deploy checks:

1. Confirm the release commit, run the filename-only secret scanner above, and
   review the changed filenames with `git status --short`. Inspect staged
   content only in a secure local diff viewer so suspected values are not
   printed into a terminal transcript. Confirm the deploy source is exactly the
   reviewed function, helper, tests, import map, and lock file.
2. Confirm the linked project is the intended environment:

   ```sh
   supabase projects list
   supabase functions list
   supabase migration list
   ```

3. Confirm required secret *names* exist in the target without displaying or
   copying their values. Verify the hosted Auth/JWT policy separately; local
   `verify_jwt = false` delegates authentication to the function's
   `withSupabase({ auth: ["user", "publishable"] })` wrapper but is not proof of
   the deployed gateway setting.
4. Run reproducible checks and local smoke requests with a non-production test
   account and publishable key supplied through environment variables. Refuse a
   dirty staged or working-tree lock before and after Deno runs; `--frozen`
   makes an out-of-date lock an error instead of updating it:

   ```bash
   set -euo pipefail

   git diff --quiet -- supabase/functions/metadata/deno.lock
   git diff --cached --quiet -- supabase/functions/metadata/deno.lock
   deno check --config supabase/functions/metadata/deno.json \
     --lock supabase/functions/metadata/deno.lock \
     --frozen \
     supabase/functions/metadata/index.ts
   git diff --quiet -- supabase/functions/metadata/deno.lock
   git diff --cached --quiet -- supabase/functions/metadata/deno.lock
   supabase functions serve metadata --env-file supabase/.env
   ```

5. Exercise TMDB and TVDB search/details, invalid input, a missing/invalid
   credential, and protected seed/status/reindex actions. Do not place tokens in
   shell history, URLs, screenshots, or captured logs.

Deploy only after those checks and an approved change window. The final gate is
intentionally repeated in the same fail-closed Bash process as the live deploy;
any dirty lock, frozen Deno failure, or post-check failure prevents the deploy:

```bash
set -euo pipefail

git diff --quiet -- supabase/functions/metadata/deno.lock
git diff --cached --quiet -- supabase/functions/metadata/deno.lock
deno check --config supabase/functions/metadata/deno.json \
  --lock supabase/functions/metadata/deno.lock \
  --frozen \
  supabase/functions/metadata/index.ts
git diff --quiet -- supabase/functions/metadata/deno.lock
git diff --cached --quiet -- supabase/functions/metadata/deno.lock
supabase functions deploy metadata
```

Post-deploy verification:

- Record the deployed function version and time, then check Dashboard Edge
  Function logs for invocation failures without copying credentials or provider
  payloads.
- From an internal build, sign in, run a known TMDB search/details request, run
  a TVDB series search/details request that depends on the improved identifier
  handling, and repeat one request to exercise the cache.
- Confirm anonymous or publishable access matches the intended discovery
  contract, malformed requests fail safely, protected operational actions
  reject the wrong seed token, and user-owned tables remain protected by RLS.
- Observe provider error rate and latency through the initial release window.
  Stop the rollout if TVDB identifiers regress, provider failures rise, or
  cache writes fail.

To roll back, check out the last known-good reviewed function source and lock
file, rerun its checks, and redeploy `metadata` with the same command. This is a
new deployment; do not claim an in-place platform rollback. If the new function
depends on a migration, prefer a backward-compatible function rollback. If that
is impossible, deploy a forward fix and follow the database recovery policy.
Afterward, repeat the smoke checks and preserve the failed deployment logs.

## Apple release and libmpv validation

1. Pin the release commit and `Package.resolved`; resolve Swift packages without
   silently updating them.
2. Verify version/build numbers, bundle identifiers, signing team, entitlements,
   capabilities, Supabase environment, and OAuth callback allow-list.
3. Build the pinned source closure from
   `NativeDependencies/playback-dependencies.json` using
   `Scripts/build-playback-dependencies.sh` in a controlled macOS job. Preserve
   the source/build metadata, SPDX SBOM, exact license files, and SHA-256 of
   every universal dylib. Build the same commit and manifest on a second clean
   controlled builder and compare the complete pre-signing artifact inventory.
   Homebrew discovery is permitted only for Debug builds and is not release
   evidence.
4. Build macOS and the iOS Simulator target using the commands above;
   then archive each shipping destination with the intended distribution
   identity.
5. Inspect the macOS archive before upload:

   ```sh
   otool -L /path/to/Omnia.app/Contents/MacOS/Omnia
   find /path/to/Omnia.app/Contents/Frameworks -type f -name '*.dylib' \
     -exec otool -L {} \;
   codesign --verify --deep --strict --verbose=2 /path/to/Omnia.app
   codesign -d --entitlements :- /path/to/Omnia.app
   ```

   All non-system references must resolve to bundled `@rpath` libraries; system
   libraries may remain absolute. Confirm the embedded
   `Resources/NativePlayback/native-playback.spdx.json`, package license texts,
   and build metadata match the verified artifact root. Confirm the hardened
   runtime, the reviewed JIT entitlement, nested signatures, launch, video,
   audio/subtitle selection, seeking, and clean failure for a bad stream.
6. Distribute to internal TestFlight/App Store Connect testers first. Smoke-test
   Auth callbacks, metadata, Stremio browsing, resolver allow-list rejection,
   macOS libmpv playback, and iOS AVPlayer playback. Add library/progress sync
   to this gate only after that client integration is connected to app state.
   Expand the staged release only while crash, authentication, metadata, and
   playback indicators remain healthy.

For an app regression, pause the phased release and stop promoting the build.
Restore service compatibility first if a backend change caused it. Apple store
users cannot be forced onto an older installed build; submit a higher-numbered
known-good or fixed build. Preserve the failed archive and symbol files for
diagnosis.

## Observability and incident response

In the current working snapshot, the modified metadata function emits a single
unstructured `console.error` path; that modified function is not committed in
this documentation branch. The inspected repository configuration defines no
metrics, traces, dashboards, SLOs, or alerts. During operations, use Supabase
Edge Function, Auth, Postgres, and API logs plus Apple crash/diagnostic reports,
while treating logs as sensitive.

At minimum, instrument request count, error count/rate, and latency by safe
operation/provider; cache hit rate; provider timeout/rate-limit failures;
database/Realtime failures; Auth callback failures; app crashes; and playback
start/failure. Never log bearer/JWT/provider tokens, seed tokens, request
authorization headers, full user identifiers, resolver URLs with credentials,
or upstream response bodies. Use correlation IDs and bounded error categories
instead of sensitive payloads.

Incident sequence:

1. Acknowledge and name an incident lead; record start time, affected version,
   environment, and symptoms.
2. Contain by pausing the app rollout, function deploys, migration work, or
   affected provider path. Rotate exposed credentials immediately.
3. Preserve relevant logs and release identifiers, diagnose the failing
   boundary, and choose the rollback/recovery runbook above.
4. Verify Auth, metadata, RLS, resolver rejection, playback, and every other
   capability included in the affected release after mitigation. Include
   Realtime app sync only after that integration exists. Communicate impact
   without exposing user or secret data.
5. Write a post-incident review with timeline, cause, recovery point, follow-up
   owners, and prevention tests.

## Backup and recovery

Migrations are schema history, not data backups. Before relying on recovery,
verify the production Supabase plan's backup retention and PITR capability in
the Dashboard, identify who can initiate and approve a restore, and document
the expected RPO/RTO. Do not invent guarantees from local configuration.

Quarterly, restore the latest backup to an isolated non-production project,
apply any later migrations, and validate row counts, critical constraints/RLS,
metadata/discovery cache behavior, Auth linkage, and two-user library/progress
isolation. Record backup time, restore start/end, achieved recovery point,
results, operator, and cleanup. A drill is complete only when application smoke
tests pass against the restored project; delete the isolated copy through the
approved project-retention process afterward.

## Infrastructure findings

| Priority | Finding and evidence | Risk | Exit criterion |
| --- | --- | --- | --- |
| P0 | Production Supabase settings require verification. `supabase/config.toml` is local CLI configuration; the repository cannot prove hosted Auth providers/redirects, JWT/gateway behavior, exposed Data API tables, RLS state, backup retention, or network policy. | A release can target or trust settings that differ from review. | For each environment, capture a dated, secret-free checklist showing project reference, migrations, function version, secret names, Auth redirects/providers, Data API exposure, RLS/grants, Realtime publication, backup/PITR, and owners; require it at release approval. |
| P1 | CI/CD is absent: there is no `.github/workflows/` directory or other checked-in pipeline in the inspected tree. | Lint, tests, dependency locks, builds, and deploy approvals depend on a workstation. | Add protected CI that checks migrations, Deno check/test with the lock, Swift build/test on supported destinations, secret scanning, and artifact signing checks; gate remote deploy jobs with environment approval and immutable release refs. |
| P1 | A root `.gitignore` exists, but general root ignore coverage is effectively missing: it contains only `.worktrees/`. Supabase has its own ignore file, but root build products, user state, and generic local secrets are not covered there. | Accidental local artifacts or credentials may be staged. | Review repository needs and expand the root policy to cover Xcode user/build output and local secret files without hiding source; test representative paths with `git check-ignore -v`. |
| P1 | Seed configuration is broken: `[db.seed]` enables `./seed.sql`, but `supabase/seed.sql` is absent. | `supabase db reset` is not a reproducible clean-room setup. | Add a safe deterministic `seed.sql` with tests, or deliberately disable seeding; prove `supabase db reset` succeeds from a clean local stack. |
| P1 | App/backend configuration is single-environment: `AppInfo.plist` carries one Supabase URL/publishable key and no per-environment `.xcconfig` files were found. | Development or staging work can affect production, and releases can target the wrong project. | Create separate Supabase projects and explicit Debug/Staging/Production build configurations using reviewed `.xcconfig` inputs; add a visible environment assertion and release check. |
| P1 | No completed backup/restore drill or RPO/RTO is evidenced by the inspected configuration and Supabase guide. | Backups may be unavailable, too old, or operationally unusable during an incident. | Assign owners and RPO/RTO; complete and record a non-production restore drill using the validation in this guide on a defined cadence. |
| P1 | Observability is limited: in the current working snapshot, the uncommitted 954-line metadata entry point has one generic `console.error` path; no checked-in structured metrics, traces, dashboards, or log schema were found. | Provider, cache, and authorization failures can be slow to detect and hard to correlate. | Integrate the metadata prerequisites together, emit redacted structured events/correlation IDs, define the minimum metrics above, provision dashboards, and demonstrate a synthetic failure from request through diagnosis. |
| P1 | No SLOs or alert rules are defined in the inspected repository. | Operators have no agreed reliability target or automated escalation threshold. | Approve measurable Auth, metadata, sync, and playback SLIs/SLOs; add burn-rate/error/latency alerts with owners, paging routes, runbook links, and a successful alert test. |
| P1 | In the current working snapshot, the uncommitted `embed-libmpv.sh` discovers whichever Homebrew `libmpv.2.dylib` and dependency closure is installed; the prerequisite is not yet part of this documentation branch's history. | Identical commits can ship different native code and signatures, or the documented embed phase may be omitted during integration. | Integrate the script and project changes in the release commit, pin the mpv formula/bottle and full closure in a controlled builder or vendored artifact, verify checksums/licenses/architecture, and reproduce an identical signed pre-signing payload in two clean builds. |
| P2 | In the current working snapshot, the modified `index.ts` is a 954-line monolith combining request validation/auth, TMDB, TVDB, database/cache, discovery seeding/reindexing, and routing; the TVDB helper/tests are also uncommitted prerequisites. | Provider or operational changes have a large blast radius and are harder to test/deploy independently; incomplete integration could omit the identifier fix or tests. | First integrate the function, helper/tests, import map, and lock in one reviewed commit. Then split pure schemas/validation, provider adapters, persistence, operational handlers, and router into focused modules with unit/contract tests; keep one reviewed entry point only for composition. |

## Release evidence checklist

Attach these secret-free items to each release record:

- source commit, reviewer, environment/project reference, operator, and times;
- proof that `embed-libmpv.sh`, its project changes, `OmniaTests/`, and the TVDB
  function/helper/tests plus dependency files are present together in that
  reviewed source commit;
- `git status`, migration list and dry-run review, Deno check/test result, and
  Xcode build/test result for affected destinations;
- deployed migration versions and Edge Function version, with the TVDB change
  marked pending until its deployment and post-deploy checks actually occur;
- macOS mpv/closure versions and checksums, archive identifiers, signing and
  `otool` verification, plus Apple build numbers;
- Auth, metadata, RLS, resolver, and player smoke-test results, plus Realtime
  app-sync evidence after that integration exists;
- backup/PITR verification, rollback owner/trigger, monitoring window, and any
  accepted findings with owner and due date.

## Account credential vault release gate

**Status: first release deployed to Omnia on 2026-10-22 with explicit owner authorization.**
Migration, managed secrets, function activation and focused hosted API/isolation
checks passed; native two-device and accessibility checks remain pending. See
[the deployment record](docs/research/account-credential-vault-deployment-2026-10-22.md).
This gate is separate from the pending metadata deployment. See the
[approved design](docs/superpowers/specs/2026-10-22-account-credential-sync-design.md)
and [Supabase credential contract](supabase/README.md#credential-boundary).

Before activation, review the exact migration
`20261022140828_credential_vault.sql`, the complete `credential-vault` source/import
map/lock, native adapters/coordinator and the filename-only secret scan above.
Record immutable release source, target project identity, prior deployed source,
DB backup/restore evidence, key backup owner and rollback trigger. Confirm
`pg_cron` is available and authorized for this target. Do not disable checks or
change the metadata deployment to work around vault failures.

Dependency review: no new Swift or external Deno dependency is added; the function
reuses the repository's existing resolved Supabase dependency tree and Web Crypto.
Scheduled cleanup uses Supabase's bundled `pg_cron` platform extension because
request-only cleanup cannot retire abandoned uploads for inactive accounts.
Provenance is [Citus Data's pg_cron](https://github.com/citusdata/pg_cron), under its
[permissive PostgreSQL-style license](https://github.com/citusdata/pg_cron/blob/main/LICENSE).
No extension binary is downloaded or bundled with the app. Record the target's
Postgres and installed `pg_cron` extension versions and review platform advisories
before activation; [Supabase ignores explicit extension version pins](https://supabase.com/changelog/extension-version-pinning-ignored).
Its additional privilege is a database-local scheduled deletion job: the private
function has no HTTP access, deletes only expired upload generations in bounded
batches, and leaves current entries/tombstones intact. Monitor its execution and
backlog; do not grant client access to cron metadata or cleanup functions.

Local gates: frozen Deno check with the function's own config/lock, local migration
apply and database lint, service-only grants/RLS/RPC verification, plus a signed
Mac build and supported-destination builds. No automated tests, fixtures, suites
or scripts; follow AGENTS.md. Source-only review does not prove SQL/runtime grants.

For an authorized activation window, the operator separately approves migration
application, creation of `CREDENTIAL_VAULT_KEYS` and `CREDENTIAL_VAULT_ACTIVE_KEY`
in managed Edge Function secrets, and deployment of `credential-vault` only.
Create a cryptographically random 32-byte key out of band; never put its value,
Auth tokens or decrypted payloads into shell arguments, logs or evidence files.
An encrypted operational backup of every retained key version is required before
writing ciphertext. Verify project and secret **names**, not values, in evidence.
The function verifies user identity through Auth even though its gateway
`verify_jwt` setting is false; missing/invalid/publishable-only/anonymous callers
must fail and cause no vault read or write.

Required manual smoke matrix using isolated accounts and synthetic credentials:

- Fresh sign-in on a second device restores each provider key, profile PIN,
  media-server connection and Live TV URL/login/imported M3U. Provider expiry or
  revoked media-server token offers reconnect without erasing other entries.
- Correct PIN accepted, wrong PIN rejected, missing verifier stays locked with
  an accessible retry. PIN changes/removal and profile deletion propagate.
- Offline edits survive relaunch; empty fresh devices pull before upload; stale
  writes produce an explicit keep-device/keep-account conflict; deleted entries
  do not reappear. An edit during upload receives a subsequent sync pass.
- Switch A→B during read/upload/apply and sign out during requests; no A secrets
  are applied or uploaded to B. Failed sign-out recovers without an endless
  spinner. Pending changes stay encrypted for the outgoing account.
- Partial Keychain failures retain previous values. Missing/corrupt playlist
  chunks never publish a partial local file; byte-count/hash mismatches fail.
- Invalid owner selectors, oversized bodies, unknown IDs, bad chunks and direct
  anon/authenticated RPC/table access fail. Confirm ciphertext-only tables and
  generic diagnostics without displaying plaintext in captured evidence.

Entry IDs include permanent tombstones (1,000 active / 2,000 total); monitor quota
rejections before a user reaches the reserved-ID ceiling. Attachments reserve
quota including ciphertext/base64/envelope overhead, so usable plaintext is less
than 256 MiB per account. Expired uncommitted uploads and retired generations
become eligible after 24 hours; request cleanup and an hourly private cron job
remove them. The scheduled job examines at most 128 oldest candidates and removes
at most 16 uploads per run, skipping busy account locks. Monitor expired backlog
and `cron.job_run_details`; 24 hours is eligibility, not a guaranteed deletion SLA.
Validate that current committed attachments and tombstones survive maintenance.

Rotation: add a new random key under a new version while retaining old versions,
validate reads under all retained versions, then change only the active encryption
version. Existing records remain readable with their recorded version. Do not
remove old keys until all records/attachments and retained recovery backups have
been re-encrypted or retired through a separately reviewed operation. A database
backup without its matching key versions is insufficient for recovery.

Rollback: stop vault writes/deploy the reviewed previous function or disable the
new vault endpoint and restore the previous client release. Device-local values
continue to work; a fresh device cannot restore until the endpoint is recovered.
Retain all ciphertext tables, pending device snapshots and key versions. Do not
roll back by dropping data, pruning tombstones or replacing keys. Record generic
failure categories and the action taken; never preserve secret-bearing payloads.
Older clients do not participate in vault edits/deletions, so credential-sensitive
rollout must identify and communicate that version boundary.
