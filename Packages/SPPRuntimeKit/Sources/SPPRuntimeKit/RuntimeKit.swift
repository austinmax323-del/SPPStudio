import Foundation
import Combine

// MARK: - RuntimeEventKind

/// Discriminates the kind of runtime event captured during replay or live monitoring.
public enum RuntimeEventKind: String, Codable, Hashable, Sendable, CaseIterable {
    case hookInvoked
    case viewCreated
    case viewDestroyed
    case methodCalled
    case notificationPosted
    case memoryWarning
    case springBoardActivation
    case preferenceChanged
    case custom
}

// MARK: - RuntimeEvent

/// A single observable occurrence in the runtime timeline.
public struct RuntimeEvent: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let kind: RuntimeEventKind
    /// Virtual clock time (not wall time).
    public let timestamp: TimeInterval
    public let hookID: String?
    public let className: String?
    public let selectorName: String?
    public let metadata: [String: String]

    public init(
        id: UUID = UUID(),
        kind: RuntimeEventKind,
        timestamp: TimeInterval,
        hookID: String? = nil,
        className: String? = nil,
        selectorName: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.timestamp = timestamp
        self.hookID = hookID
        self.className = className
        self.selectorName = selectorName
        self.metadata = metadata
    }
}

// MARK: - TimelineBookmark

/// A named point on the virtual timeline used for navigation.
public struct TimelineBookmark: Identifiable, Codable, Sendable {
    public let id: UUID
    public var label: String
    public let timestamp: TimeInterval

    public init(id: UUID = UUID(), label: String, timestamp: TimeInterval) {
        self.id = id
        self.label = label
        self.timestamp = timestamp
    }
}

// MARK: - EventSnapshot

/// An immutable snapshot of events up to a given virtual timestamp.
public struct EventSnapshot: Codable, Sendable {
    public let timestamp: TimeInterval
    public let events: [RuntimeEvent]
    public let label: String

    public init(timestamp: TimeInterval, events: [RuntimeEvent], label: String) {
        self.timestamp = timestamp
        self.events = events
        self.label = label
    }
}

// MARK: - PlaybackState

/// Describes the current state of the replay engine.
public enum PlaybackState: String, Codable, Sendable {
    case idle
    case playing
    case paused
    case stepping
    case finished
}

// MARK: - ReplayClock

/// A virtual clock that drives replay without depending on wall time.
///
/// Advancement is driven externally via `advance(by:)`, which is typically
/// called from a display-link callback or a timer on the caller's side.
public actor ReplayClock {
    public private(set) var virtualTime: TimeInterval = 0
    public private(set) var rate: Double = 1.0
    public private(set) var state: PlaybackState = .idle

    public init() {}

    /// Begin playback at the given speed multiplier.
    public func play(rate: Double = 1.0) {
        self.rate = max(0, rate)
        state = .playing
    }

    /// Suspend playback, preserving current virtual time.
    public func pause() {
        state = .paused
    }

    /// Jump to an arbitrary virtual time without changing playback state.
    public func seek(to time: TimeInterval) {
        virtualTime = max(0, time)
    }

    /// Advance one frame (~16 ms at 60 fps) and enter `.stepping` state.
    public func stepForward(by delta: TimeInterval = 0.016) {
        state = .stepping
        virtualTime += delta
    }

    /// Reset the clock to its initial state.
    public func reset() {
        virtualTime = 0
        rate = 1.0
        state = .idle
    }

    /// Advance virtual time by `delta * rate` if currently playing.
    ///
    /// Call this from your display-link or timer handler. Does nothing unless
    /// `state == .playing`.
    public func advance(by delta: TimeInterval) {
        guard state == .playing else { return }
        virtualTime += delta * rate
    }
}

// MARK: - RuntimeTimeline

/// An ordered, append-only log of runtime events with bookmark and snapshot support.
public actor RuntimeTimeline {
    public private(set) var events: [RuntimeEvent] = []
    public private(set) var bookmarks: [TimelineBookmark] = []
    public private(set) var snapshots: [EventSnapshot] = []

    public init() {}

    /// Append a single event, maintaining sort order by timestamp.
    public func append(_ event: RuntimeEvent) {
        // Insert in sorted position to support out-of-order ingestion.
        let insertionIndex = events.partitioningIndex { $0.timestamp > event.timestamp }
        events.insert(event, at: insertionIndex)
    }

    /// Create and store a bookmark at the specified virtual time.
    @discardableResult
    public func addBookmark(label: String, at timestamp: TimeInterval) -> TimelineBookmark {
        let bookmark = TimelineBookmark(label: label, timestamp: timestamp)
        bookmarks.append(bookmark)
        return bookmark
    }

    /// Remove a previously added bookmark by its identifier.
    public func removeBookmark(id: UUID) {
        bookmarks.removeAll { $0.id == id }
    }

    /// Capture all events up to (and including) `timestamp` as an immutable snapshot.
    @discardableResult
    public func takeSnapshot(label: String, upTo timestamp: TimeInterval) -> EventSnapshot {
        let captured = events.filter { $0.timestamp <= timestamp }
        let snapshot = EventSnapshot(timestamp: timestamp, events: captured, label: label)
        snapshots.append(snapshot)
        return snapshot
    }

    /// Return all events whose timestamps fall within the closed range.
    public func events(in range: ClosedRange<TimeInterval>) -> [RuntimeEvent] {
        events.filter { range.contains($0.timestamp) }
    }

    /// Remove all events, bookmarks, and snapshots.
    public func clear() {
        events.removeAll()
        bookmarks.removeAll()
        snapshots.removeAll()
    }
}

