import Foundation
import SQLite3

public struct OpenJarvisStatusSnapshot: Hashable {
    public var databaseURL: URL
    public var databaseExists: Bool
    public var taskCount: Int?
    public var latestTask: OpenJarvisTaskSummary?
}

public enum OpenJarvisStatusReader {
    public static func read(databaseURL: URL? = nil, fileManager: FileManager = .default) throws -> OpenJarvisStatusSnapshot {
        let url = try databaseURL ?? OpenJarvisPaths.databaseURL(fileManager: fileManager, createDirectory: false)
        guard fileManager.fileExists(atPath: url.path) else {
            return OpenJarvisStatusSnapshot(databaseURL: url, databaseExists: false, taskCount: nil, latestTask: nil)
        }

        var handle: OpaquePointer?
        let openResult = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open SQLite database at \(url.path)"
            if let handle { sqlite3_close(handle) }
            throw NSError(domain: "OpenJarvisStatusReader", code: Int(openResult), userInfo: [NSLocalizedDescriptionKey: message])
        }
        defer { sqlite3_close(handle) }

        let taskCount = try queryInt(handle: handle, sql: "SELECT COUNT(*) FROM tasks")
        let latestTask = try queryLatestTask(handle: handle)
        return OpenJarvisStatusSnapshot(databaseURL: url, databaseExists: true, taskCount: taskCount, latestTask: latestTask)
    }

    private static func queryInt(handle: OpaquePointer, sql: String) throws -> Int {
        var statement: OpaquePointer?
        let prepare = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard prepare == SQLITE_OK, let statement else {
            throw sqliteError(handle: handle, code: prepare, fallback: "Could not prepare SQL: \(sql)")
        }
        defer { sqlite3_finalize(statement) }

        let step = sqlite3_step(statement)
        guard step == SQLITE_ROW else {
            throw sqliteError(handle: handle, code: step, fallback: "Could not read SQL row: \(sql)")
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private static func queryLatestTask(handle: OpaquePointer) throws -> OpenJarvisTaskSummary? {
        let sql = """
        SELECT id, interpreted_objective, stage, execution_state, completion_state, writeback_state,
               target_worker, updated_at
        FROM tasks
        ORDER BY updated_at DESC
        LIMIT 1
        """
        var statement: OpaquePointer?
        let prepare = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard prepare == SQLITE_OK, let statement else {
            throw sqliteError(handle: handle, code: prepare, fallback: "Could not prepare SQL: \(sql)")
        }
        defer { sqlite3_finalize(statement) }

        let step = sqlite3_step(statement)
        if step == SQLITE_DONE {
            return nil
        }
        guard step == SQLITE_ROW else {
            throw sqliteError(handle: handle, code: step, fallback: "Could not read SQL row: \(sql)")
        }
        return OpenJarvisTaskSummary(
            id: text(statement, 0),
            stage: OpenJarvisStage(rawValue: text(statement, 2)) ?? .intake,
            executionState: OpenJarvisExecutionState(rawValue: text(statement, 3)) ?? .pending,
            completionState: OpenJarvisCompletionState(rawValue: text(statement, 4)) ?? .open,
            writebackState: OpenJarvisWritebackState(rawValue: text(statement, 5)) ?? .pending,
            worker: sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : OpenJarvisWorkerKind(rawValue: text(statement, 6)),
            objective: text(statement, 1),
            updatedAt: text(statement, 7)
        )
    }

    private static func text(_ statement: OpaquePointer, _ index: Int32) -> String {
        String(cString: sqlite3_column_text(statement, index))
    }

    private static func sqliteError(handle: OpaquePointer, code: Int32, fallback: String) -> NSError {
        let message = code == SQLITE_DONE ? fallback : String(cString: sqlite3_errmsg(handle))
        return NSError(domain: "OpenJarvisStatusReader", code: Int(code), userInfo: [NSLocalizedDescriptionKey: message])
    }
}
