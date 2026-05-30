import Foundation
import Combine
import SPPCore
import SPPRuntimeKit
import SPPSymbolKit

// MARK: - InstrumentationCapabilities

/// A bitmask describing the runtime capabilities offered by a particular adapter.
public struct InstrumentationCapabilities: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// Adapter can resolve symbol names to runtime addresses.
    public static let symbolResolution  = InstrumentationCapabilities(rawValue: 1 << 0)
    /// Adapter can intercept Objective-C method calls via hook injection.
    public static let methodHooking     = InstrumentationCapabilities(rawValue: 1 << 1)
    /// Adapter can read and (optionally) write process memory regions.
    public static let memoryInspection  = InstrumentationCapabilities(rawValue: 1 << 2)
    /// Adapter can enumerate loaded Objective-C classes at runtime.
    public static let classListing      = InstrumentationCapabilities(rawValue: 1 << 3)
    /// Adapter can enumerate methods on a given Objective-C class.
    public static let methodListing     = InstrumentationCapabilities(rawValue: 1 << 4)
    /// Adapter supports injecting updated code without relaunching the target.
    public static let liveReload        = InstrumentationCapabilities(rawValue: 1 << 5)

    /// Convenience union of every capability flag defined above.
    public static let all: InstrumentationCapabilities = [
        .symbolResolution,
        .methodHooking,
        .memoryInspection,
        .classListing,
        .methodListing,
        .liveReload
    ]
}

// MARK: - InstrumentationTarget

/// Identifies the process that an instrumentation session attaches to.
///
/// At a minimum `processName` must be non-empty; `bundleID`, `pid`, and
/// `deviceID` are optional and narrow the match when present.
public struct InstrumentationTarget: Codable, Sendable {
    /// Short process name as it appears in the target's process list (e.g. `"SpringBoard"`).
    public let processName: String
    /// Bundle identifier of the target application (e.g. `"com.apple.springboard"`).
    public let bundleID: String?
    /// UNIX process ID, if already known.
    public let pid: Int?
    /// Identifier of the remote device (Frida device ID, UDID, etc.). `nil` implies local.
    public let deviceID: String?

    public init(
        processName: String,
        bundleID: String? = nil,
        pid: Int? = nil,
        deviceID: String? = nil
    ) {
        self.processName = processName
        self.bundleID = bundleID
        self.pid = pid
        self.deviceID = deviceID
    }
}

// MARK: - RuntimeProbe

/// Specifies a single observation point attached to a hook during a session.
///
/// Probes are keyed by `hookID` (which maps to an `SPPHook` registered in the
/// project) and carry optional filtering and capture settings.
public struct RuntimeProbe: Identifiable, Sendable {
    /// Stable identity for attaching/detaching within a session.
    public let id: UUID
    /// The hook identifier this probe observes (matches `SPPHook.id`).
    public let hookID: String
    /// An optional JavaScript-style boolean expression evaluated against the
    /// invocation's arguments at runtime (e.g. `"arg0 != nil"`).
    public let condition: String?
    /// When `true`, the adapter captures a stack backtrace on each invocation.
    public let collectsBacktrace: Bool
    /// When `true`, the adapter captures argument values on each invocation.
    public let collectsArguments: Bool

    public init(
        id: UUID = UUID(),
        hookID: String,
        condition: String? = nil,
        collectsBacktrace: Bool = false,
        collectsArguments: Bool = true
    ) {
        self.id = id
        self.hookID = hookID
        self.condition = condition
        self.collectsBacktrace = collectsBacktrace
        self.collectsArguments = collectsArguments
    }
}

// MARK: - InstrumentationSessionState

/// Lifecycle state of an `InstrumentationSession`.
public enum InstrumentationSessionState: Sendable {
    /// Not connected to any target process.
    case disconnected
    /// Handshake with the target is in progress.
    case connecting
    /// Fully attached and able to fire probes.
    case active
    /// Temporarily halted; probes remain registered but will not fire.
    case suspended
    /// An unrecoverable error has occurred; the associated value carries a description.
    case error(String)
}

// MARK: - InstrumentationSession

/// An active connection to a target process that can be observed via `RuntimeProbe`s.
///
/// Conforming types are responsible for thread-safety; all mutating operations
/// are async to support actor-based implementations.
public protocol InstrumentationSession: Sendable {
    /// Unique identifier for this session instance.
    var id: UUID { get }
    /// The target process this session is attached to.
    var target: InstrumentationTarget { get }
    /// The current lifecycle state of this session.
    var state: InstrumentationSessionState { get async }
    /// Combine publisher that streams `RuntimeEvent` values as probes fire.
    var eventPublisher: AnyPublisher<RuntimeEvent, Never> { get }

    /// Registers a new probe with the attached process.
    /// - Throws: `SPPError.unsupported` if the adapter does not support the
    ///   probe's required capabilities, or an adapter-specific error.
    func attachProbe(_ probe: RuntimeProbe) async throws

    /// Removes a previously registered probe by its identity.
    func detachProbe(id: UUID) async throws

    /// Temporarily halts probe firing without disconnecting.
    func suspend() async throws

    /// Resumes a suspended session so probes fire again.
    func resume() async throws

