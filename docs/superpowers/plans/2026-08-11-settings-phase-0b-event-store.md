# Settings Phase 0B Event Store Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build profile-isolated SwiftData event stores whose append-only events, transactional projections, delivery outbox, replay, bounded retention, and verified erasure become Omnia’s durable progress/watchlist foundation.

**Architecture:** Each profile owns a separate versioned store generation under Application Support. A profile-scoped actor serializes command handling, event append, projection updates, checkpoints, and delivery mutations; network work occurs outside transactions and returns correlated results. Current `OmniaStore` remains authoritative until a later approved migration phase.

**Tech Stack:** Swift 6, SwiftData, Foundation, CryptoKit, Security, XCTest, Phase 0A contracts/test doubles; no new dependency.

**Design:** `docs/superpowers/specs/2026-08-11-settings-phase-0b-event-store-design.md`

## Global Constraints

- Phase 0A must be complete and its focused tests passing before this plan begins.
- Preserve all unrelated dirty and staged work; every commit is path-scoped.
- Use full event sourcing: the retained event stream, not a projection, is the source of truth.
- Keep device-only and signed-in account data in physically separate stores.
- Signing in never migrates device data automatically.
- Use a one-year user-visible history default with 3 months, 6 months, 1 year, and Keep All choices.
- Pending, conflicted, blocked, and unacknowledged work is never pruned automatically.
- Do not persist credentials, callbacks, authorization headers/codes, signed URLs, resolver tokens, subtitle dialogue, prompts, responses, or model output.
- Do not compose Supabase cloud sync or call a real provider.
- Do not replace `OmniaStore`, `SettingsView`, or current playback persistence in this phase.
- Do not mutate hosted Supabase, secrets, provider state, migrations, or deployments.
- Use deterministic clocks, identifiers, fixtures, fault injection, and no live network.
- Build iPhone/iPad Simulator and Mac; keep physical-device, archive, hosted, legal, and Instruments checks pending until performed.
- Test helpers named `fixtureA`, `fixtureB`, `id1`, `id2`, or `fixture` use fixed values declared in the named test file: profile UUIDs ending in `00a1`/`00b2`, command UUIDs ending in `0101`/`0102`, `Date(timeIntervalSince1970: 1_700_000_000)`, media key `tmdb:movie:550`, and episode key `season:1:episode:1`. No helper may fall back to random values.

---

### Task 1: Define the SwiftData Store Schema

**Files:**
- Create: `Omnia/Data/Persistence/EventStore/EventRecord.swift`
- Create: `Omnia/Data/Persistence/EventStore/ProcessedCommandRecord.swift`
- Create: `Omnia/Data/Persistence/EventStore/EventSequenceRecord.swift`
- Create: `Omnia/Data/Persistence/EventStore/EventDeliveryRecord.swift`
- Create: `Omnia/Data/Persistence/EventStore/ProjectionCheckpointRecord.swift`
- Create: `Omnia/Data/Persistence/EventStore/EventStoreSchema.swift`
- Test: `OmniaTests/EventStoreSchemaTests.swift`

**Interfaces:**
- Consumes: `ProfileID` and event metadata from Phase 0A.
- Produces: `EventStoreSchema.makeContainer(isStoredInMemoryOnly:)` and the internal SwiftData records used by every Phase 0B task.

- [ ] **Step 1: Write failing in-memory schema tests**

~~~swift
import SwiftData
import XCTest
@testable import Omnia

final class EventStoreSchemaTests: XCTestCase {
    func testSchemaCreatesEveryRequiredModel() throws {
        let container = try EventStoreSchema.makeContainer(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        context.insert(EventSequenceRecord(nextSequence: 1))
        context.insert(ProjectionCheckpointRecord(name: "progress", lastSequence: 0))
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<EventSequenceRecord>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ProjectionCheckpointRecord>()).count, 1)
    }

    func testDuplicateEventIDIsRejected() throws {
        let container = try EventStoreSchema.makeContainer(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        let id = UUID()
        context.insert(EventRecord.fixture(eventID: id, sequence: 1))
        context.insert(EventRecord.fixture(eventID: id, sequence: 2))
        XCTAssertThrowsError(try context.save())
    }
}
~~~

- [ ] **Step 2: Run RED**

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test -only-testing:OmniaTests/EventStoreSchemaTests
~~~

Expected: compilation fails because the SwiftData models are absent.

- [ ] **Step 3: Implement the minimal schema**

`EventRecord` stores unique event ID, unique profile-local sequence, profile ID, type, schema version, command/correlation IDs, origin, timestamp, payload `Data`, and SHA-256 payload checksum. `ProcessedCommandRecord` has a unique command ID. `EventSequenceRecord` has the unique key `"profile-sequence"` and next sequence. `EventDeliveryRecord` stores no payload; it references source event ID and normalized provider/account/capability/status metadata. `ProjectionCheckpointRecord` is unique by projection name.

~~~swift
enum EventStoreSchema {
    static let schema = Schema([
        EventRecord.self,
        ProcessedCommandRecord.self,
        EventSequenceRecord.self,
        EventDeliveryRecord.self,
        ProjectionCheckpointRecord.self
    ])

