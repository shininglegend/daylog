import Foundation

public struct Settings: Equatable, Sendable {
    public var pollInterval: TimeInterval = 5
    public var idleThreshold: TimeInterval = 120
    /// nil keeps daily totals forever.
    public var totalsRetentionDays: Int? = 90
    public var onboarded = false
    public var requireTouchID = false

    public init() {}

    public static let retentionChoices: [Int?] = [30, 90, 180, 365, nil]
}

extension DayLogStore {
    private func value(_ key: String) throws -> String? {
        try db.query("SELECT value FROM settings WHERE key = ?", [key]) { $0.text(0) }.first ?? nil
    }

    private func set(_ key: String, _ value: String) throws {
        try db.run("INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", [key, value])
    }

    public func loadSettings() throws -> Settings {
        var s = Settings()
        if let v = try value("poll_interval").flatMap(Double.init), v >= 1 { s.pollInterval = v }
        if let v = try value("idle_threshold").flatMap(Double.init), v >= 10 { s.idleThreshold = v }
        if let v = try value("totals_retention_days") { s.totalsRetentionDays = v == "forever" ? nil : Int(v).map { max(30, $0) } ?? 90 }
        if let v = try value("onboarded") { s.onboarded = v == "1" }
        if let v = try value("require_touch_id") { s.requireTouchID = v == "1" }
        return s
    }

    public func saveSettings(_ s: Settings) throws {
        try db.transaction {
            try set("poll_interval", String(s.pollInterval))
            try set("idle_threshold", String(s.idleThreshold))
            try set("totals_retention_days", s.totalsRetentionDays.map { String(max(30, $0)) } ?? "forever")
            try set("onboarded", s.onboarded ? "1" : "0")
            try set("require_touch_id", s.requireTouchID ? "1" : "0")
        }
    }
}
