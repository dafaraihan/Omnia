import XCTest
@testable import Omnia

final class SubtitleAppearanceSettingsModelTests: XCTestCase {
    func testPresetSelectionProducesTheDocumentedStyle() {
        let model = SubtitleAppearanceSettingsModel(mode: .boxed, custom: .default)

        XCTAssertEqual(model.resolvedAppearance, .boxed)
        XCTAssertFalse(model.usesCustomControls)
    }

    func testEditingAStyleTransitionsToCustomAndNormalizesBounds() {
        var model = SubtitleAppearanceSettingsModel(mode: .standard, custom: .default)

        model.updateCustom { appearance in
            appearance.textScalePercent = 203
            appearance.horizontalMarginPercent = -4
        }

        XCTAssertEqual(model.mode, .custom)
        XCTAssertEqual(model.custom.textScalePercent, 200)
        XCTAssertEqual(model.custom.horizontalMarginPercent, 0)
        XCTAssertTrue(model.usesCustomControls)
    }

    func testResetRequiresMatchingConfirmation() {
        var model = SubtitleAppearanceSettingsModel(mode: .bold, custom: .bold)
        let confirmation = model.makeResetConfirmation()

        XCTAssertFalse(model.reset(confirmation: UUID()))
        XCTAssertEqual(model.mode, .bold)
        XCTAssertTrue(model.reset(confirmation: confirmation))
        XCTAssertEqual(model.mode, .followSystem)
        XCTAssertEqual(model.custom, .default)
    }
}