    static func makeContainer(isStoredInMemoryOnly: Bool) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
~~~

Add explicit initializers; do not expose mutable records outside `Data/Persistence/EventStore`.

- [ ] **Step 4: Run GREEN and commit**

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test -only-testing:OmniaTests/EventStoreSchemaTests
git diff --check -- Omnia/Data/Persistence/EventStore OmniaTests/EventStoreSchemaTests.swift
git add -- Omnia/Data/Persistence/EventStore OmniaTests/EventStoreSchemaTests.swift
git commit --only -m "Define the profile event store schema" -- Omnia/Data/Persistence/EventStore OmniaTests/EventStoreSchemaTests.swift
~~~

### Task 2: Define the Initial Event Catalog and Upcasting

**Files:**
- Create: `Omnia/Domain/Events/ProgressEvents.swift`
- Create: `Omnia/Domain/Events/WatchlistEvents.swift`
- Create: `Omnia/Domain/Events/OwnershipEvents.swift`
- Create: `Omnia/Domain/Events/ProviderConnectionEvents.swift`
- Create: `Omnia/Domain/Events/DeliveryEvents.swift`
- Create: `Omnia/Domain/Events/ConflictEvents.swift`
- Create: `Omnia/Domain/Events/MigrationEvents.swift`
- Create: `Omnia/Domain/Events/MaintenanceEvents.swift`
- Create: `Omnia/Data/Persistence/EventStore/DomainEventCodec.swift`
- Test: `OmniaTests/DomainEventCodecTests.swift`

**Interfaces:**
- Consumes: `DomainEventPayload` and `UncommittedDomainEvent`.
- Produces: `DecodedDomainEvent`, `DomainEventCodec.decode(type:version:payload:)`, and `EventUpcaster`.

- [ ] **Step 1: Write failing round-trip and rejection tests**

~~~swift
func testProgressRecordedRoundTrips() throws {
    let payload = ProgressRecordedEvent(
        mediaKey: .init(rawValue: "tmdb:movie:550"),
        episodeKey: nil,
        positionSeconds: 120,
        durationSeconds: 600,
        occurredAt: .fixture
    )
    let encoded = try UncommittedDomainEvent(payload: payload, origin: .playback)
    XCTAssertEqual(
        try DomainEventCodec.standard.decode(
            type: encoded.type,
            version: encoded.schemaVersion,
            payload: encoded.payload
        ),
        .progressRecorded(payload)
    )
}

func testUnknownTypeAndFutureVersionAreRejected() {
    XCTAssertThrowsError(try DomainEventCodec.standard.decode(type: "unknown", version: 1, payload: Data()))
    XCTAssertThrowsError(try DomainEventCodec.standard.decode(type: ProgressRecordedEvent.eventType, version: 99, payload: Data("{}".utf8)))
}
~~~

Also test malformed data, invalid positions/durations, oversized identifiers, and a test-only v1-to-v2 upcaster registered in a local codec.

- [ ] **Step 2: Run RED**

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test -only-testing:OmniaTests/DomainEventCodecTests
~~~

- [ ] **Step 3: Implement normalized payloads**

Use bounded `MediaKey` and `EpisodeKey` values. Initial payloads include progress recorded/cleared/completed, watchlist added/removed, owner change requested/committed, delivery acknowledged/rejected/retry scheduled, conflict detected/resolved, migration requested/committed/cancelled, retention changed, baseline established, compaction verified/failed, and erasure requested/completed/failed.

~~~swift
enum DecodedDomainEvent: Equatable, Sendable {
    case progressRecorded(ProgressRecordedEvent)
    case progressCleared(ProgressClearedEvent)
    case progressCompleted(ProgressCompletedEvent)
    case watchlistAdded(WatchlistAddedEvent)
    case watchlistRemoved(WatchlistRemovedEvent)
    case ownershipChangeRequested(OwnershipChangeRequestedEvent)
    case ownershipChanged(OwnershipChangedEvent)
    case providerConnectionChanged(ProviderConnectionChangedEvent)
    case deliveryAcknowledged(DeliveryAcknowledgedEvent)
    case deliveryRejected(DeliveryRejectedEvent)
    case deliveryRetryScheduled(DeliveryRetryScheduledEvent)
    case conflictDetected(ConflictDetectedEvent)
    case conflictResolved(ConflictResolvedEvent)
    case migrationRequested(MigrationRequestedEvent)
    case migrationCommitted(MigrationCommittedEvent)
    case migrationCancelled(MigrationCancelledEvent)
    case retentionChanged(RetentionChangedEvent)
    case baselineEstablished(BaselineEstablishedEvent)
    case compactionVerified(CompactionVerifiedEvent)
    case compactionFailed(CompactionFailedEvent)
    case erasureRequested(ErasureRequestedEvent)
    case erasureCompleted(ErasureCompletedEvent)
    case erasureFailed(ErasureFailedEvent)
}
~~~

- [ ] **Step 4: Implement explicit upcasting**

`DomainEventCodec` has a closed registration table keyed by event type. It decodes the current version directly, applies a contiguous registered upcast chain for older versions, and rejects gaps/future versions. Upcasters are pure `Data -> Data` functions and must pass canonical sorted-key output to the next step.

- [ ] **Step 5: Run GREEN and commit**

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test -only-testing:OmniaTests/DomainEventCodecTests
git diff --check -- Omnia/Domain/Events Omnia/Data/Persistence/EventStore/DomainEventCodec.swift OmniaTests/DomainEventCodecTests.swift
git add -- Omnia/Domain/Events Omnia/Data/Persistence/EventStore/DomainEventCodec.swift OmniaTests/DomainEventCodecTests.swift
git commit --only -m "Define versioned domain events" -- Omnia/Domain/Events Omnia/Data/Persistence/EventStore/DomainEventCodec.swift OmniaTests/DomainEventCodecTests.swift
~~~

### Task 3: Create Physically Separate Profile Stores

**Files:**
- Create: `Omnia/Data/Persistence/Profiles/ProfileMappingStore.swift`
- Create: `Omnia/Data/Persistence/Profiles/ProfileStoreDescriptor.swift`
- Create: `Omnia/Data/Persistence/Profiles/ProfileStoreLocator.swift`
- Create: `Omnia/Data/Persistence/Profiles/ProfileStoreFactory.swift`
- Create: `Omnia/Data/Persistence/Profiles/ProfileStoreCoordinator.swift`
- Create: `OmniaTests/TestSupport/InMemoryProfileMappingStore.swift`
- Test: `OmniaTests/ProfileStoreIsolationTests.swift`

**Interfaces:**
- Consumes: `ProfileID`, `ProfileActivation`, `KeychainStore`, and `EventStoreSchema`.
- Produces: `ProfileMappingStore`, `ProfileStoreLocator.descriptor(for:)`, `ProfileStoreFactory.open(_:)`, and `ProfileStoreHandle`.

- [ ] **Step 1: Write failing physical-isolation tests**

~~~swift
func testTwoProfilesReceiveDifferentStoreRoots() async throws {
    let root = temporaryDirectory()
    let locator = ProfileStoreLocator(rootURL: root, mappings: InMemoryProfileMappingStore())
    let first = try await locator.descriptor(for: .fixtureA)
    let second = try await locator.descriptor(for: .fixtureB)
    XCTAssertNotEqual(first.profileRootURL, second.profileRootURL)
    XCTAssertFalse(first.profileRootURL.lastPathComponent.contains(ProfileID.fixtureA.rawValue.uuidString))
}

func testFailedDestinationOpenLeavesCurrentHandleActive() async throws {
    let coordinator = ProfileStoreCoordinator(factory: FailingSecondOpenFactory())
    let first = try await coordinator.activate(.fixtureA)
    await XCTAssertThrowsErrorAsync(try await coordinator.activate(.fixtureB))
    XCTAssertEqual(await coordinator.activeActivation, first.activation)
}
~~~

- [ ] **Step 2: Run RED**

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test -only-testing:OmniaTests/ProfileStoreIsolationTests
~~~

- [ ] **Step 3: Implement opaque store mapping**

The Keychain mapping stores an opaque random store UUID using the service `PrimeDeca.Omnia.ProfileStores`. The filesystem layout is:

~~~text
Application Support/Omnia/ProfileStores/<opaque-store-id>/
├── active-generation.json
└── generations/<generation-id>/omnia.store
~~~

The pointer contains only generation ID and last verified event sequence. Create it with owner-only filesystem permissions. Test mappings use memory and temporary directories.

- [ ] **Step 4: Implement safe activation**

`ProfileStoreCoordinator.activate` stops new work for the previous activation, waits for its actor queue, releases its handle, opens and validates the destination, then publishes a new random activation token. On failure it reopens/retains the prior handle and token. It does not copy data.

- [ ] **Step 5: Run GREEN and commit**

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test -only-testing:OmniaTests/ProfileStoreIsolationTests
git diff --check -- Omnia/Data/Persistence/Profiles OmniaTests/TestSupport/InMemoryProfileMappingStore.swift OmniaTests/ProfileStoreIsolationTests.swift
git add -- Omnia/Data/Persistence/Profiles OmniaTests/TestSupport/InMemoryProfileMappingStore.swift OmniaTests/ProfileStoreIsolationTests.swift
git commit --only -m "Isolate event stores by profile" -- Omnia/Data/Persistence/Profiles OmniaTests/TestSupport/InMemoryProfileMappingStore.swift OmniaTests/ProfileStoreIsolationTests.swift
~~~

### Task 4: Append Events Atomically and Replay Them

**Files:**
- Create: `Omnia/Data/Persistence/EventStore/EventProjecting.swift`
- Create: `Omnia/Data/Persistence/EventStore/ProfileEventStore.swift`
- Create: `Omnia/Data/Persistence/EventStore/EventStoreReader.swift`
- Create: `OmniaTests/TestSupport/RecordingEventProjector.swift`
- Test: `OmniaTests/ProfileEventStoreTests.swift`
- Test: `OmniaTests/EventReplayTests.swift`

**Interfaces:**
- Consumes: Tasks 1–3 and Phase 0A deterministic inputs.
- Produces: `ProfileEventStore.execute(_:produce:)`, `EventStoreReader.events(after:)`, `EventProjecting.apply`, and `EventStoreSnapshot`.

- [ ] **Step 1: Write failing append invariants**

~~~swift
func testCommandAppendsContiguousEventsExactlyOnce() async throws {
    let projector = RecordingEventProjector()
    let store = try ProfileEventStore.inMemory(profile: .fixtureA, projector: projector)
    let command = DomainCommand.fixture(id: .fixtureCommand, activation: store.activation)
    let first = try await store.execute(command) { [.fixtureProgress, .fixtureWatchlist] }
    XCTAssertEqual(first.map(\.sequence), [1, 2])
    await XCTAssertThrowsErrorAsync(try await store.execute(command) { [.fixtureProgress] }) {
        XCTAssertEqual($0 as? EventStoreError, .duplicateCommand(.fixtureCommand))
    }
}

func testStaleActivationCannotWrite() async throws {
    let store = try ProfileEventStore.inMemory(profile: .fixtureA, projector: RecordingEventProjector())
    await XCTAssertThrowsErrorAsync(
        try await store.execute(.fixture(activation: .differentToken)) { [.fixtureProgress] }
    )
}
~~~

- [ ] **Step 2: Run RED**

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test -only-testing:OmniaTests/ProfileEventStoreTests
~~~

- [ ] **Step 3: Implement the serialized transaction**

The store actor validates activation and duplicate command, obtains contiguous sequence numbers, computes SHA-256 payload checksums, inserts event/processed-command records, calls the injected `EventProjecting` implementation, updates checkpoints and delivery records, then saves once. On any error call `modelContext.rollback()` and expose no partial result. Never perform network work inside `execute`. `RecordingEventProjector` records sequences and can inject a failure so atomic rollback is testable before concrete projections exist.

~~~swift
actor ProfileEventStore {
    func execute<Payload: DomainCommandPayload>(
        _ command: DomainCommand<Payload>,
        produce: (Payload) throws -> [UncommittedDomainEvent]
    ) throws -> [StoredDomainEvent]
}
~~~

Keep the exact signature if Swift actor isolation permits a synchronous producer; otherwise mark the producer `@Sendable` without making it async.

- [ ] **Step 4: Write failing replay and corruption tests**

Verify ordered paging, payload checksum rejection, duplicate sequence rejection, checkpoint gaps, unknown event type/version, and cancellation between pages. Replay must stop at the first invalid record and preserve its sequence/type in a payload-free error.

- [ ] **Step 5: Implement replay and run GREEN**

`EventStoreReader.events(after:limit:)` returns sequence-ordered pages capped at 500. `ProfileEventStore.replay(into:)` sends validated decoded events to an injected projector in order. It never deletes event records to recover a projection.

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test -only-testing:OmniaTests/ProfileEventStoreTests -only-testing:OmniaTests/EventReplayTests
~~~

- [ ] **Step 6: Commit**

~~~sh
git diff --check -- Omnia/Data/Persistence/EventStore OmniaTests/TestSupport/RecordingEventProjector.swift OmniaTests/ProfileEventStoreTests.swift OmniaTests/EventReplayTests.swift
git add -- Omnia/Data/Persistence/EventStore OmniaTests/TestSupport/RecordingEventProjector.swift OmniaTests/ProfileEventStoreTests.swift OmniaTests/EventReplayTests.swift
git commit --only -m "Append and replay profile events" -- Omnia/Data/Persistence/EventStore OmniaTests/TestSupport/RecordingEventProjector.swift OmniaTests/ProfileEventStoreTests.swift OmniaTests/EventReplayTests.swift
~~~

### Task 5: Project Progress, Watchlist, and Ownership

**Files:**
- Create: `Omnia/Data/Persistence/Projections/ProgressProjectionRecord.swift`
- Create: `Omnia/Data/Persistence/Projections/WatchlistProjectionRecord.swift`
- Create: `Omnia/Data/Persistence/Projections/OwnershipProjectionRecord.swift`
- Create: `Omnia/Data/Persistence/EventStore/EventProjectionEngine.swift`
- Create: `Omnia/Domain/Progress/ProgressCommandHandler.swift`
- Create: `Omnia/Domain/Watchlist/WatchlistCommandHandler.swift`
- Create: `Omnia/Domain/Sync/OwnershipCommandHandler.swift`
- Modify: `Omnia/Data/Persistence/EventStore/EventStoreSchema.swift`
- Test: `OmniaTests/ProjectionTests.swift`
- Test: `OmniaTests/CommandHandlerTests.swift`

**Interfaces:**
- Consumes: `ProfileEventStore.execute` and decoded events.
- Produces: typed progress/watchlist/ownership commands and disposable read projections.

- [ ] **Step 1: Write failing projection tests**

~~~swift
func testProgressProjectionUsesNewestLocalSequence() async throws {
    let store = try ProfileEventStore.inMemory(profile: .fixtureA)
    try await store.recordProgress(.fixture(position: 100), commandID: .id1)
    try await store.recordProgress(.fixture(position: 140), commandID: .id2)
    let projection = try await store.progress(mediaKey: .fixture, episodeKey: nil)
    XCTAssertEqual(projection?.positionSeconds, 140)
    XCTAssertEqual(projection?.lastSequence, 2)
}

func testWatchlistRemoveIsRebuiltFromEvents() async throws {
    let store = try ProfileEventStore.inMemory(profile: .fixtureA)
    try await store.addToWatchlist(.fixture, commandID: .id1)
    try await store.removeFromWatchlist(.fixture, commandID: .id2)
    try await store.rebuildProjections()
    XCTAssertNil(try await store.watchlistItem(mediaKey: .fixture))
}
~~~

Add completion, clear, invalid duration, backward-progress policy, duplicate command, Continue Watching ordering, and owner capability validation.

- [ ] **Step 2: Run RED**

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test -only-testing:OmniaTests/ProjectionTests -only-testing:OmniaTests/CommandHandlerTests
~~~

- [ ] **Step 3: Implement projections and command handlers**

Projection unique keys are bounded normalized media/episode keys. Every row stores last applied sequence. Handlers validate values and owner capability, emit events, and delegate atomic append/projection to `ProfileEventStore`. Coalesce playback updates unless position changed by at least ten seconds, completion state changed, or a forced stop event occurs; never emit at the 250 ms player observation rate.

- [ ] **Step 4: Prove deterministic rebuild**

Capture normalized projections, delete projection rows/checkpoints, rebuild, and compare all value fields and last sequences. Run the same fixture twice from fresh stores.

- [ ] **Step 5: Run GREEN and commit**

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test -only-testing:OmniaTests/ProjectionTests -only-testing:OmniaTests/CommandHandlerTests
git diff --check -- Omnia/Data/Persistence Omnia/Domain/Progress Omnia/Domain/Watchlist Omnia/Domain/Sync OmniaTests/ProjectionTests.swift OmniaTests/CommandHandlerTests.swift
git add -- Omnia/Data/Persistence Omnia/Domain/Progress Omnia/Domain/Watchlist Omnia/Domain/Sync OmniaTests/ProjectionTests.swift OmniaTests/CommandHandlerTests.swift
git commit --only -m "Project local progress and watchlist events" -- Omnia/Data/Persistence Omnia/Domain/Progress Omnia/Domain/Watchlist Omnia/Domain/Sync OmniaTests/ProjectionTests.swift OmniaTests/CommandHandlerTests.swift
~~~

### Task 6: Implement Delivery and Offline Recovery

**Files:**
- Create: `Omnia/Data/Persistence/Delivery/ProviderDeliveryAdapter.swift`
- Create: `Omnia/Data/Persistence/Delivery/OutboxWorker.swift`
- Create: `OmniaTests/TestSupport/FixtureDeliveryAdapter.swift`
- Test: `OmniaTests/OutboxWorkerTests.swift`

**Interfaces:**
- Consumes: `EventDeliveryRecord`, `ProfileEventStore`, `OmniaClock`, and normalized provider capability contracts.
- Produces: `ProviderMutation`, `DeliveryResult`, `ProviderDeliveryAdapter.deliver`, and `OutboxWorker.runEligible()`.

- [ ] **Step 1: Write failing recovery tests**

~~~swift
func testAcknowledgementClearsOnlyCorrelatedDelivery() async throws {
    let fixture = try OutboxFixture.pending(count: 2)
    let worker = OutboxWorker(store: fixture.store, adapter: fixture.adapter.acknowledgingFirst)
    try await worker.runEligible()
    XCTAssertEqual(try await fixture.store.pendingDeliveryIDs(), [fixture.secondID])
    XCTAssertTrue(try await fixture.store.containsAcknowledgement(for: fixture.firstID))
}

func testStaleProfileCompletionCannotAcknowledge() async throws {
    let fixture = try OutboxFixture.pending(count: 1)
    let task = Task { try await fixture.worker.runEligible() }
    await fixture.adapter.waitUntilStarted()
    await fixture.store.invalidateActivation()
    await fixture.adapter.completeWithAcknowledgement()
    await XCTAssertThrowsErrorAsync(try await task.value)
    XCTAssertEqual(try await fixture.store.pendingDeliveryIDs(), [fixture.firstID])
}
~~~

Add restart, offline, cancellation, duplicate acknowledgement, Retry-After, bounded exponential backoff, permanent rejection, and per-item partial batch cases.

- [ ] **Step 2: Run RED**

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test -only-testing:OmniaTests/OutboxWorkerTests
~~~

- [ ] **Step 3: Implement network-outside-transaction delivery**

The worker fetches an immutable normalized mutation, releases the store actor, calls the adapter, then returns with original activation/event/delivery IDs. The store validates them before appending acknowledgement/retry/rejection events and mutating exactly one delivery in one save.

~~~swift
enum DeliveryResult: Equatable, Sendable {
    case acknowledged(providerRevision: String?)
    case retry(after: Duration, reason: DeliveryFailureClass)
    case rejected(reason: DeliveryFailureClass)
}
~~~

Do not store adapter request/response bodies or error descriptions.

- [ ] **Step 4: Run GREEN and commit**

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test -only-testing:OmniaTests/OutboxWorkerTests
git diff --check -- Omnia/Data/Persistence/Delivery OmniaTests/TestSupport/FixtureDeliveryAdapter.swift OmniaTests/OutboxWorkerTests.swift
git add -- Omnia/Data/Persistence/Delivery OmniaTests/TestSupport/FixtureDeliveryAdapter.swift OmniaTests/OutboxWorkerTests.swift
git commit --only -m "Recover provider deliveries offline" -- Omnia/Data/Persistence/Delivery OmniaTests/TestSupport/FixtureDeliveryAdapter.swift OmniaTests/OutboxWorkerTests.swift
~~~

### Task 7: Implement Conflicts and Explicit Provider Switching

**Files:**
- Create: `Omnia/Data/Persistence/Projections/ConflictProjectionRecord.swift`
- Create: `Omnia/Domain/Sync/ConflictResolver.swift`
- Create: `Omnia/Domain/Sync/ProviderMigrationCoordinator.swift`
- Modify: `Omnia/Data/Persistence/EventStore/EventStoreSchema.swift`
- Modify: `Omnia/Data/Persistence/EventStore/EventProjectionEngine.swift`
- Test: `OmniaTests/ConflictResolutionTests.swift`
- Test: `OmniaTests/ProviderMigrationTests.swift`

**Interfaces:**
- Consumes: provider observations, ownership projection, pending deliveries, and event append.
- Produces: `ConflictDecision`, `ProviderMigrationChoice`, `ProviderMigrationPreview`, and staged migration events.

- [ ] **Step 1: Write failing conflict tests**

~~~swift
func testAmbiguousRemoteObservationCreatesConflictWithoutOverwrite() async throws {
    let store = try ProfileEventStore.withLocalPendingProgress()
    try await store.observeRemoteProgress(.newerButUnordered)
    XCTAssertEqual(try await store.progress(.fixture), .localPending)
    XCTAssertEqual(try await store.conflicts().count, 1)
}

func testResolutionAppendsDecisionAndUnblocksOnlyAffectedItem() async throws {
    let store = try ProfileEventStore.withTwoConflicts()
    try await store.resolveConflict(store.firstConflictID, decision: .keepLocal)
    XCTAssertFalse(try await store.isBlocked(store.firstMediaKey))
    XCTAssertTrue(try await store.isBlocked(store.secondMediaKey))
}
~~~

- [ ] **Step 2: Run RED and implement explicit conflict projection**

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test -only-testing:OmniaTests/ConflictResolutionTests
~~~

Remote state appends a normalized observation. Trusted documented revisions/timestamps may establish ordering; otherwise simultaneous newer state creates a conflict event and blocks only that item. Never compare provider timestamps that the official contract does not define.

- [ ] **Step 3: Write failing provider-switch tests**

Cover `copyCurrent`, `replaceAfterPreview`, `startEmpty`, cancellation before commit, unsupported owner, pending-conflict blocking, duplicate correlation ID, and device-to-account copy that leaves the source unchanged.

- [ ] **Step 4: Implement migration staging**

~~~swift
enum ProviderMigrationChoice: Equatable, Sendable {
    case copyCurrent
    case replaceAfterPreview
    case startEmpty
}
~~~

Build a bounded preview first. A commit appends migration and ownership events atomically within one profile. Cross-profile copy writes idempotent correlated import events to the destination only; source deletion is never part of migration.

- [ ] **Step 5: Run GREEN and commit**

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test -only-testing:OmniaTests/ConflictResolutionTests -only-testing:OmniaTests/ProviderMigrationTests
git diff --check -- Omnia/Data/Persistence Omnia/Domain/Sync OmniaTests/ConflictResolutionTests.swift OmniaTests/ProviderMigrationTests.swift
git add -- Omnia/Data/Persistence Omnia/Domain/Sync OmniaTests/ConflictResolutionTests.swift OmniaTests/ProviderMigrationTests.swift
git commit --only -m "Make provider conflicts explicit" -- Omnia/Data/Persistence Omnia/Domain/Sync OmniaTests/ConflictResolutionTests.swift OmniaTests/ProviderMigrationTests.swift
~~~

### Task 8: Add Bounded Retention and Verified Generation Rollover

**Files:**
- Create: `Omnia/Domain/History/HistoryRetentionPolicy.swift`
- Create: `Omnia/Data/Persistence/Maintenance/BaselineBuilder.swift`
- Create: `Omnia/Data/Persistence/Maintenance/ProfileStoreCompactor.swift`
- Create: `Omnia/Data/Persistence/Maintenance/GenerationPointer.swift`
- Create: `OmniaTests/TestSupport/CompactionFaultInjector.swift`
- Test: `OmniaTests/RetentionPolicyTests.swift`
- Test: `OmniaTests/ProfileStoreCompactionTests.swift`

**Interfaces:**
- Consumes: profile stores, event reader/codec/projector, deterministic clock/IDs, and pending delivery state.
- Produces: `HistoryRetentionPolicy`, `BaselineBuilder`, and `ProfileStoreCompactor.compact`.

- [ ] **Step 1: Write failing retention tests**

~~~swift
func testDefaultRetentionIsOneYear() {
    XCTAssertEqual(HistoryRetentionPolicy.default, .oneYear)
}

func testPendingOrConflictedEventsRemainEligibleForRetention() {
    let decision = RetentionDecision.evaluate(.fixturePendingOldEvent, cutoff: .fixture)
    XCTAssertEqual(decision, .retain)
}
~~~

Test 3 months, 6 months, 1 year, Keep All, unfinished progress, current watchlist membership, and calendar-boundary behavior with a fixed Gregorian calendar/time zone.

- [ ] **Step 2: Run RED and implement policy**

~~~swift
enum HistoryRetentionPolicy: String, Codable, CaseIterable, Sendable {
    case threeMonths
    case sixMonths
    case oneYear
    case keepAll

