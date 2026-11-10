import XCTest
@testable import DayLogCore

final class TitleNormalizerTests: XCTestCase {
    func testAdobeZoomAndUnsavedMarker() {
        let expected = "Sattler Scroll Fall 26.indd"
        XCTAssertEqual(TitleNormalizer.normalize("*Sattler Scroll Fall 26.indd @ 61% [GPU Preview]"), expected)
        XCTAssertEqual(TitleNormalizer.normalize("*Sattler Scroll Fall 26.indd @ 72% [GPU Preview]"), expected)
        XCTAssertEqual(TitleNormalizer.normalize("Sattler Scroll Fall 26.indd @ 61%"), expected)
        XCTAssertEqual(TitleNormalizer.normalize("Photo.psd @ 66.7% (Layer 1, RGB/8)"), "Photo.psd")
    }

    func testAppKitEditedSuffix() {
        XCTAssertEqual(TitleNormalizer.normalize("Notes.txt — Edited"), "Notes.txt")
    }

    func testLeavesOrdinaryTitlesAlone() {
        XCTAssertEqual(TitleNormalizer.normalize("Paragraph Style Options"), "Paragraph Style Options")
        XCTAssertEqual(TitleNormalizer.normalize("Email me @ 5pm"), "Email me @ 5pm")
        XCTAssertNil(TitleNormalizer.normalize(nil))
        XCTAssertNil(TitleNormalizer.normalize("  "))
    }
}
