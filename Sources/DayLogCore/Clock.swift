import Foundation

/// Source of "now". Injected everywhere time matters so purge and rollup are testable.
public protocol Clock: AnyObject {
    var now: Date { get }
}

public final class SystemClock: Clock {
    public init() {}
    public var now: Date { Date() }
}

/// A clock tests (and the "simulate purge" debug path) can move by hand.
public final class ManualClock: Clock {
    public var now: Date
    public init(_ now: Date) { self.now = now }
    public func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

/// System time shifted by a fixed offset. Used to simulate the 48h purge
/// in the real app (see README, `DAYLOG_CLOCK_OFFSET_HOURS`).
public final class OffsetClock: Clock {
    public let offset: TimeInterval
    public init(offset: TimeInterval) { self.offset = offset }
    public var now: Date { Date().addingTimeInterval(offset) }
}