    /// Detaches from the target and tears down all resources.
    func terminate() async
}

// MARK: - InstrumentationAdapter

/// A back-end strategy that knows how to connect to a specific type of runtime
/// instrumentation infrastructure (e.g. Frida, LLDB, FLEX).
///
/// Adapters are pure protocol abstractions — no implementation details are
/// required at this layer.
public protocol InstrumentationAdapter: Sendable {
    /// Stable reverse-DNS-style identifier, e.g. `"frida.usb"`.
    var adapterID: String { get }
    /// Human-readable name shown in the UI, e.g. `"Frida (USB)"`.
    var displayName: String { get }
    /// The set of capabilities this adapter provides.
    var capabilities: InstrumentationCapabilities { get }

    /// Asynchronously tests whether the adapter can be used right now
    /// (e.g. checks that the required daemon is running).
    func isAvailable() async -> Bool

    /// Connects to `target` and returns an active session.
    /// - Throws: An adapter-specific error if the connection fails.
    func connect(to target: InstrumentationTarget) async throws -> any InstrumentationSession
}

// MARK: - InstrumentationBridgeError

/// Errors thrown by `InstrumentationBridge`.
public enum InstrumentationBridgeError: LocalizedError, Sendable {
    case adapterNotFound(String)
    case adapterUnavailable(String)
    case sessionNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case .adapterNotFound(let id):
            return "No instrumentation adapter registered with id '\(id)'."
        case .adapterUnavailable(let id):
            return "Adapter '\(id)' is currently unavailable."
        case .sessionNotFound(let id):
            return "No active instrumentation session with id '\(id)'."
        }
    }
}

// MARK: - InstrumentationBridge

/// Thread-safe registry and lifecycle manager for instrumentation adapters and sessions.
///
/// Register one or more `InstrumentationAdapter` implementations, then call
/// `connect(using:to:)` to open a session. All active sessions are tracked and
/// can be terminated individually or all at once.
public actor InstrumentationBridge {

    private var adapters: [String: any InstrumentationAdapter] = [:]
    private var activeSessions: [UUID: any InstrumentationSession] = [:]

    public init() {}

    // MARK: Adapter Registration

    /// Registers `adapter`, replacing any existing adapter with the same `adapterID`.
    public func register(_ adapter: any InstrumentationAdapter) {
        adapters[adapter.adapterID] = adapter
    }

    /// Returns the adapter registered under `id`, or `nil` if not found.
    public func adapter(id: String) -> (any InstrumentationAdapter)? {
        adapters[id]
    }

    // MARK: Adapter Discovery

    /// Returns all registered adapters for which `isAvailable()` returns `true`.
    ///
    /// Each adapter is queried concurrently via a `TaskGroup`.
    public func availableAdapters() async -> [any InstrumentationAdapter] {
        let allAdapters = Array(adapters.values)
        var available: [any InstrumentationAdapter] = []
        await withTaskGroup(of: (Bool, (any InstrumentationAdapter)).self) { group in
            for adapter in allAdapters {
                group.addTask {
                    let ok = await adapter.isAvailable()
                    return (ok, adapter)
                }
            }
            for await (ok, adapter) in group where ok {
                available.append(adapter)
            }
        }
        return available
    }

    // MARK: Session Management

    /// Connects to `target` using the adapter identified by `adapterID`.
    ///
    /// - Throws: `InstrumentationBridgeError.adapterNotFound` if no adapter is
    ///   registered under `adapterID`.
    /// - Throws: `InstrumentationBridgeError.adapterUnavailable` if
    ///   `isAvailable()` returns `false` for the adapter.
    /// - Throws: Any adapter-specific error propagated from `connect(to:)`.
    /// - Returns: The newly created, active session.
    @discardableResult
    public func connect(
        using adapterID: String,
        to target: InstrumentationTarget
    ) async throws -> any InstrumentationSession {
        guard let adapter = adapters[adapterID] else {
            throw InstrumentationBridgeError.adapterNotFound(adapterID)
        }
        guard await adapter.isAvailable() else {
            throw InstrumentationBridgeError.adapterUnavailable(adapterID)
        }
        let session = try await adapter.connect(to: target)
        activeSessions[session.id] = session
        return session
    }

    /// Returns the active session identified by `id`, or `nil` if it does not exist.
    public func session(id: UUID) -> (any InstrumentationSession)? {
        activeSessions[id]
    }

    /// Terminates the session with `id` and removes it from the registry.
    ///
    /// Does nothing if no session with that `id` exists.
    public func terminateSession(id: UUID) async {
        guard let session = activeSessions.removeValue(forKey: id) else { return }
        await session.terminate()
    }

    /// Terminates all active sessions and clears the session registry.
    public func terminateAll() async {
        let sessions = Array(activeSessions.values)
        activeSessions.removeAll()
        await withTaskGroup(of: Void.self) { group in
            for session in sessions {
                group.addTask { await session.terminate() }
            }
        }
    }

    // MARK: Introspection

    /// Returns identifiers of all currently active sessions.
    public func activeSessionIDs() -> [UUID] {
        Array(activeSessions.keys)
    }

    /// Returns all registered adapter identifiers.
    public func registeredAdapterIDs() -> [String] {
        Array(adapters.keys)
    }
}
