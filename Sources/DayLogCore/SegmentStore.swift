import Foundation

extension DayLogStore: SegmentSink {
    public func openSegment(_ state: ActivityState, start: Date, end: Date) throws -> Int64 {
        let title = try state.title.map { try crypto.seal($0, field: .title, segmentStart: start) }
        let domain = try state.domain.map { try crypto.seal($0, field: .domain, segmentStart: start) }
        try db.run(
            #"INSERT INTO segments (start, "end", bundle_id, app_name, title, domain, idle, blocked) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"#,
            [start.timeIntervalSince1970, end.timeIntervalSince1970, state.bundleID, state.appName, title, domain, state.idle, state.blocked]
        )
        return db.lastInsertRowID
    }

    public func updateSegmentEnd(id: Int64, end: Date) throws {
        try db.run(#"UPDATE segments SET "end" = ? WHERE id = ?"#, [end.timeIntervalSince1970, id])
    }

    public func deleteSegments(ids: [Int64]) throws {
        guard !ids.isEmpty else { return }
        try db.transaction {
            for id in ids { try db.run("DELETE FROM segments WHERE id = ?", [id]) }
        }
    }

    /// Segments overlapping [from, to), decrypted in memory, oldest first.
    public func segments(from: Date, to: Date) throws -> [Segment] {
        let rows = try db.query(
            #"SELECT id, start, "end", bundle_id, app_name, title, domain, idle, blocked FROM segments WHERE "end" > ? AND start < ? ORDER BY start"#,
            [from.timeIntervalSince1970, to.timeIntervalSince1970]
        ) { r in
            (id: r.int(0), start: Date(timeIntervalSince1970: r.double(1)), end: Date(timeIntervalSince1970: r.double(2)),
             bundleID: r.text(3), appName: r.text(4), title: r.blob(5), domain: r.blob(6), idle: r.int(7) != 0, blocked: r.int(8) != 0)
        }
        return rows.map { r in
            var expired = false
            func open(_ box: Data?, _ field: Crypto.Field) -> String? {
                guard let box else { return nil }
                switch crypto.open(box, field: field, segmentStart: r.start) {
                case .value(let s): return s
                case .expired: expired = true; return nil
                }
            }
            let state = ActivityState(bundleID: r.bundleID, appName: r.appName, title: open(r.title, .title),
                                      domain: open(r.domain, .domain), idle: r.idle, blocked: r.blocked)
            return Segment(id: r.id, start: r.start, end: r.end, state: state, expired: expired)
        }
    }

    /// The live 48-hour window.
    public func liveSegments() throws -> [Segment] {
        let now = clock.now
        return try segments(from: now.addingTimeInterval(-Self.liveWindow), to: now.addingTimeInterval(1))
    }

    /// Retroactive cleanup for a new rule. Matching happens in memory on decrypted values.
    public func segmentsMatching(_ rule: Rule) throws -> [Segment] {
        let matcher = RuleMatcher(rules: [rule])
        return try liveSegments().filter { !$0.state.blocked && matcher.matches($0) }
    }
}
