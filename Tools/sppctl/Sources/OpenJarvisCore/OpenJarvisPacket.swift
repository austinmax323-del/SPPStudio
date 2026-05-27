import Foundation

public final class OpenJarvisPacketAssembler {
    private let retrievalEngine: OpenJarvisRetrievalEngine

    public init(retrievalEngine: OpenJarvisRetrievalEngine) {
        self.retrievalEngine = retrievalEngine
    }

    public func assemble(task: OpenJarvisTask, role: OpenJarvisWorkerKind? = nil, limit: Int = 5, scopeOverride: [OpenJarvisRetrievalScope]? = nil) throws -> OpenJarvisWorkerPacket {
        let effectiveRole = role ?? task.targetWorker ?? .codex
        let query = [task.interpretedObjective, task.rawRequest, task.neededMemory.joined(separator: " ")].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: " ")
        let scopes = scopeOverride ?? inferOpenJarvisScopes(from: query)
        let hits = try retrievalEngine.retrieve(OpenJarvisRetrievalRequest(query: query, scopes: scopes, limit: limit))

        return OpenJarvisWorkerPacket(
            taskID: task.id,
            role: effectiveRole,
            task: task.interpretedObjective,
            allowedScope: task.allowedFiles,
            forbiddenScope: task.forbiddenFiles,
            retrievedContext: hits,
            validationRequirements: validationRequirements(for: task),
            stopConditions: stopConditions(for: task),
            writebackInstructions: writebackInstructions(for: task, role: effectiveRole)
        )
    }

    private func validationRequirements(for task: OpenJarvisTask) -> [String] {
        var items: [String] = []
        if task.checkpointRequired {
            items.append("Capture a git checkpoint before any write-heavy step.")
        }
        if task.validationRequired {
            items.append("Validate against the task acceptance criteria before closing.")
        }
        items.append("Keep the task manual-first and inspectable.")
        return items
    }

    private func stopConditions(for task: OpenJarvisTask) -> [String] {
        var items: [String] = [
            "Stop if the scope expands beyond the allowed files.",
            "Stop if the task would require autonomous execution.",
            "Stop if validation or ownership becomes unclear."
        ]
        if !task.forbiddenFiles.isEmpty {
            items.append("Stop if any forbidden file becomes necessary.")
        }
        return items
    }

    private func writebackInstructions(for task: OpenJarvisTask, role: OpenJarvisWorkerKind) -> [String] {
        var items = [
            "Write a compact memory digest.",
            "Update the session handoff.",
            "Record the decision or failure in the smallest durable note."
        ]
        if role == .claude {
            items.insert("Use architecture or recovery notes when they change future decisions.", at: 0)
        } else {
            items.insert("Use the packet to drive fast implementation, not hidden automation.", at: 0)
        }
        if task.memoryWritebackRequired == false {
            items.append("Memory writeback is not required for this task, but keep the outcome visible if it matters.")
        }
        return items
    }
}
