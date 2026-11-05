import Foundation

public struct PurgeReport: Equatable, Sendable {
    public var segmentsRolledUp = 0
    public var keysDeleted = 0
    public var totalsDeleted = 0
    public var labelsDeleted = 0
}

extension DayLogStore {
    /// Rolls up segments older than 48h (or whose hour key is gone) into daily
    /// totals, deletes them, crypto-shreds their hour keys, expires old totals,
    /// and vacuums so deleted ciphertext doesn't linger in free pages.
    /// `retentionDays == nil` keeps totals forever.
    @discardableResult
    public func purge(retentionDays: Int?) throws -> PurgeReport {
        let now = clock.now
        let cutoff = now.addingTimeInterval(-Self.liveWindow)
        var report = PurgeReport()

        try db.transaction {
            let all = try segments(from: .distantPast, to: .distantFuture)
            let rollable = all.filter { $0.end <= cutoff || $0.expired }
            for seg in rollable {
                try rollUp(seg)
            }
            for seg in rollable { try db.run("DELETE FROM segments WHERE id = ?", [seg.id]) }
            report.segmentsRolledUp = rollable.count

            if let days = retentionDays {
                let oldest = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now))!
                report.totalsDeleted = try db.run("DELETE FROM daily_totals WHERE day < ?", [dayKey(oldest)])
            }
            report.labelsDeleted = try db.run(
                "DELETE FROM domain_labels WHERE hmac NOT IN (SELECT key FROM daily_totals WHERE kind = 'domain')")
        }

        // Crypto-shred: drop hour keys no remaining segment needs, once the hour is past the cutoff.
        let liveHours = Set(try db.query("SELECT start FROM segments") {
            KeyNames.segmentKey(for: Date(timeIntervalSince1970: $0.double(0)))
        })
        for name in try keys.allKeyNames() {
            guard let hour = KeyNames.hourStart(ofSegmentKey: name), !liveHours.contains(name),
                  hour.addingTimeInterval(3600) <= cutoff
            else { continue }
            try keys.deleteKey(named: name)
            report.keysDeleted += 1
        }

        if report.segmentsRolledUp > 0 || report.totalsDeleted > 0 || report.labelsDeleted > 0 {
            try db.vacuum()
        }
        log.info("purge: rolled up \(report.segmentsRolledUp) segments, deleted \(report.keysDeleted) keys, \(report.totalsDeleted) totals")
        return report
    }

    private func rollUp(_ seg: Segment) throws {
        guard !seg.state.idle else { return }
        let appKey = seg.state.blocked ? BlockedLabel.name : (seg.state.appName ?? "Unknown")
        var domainKey: String?
        if !seg.state.blocked, let domain = seg.state.domain {
            let mac = try crypto.domainHMAC(domain)
            try db.run("INSERT OR IGNORE INTO domain_labels (hmac, label_box) VALUES (?, ?)", [mac, try crypto.sealLabel(domain)])
            domainKey = mac
        }
        for slice in splitByDay(start: seg.start, end: seg.end) where slice.seconds > 0 {
            try addTotal(day: slice.day, kind: "app", key: appKey, seconds: slice.seconds)
            if let domainKey { try addTotal(day: slice.day, kind: "domain", key: domainKey, seconds: slice.seconds) }
        }
    }

    private func addTotal(day: String, kind: String, key: String, seconds: TimeInterval) throws {
        try db.run("""
            INSERT INTO daily_totals (day, kind, key, seconds) VALUES (?, ?, ?, ?)
            ON CONFLICT(day, kind, key) DO UPDATE SET seconds = seconds + excluded.seconds
            """, [day, kind, key, seconds])
    }
}
