import XCTest
@testable import DayLogCore

final class StoreTests: XCTestCase {
    private var dirs: [URL] = []

    override func tearDown() {
        for d in dirs { try? FileManager.default.removeItem(at: d) }
    }

    private func store(_ clock: ManualClock, keys: InMemoryKeyStore = InMemoryKeyStore()) throws -> DayLogStore {
        let dir = makeTempDir()
        dirs.append(dir)
        return try makeStore(clock: clock, keys: keys, dir: dir)
    }

    @discardableResult
    private func add(_ s: DayLogStore, _ state: ActivityState, start: Date, minutes: Double) throws -> Int64 {
        try s.openSegment(state, start: start, end: start.addingTimeInterval(minutes * 60))
    }

    func testFilePermissionsAndBackupExclusion() throws {
        let s = try store(ManualClock(t0))
        let dirAttrs = try FileManager.default.attributesOfItem(atPath: s.directory.path)
        XCTAssertEqual((dirAttrs[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        let fileAttrs = try FileManager.default.attributesOfItem(atPath: s.db.url.path)
        XCTAssertEqual((fileAttrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual(try s.directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }

    func testSegmentsRoundTripDecrypted() throws {
        let clock = ManualClock(t0)
        let s = try store(clock)
        try add(s, app("Chrome", title: "Inbox", domain: "mail.google.com"), start: t0, minutes: 5)
        try add(s, .idle, start: t0.addingTimeInterval(300), minutes: 5)
        clock.advance(600)
        let segs = try s.liveSegments()
        XCTAssertEqual(segs.count, 2)
        XCTAssertEqual(segs[0].state.title, "Inbox")
        XCTAssertEqual(segs[0].state.domain, "mail.google.com")
        XCTAssertTrue(segs[1].state.idle)
    }

    func testPurgeRollsUpSplitsDaysAndExcludesIdle() throws {
        // Segment from 23:30 to 00:30 UTC crosses midnight.
        let lateNight = utcCalendar.date(bySettingHour: 23, minute: 30, second: 0, of: t0)!
        let clock = ManualClock(lateNight)
        let s = try store(clock)
        try add(s, app("Xcode"), start: lateNight, minutes: 60)
        try add(s, .idle, start: lateNight.addingTimeInterval(3600), minutes: 30)
        try add(s, .blocked, start: lateNight.addingTimeInterval(5400), minutes: 10)

        clock.advance(47 * 3600)
        XCTAssertEqual(try s.purge(retentionDays: 90).segmentsRolledUp, 0)

        clock.advance(3 * 3600)  // last segment ends 2h after the first purge's cutoff
        let report = try s.purge(retentionDays: 90)
        XCTAssertEqual(report.segmentsRolledUp, 3)
        XCTAssertTrue(try s.liveSegments().isEmpty)

        let rows = try s.db.query("SELECT day, key, seconds FROM daily_totals WHERE kind='app' ORDER BY day, key") {
            "\($0.text(0)!) \($0.text(1)!) \(Int($0.double(2)))"
        }
        XCTAssertEqual(rows, ["2026-03-10 Xcode 1800", "2026-03-11 Blocked 600", "2026-03-11 Xcode 1800"])
    }

    func testPurgeShredsHourKeysAndOldBytesCannotBeDecrypted() throws {
        let clock = ManualClock(t0)
        let keys = InMemoryKeyStore()
        let s = try store(clock, keys: keys)
        let id = try add(s, app("Notes", title: "Diary entry", domain: nil), start: t0, minutes: 10)
        let rawBox = try s.db.query("SELECT title FROM segments WHERE id = ?", [id]) { $0.blob(0) }.first!!
        // A segment in a later hour that is still live keeps its key.
        clock.advance(49 * 3600)
        try add(s, app("Notes", title: "Recent"), start: clock.now.addingTimeInterval(-60), minutes: 1)

        let report = try s.purge(retentionDays: 90)
        XCTAssertEqual(report.keysDeleted, 1)
        XCTAssertNil(try keys.key(named: KeyNames.segmentKey(for: t0)))
        XCTAssertNotNil(try keys.key(named: KeyNames.segmentKey(for: clock.now.addingTimeInterval(-60))))
        XCTAssertEqual(s.crypto.open(rawBox, field: .title, segmentStart: t0), .expired)
    }

    func testSegmentSpanningCutoffKeepsItsKey() throws {
        let clock = ManualClock(t0)
        let keys = InMemoryKeyStore()
        let s = try store(clock, keys: keys)
        try add(s, app("Xcode", title: "long"), start: t0, minutes: 120)
        clock.advance(48 * 3600 + 30 * 60)  // segment ends 1h30m after cutoff start
        XCTAssertEqual(try s.purge(retentionDays: 90).keysDeleted, 0)
        XCTAssertEqual(try s.liveSegments().first?.state.title, "long")
    }

    func testExpiredSegmentsAreDeletedOnNextPurge() throws {
        let clock = ManualClock(t0)
        let keys = InMemoryKeyStore()
        let s = try store(clock, keys: keys)
        try add(s, app("Notes", title: "x"), start: t0, minutes: 5)
        try keys.deleteKey(named: KeyNames.segmentKey(for: t0))
        clock.advance(600)
        XCTAssertEqual(try s.liveSegments().first?.expired, true)
        XCTAssertEqual(try s.purge(retentionDays: 90).segmentsRolledUp, 1)
        XCTAssertTrue(try s.liveSegments().isEmpty)
        XCTAssertEqual(try s.activeTime(firstDay: t0, lastDay: t0), 300)
    }

    func testDomainTotalsGroupThroughHMAC() throws {
        let clock = ManualClock(t0)
        let s = try store(clock)
        try add(s, app("Chrome", title: "a", domain: "github.com"), start: t0, minutes: 10)
        try add(s, app("Chrome", title: "b", domain: "github.com"), start: t0.addingTimeInterval(600), minutes: 5)
        try add(s, app("Chrome", title: "c", domain: "news.ycombinator.com"), start: t0.addingTimeInterval(900), minutes: 3)
        clock.advance(49 * 3600)
        try s.purge(retentionDays: 90)

        let keys = try s.db.query("SELECT key FROM daily_totals WHERE kind='domain'") { $0.text(0)! }
        XCTAssertEqual(keys.count, 2)
        XCTAssertFalse(keys.contains("github.com"))
        XCTAssertTrue(keys.contains(try s.crypto.domainHMAC("github.com")))

        let rows = try s.breakdown(.domain, firstDay: t0, lastDay: t0)
        XCTAssertEqual(rows, [BreakdownRow(label: "github.com", seconds: 900), BreakdownRow(label: "news.ycombinator.com", seconds: 180)])
    }

    func testBreakdownCombinesTotalsAndLiveWithoutDoubleCounting() throws {
        let clock = ManualClock(t0)
        let s = try store(clock)
        try add(s, app("Xcode"), start: t0, minutes: 30)                     // will roll up
        clock.advance(24 * 3600)
        try add(s, app("Xcode"), start: clock.now, minutes: 20)              // stays live
        try add(s, app("Mail"), start: clock.now.addingTimeInterval(1200), minutes: 10)
        clock.advance(25 * 3600)
        try s.purge(retentionDays: 90)
        XCTAssertEqual(try s.db.query("SELECT COUNT(*) FROM segments") { $0.int(0) }.first, 2)

        let before = try s.breakdown(.app, firstDay: t0, lastDay: clock.now)
        XCTAssertEqual(before, [BreakdownRow(label: "Xcode", seconds: 3000), BreakdownRow(label: "Mail", seconds: 600)])
        // Purging again (and again) must not change the totals.
        clock.advance(24 * 3600)
        try s.purge(retentionDays: 90)
        try s.purge(retentionDays: 90)
        XCTAssertEqual(try s.breakdown(.app, firstDay: t0, lastDay: clock.now), before)
        XCTAssertEqual(try s.breakdown(.app, firstDay: t0, lastDay: t0), [BreakdownRow(label: "Xcode", seconds: 1800)])
    }

    func testLiveSegmentsAreClippedToRange() throws {
        let lateNight = utcCalendar.date(bySettingHour: 23, minute: 50, second: 0, of: t0)!
        let clock = ManualClock(lateNight.addingTimeInterval(3600))
        let s = try store(clock)
        try add(s, app("Xcode"), start: lateNight, minutes: 20)
        let nextDay = lateNight.addingTimeInterval(3600)
        XCTAssertEqual(try s.activeTime(firstDay: lateNight, lastDay: lateNight), 600)
        XCTAssertEqual(try s.activeTime(firstDay: nextDay, lastDay: nextDay), 600)
    }

    func testTotalsRetentionAndLabelCleanup() throws {
        let clock = ManualClock(t0)
        let s = try store(clock)
        try add(s, app("Chrome", domain: "old.com"), start: t0, minutes: 10)
        clock.advance(49 * 3600)
        try s.purge(retentionDays: 30)
        XCTAssertEqual(try s.db.query("SELECT COUNT(*) FROM domain_labels") { $0.int(0) }.first, 1)

        clock.advance(40 * 86400)
        try s.purge(retentionDays: nil)  // forever keeps it
        XCTAssertEqual(try s.db.query("SELECT COUNT(*) FROM daily_totals") { $0.int(0) }.first, 2)
        let report = try s.purge(retentionDays: 30)
        XCTAssertEqual(report.totalsDeleted, 2)
        XCTAssertEqual(report.labelsDeleted, 1)
    }

    func testRetroactiveMatchingAndDelete() throws {
        let clock = ManualClock(t0)
        let s = try store(clock)
        try add(s, app("Chrome", title: "Bank statement", domain: "bank.com"), start: t0, minutes: 5)
        try add(s, app("Chrome", title: "Docs", domain: "docs.rs"), start: t0.addingTimeInterval(300), minutes: 5)
        clock.advance(600)
        let rule = try s.addRule(type: .domain, pattern: "bank.com")
        let matches = try s.segmentsMatching(rule)
        XCTAssertEqual(matches.map(\.state.title), ["Bank statement"])
        try s.deleteSegments(ids: matches.map(\.id))
        XCTAssertEqual(try s.liveSegments().map(\.state.title), ["Docs"])
        XCTAssertEqual(try s.rules().map(\.pattern), ["bank.com"])
    }

    func testPreferencesRoundTrip() throws {
        let s = try store(ManualClock(t0))
        XCTAssertEqual(try s.loadPreferences(), Preferences())
        var settings = Preferences()
        settings.pollInterval = 10
        settings.totalsRetentionDays = nil
        settings.onboarded = true
        try s.savePreferences(settings)
        XCTAssertEqual(try s.loadPreferences(), settings)
    }

    func testDatabaseFileContainsNoPlaintextTitlesOrDomains() throws {
        let clock = ManualClock(t0)
        let s = try store(clock)
        let secrets = ["ZebraConfidentialTitle", "zebra-secret-site.example", "PlaintextCanaryXYZ"]
        try add(s, app("Chrome", title: secrets[0], domain: secrets[1]), start: t0, minutes: 5)
        try add(s, app("Notes", title: secrets[2]), start: t0.addingTimeInterval(300), minutes: 5)
        // Roll half the data into totals so both tables are exercised.
        clock.advance(49 * 3600)
        try s.purge(retentionDays: 90)
        try add(s, app("Chrome", title: secrets[0], domain: secrets[1]), start: clock.now, minutes: 1)

        let bytes = try Data(contentsOf: s.db.url)
        for secret in secrets {
            XCTAssertNil(bytes.range(of: Data(secret.utf8)), "plaintext \(secret) found in database file")
            XCTAssertNil(bytes.range(of: Data(secret.utf16LittleEndian)), "UTF-16 \(secret) found in database file")
        }
        // Sanity: the scan does find plaintext we expect to be stored (app names).
        XCTAssertNotNil(bytes.range(of: Data("Chrome".utf8)))
    }

    func testDeleteAllDataRemovesDatabaseAndKeys() throws {
        let clock = ManualClock(t0)
        let keys = InMemoryKeyStore()
        let s = try store(clock, keys: keys)
        try add(s, app("Chrome", domain: "x.com"), start: t0, minutes: 1)
        _ = try s.crypto.domainHMAC("x.com")
        XCTAssertFalse(keys.keys.isEmpty)
        try DayLogStore.deleteAllData(directory: s.directory, keys: keys)
        XCTAssertFalse(FileManager.default.fileExists(atPath: s.directory.path))
        XCTAssertTrue(keys.keys.isEmpty)
    }
}

private extension String {
    var utf16LittleEndian: [UInt8] { utf16.flatMap { [UInt8($0 & 0xff), UInt8($0 >> 8)] } }
}
