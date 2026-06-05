import Foundation

public struct OpenJarvisRetrievalRequest {
    public var query: String
    public var scopes: [OpenJarvisRetrievalScope]
    public var limit: Int

    public init(query: String, scopes: [OpenJarvisRetrievalScope] = [], limit: Int = 8) {
        self.query = query
        self.scopes = scopes
        self.limit = limit
    }
}

public final class OpenJarvisRetrievalEngine {
    private let vaultRoot: URL
    private let fileManager: FileManager

    public init(vaultRoot: URL, fileManager: FileManager = .default) {
        self.vaultRoot = vaultRoot.resolvingSymlinksInPath().standardizedFileURL
        self.fileManager = fileManager
    }

    public func retrieve(_ request: OpenJarvisRetrievalRequest) throws -> [OpenJarvisRetrievalHit] {
        let files = try markdownFiles(scopes: request.scopes)
        let terms = normalizeTerms(request.query)

        let hits = files.compactMap { path -> OpenJarvisRetrievalHit? in
            guard let text = try? String(contentsOf: path, encoding: .utf8) else { return nil }
            let rel = relativePath(for: path)
            let title = firstHeading(in: text) ?? path.deletingPathExtension().lastPathComponent
            let tags = extractTags(from: text)
            let links = extractLinks(from: text)
            let excerpt = excerpt(from: text)
            let score = score(path: rel, title: title, body: text, tags: tags, links: links, terms: terms, scopes: request.scopes)
            guard score > 0 else { return nil }
            let reasons = reasons(path: rel, title: title, body: text, tags: tags, links: links, terms: terms, scopes: request.scopes)
            return OpenJarvisRetrievalHit(path: rel, title: title, score: score, reasons: reasons, excerpt: excerpt, tags: tags, links: links)
        }

        return hits.sorted { lhs, rhs in
            if lhs.score == rhs.score { return lhs.path < rhs.path }
            return lhs.score > rhs.score
        }.prefix(request.limit).map { $0 }
    }

    private func markdownFiles(scopes: [OpenJarvisRetrievalScope]) throws -> [URL] {
        let enumerator = fileManager.enumerator(at: vaultRoot, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        var all: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            all.append(url)
        }
        let markdown = all.filter { $0.pathExtension.lowercased() == "md" }
        let scoped = scopes.isEmpty ? markdown : markdown.filter { url in
            let rel = relativePath(for: url).lowercased()
            return scopes.contains { scope in
                scope.pathPrefixes.contains { prefix in
                    rel.hasPrefix(prefix.lowercased())
                }
            }
        }
        return scoped.filter { !isNoise($0) }
    }

    private func isNoise(_ url: URL) -> Bool {
        let rel = relativePath(for: url)
        let noiseFragments = [
            "/.obsidian/",
            "/Queue/",
            "/SessionNotes/",
            "/Screenshots/",
            "/60_DeliveryValidation/VerificationArtifacts/",
            "/Excalidraw/",
            "/Canvases/",
            ".codex-backup"
        ]
        return noiseFragments.contains { rel.contains($0) }
    }

    private func relativePath(for url: URL) -> String {
        let rootPath = vaultRoot.resolvingSymlinksInPath().path
        let filePath = url.resolvingSymlinksInPath().path
        if filePath.hasPrefix(rootPath + "/") {
            return String(filePath.dropFirst(rootPath.count + 1))
        }
        if filePath == rootPath {
            return url.lastPathComponent
        }
        return filePath
    }

    private static let stopWords: Set<String> = [
        "a", "and", "current", "for", "in", "of", "on", "review", "the", "with"
    ]

    private func normalizeTerms(_ raw: String) -> [String] {
        let lower = raw.lowercased()
        let regex = try? NSRegularExpression(pattern: #"[a-z0-9]+"#, options: [])
        let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
        var seen = Set<String>()
        var terms: [String] = []
        regex?.enumerateMatches(in: lower, options: [], range: range) { match, _, _ in
            guard let match, let r = Range(match.range, in: lower) else { return }
            let term = String(lower[r])
            guard term.count >= 2, !Self.stopWords.contains(term), seen.insert(term).inserted else { return }
            terms.append(term)
        }
        return terms
    }

    private func firstHeading(in text: String) -> String? {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("# ") {
                return String(line.dropFirst(2))
            }
        }
        return nil
    }

    private func extractTags(from text: String) -> [String] {
        var tags: [String] = []
        let regex = try? NSRegularExpression(pattern: #"(#[a-z0-9]+(?:/[a-z0-9_-]+)+)"#, options: [.caseInsensitive])
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        regex?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match, let r = Range(match.range(at: 1), in: text) else { return }
            tags.append(String(text[r]).lowercased())
        }
        return Array(Set(tags))
    }

