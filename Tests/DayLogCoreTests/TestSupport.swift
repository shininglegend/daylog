import Foundation
@testable import DayLogCore

/// Fixed UTC calendar so day boundaries don't depend on the machine.
var utcCalendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

/// 2026-03-10 09:00:00 UTC
let t0 = Date(timeIntervalSince1970: 1_773_133_200)

func makeTempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("daylog-tests-\(UUID().uuidString)", isDirectory: true)
    return dir
}

func makeStore(clock: ManualClock, keys: InMemoryKeyStore = InMemoryKeyStore(), dir: URL = makeTempDir()) throws -> DayLogStore {
    try DayLogStore(directory: dir, keys: keys, clock: clock, calendar: utcCalendar)
}

func app(_ name: String, title: String? = nil, domain: String? = nil) -> ActivityState {
    ActivityState(bundleID: "com.example.\(name.lowercased())", appName: name, title: title, domain: domain)
}
