import XCTest
@testable import DayLogCore

final class RuleMatcherTests: XCTestCase {
    private func rule(_ type: RuleType, _ p: String) -> Rule { Rule(type: type, pattern: p, createdAt: t0) }

    func testAppRuleIsCaseInsensitiveExact() {
        let m = RuleMatcher(rules: [rule(.app, "com.apple.Notes")])
        XCTAssertTrue(m.matches(bundleID: "com.apple.notes", title: nil, domain: nil))
        XCTAssertFalse(m.matches(bundleID: "com.apple.notes2", title: nil, domain: nil))
    }

    func testDomainExactAndSuffix() {
        let m = RuleMatcher(rules: [rule(.domain, "www.bank.com")])
        XCTAssertTrue(m.matches(bundleID: nil, title: nil, domain: "bank.com"))
        XCTAssertTrue(m.matches(bundleID: nil, title: nil, domain: "login.bank.com"))
        XCTAssertFalse(m.matches(bundleID: nil, title: nil, domain: "notbank.com"))
        XCTAssertTrue(RuleMatcher(rules: [rule(.domain, "*.health.org")]).matches(bundleID: nil, title: nil, domain: "health.org"))
    }

    func testTitleContainsCaseInsensitive() {
        let m = RuleMatcher(rules: [rule(.titleContains, "Therapy")])
        XCTAssertTrue(m.matches(bundleID: nil, title: "my therapy notes", domain: nil))
        XCTAssertFalse(m.matches(bundleID: nil, title: "nothing", domain: nil))
        XCTAssertFalse(m.matches(bundleID: nil, title: nil, domain: nil))
    }

    func testTitleRegexAndInvalidRegex() {
        let m = RuleMatcher(rules: [rule(.titleRegex, #"^Invoice \d+"#), rule(.titleRegex, "([")])
        XCTAssertTrue(m.matches(bundleID: nil, title: "Invoice 42 - Mail", domain: nil))
        XCTAssertFalse(m.matches(bundleID: nil, title: "Re: Invoice 42", domain: nil))
        XCTAssertFalse(RuleMatcher.isValidRegex("(["))
    }

    func testApplyStripsIdentifyingFields() {
        let m = RuleMatcher(rules: [rule(.domain, "secret.com")])
        let blocked = m.apply(Observation(bundleID: "com.google.Chrome", appName: "Google Chrome", title: "Secret", domain: "secret.com"))
        XCTAssertEqual(blocked, .blocked)
        XCTAssertNil(blocked.title); XCTAssertNil(blocked.domain); XCTAssertNil(blocked.bundleID)
        XCTAssertEqual(blocked.appName, "Blocked")
        let ok = m.apply(Observation(bundleID: "a", appName: "A", title: "t", domain: "fine.com"))
        XCTAssertFalse(ok.blocked)
        XCTAssertEqual(ok.domain, "fine.com")
    }
}
