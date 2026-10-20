# Settings Phase 0B: Event Store Design

> **Automated-validation policy:** Follow the repository-root `AGENTS.md`. Instructions below that call for automated test targets, suites, fixtures, or scripts are historical and superseded; use builds, static checks, and focused manual evidence instead.

**Status:** Approved on 2026-08-11

**Depends on:** Phase 0A contracts and deterministic test infrastructure

**Scope:** Profile-isolated SwiftData event stores, projections, delivery, replay, retention, and erasure

**Production UI:** Unchanged until Phase 1

## Objective

Make full event sourcing the durable foundation for Omnia progress, watchlist, authoritative-provider ownership, and synchronization. The append-only event stream is the source of truth. SwiftData projections are disposable read models optimized for Settings, Home, Library, and playback.

Omnia keeps device-only and signed-in account data separate. It never automatically migrates, mirrors, or merges their histories.

## Alternatives Considered

### Snapshot plus outbox

This is simpler and was the initial recommendation, but it loses the complete sequence needed to explain conflicts and reconstruct synchronization decisions.

### Full event sourcing — selected

Immutable events, deterministic projections, and explicit delivery records provide reproducible offline recovery, provider-switch history, and conflict evidence. The cost is stricter schema evolution, replay, retention, and performance engineering.

### Direct provider writes

This was rejected because network availability would determine whether local actions survive, and delayed responses could silently overwrite newer state.

## Store Isolation and Lifecycle

Each `ProfileID` maps to a physically separate SwiftData store under Application Support. The device profile receives a stable random identifier. Signed-in profiles use opaque local store identifiers rather than exposing account identifiers in filenames. Profile-to-store mappings are stored as device-only Keychain records.

Opening a profile is an explicit state transition:

1. Cancel work associated with the previous profile.
2. Flush its completed transaction, stop access to its model context, and release the active container.
3. Resolve the destination's opaque store identifier.
4. Open and validate the destination store.
5. Verify event and projection checkpoints.
6. Publish the new active profile token.

If any step fails, Omnia keeps the previous profile active. Results tagged with an obsolete profile token are discarded before persistence.

## Event Envelope

Every persisted event contains:

- globally unique event ID;
- profile-local monotonic sequence;
- event type and schema version;
- command and correlation IDs;
- origin: local user action, playback, imported remote observation, provider acknowledgement, maintenance, or migration;
- recorded timestamp from the injected clock;
- bounded encoded payload;
- payload checksum for corruption detection.

Payloads use explicit versioned `Codable` schemas. Unknown event types or unsupported future versions stop projection advancement and surface a recoverable store error; they are never skipped silently. Upcasters are pure functions with fixture coverage.

Sensitive values are excluded by construction. Credential material, callbacks, authorization codes, bearer headers, signed media URLs, resolver tokens, subtitle text, prompts, responses, and model output cannot appear in an event payload or projection.

## Command Transaction

A single profile-scoped persistence actor serializes commands. Within one SwiftData transaction it:

1. Rejects a duplicate command ID or stale profile token.
2. Loads only the projections needed for validation.
3. Produces immutable events.
4. Assigns contiguous local sequences.
5. Appends the events.
6. Applies them to affected projections.
7. Creates or updates provider-delivery records where required.
8. Advances projection checkpoints.
9. Commits once.

No network request occurs inside this transaction. If commit fails, none of the events, projections, checkpoints, or delivery changes become visible.

## Projections

Initial materialized projections are:

- current progress by profile, media, and episode;
- Continue Watching ordering and limit eligibility;
- current watchlist membership;
- authoritative owner per data type;
- anime progress owner;
- provider connection and last-sync summary without secrets;
- pending, retryable, conflicted, and blocked delivery counts;
- upcoming-content inputs derived from truthful supported owners;
- retention policy and last maintenance outcome.

Projection rows store the last applied event sequence. Startup applies only events after the checkpoint. A repair command can delete projections and rebuild them from the retained baseline and subsequent events. Replay must produce byte-equivalent normalized projection fixtures.

## Delivery and Offline Outbox

Provider delivery is represented separately from the immutable event. A delivery record identifies the source event, exact profile and provider account, capability, attempt count, next eligible attempt, and non-sensitive failure classification.

- Local commit always precedes delivery.
- Pending work survives restart and loss of connectivity.
- One delivery worker operates per active profile and provider account.
- Retries are bounded, cancellable, and respect officially documented `Retry-After` behavior.
- Provider acknowledgement appends an acknowledgement event and removes only the correlated delivery.
- Duplicate acknowledgement is idempotent.
- Partial failure identifies affected local item IDs without retaining raw provider payloads.
- Account switching stops the worker; a stale completion cannot append into another profile.

Real provider traffic is outside Phase 0B. Tests use fake adapters that can reorder, duplicate, delay, reject, or partially acknowledge operations.

## Conflict and Provider Switching