    static let `default`: Self = .oneYear
}
~~~

Use calendar subtraction from the injected clock, not fixed 30/365-day seconds.

- [ ] **Step 3: Write failing rollover tests**

Prove normalized projections before and after compaction are equal; old eligible activity is absent; pending/conflicted/unacknowledged events remain; cancellation and injected failures before pointer replacement preserve the old generation; failures after pointer replacement retain a valid new generation; and the pointer never names a partially written directory.

- [ ] **Step 4: Implement baseline and atomic pointer replacement**

The builder writes a versioned `BaselineEstablishedEvent` containing minimum current state, then copies retained events in original logical order into a new generation. Replay the new generation in isolation and compare normalized projections. Write a temporary pointer file, fsync it and its directory where supported, then use `FileManager.replaceItemAt` for the active pointer. Delete the old generation only after reopening the new one successfully.

- [ ] **Step 5: Run GREEN and commit**

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test -only-testing:OmniaTests/RetentionPolicyTests -only-testing:OmniaTests/ProfileStoreCompactionTests
git diff --check -- Omnia/Domain/History Omnia/Data/Persistence/Maintenance OmniaTests/TestSupport/CompactionFaultInjector.swift OmniaTests/RetentionPolicyTests.swift OmniaTests/ProfileStoreCompactionTests.swift
git add -- Omnia/Domain/History Omnia/Data/Persistence/Maintenance OmniaTests/TestSupport/CompactionFaultInjector.swift OmniaTests/RetentionPolicyTests.swift OmniaTests/ProfileStoreCompactionTests.swift
git commit --only -m "Bound local event history retention" -- Omnia/Domain/History Omnia/Data/Persistence/Maintenance OmniaTests/TestSupport/CompactionFaultInjector.swift OmniaTests/RetentionPolicyTests.swift OmniaTests/ProfileStoreCompactionTests.swift
~~~

### Task 9: Implement Erasure and Corruption Recovery

**Files:**
- Create: `Omnia/Data/Persistence/Maintenance/WatchHistoryEraser.swift`
- Create: `Omnia/Data/Persistence/Maintenance/ProfileDataEraser.swift`
- Create: `Omnia/Data/Persistence/EventStore/EventStoreValidator.swift`
- Create: `Omnia/Data/Persistence/EventStore/StoreDiagnosticReport.swift`
- Test: `OmniaTests/WatchHistoryErasureTests.swift`
- Test: `OmniaTests/ProfileDataErasureTests.swift`
- Test: `OmniaTests/EventStoreValidationTests.swift`

**Interfaces:**
- Consumes: generation rollover, Keychain/profile mappings, translated-cache directory contract, and store schema.
- Produces: genuine watch-history/profile erasure and payload-free corruption reports.

- [ ] **Step 1: Write failing erasure tests**

Test clear-history rollover with keep/remove unfinished progress choices; watchlist preservation; no deleted event in any remaining generation; interrupted erasure rollback; full profile generation/cache/credential/mapping deletion; partial filesystem/Keychain failure categories; and inactive-profile requirement.

~~~swift
func testClearHistoryRemovesActivityFromEveryRemainingGeneration() async throws {
    let fixture = try ErasureFixture.withOldAndCurrentActivity()
    try await fixture.eraser.clearWatchHistory(unfinishedProgress: .keep)
    XCTAssertTrue(try fixture.scanAllRemainingEvents().allSatisfy { !$0.isRemovedWatchActivity })
    XCTAssertEqual(try await fixture.rebuiltProgress(), fixture.expectedUnfinishedProgress)
}
~~~

- [ ] **Step 2: Run RED and implement erasure through generation rollover**

Do not append a tombstone as the only action. Build and verify a generation excluding selected activity, swap the pointer, reopen it, then remove old generation files using supported filesystem deletion. Do not claim forensic secure erasure on flash storage. Profile deletion first cancels work and releases the handle, then deletes generations/cache and profile-scoped Keychain records.

- [ ] **Step 3: Write failing corruption tests**

Cover duplicate/gapped sequence, checksum mismatch, unsupported schema, checkpoint beyond event tail, projection mismatch, missing pointer, pointer to missing generation, and malformed pointer. Diagnostic reports may contain schema versions, sequences, type names, counts, and failure classes only.

- [ ] **Step 4: Implement validation and projection-only repair**

A projection/checkpoint mismatch triggers projection deletion and deterministic rebuild. Event corruption stops writes and preserves files. Never skip, rewrite, or guess an invalid event. Provide a `StoreDiagnosticReport` encoder whose test asserts prohibited payload fields are absent.

- [ ] **Step 5: Run GREEN and commit**

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test -only-testing:OmniaTests/WatchHistoryErasureTests -only-testing:OmniaTests/ProfileDataErasureTests -only-testing:OmniaTests/EventStoreValidationTests
git diff --check -- Omnia/Data/Persistence OmniaTests/WatchHistoryErasureTests.swift OmniaTests/ProfileDataErasureTests.swift OmniaTests/EventStoreValidationTests.swift
git add -- Omnia/Data/Persistence OmniaTests/WatchHistoryErasureTests.swift OmniaTests/ProfileDataErasureTests.swift OmniaTests/EventStoreValidationTests.swift
git commit --only -m "Erase and validate profile event data" -- Omnia/Data/Persistence OmniaTests/WatchHistoryErasureTests.swift OmniaTests/ProfileDataErasureTests.swift OmniaTests/EventStoreValidationTests.swift
~~~

### Task 10: Measure Event-Store Engineering Baselines

**Files:**
- Create: `OmniaTests/EventStorePerformanceTests.swift`
- Create: `docs/superpowers/evidence/2026-08-11-settings-phase-0b-event-store.md`

**Interfaces:**
- Consumes: the complete event store.
- Produces: reproducible engineering measurements without product-performance claims.

- [ ] **Step 1: Add deterministic performance scenarios**

Use XCTest metrics for 1,000 and 10,000 event append/replay fixtures, incremental open after a checkpoint, cold projection rebuild, and compaction. Fixtures contain fixed IDs and payload sizes.

~~~swift
func testMeasureIncrementalProjectionAfterCheckpoint() throws {
    let fixture = try PerformanceStoreFixture(events: 10_000, checkpointEvery: 500)
    measure(metrics: [XCTClockMetric(), XCTMemoryMetric(), XCTStorageMetric()]) {
        try fixture.openAndApplyTail(eventCount: 25)
    }
}
~~~

Do not add pass/fail time thresholds before representative Release hardware evidence exists.

- [ ] **Step 2: Run the measurement once in Release and record raw evidence**

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -configuration Release -destination 'platform=macOS' test -only-testing:OmniaTests/EventStorePerformanceTests
~~~

Record hardware, OS, build configuration, fixture sizes, each metric sample, variance, and limitations in the evidence file. Do not describe the result as faster, smooth, low-memory, or efficient.

- [ ] **Step 3: Commit**

~~~sh
git diff --check -- OmniaTests/EventStorePerformanceTests.swift docs/superpowers/evidence/2026-08-11-settings-phase-0b-event-store.md
git add -- OmniaTests/EventStorePerformanceTests.swift docs/superpowers/evidence/2026-08-11-settings-phase-0b-event-store.md
git commit --only -m "Measure the profile event store" -- OmniaTests/EventStorePerformanceTests.swift docs/superpowers/evidence/2026-08-11-settings-phase-0b-event-store.md
~~~

### Task 11: Verify Phase 0B

**Files:**
- Modify: `docs/superpowers/evidence/2026-08-11-settings-phase-0b-event-store.md`
- Modify only if verified behavior changes policy: `SECURITY.md`
- Modify only if local storage topology changes documentation: `INFRASTRUCTURE.md`

**Interfaces:**
- Consumes: Tasks 1–10 and the Phase 0A verification state.
- Produces: Phase 0B completion evidence and explicit pending gates.

- [ ] **Step 1: Run the focused suite**

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test -only-testing:OmniaTests/EventStoreSchemaTests -only-testing:OmniaTests/DomainEventCodecTests -only-testing:OmniaTests/ProfileStoreIsolationTests -only-testing:OmniaTests/ProfileEventStoreTests -only-testing:OmniaTests/EventReplayTests -only-testing:OmniaTests/ProjectionTests -only-testing:OmniaTests/CommandHandlerTests -only-testing:OmniaTests/OutboxWorkerTests -only-testing:OmniaTests/ConflictResolutionTests -only-testing:OmniaTests/ProviderMigrationTests -only-testing:OmniaTests/RetentionPolicyTests -only-testing:OmniaTests/ProfileStoreCompactionTests -only-testing:OmniaTests/WatchHistoryErasureTests -only-testing:OmniaTests/ProfileDataErasureTests -only-testing:OmniaTests/EventStoreValidationTests
~~~

Expected: every test passes with temporary/in-memory stores and no live provider.

- [ ] **Step 2: Run full affected verification**

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' build
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test
xcodebuild -project Omnia.xcodeproj -scheme Omnia -configuration Release -destination 'generic/platform=iOS Simulator' build
deno check --config supabase/functions/metadata/deno.json --lock supabase/functions/metadata/deno.lock --frozen supabase/functions/metadata/index.ts
deno test --config supabase/functions/metadata/deno.json --lock supabase/functions/metadata/deno.lock --frozen supabase/functions/metadata
git diff --quiet -- supabase/functions/metadata/deno.lock
~~~

- [ ] **Step 3: Review persistence and privacy invariants**

~~~sh
git status --short
git diff --check
git diff -- Omnia/Data/Persistence Omnia/Domain OmniaTests docs/superpowers/evidence SECURITY.md INFRASTRUCTURE.md
rg -n 'token|authorization|callback|signedURL|subtitleText|prompt|response|modelOutput' Omnia/Data/Persistence
git grep -nE '(sk_live_[A-Za-z0-9]+|ghp_[A-Za-z0-9]+|Bearer[[:space:]]+[A-Za-z0-9._-]+)' -- Omnia OmniaTests docs
~~~

Every persistence match must be an explicit prohibited-field guard, deletion path, or test—not a persisted property. No credential value may match.

- [ ] **Step 4: Record remaining gates**

Keep current-store migration, Settings UI, physical iPhone/iPad, iPad multitasking, accessibility UI, archive/notarization, hosted Supabase, real provider contracts, legal approval, production credentials, and comparative Instruments claims pending.

- [ ] **Step 5: Commit only Phase 0B evidence/policy documentation**

~~~sh
git add -- docs/superpowers/evidence/2026-08-11-settings-phase-0b-event-store.md
git commit --only -m "Verify the profile event store" -- docs/superpowers/evidence/2026-08-11-settings-phase-0b-event-store.md
~~~

If `SECURITY.md` or `INFRASTRUCTURE.md` has a verified Phase 0B edit, name it explicitly in both commands. Never stage unrelated documentation or existing user changes.
