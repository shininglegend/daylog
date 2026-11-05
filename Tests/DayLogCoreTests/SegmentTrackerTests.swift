import XCTest
@testable import DayLogCore

private final class RecordingSink: SegmentSink {
    struct Row: Equatable { var state: ActivityState; var start: Date; var end: Date }
    var rows: [Row] = []
    var endWrites = 0
    func openSegment(_ state: ActivityState, start: Date, end: Date) throws -> Int64 {
        rows.append(Row(state: state, start: start, end: end))
        return Int64(rows.count - 1)
    }
    func updateSegmentEnd(id: Int64, end: Date) throws {
        endWrites += 1
        rows[Int(id)].end = end
    }
}

final class SegmentTrackerTests: XCTestCase {
    private var clock: ManualClock!
    private var sink: RecordingSink!
    private var tracker: SegmentTracker!

    override func setUp() {
        clock = ManualClock(t0)
        sink = RecordingSink()
        tracker = SegmentTracker(sink: sink, clock: clock, flushInterval: 60, maxGap: 30)
    }

    func testSameStateExtendsOneSegment() throws {
        for _ in 0..<5 { try tracker.observe(app("Xcode")); clock.advance(5) }
        XCTAssertEqual(sink.rows.count, 1)
        XCTAssertEqual(sink.rows[0].start, t0)
    }

    func testChangeClosesAndOpens() throws {
        try tracker.observe(app("Xcode"))
        clock.advance(10)
        try tracker.observe(app("Xcode", title: "other.swift"))
        XCTAssertEqual(sink.rows.count, 2)
        XCTAssertEqual(sink.rows[0].end, t0.addingTimeInterval(10))
        XCTAssertEqual(sink.rows[1].start, t0.addingTimeInterval(10))
    }

    func testFlushesEndAtLeastEveryInterval() throws {
        try tracker.observe(app("Xcode"))
        for _ in 0..<24 { clock.advance(5); try tracker.observe(app("Xcode")) }  // 120s
        XCTAssertEqual(sink.endWrites, 2)
        XCTAssertEqual(sink.rows[0].end, t0.addingTimeInterval(120))
    }

    func testIdleBackdatesChange() throws {
        try tracker.observe(app("Mail"))
        clock.advance(25)
        try tracker.observe(app("Mail"))
        clock.advance(5)
        // idle threshold hit; last input was 10s after start
        try tracker.observe(.idle, since: t0.addingTimeInterval(10))
        XCTAssertEqual(sink.rows[0].end, t0.addingTimeInterval(10))
        XCTAssertEqual(sink.rows[1].state, .idle)
        XCTAssertEqual(sink.rows[1].start, t0.addingTimeInterval(10))
    }

    func testStopClosesAndNextObserveStartsFresh() throws {
        try tracker.observe(app("Mail"))
        clock.advance(5)
        try tracker.stop()
        XCTAssertNil(tracker.open)
        XCTAssertEqual(sink.rows[0].end, t0.addingTimeInterval(5))
        clock.advance(600)
        try tracker.observe(app("Mail"))
        XCTAssertEqual(sink.rows.count, 2)
        XCTAssertEqual(sink.rows[1].start, t0.addingTimeInterval(605))
    }

    func testMissedPollsDoNotStretchSegmentOverGap() throws {
        try tracker.observe(app("Mail"))
        clock.advance(5)
        try tracker.observe(app("Mail"))
        clock.advance(3600)  // e.g. slept without a notification
        try tracker.observe(app("Mail"))
        XCTAssertEqual(sink.rows.count, 2)
        XCTAssertEqual(sink.rows[0].end, t0.addingTimeInterval(5))
        XCTAssertEqual(sink.rows[1].start, t0.addingTimeInterval(3605))
    }

    // MARK: Minimum duration

    private func minTracker() -> SegmentTracker {
        SegmentTracker(sink: sink, clock: clock, flushInterval: 60, maxGap: 30, minDuration: 10)
    }

    func testStateIsWrittenOnlyAfterMinDuration() throws {
        let tracker = minTracker()
        try tracker.observe(app("Xcode"))
        clock.advance(5)
        try tracker.observe(app("Xcode"))
        XCTAssertTrue(sink.rows.isEmpty)
        clock.advance(5)
        try tracker.observe(app("Xcode"))
        XCTAssertEqual(sink.rows, [.init(state: app("Xcode"), start: t0, end: t0.addingTimeInterval(10))])
    }

    func testShortInterruptionIsAbsorbedIntoOpenSegment() throws {
        let tracker = minTracker()
        for _ in 0..<3 { try tracker.observe(app("Xcode")); clock.advance(5) }  // 0, 5, 10
        try tracker.observe(app("Finder"))                                        // 15
        clock.advance(5)
        for _ in 0..<3 { try tracker.observe(app("Xcode")); clock.advance(5) }  // 20, 25, 30
        try tracker.stop()                                                        // 35
        XCTAssertEqual(sink.rows.count, 1)
        XCTAssertEqual(sink.rows[0].start, t0)
        XCTAssertEqual(sink.rows[0].end, t0.addingTimeInterval(35))
    }

    func testShortActivityBetweenTwoLongOnesIsNotRecorded() throws {
        let tracker = minTracker()
        for _ in 0..<3 { try tracker.observe(app("Xcode")); clock.advance(5) }  // 0, 5, 10
        try tracker.observe(app("Finder"))                                        // 15
        clock.advance(5)
        for _ in 0..<3 { try tracker.observe(app("Mail")); clock.advance(5) }   // 20, 25, 30
        XCTAssertEqual(sink.rows.map(\.state), [app("Xcode"), app("Mail")])
        XCTAssertEqual(sink.rows[0].end, t0.addingTimeInterval(15))
        XCTAssertEqual(sink.rows[1].start, t0.addingTimeInterval(20))
    }

    func testActivityLastingMinDurationBetweenPollsIsRecorded() throws {
        let tracker = minTracker()
        for _ in 0..<3 { try tracker.observe(app("Xcode")); clock.advance(5) }  // 0, 5, 10
        try tracker.observe(app("Finder"))                                        // 15
        clock.advance(10)
        try tracker.observe(app("Mail"))                                          // 25: Finder lasted 10s
        XCTAssertEqual(sink.rows.map(\.state), [app("Xcode"), app("Finder")])
        XCTAssertEqual(sink.rows[1].start, t0.addingTimeInterval(15))
        XCTAssertEqual(sink.rows[1].end, t0.addingTimeInterval(25))
    }

    func testStopDropsShortPendingAndClosesOpenWhereItWasLeft() throws {
        let tracker = minTracker()
        for _ in 0..<3 { try tracker.observe(app("Xcode")); clock.advance(5) }  // 0, 5, 10
        try tracker.observe(app("Finder"))                                        // 15
        clock.advance(3)
        try tracker.stop()
        XCTAssertEqual(sink.rows.count, 1)
        XCTAssertEqual(sink.rows[0].end, t0.addingTimeInterval(15))
        XCTAssertNil(tracker.open)
        XCTAssertNil(tracker.pending)
    }

    func testBackdatedIdleIsWrittenImmediately() throws {
        let tracker = minTracker()
        for _ in 0..<7 { try tracker.observe(app("Mail")); clock.advance(5) }   // 0 ... 30
        try tracker.observe(.idle, since: t0.addingTimeInterval(10))             // 35
        XCTAssertEqual(sink.rows.map(\.state), [app("Mail"), .idle])
        XCTAssertEqual(sink.rows[0].end, t0.addingTimeInterval(10))
        XCTAssertEqual(sink.rows[1].start, t0.addingTimeInterval(10))
    }
}
