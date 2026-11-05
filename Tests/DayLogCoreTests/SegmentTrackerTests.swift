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
}
