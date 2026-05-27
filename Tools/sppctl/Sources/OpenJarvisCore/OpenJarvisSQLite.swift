import Foundation
import SQLite3

enum OpenJarvisSQLiteValue {
    case text(String)
    case int(Int64)
    case null
}

private let openJarvisSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class OpenJarvisSQLiteDatabase {
    private static let schemaVersion: Int32 = 1
    private var handle: OpaquePointer?

    init(url: URL) throws {
        let rc = sqlite3_open(url.path, &handle)
        guard rc == SQLITE_OK else {
            throw Self.error(from: handle, code: rc, fallback: "Could not open SQLite database at \(url.path)")
        }
        guard handle != nil else {
            throw Self.error(from: handle, code: rc, fallback: "Could not open SQLite database at \(url.path)")
        }
        try execute("PRAGMA journal_mode = WAL;")
        try execute("PRAGMA foreign_keys = ON;")
        let currentVersion = try queryOne("PRAGMA user_version;", map: { row in
            sqlite3_column_int(row, 0)
        }) ?? 0
        if currentVersion == 0 {
            try execute("PRAGMA user_version = \(Self.schemaVersion);")
        } else if currentVersion != Self.schemaVersion {
            throw NSError(
                domain: "OpenJarvisSQLite",
                code: Int(currentVersion),
                userInfo: [NSLocalizedDescriptionKey: "Unsupported SQLite schema version \(currentVersion); expected \(Self.schemaVersion)."]
            )
        }
    }

    deinit {
        if let handle {
            sqlite3_close(handle)
        }
    }

    func execute(_ sql: String, bindings: [OpenJarvisSQLiteValue] = []) throws {
        var statement: OpaquePointer?
        let prepare = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard prepare == SQLITE_OK, let statement else {
            throw Self.error(from: handle, code: prepare, fallback: "Could not prepare SQL: \(sql)")
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE {
                break
            } else if step == SQLITE_ROW {
                continue
            } else {
                throw Self.error(from: handle, code: step, fallback: "Could not execute SQL: \(sql)")
            }
        }
    }

    func query<T>(_ sql: String, bindings: [OpenJarvisSQLiteValue] = [], map: (OpaquePointer) throws -> T) throws -> [T] {
        var statement: OpaquePointer?
        let prepare = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard prepare == SQLITE_OK, let statement else {
            throw Self.error(from: handle, code: prepare, fallback: "Could not prepare SQL: \(sql)")
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        var rows: [T] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW {
                rows.append(try map(statement))
            } else if step == SQLITE_DONE {
                break
            } else {
                throw Self.error(from: handle, code: step, fallback: "Could not read SQL rows: \(sql)")
            }
        }
        return rows
    }

    func queryOne<T>(_ sql: String, bindings: [OpenJarvisSQLiteValue] = [], map: (OpaquePointer) throws -> T) throws -> T? {
        try query(sql, bindings: bindings, map: map).first
    }

    private func bind(_ values: [OpenJarvisSQLiteValue], to statement: OpaquePointer) throws {
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case .text(let string):
                let result = string.withCString { sqlite3_bind_text(statement, position, $0, -1, openJarvisSQLiteTransient) }
                guard result == SQLITE_OK else {
                    throw Self.error(from: handle, code: result, fallback: "Could not bind text value")
                }
            case .int(let int):
                let result = sqlite3_bind_int64(statement, position, int)
                guard result == SQLITE_OK else {
                    throw Self.error(from: handle, code: result, fallback: "Could not bind integer value")
                }
            case .null:
                let result = sqlite3_bind_null(statement, position)
                guard result == SQLITE_OK else {
                    throw Self.error(from: handle, code: result, fallback: "Could not bind null value")
                }
            }
        }
    }

    private static func error(from handle: OpaquePointer?, code: Int32, fallback: String) -> NSError {
        let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? fallback
        return NSError(domain: "OpenJarvisSQLite", code: Int(code), userInfo: [NSLocalizedDescriptionKey: message])
    }
}
