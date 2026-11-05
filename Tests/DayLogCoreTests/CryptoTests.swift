import CryptoKit
import XCTest
@testable import DayLogCore

final class CryptoTests: XCTestCase {
    func testRoundTrip() throws {
        let crypto = Crypto(keys: InMemoryKeyStore())
        let box = try crypto.seal("Quarterly plan.key — Keynote", field: .title, segmentStart: t0)
        XCTAssertEqual(crypto.open(box, field: .title, segmentStart: t0), .value("Quarterly plan.key — Keynote"))
    }

    func testRandomNonceAndFieldBinding() throws {
        let crypto = Crypto(keys: InMemoryKeyStore())
        let a = try crypto.seal("same", field: .title, segmentStart: t0)
        let b = try crypto.seal("same", field: .title, segmentStart: t0)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(crypto.open(a, field: .domain, segmentStart: t0), .expired)
    }

    func testOneKeyPerUTCHour() throws {
        let keys = InMemoryKeyStore()
        let crypto = Crypto(keys: keys)
        _ = try crypto.seal("x", field: .title, segmentStart: t0)
        _ = try crypto.seal("x", field: .title, segmentStart: t0.addingTimeInterval(3599))
        _ = try crypto.seal("x", field: .title, segmentStart: t0.addingTimeInterval(3600))
        XCTAssertEqual(Set(keys.keys.keys), ["local.daylog.seg.2026031009", "local.daylog.seg.2026031010"])
        XCTAssertEqual(KeyNames.hourStart(ofSegmentKey: "local.daylog.seg.2026031009"), t0)
    }

    func testMissingKeyReadsExpired() throws {
        let keys = InMemoryKeyStore()
        let crypto = Crypto(keys: keys)
        let box = try crypto.seal("x", field: .title, segmentStart: t0)
        try keys.deleteKey(named: KeyNames.segmentKey(for: t0))
        XCTAssertEqual(crypto.open(box, field: .title, segmentStart: t0), .expired)
    }

    func testDomainHMACIsStableAndKeyed() throws {
        let crypto = Crypto(keys: InMemoryKeyStore())
        XCTAssertEqual(try crypto.domainHMAC("github.com"), try crypto.domainHMAC("github.com"))
        XCTAssertNotEqual(try crypto.domainHMAC("github.com"), try crypto.domainHMAC("gitlab.com"))
        XCTAssertNotEqual(try crypto.domainHMAC("github.com"), try Crypto(keys: InMemoryKeyStore()).domainHMAC("github.com"))
        XCTAssertEqual(crypto.openLabel(try crypto.sealLabel("github.com")), "github.com")
    }
}