    private func extractLinks(from text: String) -> [String] {
        let regex = try? NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#, options: [])
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var links: [String] = []
        regex?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match, let r = Range(match.range(at: 1), in: text) else { return }
            let target = String(text[r]).split(separator: "|").first.map(String.init) ?? ""
            let cleaned = target.split(separator: "#").first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !cleaned.isEmpty { links.append(cleaned) }
        }
        return Array(Set(links))
    }

    private func excerpt(from text: String, limit: Int = 220) -> String {
        let allLines = text.components(separatedBy: "\n")
        var startIndex = 0
        if allLines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            for i in 1..<allLines.count {
                let t = allLines[i].trimmingCharacters(in: .whitespaces)
                if t == "---" || t == "..." { startIndex = i + 1; break }
            }
        }
        var collected: [String] = []
        for i in startIndex..<allLines.count {
            let trimmed = allLines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { if !collected.isEmpty { break }; continue }
            if trimmed.hasPrefix("#") { continue }
            if trimmed.hasPrefix("|") { continue }
            if trimmed.hasPrefix("---") || trimmed.hasPrefix("***") { continue }
            if trimmed.hasPrefix("```") { continue }
            collected.append(trimmed)
            if collected.count >= 3 { break }
        }
        let body = collected.joined(separator: " ")
        let collapsed = body.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return String(collapsed.prefix(limit))
    }

    private func score(
        path: String,
        title: String,
        body: String,
        tags: [String],
        links: [String],
        terms: [String],
        scopes: [OpenJarvisRetrievalScope]
    ) -> Int {
        let loweredPath = path.lowercased()
        let loweredTitle = title.lowercased()
        let loweredBody = body.lowercased()
        var score = 0
        let depth = path.split(separator: "/").count

        for term in terms {
            if loweredPath.contains(term) { score += 5 }
            if loweredTitle.contains(term) { score += 6 }
            if tags.contains(where: { $0.contains(term) }) { score += 5 }
            if links.contains(where: { $0.lowercased().contains(term) }) { score += 3 }
            let bodyCount = loweredBody.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0 == term }.count
            score += min(bodyCount, 3)
        }

        if title.contains("Index") || title.contains("Handoff") || title.contains("Log") || title.contains("Map") || title.contains("Packet") || title.contains("Digest") {
            score += 6
        }
        if depth <= 2 { score += 3 }
        score -= max(0, depth - 2)

        for scope in scopes {
            if scope.pathPrefixes.contains(where: { loweredPath.hasPrefix($0.lowercased()) }) {
                score += 8
            }
        }

        if loweredPath.contains("openjarvis") { score += 4 }
        return score
    }

    private func reasons(
        path: String,
        title: String,
        body: String,
        tags: [String],
        links: [String],
        terms: [String],
        scopes: [OpenJarvisRetrievalScope]
    ) -> [String] {
        var reasons: [String] = []
        let loweredPath = path.lowercased()
        let loweredTitle = title.lowercased()
        for term in terms {
            if loweredTitle.contains(term) { reasons.append("title") }
            if loweredPath.contains(term) { reasons.append("path") }
            if tags.contains(where: { $0.contains(term) }) { reasons.append("tag") }
            if links.contains(where: { $0.lowercased().contains(term) }) { reasons.append("link") }
            if body.lowercased().contains(term) { reasons.append("body") }
        }
        if title.contains("Index") { reasons.append("hub") }
        if scopes.contains(where: { scope in scope.pathPrefixes.contains(where: { loweredPath.hasPrefix($0.lowercased()) }) }) {
            reasons.append("scope")
        }
        return Array(Set(reasons)).sorted()
    }
}

public func inferOpenJarvisScopes(from query: String) -> [OpenJarvisRetrievalScope] {
    let lower = query.lowercased()
    var scopes: [OpenJarvisRetrievalScope] = []
    func add(_ scope: OpenJarvisRetrievalScope) {
        if !scopes.contains(scope) { scopes.append(scope) }
    }

    if lower.contains("arch") || lower.contains("topology") || lower.contains("decision") || lower.contains("invariant") || lower.contains("contract") {
        add(.architecture)
    }
    if lower.contains("runtime") || lower.contains("bug") || lower.contains("regression") || lower.contains("failure") || lower.contains("issue") {
        add(.runtime)
        add(.failures)
    }
    if lower.contains("coord") || lower.contains("prompt") || lower.contains("claude") || lower.contains("codex") || lower.contains("jarvis") {
        add(.coordination)
    }
    if lower.contains("valid") || lower.contains("proof") || lower.contains("build") || lower.contains("test") {
        add(.validation)
    }
    if lower.contains("session") || lower.contains("handoff") || lower.contains("recover") || lower.contains("resume") {
        add(.continuity)
        add(.activeTasks)
    }
    if lower.contains("memory") || lower.contains("digest") || lower.contains("distill") {
        add(.memoryDigests)
    }
    if lower.contains("decision") {
        add(.decisions)
    }

    return scopes
}
