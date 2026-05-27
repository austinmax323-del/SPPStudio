import Foundation

public enum OpenJarvisStage: String, Codable, CaseIterable {
    case intake
    case retrieve
    case assemble
    case assignWorker = "assign_worker"
    case validateScope = "validate_scope"
    case checkpointRequirement = "checkpoint_requirement"
    case executionReady = "execution_ready"
    case completed
    case writeback
}

public enum OpenJarvisExecutionState: String, Codable, CaseIterable {
    case pending
    case ready
    case blocked
    case done
}

public enum OpenJarvisCompletionState: String, Codable, CaseIterable {
    case open
    case completed
}

public enum OpenJarvisWritebackState: String, Codable, CaseIterable {
    case notRequired = "not_required"
    case pending
    case written
}

public enum OpenJarvisWorkerKind: String, Codable, CaseIterable {
    case claude
    case codex
    case localModel = "local_model"

    public var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .localModel: return "Local Model"
        }
    }
}

public enum OpenJarvisRetrievalScope: String, Codable, CaseIterable {
    case architecture
    case runtime
    case coordination
    case validation
    case continuity
    case memoryDigests = "memory_digests"
    case activeTasks = "active_tasks"
    case failures
    case decisions

    public var pathPrefixes: [String] {
        switch self {
        case .architecture:
            return ["20_ArchitectureMemory/"]
        case .runtime:
            return ["50_RuntimeOps/"]
        case .coordination:
            return ["30_AI_Coordination/"]
        case .validation:
            return ["60_DeliveryValidation/"]
        case .continuity:
            return ["70_SessionContinuity/"]
        case .memoryDigests:
            return ["80_SessionMemory/"]
        case .activeTasks:
            return ["70_SessionContinuity/OpenJarvis Active Task.md", "70_SessionContinuity/OpenJarvis Session Handoff.md"]
        case .failures:
            return ["50_RuntimeOps/", "20_ArchitectureMemory/Known Failure Modes.md", "20_ArchitectureMemory/Failure Mode Map.md"]
        case .decisions:
            return ["20_ArchitectureMemory/Decision Log.md", "20_ArchitectureMemory/Architecture Contracts.md"]
        }
    }
}

public struct OpenJarvisRetrievalHit: Codable, Hashable {
    public var path: String
    public var title: String
    public var score: Int
    public var reasons: [String]
    public var excerpt: String
    public var tags: [String]
    public var links: [String]
}

public struct OpenJarvisTaskEvent: Codable, Hashable {
    public var id: Int
    public var taskID: String?
    public var type: String
    public var payloadJSON: String
    public var createdAt: String
}

public struct OpenJarvisTaskDraft {
    public var rawRequest: String
    public var interpretedObjective: String
    public var projectContext: String?
    public var trustZone: String
    public var riskLevel: String
    public var allowedFiles: [String]
    public var forbiddenFiles: [String]
    public var targetWorker: OpenJarvisWorkerKind?
    public var neededMemory: [String]
    public var checkpointRequired: Bool
    public var validationRequired: Bool
    public var memoryWritebackRequired: Bool
    public var nextAction: String?
    public var vaultRoot: String?

    public init(
        rawRequest: String,
        interpretedObjective: String,
        projectContext: String? = nil,
        trustZone: String,
        riskLevel: String,
        allowedFiles: [String],
        forbiddenFiles: [String],
        targetWorker: OpenJarvisWorkerKind? = nil,
        neededMemory: [String],
        checkpointRequired: Bool,
        validationRequired: Bool,
        memoryWritebackRequired: Bool,
        nextAction: String? = nil,
        vaultRoot: String? = nil
    ) {
        self.rawRequest = rawRequest
        self.interpretedObjective = interpretedObjective
        self.projectContext = projectContext
        self.trustZone = trustZone
        self.riskLevel = riskLevel
        self.allowedFiles = allowedFiles
        self.forbiddenFiles = forbiddenFiles
        self.targetWorker = targetWorker
        self.neededMemory = neededMemory
        self.checkpointRequired = checkpointRequired
        self.validationRequired = validationRequired
        self.memoryWritebackRequired = memoryWritebackRequired
        self.nextAction = nextAction
        self.vaultRoot = vaultRoot
    }
}

public struct OpenJarvisTask: Codable, Identifiable, Hashable {
    public var id: String
    public var rawRequest: String
    public var interpretedObjective: String
    public var projectContext: String?
    public var trustZone: String
    public var riskLevel: String
    public var allowedFiles: [String]
    public var forbiddenFiles: [String]
    public var targetWorker: OpenJarvisWorkerKind?
    public var neededMemory: [String]
    public var checkpointRequired: Bool
    public var validationRequired: Bool
    public var memoryWritebackRequired: Bool
    public var nextAction: String?
    public var vaultRoot: String?
    public var stage: OpenJarvisStage
    public var executionState: OpenJarvisExecutionState
    public var completionState: OpenJarvisCompletionState
    public var writebackState: OpenJarvisWritebackState
    public var retrievedContext: [OpenJarvisRetrievalHit]
    public var packetText: String?
    public var createdAt: String
    public var updatedAt: String
    public var completedAt: String?
    public var writtenBackAt: String?

