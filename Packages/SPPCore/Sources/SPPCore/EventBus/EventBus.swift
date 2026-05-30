import Combine
import Foundation

public protocol SPPEvent: Sendable {}

public final class EventBus: @unchecked Sendable {
    private let subject = PassthroughSubject<any SPPEvent, Never>()
    private let lock = NSLock()

    public init() {}

    public func publish<E: SPPEvent>(_ event: E) {
        subject.send(event)
    }

    public func publisher<E: SPPEvent>(for eventType: E.Type) -> AnyPublisher<E, Never> {
        subject
            .compactMap { $0 as? E }
            .eraseToAnyPublisher()
    }
}

// MARK: - Core events

public struct ProjectOpenedEvent: SPPEvent {
    public let projectID: UUID
    public init(projectID: UUID) { self.projectID = projectID }
}

public struct ProjectClosedEvent: SPPEvent {
    public let projectID: UUID
    public init(projectID: UUID) { self.projectID = projectID }
}

public struct ProjectSavedEvent: SPPEvent {
    public let projectID: UUID
    public init(projectID: UUID) { self.projectID = projectID }
}

public struct FileSelectedEvent: SPPEvent {
    public let fileID: UUID
    public init(fileID: UUID) { self.fileID = fileID }
}

public struct BuildStartedEvent: SPPEvent {
    public let projectID: UUID
    public init(projectID: UUID) { self.projectID = projectID }
}

public struct BuildCompletedEvent: SPPEvent {
    public let projectID: UUID
    public let success: Bool
    public init(projectID: UUID, success: Bool) {
        self.projectID = projectID
        self.success = success
    }
}

public struct BuildOutputLineEvent: SPPEvent {
    public let line: String
    public let isError: Bool
    public init(line: String, isError: Bool = false) { self.line = line; self.isError = isError }
}

public struct LogEntryEvent: SPPEvent {
    public let category: String
    public let level: String
    public let message: String
    public init(category: String, level: String, message: String) {
        self.category = category; self.level = level; self.message = message
    }
}