Remote responses are observations, not authoritative rewrites of local history. Importing remote state appends a versioned observation event containing only normalized fields and documented provider revisions. Conflict evaluation considers local sequence, pending delivery, trusted provider revision or timestamp, and explicit ownership.

Omnia never resolves an ambiguous newer-versus-newer conflict silently. It appends a conflict-detected event and blocks the affected delivery until an explicit resolution command chooses local, remote, or a supported field-level result.

Switching an authoritative provider pauses affected commands and requires one choice:

- copy current state to the new owner;
- replace local current state after a reviewed remote preview;
- start empty with the new owner.

The migration has a correlation ID and staged events. Cancellation before commit leaves ownership unchanged. Device and signed-in profile migration is always a copy; the source store is not deleted.

## Retention, Compaction, and Erasure

Watch-activity retention is user-visible:

- 3 months;
- 6 months;
- 1 year, the default;
- Keep All History.

Pending, conflicted, blocked, or unacknowledged events are never pruned automatically. Before removing eligible history, maintenance writes a versioned baseline event containing the minimum state needed to rebuild current projections. It replays the proposed retained generation in isolation and compares normalized projections with the active generation.

Successful maintenance creates a new store generation, validates it, and atomically replaces a small active-generation pointer inside the profile's Application Support directory before deleting the old generation. The stable profile-to-store Keychain mapping does not change during compaction. Cancellation or failure leaves the old store authoritative. Maintenance runs only while idle, is cancellable, and records a non-sensitive outcome.

`Clear Watch History` uses the same verified generation rollover but excludes the selected activity. It performs actual local erasure rather than appending only a tombstone. Current watchlist membership and unfinished progress are retained only when the user's chosen operation says so.

`Delete Profile Data` cancels profile work, releases the active store, deletes all generations and translated-subtitle caches, and removes profile-scoped credentials and mappings. Failure reports the exact local category that remains without exposing private data.

## Recovery and Corruption

On open, Omnia verifies schema compatibility, sequence uniqueness, payload bounds and checksums, and projection checkpoints. A projection mismatch triggers projection-only rebuild. An invalid event stream never falls back to guessed state; Omnia preserves the store, stops writes, and offers a diagnostic export containing schema and failure metadata but no event payloads.

Store replacement uses atomic filesystem operations supported by the platform. Backup or cloud mirroring is not implied. Supabase remains uncomposed until a separately approved authoritative-provider design exists and its reconnect, conflict, account-switch, and cross-user tests pass.

## Performance and Resource Policy

Normal launch does not replay the complete retained history. It opens validated projections and replays only events after their checkpoints. Commands fetch indexed projection keys, append bounded event batches, and save once. Playback progress is coalesced into meaningful state changes rather than generating events from the existing 250 ms observation loop.

Benchmarks record event append latency, incremental projection latency, cold rebuild duration, store size, compaction peak disk usage, and memory. They are engineering evidence, not product performance claims. Any claim of improved speed, memory, or energy requires before-and-after Release Instruments evidence on representative devices.

## Test Matrix

Phase 0B tests must cover:

- physical store separation and failed profile switching;
- duplicate commands, events, and acknowledgements;
- contiguous sequencing under concurrent commands;
- transaction failure at each commit boundary;
- deterministic replay and projection-only rebuild;
- supported upcasting and rejection of unknown versions;
- malformed, oversized, or checksum-invalid payloads;
- restart with pending delivery;
- offline, cancellation, retry, rate limit, stale response, reordering, and partial acknowledgement;
- explicit provider-switch choices and cancellation;
- retention boundaries and baseline equivalence;
- interrupted generation rollover and rollback;
- watch-history erasure and complete profile deletion;
- bounded progress-event generation during playback;
- absence of prohibited sensitive fields from persisted models and diagnostic output.

## Verification and Acceptance

Phase 0B is complete when:

1. Failing tests precede each production behavior and pass after implementation.
2. A profile store can rebuild every projection from its retained baseline and events.
3. Fault-injection tests prove atomic command writes, outbox recovery, and generation rollover.
4. Cross-profile tests prove data, credentials, callbacks, workers, and stale results cannot cross boundaries.
5. The macOS app builds, signed macOS XCTest passes, and generic iOS Simulator builds.
6. Relevant accessibility verification covers any diagnostic or recovery surface actually introduced; otherwise UI remains deferred to Phase 1.
7. `git diff --check` passes and review finds no unrelated edit, hosted mutation, live-provider call, or Release enablement.
8. Physical-device, orientation, iPad multitasking, archive, notarization, Instruments, hosted, provider-contract, and legal gates are reported as pending until actually completed.

## Relationship to Later Phases

Phase 1 exposes completed capabilities through native Settings navigation and accessible controls. Phases 2 through 7 add bounded add-on and provider adapters without changing the event-store invariants. Phase 8 derives privacy and data-retention disclosures from the behavior verified here.
