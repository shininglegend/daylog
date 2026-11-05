import Foundation

/// Where the tracker writes segments. `SegmentStore` is the real one.
public protocol SegmentSink: AnyObject {
    func openSegment(_ state: ActivityState, start: Date, end: Date) throws -> Int64
    func updateSegmentEnd(id: Int64, end: Date) throws
}

/// Keeps one open segment while the activity state is unchanged; closes it
/// and opens a new one on change. Persists the open segment's end at least
/// every `flushInterval` seconds so a crash loses little.
///
/// A new state is held in memory (`pending`) and only written once it has lasted
/// `minDuration`. Shorter activity is never written: if the previous state comes
/// back, its segment simply continues; otherwise the short span is left unrecorded.
public final class SegmentTracker {
    public struct Open: Equatable {
        public let id: Int64
        public let state: ActivityState
        public let start: Date
        public fileprivate(set) var lastObserved: Date
        public fileprivate(set) var lastFlushed: Date
    }

    /// A state seen at recent polls that hasn't lasted `minDuration` yet.
    public struct Pending: Equatable {
        public let state: ActivityState
        public let start: Date
        public fileprivate(set) var lastObserved: Date
    }

    private let sink: SegmentSink
    private let clock: Clock
    public var flushInterval: TimeInterval
    /// If polls stop for longer than this (missed sleep notification, hung main
    /// thread), the open segment ends at the last poll rather than stretching over the gap.
    public var maxGap: TimeInterval
    /// Activity must last at least this long to be recorded. 0 records every change.
    public var minDuration: TimeInterval

    public private(set) var open: Open?
    public private(set) var pending: Pending?
    /// When the open segment's state was first seen to end, while a pending state
    /// hasn't been committed yet. The open segment is closed here if one is.
    private var openLeftAt: Date?

    public init(sink: SegmentSink, clock: Clock, flushInterval: TimeInterval = 60, maxGap: TimeInterval = 30,
                minDuration: TimeInterval = 0) {
        self.sink = sink
        self.clock = clock
        self.flushInterval = flushInterval
        self.maxGap = maxGap
        self.minDuration = minDuration
    }

    private var lastObserved: Date? { pending?.lastObserved ?? open?.lastObserved }

    /// Record the state seen at this poll. `since` back-dates a change (used for
    /// idle, which began `secondsSinceLastEvent` ago); it is clamped to the open segment.
    public func observe(_ state: ActivityState, since: Date? = nil) throws {
        let now = clock.now
        if let last = lastObserved, now.timeIntervalSince(last) > maxGap {
            try finish(at: last)
        }

        if let p = pending {
            if p.state == state {
                pending?.lastObserved = now
                if now.timeIntervalSince(p.start) >= minDuration { try commitPending(end: now) }
                return
            }
            // The pending state ended at this poll: keep it only if it lasted long enough.
            if now.timeIntervalSince(p.start) >= minDuration {
                try commitPending(end: now)
                openLeftAt = now
            } else {
                pending = nil
            }
        }

        var changeAt = min(now, since ?? now)
        if var current = open {
            if current.state == state {
                // Unchanged, or back after an interruption too short to record.
                openLeftAt = nil
                current.lastObserved = now
                if now.timeIntervalSince(current.lastFlushed) >= flushInterval {
                    try sink.updateSegmentEnd(id: current.id, end: now)
                    current.lastFlushed = now
                }
                open = current
                return
            }
            changeAt = max(current.start, changeAt)
            if openLeftAt == nil { openLeftAt = changeAt }
        }
        pending = Pending(state: state, start: changeAt, lastObserved: now)
        // A back-dated change (idle) may already be long enough.
        if now.timeIntervalSince(changeAt) >= minDuration { try commitPending(end: now) }
    }

    /// Close the open segment now (pause, lock, sleep, session switch, quit).
    public func stop() throws {
        guard let last = lastObserved else { return }
        let now = clock.now
        try finish(at: now.timeIntervalSince(last) > maxGap ? last : now)
    }

    /// Ends everything at `end`: a long-enough pending state is written, a short one dropped.
    private func finish(at end: Date) throws {
        if let p = pending {
            if end.timeIntervalSince(p.start) >= minDuration { try commitPending(end: end) } else { pending = nil }
        }
        try close(at: openLeftAt ?? end)
    }

    /// Writes the pending state as a new segment, closing the open one where it was left.
    private func commitPending(end: Date) throws {
        guard let p = pending else { return }
        pending = nil
        try close(at: min(openLeftAt ?? p.start, p.start))
        try begin(p.state, at: p.start, now: end)
    }

    private func begin(_ state: ActivityState, at start: Date, now: Date) throws {
        let id = try sink.openSegment(state, start: start, end: now)
        open = Open(id: id, state: state, start: start, lastObserved: now, lastFlushed: now)
    }

    private func close(at end: Date) throws {
        openLeftAt = nil
        guard let current = open else { return }
        open = nil
        try sink.updateSegmentEnd(id: current.id, end: max(current.start, end))
    }

    /// Forget the open segment without writing (e.g. it was just deleted).
    public func discardOpen() {
        open = nil
        openLeftAt = nil
    }
}
