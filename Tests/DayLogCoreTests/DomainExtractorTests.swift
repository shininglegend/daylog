import XCTest
@testable import DayLogCore

final class DomainExtractorTests: XCTestCase {
    func testHostOnlyWithWWWStripped() {
        XCTAssertEqual(DomainExtractor.domain(fromURL: "https://www.example.com/secret/path?q=token#frag"), "example.com")
        XCTAssertEqual(DomainExtractor.domain(fromURL: "http://Docs.Google.com/document/d/abc"), "docs.google.com")
        XCTAssertEqual(DomainExtractor.domain(fromURL: "https://user:pass@www.site.org:8443/x"), "site.org")
        XCTAssertEqual(DomainExtractor.domain(fromURL: "https://example.com./"), "example.com")
    }

    func testInternalPages() {
        XCTAssertEqual(DomainExtractor.domain(fromURL: "chrome://settings/passwords"), "chrome")
        XCTAssertEqual(DomainExtractor.domain(fromURL: "chrome-extension://abcdef/popup.html"), "chrome")
        XCTAssertEqual(DomainExtractor.domain(fromURL: "about:blank"), "chrome")
        XCTAssertEqual(DomainExtractor.domain(fromURL: "devtools://devtools/bundled/inspector.html"), "chrome")
    }

    func testFileAndJunk() {
        XCTAssertEqual(DomainExtractor.domain(fromURL: "file:///Users/me/Secret.pdf"), "file")
        XCTAssertNil(DomainExtractor.domain(fromURL: ""))
        XCTAssertNil(DomainExtractor.domain(fromURL: "missing value"))
        XCTAssertNil(DomainExtractor.domain(fromURL: "data:text/html,hello"))
        XCTAssertNil(DomainExtractor.domain(fromURL: "https://"))
    }
}
