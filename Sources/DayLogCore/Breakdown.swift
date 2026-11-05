import Foundation

public enum BreakdownKind: String, Sendable { case app, domain }

public struct BreakdownRow: Identifiable, Equatable, Sendable {
    public var label: String
    public var seconds: TimeInterval
    public var id: String { label }
    public init(label: String, seconds: TimeInterval) {
        self.label = label
        self.seconds = seconds
    }
}

extension DayLogStore {
    /// Active (non-idle) time per app or domain over the local days `firstDay...lastDay`.
    ///
    /// Each second of activity is in exactly one place: still in `segments` (last 48h)
    /// or already rolled into `daily_totals` and deleted. Summing both therefore
    /// never double counts. Live segments are clipped to the range.
    public func breakdown(_ kind: BreakdownKind, firstDay: Date, lastDay: Date) throws -> [BreakdownRow] {
        let from = calendar.startOfDay(for: firstDay)
        let to = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: lastDay))!
        var totals: [String: TimeInterval] = [:]

        let stored = try db.query(
            "SELECT key, SUM(seconds) FROM daily_totals WHERE kind = ? AND day >= ? AND day <= ? GROUP BY key",
            [kind.rawValue, dayKey(from), dayKey(lastDay)]
        ) { ($0.text(0) ?? "", $0.double(1)) }
        for (key, seconds) in stored {
            let label = kind == .domain ? try domainLabel(hmac: key) : key
            totals[label, default: 0] += seconds
        }

        for seg in try segments(from: from, to: to) where !seg.state.idle {
            let label: String
            switch kind {
            case .app: label = seg.state.blocked ? BlockedLabel.name : (seg.state.appName ?? "Unknown")
            case .domain:
                guard !seg.state.blocked, let d = seg.state.domain else { continue }
                label = d
            }
            let seconds = min(seg.end, to).timeIntervalSince(max(seg.start, from))
            if seconds > 0 { totals[label, default: 0] += seconds }
        }

        return totals.map { BreakdownRow(label: $0.key, seconds: $0.value) }
            .sorted { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.label < $1.label }
    }

    /// Total active time across all apps for the given days.
    public func activeTime(firstDay: Date, lastDay: Date) throws -> TimeInterval {
        try breakdown(.app, firstDay: firstDay, lastDay: lastDay).reduce(0) { $0 + $1.seconds }
    }

    private func domainLabel(hmac: String) throws -> String {
        let box = try db.query("SELECT label_box FROM domain_labels WHERE hmac = ?", [hmac]) { $0.blob(0) }.first ?? nil
        return box.flatMap { crypto.openLabel($0) } ?? "[unknown]"
    }
}
