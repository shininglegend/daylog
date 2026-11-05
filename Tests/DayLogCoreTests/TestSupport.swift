import CryptoKit
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

func makeStore(clock: ManualClock, keys: KeyStore = InMemoryKeyStore(), dir: URL = makeTempDir()) throws -> DayLogStore {
    try DayLogStore(directory: dir, keys: keys, clock: clock, calendar: utcCalendar)
}

/// In-memory key store whose reads can be made to fail, like a locked or denied keychain.
final class FailingKeyStore: KeyStore {
    struct Unreadable: Error {}
    private let inner = InMemoryKeyStore()
    var failReads = false

    func key(named name: String) throws -> SymmetricKey? {
        if failReads { throw Unreadable() }
        return try inner.key(named: name)
    }
    func keyCreatingIfNeeded(named name: String) throws -> SymmetricKey {
        if failReads { throw Unreadable() }
        return try inner.keyCreatingIfNeeded(named: name)
    }
    func deleteKey(named name: String) throws { try inner.deleteKey(named: name) }
    func allKeyNames() throws -> [String] { try inner.allKeyNames() }
}

func app(_ name: String, title: String? = nil, domain: String? = nil) -> ActivityState {
    ActivityState(bundleID: "com.example.\(name.lowercased())", appName: name, title: title, domain: domain)
}
