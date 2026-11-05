import Foundation

/// Where the tracker writes segments. `SegmentStore` is the real one.
public protocol SegmentSink: AnyObject {
    func openSegment(_ state: ActivityState, start: Date, end: Date) throws -> Int64
    func updateSegmentEnd(id: Int64, end: Date) throws
}

/// Keeps one open segment while the activity state is unchanged; closes it
/// and opens a new one on change. Persists the open segment's end at least
/// every `flushInterval` seconds so a crash loses little.
public final class SegmentTracker {
    public struct Open: Equatable {
        public let id: Int64
        public let state: ActivityState
        public let start: Date
        public fileprivate(set) var lastObserved: Date
        public fileprivate(set) var lastFlushed: Date
    }

    private let sink: SegmentSink
    private let clock: Clock
    public var flushInterval: TimeInterval
    /// If polls stop for longer than this (missed sleep notification, hung main
    /// thread), the open segment ends at the last poll rather than stretching over the gap.
    public var maxGap: TimeInterval

    public private(set) var open: Open?

    public init(sink: SegmentSink, clock: Clock, flushInterval: TimeInterval = 60, maxGap: TimeInterval = 30) {
        self.sink = sink
        self.clock = clock
        self.flushInterval = flushInterval
        self.maxGap = maxGap
    }

    /// Record the state seen at this poll. `since` back-dates a change (used for
    /// idle, which began `secondsSinceLastEvent` ago); it is clamped to the open segment.
    public func observe(_ state: ActivityState, since: Date? = nil) throws {
        let now = clock.now
        if var current = open {
            if now.timeIntervalSince(current.lastObserved) > maxGap {
                try close(at: current.lastObserved)
            } else if current.state == state {
                current.lastObserved = now
                if now.timeIntervalSince(current.lastFlushed) >= flushInterval {
                    try sink.updateSegmentEnd(id: current.id, end: now)
                    current.lastFlushed = now
                }
                open = current
                return
            } else {
                let changeAt = min(now, max(current.start, since ?? now))
                try close(at: changeAt)
                try begin(state, at: changeAt, now: now)
                return
            }
        }
        try begin(state, at: min(now, since ?? now), now: now)
    }

    /// Close the open segment now (pause, lock, sleep, session switch, quit).
    public func stop() throws {
        guard let current = open else { return }
        let now = clock.now
        let end = now.timeIntervalSince(current.lastObserved) > maxGap ? current.lastObserved : now
        try close(at: end)
    }

    private func begin(_ state: ActivityState, at start: Date, now: Date) throws {
        let id = try sink.openSegment(state, start: start, end: now)
        open = Open(id: id, state: state, start: start, lastObserved: now, lastFlushed: now)
    }

    private func close(at end: Date) throws {
        guard let current = open else { return }
        open = nil
        try sink.updateSegmentEnd(id: current.id, end: max(current.start, end))
    }

    /// Forget the open segment without writing (e.g. it was just deleted).
    public func discardOpen() { open = nil }
}
