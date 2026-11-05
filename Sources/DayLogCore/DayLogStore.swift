import Foundation
import os

let log = Logger(subsystem: "local.daylog", category: "store")

/// Owns the database, keys, and crypto. All persistence goes through here.
/// Use from one thread (the app uses the main thread).
public final class DayLogStore {
    public let db: Database
    public let crypto: Crypto
    public let keys: KeyStore
    public let clock: Clock
    public let directory: URL
    /// Defines local days for `daily_totals`.
    public var calendar: Calendar

    public static let fileName = "daylog.sqlite"
    public static let liveWindow: TimeInterval = 48 * 3600

    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DayLog.noindex", isDirectory: true)
    }

    public init(directory: URL = DayLogStore.defaultDirectory, keys: KeyStore, clock: Clock, calendar: Calendar = .current) throws {
        try Self.prepareDirectory(directory)
        self.directory = directory
        self.keys = keys
        self.clock = clock
        self.calendar = calendar
        self.crypto = Crypto(keys: keys)
        self.db = try Database(url: directory.appendingPathComponent(Self.fileName))
    }

    /// Creates the directory owner-only and excludes it from Time Machine.
    static func prepareDirectory(_ url: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        var u = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try u.setResourceValues(values)
    }

    /// Removes the database directory and every `local.daylog.*` keychain item.
    public static func deleteAllData(directory: URL = DayLogStore.defaultDirectory, keys: KeyStore) throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        for name in try keys.allKeyNames() where name.hasPrefix(KeyNames.prefix) {
            try keys.deleteKey(named: name)
        }
    }

    // MARK: Days

    private lazy var dayFormatter: DateFormatter = makeDayFormatter()

    private func makeDayFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    public func dayKey(_ date: Date) -> String {
        if dayFormatter.timeZone != calendar.timeZone { dayFormatter = makeDayFormatter() }
        return dayFormatter.string(from: date)
    }

    /// Splits [start, end) at local midnights.
    func splitByDay(start: Date, end: Date) -> [(day: String, seconds: TimeInterval)] {
        var out: [(String, TimeInterval)] = []
        var cursor = start
        while cursor < end {
            let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: cursor))!
            let sliceEnd = min(next, end)
            out.append((dayKey(cursor), sliceEnd.timeIntervalSince(cursor)))
            cursor = sliceEnd
        }
        return out
    }
}
