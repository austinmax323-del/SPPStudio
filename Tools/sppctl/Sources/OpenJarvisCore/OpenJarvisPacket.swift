import Foundation

public final class OpenJarvisPacketAssembler {
    private let retrievalEngine: OpenJarvisRetrievalEngine

    public init(retrievalEngine: OpenJarvisRetrievalEngine) {
        self.retrievalEngine = retrievalEngine
    }

    public func assemble(task: OpenJarvisTask, role: OpenJarvisWorkerKind? = nil, limit: Int = 5, scopeOverride: [OpenJarvisRetrievalScope]? = nil) throws -> OpenJarvisWorkerPacket {
        let effectiveRole = role ?? task.targetWorker ?? .codex
        var queryParts: [String] = [task.interpretedObjective]
        let normalizedObjective = task.interpretedObjective.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedRawRequest = task.rawRequest.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedRawRequest != normalizedObjective {
            queryParts.append(task.rawRequest)
        }
        queryParts.append(contentsOf: task.neededMemory)
        let query = queryParts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: " ")
        let scopes = scopeOverride ?? inferOpenJarvisScopes(from: query)
        let hits = try retrievalEngine.retrieve(OpenJarvisRetrievalRequest(query: query, scopes: scopes, limit: limit))

        return OpenJarvisWorkerPacket(
            taskID: task.id,
            role: effectiveRole,
            task: task.interpretedObjective,
            allowedScope: task.allowedFiles,
            forbiddenScope: task.forbiddenFiles,
            retrievedContext: hits
        )
    }
}
