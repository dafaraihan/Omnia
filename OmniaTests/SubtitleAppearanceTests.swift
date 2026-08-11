import XCTest
@testable import Omnia

final class SubtitleAppearanceTests: XCTestCase {
    func testPresetsResetAndNormalizeCustomBounds() {
        XCTAssertEqual(SubtitleAppearance.standard, .default)
        XCTAssertTrue(SubtitleAppearance.boxed.usesBackground)
        XCTAssertTrue(SubtitleAppearance.bold.isBold)

        var custom = SubtitleAppearance.default
        custom.textScalePercent = 999
        custom.backgroundOpacityPercent = -20
        custom.horizontalMarginPercent = 50
        let normalized = custom.normalized
        XCTAssertEqual(normalized.textScalePercent, 200)
        XCTAssertEqual(normalized.backgroundOpacityPercent, 0)
        XCTAssertEqual(normalized.horizontalMarginPercent, 15)
        XCTAssertEqual(normalized.reset(), .default)
    }
}