    public init(
        id: String = UUID().uuidString,
        rawRequest: String,
        interpretedObjective: String,
        projectContext: String?,
        trustZone: String,
        riskLevel: String,
        allowedFiles: [String],
        forbiddenFiles: [String],
        targetWorker: OpenJarvisWorkerKind?,
        neededMemory: [String],
        checkpointRequired: Bool,
        validationRequired: Bool,
        memoryWritebackRequired: Bool,
        nextAction: String?,
        vaultRoot: String?,
        stage: OpenJarvisStage = .intake,
        executionState: OpenJarvisExecutionState = .pending,
        completionState: OpenJarvisCompletionState = .open,
        writebackState: OpenJarvisWritebackState? = nil,
        retrievedContext: [OpenJarvisRetrievalHit] = [],
        packetText: String? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil,
        completedAt: String? = nil,
        writtenBackAt: String? = nil
    ) {
        let timestamp = ISO8601DateFormatter.openJarvis.string(from: Date())
        self.id = id
        self.rawRequest = rawRequest
        self.interpretedObjective = interpretedObjective
        self.projectContext = projectContext
        self.trustZone = trustZone
        self.riskLevel = riskLevel
        self.allowedFiles = allowedFiles
        self.forbiddenFiles = forbiddenFiles
        self.targetWorker = targetWorker
        self.neededMemory = neededMemory
        self.checkpointRequired = checkpointRequired
        self.validationRequired = validationRequired
        self.memoryWritebackRequired = memoryWritebackRequired
        self.nextAction = nextAction
        self.vaultRoot = vaultRoot
        self.stage = stage
        self.executionState = executionState
        self.completionState = completionState
        self.writebackState = writebackState ?? (memoryWritebackRequired ? .pending : .notRequired)
        self.retrievedContext = retrievedContext
        self.packetText = packetText
        self.createdAt = createdAt ?? timestamp
        self.updatedAt = updatedAt ?? timestamp
        self.completedAt = completedAt
        self.writtenBackAt = writtenBackAt
    }
}

public struct OpenJarvisWorkerPacket: Codable, Hashable {
    public var taskID: String
    public var role: OpenJarvisWorkerKind
    public var task: String
    public var allowedScope: [String]
    public var forbiddenScope: [String]
    public var retrievedContext: [OpenJarvisRetrievalHit]
    public var validationRequirements: [String]
    public var stopConditions: [String]
    public var writebackInstructions: [String]

    public var markdown: String {
        var lines: [String] = []
        lines.append("# OpenJarvis Worker Packet")
        lines.append("")
        lines.append("Task: \(task)")
        lines.append("Role: \(role.displayName)")
        lines.append("")
        lines.append("Allowed scope:")
        lines.append(contentsOf: allowedScope.isEmpty ? ["- (not specified)"] : allowedScope.map { "- \($0)" })
        lines.append("")
        lines.append("Forbidden scope:")
        lines.append(contentsOf: forbiddenScope.isEmpty ? ["- (not specified)"] : forbiddenScope.map { "- \($0)" })
        lines.append("")
        lines.append("Retrieved context:")
        if retrievedContext.isEmpty {
            lines.append("- (none)")
        } else {
            for hit in retrievedContext {
                lines.append("- [\(hit.score)] \(hit.title) — \(hit.path)")
                if !hit.reasons.isEmpty {
                    lines.append("  - reasons: \(hit.reasons.joined(separator: ", "))")
                }
                if !hit.excerpt.isEmpty {
                    lines.append("  - excerpt: \(hit.excerpt)")
                }
            }
        }
        lines.append("")
        lines.append("Validation requirements:")
        lines.append(contentsOf: validationRequirements.isEmpty ? ["- (not specified)"] : validationRequirements.map { "- \($0)" })
        lines.append("")
        lines.append("Stop conditions:")
        lines.append(contentsOf: stopConditions.isEmpty ? ["- scope expands", "- validation fails", "- blocked state appears"] : stopConditions.map { "- \($0)" })
        lines.append("")
        lines.append("Writeback instructions:")
        lines.append(contentsOf: writebackInstructions.isEmpty ? ["- update OpenJarvis memory digest", "- record the session handoff", "- keep the result manual-first"] : writebackInstructions.map { "- \($0)" })
        return lines.joined(separator: "\n")
    }
}

public struct OpenJarvisTaskSummary: Hashable {
    public var id: String
    public var stage: OpenJarvisStage
    public var executionState: OpenJarvisExecutionState
    public var completionState: OpenJarvisCompletionState
    public var writebackState: OpenJarvisWritebackState
    public var worker: OpenJarvisWorkerKind?
    public var objective: String
    public var updatedAt: String
}

extension ISO8601DateFormatter {
    static let openJarvis: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
