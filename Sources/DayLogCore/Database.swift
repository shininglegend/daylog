import Foundation
import SQLite3

public struct DatabaseError: Error, CustomStringConvertible {
    public let code: Int32
    public let message: String
    public var description: String { "SQLite error \(code): \(message)" }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Values bindable to a statement.
public enum SQLValue: Equatable {
    case null
    case int(Int64)
    case double(Double)
    case text(String)
    case blob(Data)
}

public protocol SQLBindable { var sqlValue: SQLValue { get } }
extension Int: SQLBindable { public var sqlValue: SQLValue { .int(Int64(self)) } }
extension Int64: SQLBindable { public var sqlValue: SQLValue { .int(self) } }
extension Double: SQLBindable { public var sqlValue: SQLValue { .double(self) } }
extension Bool: SQLBindable { public var sqlValue: SQLValue { .int(self ? 1 : 0) } }
extension String: SQLBindable { public var sqlValue: SQLValue { .text(self) } }
extension Data: SQLBindable { public var sqlValue: SQLValue { .blob(self) } }
extension Optional: SQLBindable where Wrapped: SQLBindable {
    public var sqlValue: SQLValue { self?.sqlValue ?? .null }
}

/// One result row, read by column index.
public struct Row {
    fileprivate let stmt: OpaquePointer
    public func isNull(_ i: Int32) -> Bool { sqlite3_column_type(stmt, i) == SQLITE_NULL }
    public func int(_ i: Int32) -> Int64 { sqlite3_column_int64(stmt, i) }
    public func double(_ i: Int32) -> Double { sqlite3_column_double(stmt, i) }
    public func text(_ i: Int32) -> String? {
        guard let p = sqlite3_column_text(stmt, i) else { return nil }
        return String(cString: p)
    }
    public func blob(_ i: Int32) -> Data? {
        guard !isNull(i), let p = sqlite3_column_blob(stmt, i) else { return nil }
        return Data(bytes: p, count: Int(sqlite3_column_bytes(stmt, i)))
    }
}

/// Thin wrapper over the system SQLite3 C API. Not thread-safe: use from one thread.
public final class Database {
    private var handle: OpaquePointer?
    public let url: URL

    public init(url: URL) throws {
        self.url = url
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(url.path, &handle, flags, nil)
        guard rc == SQLITE_OK else {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(handle)
            throw DatabaseError(code: rc, message: msg)
        }
        // Owner read/write only, set before any data is written.
        chmod(url.path, 0o600)
        try execute("PRAGMA secure_delete = ON")
        try execute("PRAGMA journal_mode = DELETE")
        try execute("PRAGMA foreign_keys = ON")
        try Schema.migrate(self)
    }

    deinit { close() }

    /// Closes the connection. Further calls fail.
    public func close() {
        guard let handle else { return }
        sqlite3_close_v2(handle)
        self.handle = nil
    }

    public func execute(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &err)
        if rc != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "exec failed"
            sqlite3_free(err)
            throw DatabaseError(code: rc, message: msg)
        }
    }

    @discardableResult
    public func run(_ sql: String, _ params: [SQLBindable] = []) throws -> Int {
        try withStatement(sql, params) { stmt in
            let rc = sqlite3_step(stmt)
            guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw lastError(rc) }
        }
        return Int(sqlite3_changes(handle))
    }

    public func query<T>(_ sql: String, _ params: [SQLBindable] = [], _ map: (Row) throws -> T) throws -> [T] {
        try withStatement(sql, params) { stmt in
            var out: [T] = []
            while true {
                let rc = sqlite3_step(stmt)
                if rc == SQLITE_DONE { break }
                guard rc == SQLITE_ROW else { throw lastError(rc) }
                out.append(try map(Row(stmt: stmt)))
            }
            return out
        }
    }

    public var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(handle) }

    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    /// Rewrites the file so freed pages holding old ciphertext are dropped.
    public func vacuum() throws { try execute("VACUUM") }

    private func withStatement<T>(_ sql: String, _ params: [SQLBindable], _ body: (OpaquePointer) throws -> T) throws -> T {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt else { throw lastError(rc) }
        defer { sqlite3_finalize(stmt) }
        for (i, p) in params.enumerated() {
            let idx = Int32(i + 1)
            switch p.sqlValue {
            case .null: sqlite3_bind_null(stmt, idx)
            case .int(let v): sqlite3_bind_int64(stmt, idx, v)
            case .double(let v): sqlite3_bind_double(stmt, idx, v)
            case .text(let v): sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT)
            case .blob(let v):
                _ = v.withUnsafeBytes { sqlite3_bind_blob(stmt, idx, $0.baseAddress, Int32(v.count), SQLITE_TRANSIENT) }
            }
        }
        return try body(stmt)
    }

    private func lastError(_ rc: Int32) -> DatabaseError {
        DatabaseError(code: rc, message: String(cString: sqlite3_errmsg(handle)))
    }
}

enum Schema {
    static let version: Int64 = 1

    static func migrate(_ db: Database) throws {
        let current = try db.query("PRAGMA user_version") { $0.int(0) }.first ?? 0
        guard current < version else { return }
        try db.transaction {
            try db.execute("""
            CREATE TABLE IF NOT EXISTS segments (
                id INTEGER PRIMARY KEY,
                start REAL NOT NULL,
                "end" REAL NOT NULL,
                bundle_id TEXT,
                app_name TEXT,
                title BLOB,
                domain BLOB,
                idle INTEGER NOT NULL DEFAULT 0,
                blocked INTEGER NOT NULL DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS segments_start ON segments(start);
            CREATE INDEX IF NOT EXISTS segments_end ON segments("end");
            CREATE TABLE IF NOT EXISTS daily_totals (
                day TEXT NOT NULL,
                kind TEXT NOT NULL CHECK (kind IN ('app', 'domain')),
                key TEXT NOT NULL,
                seconds REAL NOT NULL,
                PRIMARY KEY (day, kind, key)
            );
            CREATE TABLE IF NOT EXISTS domain_labels (
                hmac TEXT PRIMARY KEY,
                label_box BLOB NOT NULL
            );
            CREATE TABLE IF NOT EXISTS rules (
                id INTEGER PRIMARY KEY,
                type TEXT NOT NULL,
                pattern TEXT NOT NULL,
                created_at REAL NOT NULL
            );
            CREATE TABLE IF NOT EXISTS settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            PRAGMA user_version = \(version);
            """)
        }
    }
}