// MARK: - RuntimeSession

/// Lightweight value that identifies a recording or replay session.
public struct RuntimeSession: Sendable {
    public let id: UUID
    public let startedAt: Date
    public var label: String

    public init(label: String = "Session") {
        self.id = UUID()
        self.startedAt = Date()
        self.label = label
    }
}

// MARK: - ReplayEngine

/// Coordinates the clock, timeline, and event delivery for replay.
///
/// Callers drive the engine by calling `tick(wallDelta:)` from their display-link
/// or timer callback. The engine advances the virtual clock and emits events
/// through `publisher` as they become current.
public actor ReplayEngine {
    public let timeline: RuntimeTimeline
    public let clock: ReplayClock

    // `nonisolated(unsafe)` because PassthroughSubject is not Sendable; all
    // mutations happen inside actor-isolated methods, so this is safe.
    nonisolated(unsafe) private let eventPublisher = PassthroughSubject<RuntimeEvent, Never>()

    /// Combine publisher that emits events in virtual time order as they are
    /// reached during playback or stepping.
    nonisolated public var publisher: AnyPublisher<RuntimeEvent, Never> {
        eventPublisher.eraseToAnyPublisher()
    }

    /// The virtual time from which the current playback window starts.
    /// Updated each tick to avoid re-emitting already-published events.
    private var lastEmittedTime: TimeInterval = 0

    public init(timeline: RuntimeTimeline) {
        self.timeline = timeline
        self.clock = ReplayClock()
    }

    /// Start replay from the clock's current virtual time.
    public func play(rate: Double = 1.0) async {
        await clock.play(rate: rate)
    }

    /// Pause without resetting position.
    public func pause() async {
        await clock.pause()
    }

    /// Seek the clock to `time` and reset the emission cursor.
    public func seek(to time: TimeInterval) async {
        await clock.seek(to: time)
        lastEmittedTime = time
    }

    /// Advance exactly one frame and emit any events in that window.
    public func step() async {
        let before = await clock.virtualTime
        await clock.stepForward()
        let after = await clock.virtualTime
        await emitEvents(in: before...after)
        lastEmittedTime = after
    }

    /// Advance the virtual clock by `wallDelta` (scaled by the clock's rate)
    /// and publish any events that fall within the advanced window.
    ///
    /// Designed to be called from a display-link handler on an arbitrary queue.
    public func tick(wallDelta: TimeInterval) async {
        let before = await clock.virtualTime
        await clock.advance(by: wallDelta)
        let after = await clock.virtualTime

        guard after > before else { return }

        await emitEvents(in: before...after)
        lastEmittedTime = after

        // Detect end-of-timeline.
        let allEvents = await timeline.events
        if let last = allEvents.last, after >= last.timestamp {
            await clock.pause()
        }
    }

    // MARK: Private helpers

    private func emitEvents(in range: ClosedRange<TimeInterval>) async {
        let window = await timeline.events(in: range)
        for event in window {
            eventPublisher.send(event)
        }
    }
}

// MARK: - LifecycleSimulator

/// Generates synthetic runtime event sequences for testing and demonstration.
public actor LifecycleSimulator {

    public init() {}

    /// Produce a realistic SpringBoard app-launch event sequence.
    ///
    /// - Parameter baseTime: The virtual timestamp assigned to the first event.
    /// - Returns: Five ordered `RuntimeEvent` values spaced 0.1 s apart.
    public static func springBoardLaunchSequence(at baseTime: TimeInterval = 0) -> [RuntimeEvent] {
        let step: TimeInterval = 0.1
        return [
            RuntimeEvent(
                kind: .springBoardActivation,
                timestamp: baseTime,
                metadata: ["phase": "willActivate"]
            ),
            RuntimeEvent(
                kind: .hookInvoked,
                timestamp: baseTime + step,
                hookID: "hook.applicationWillFinishLaunching",
                selectorName: "applicationWillFinishLaunching:",
                metadata: ["source": "SpringBoard"]
            ),
            RuntimeEvent(
                kind: .hookInvoked,
                timestamp: baseTime + step * 2,
                hookID: "hook.applicationDidFinishLaunching",
                selectorName: "applicationDidFinishLaunching:",
                metadata: ["source": "SpringBoard"]
            ),
            RuntimeEvent(
                kind: .viewCreated,
                timestamp: baseTime + step * 3,
                className: "UIWindow",
                metadata: ["isKeyWindow": "true"]
            ),
            RuntimeEvent(
                kind: .viewCreated,
                timestamp: baseTime + step * 4,
                className: "UIRootViewController",
                metadata: ["isInitialController": "true"]
            )
        ]
    }
}

// MARK: - Collection helpers

private extension Collection {
    /// Returns the index of the first element satisfying `predicate`, or
    /// `endIndex` if none does. Used for sorted insertion.
    func partitioningIndex(where predicate: (Element) -> Bool) -> Index {
        var lo = startIndex
        var hi = endIndex
        while lo < hi {
            let mid = index(lo, offsetBy: distance(from: lo, to: hi) / 2)
            if predicate(self[mid]) {
                hi = mid
            } else {
                lo = index(after: mid)
            }
        }
        return lo
    }
}
