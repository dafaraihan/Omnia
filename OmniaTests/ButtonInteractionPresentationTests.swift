import XCTest
@testable import Omnia

final class ButtonInteractionPresentationTests: XCTestCase {
    func testActiveStateIncludesPointerHoverAndNativeButtonPress() {
        XCTAssertFalse(ButtonInteractionPresentation.isActive(isHovered: false, isPressed: false))
        XCTAssertTrue(ButtonInteractionPresentation.isActive(isHovered: true, isPressed: false))
        XCTAssertTrue(ButtonInteractionPresentation.isActive(isHovered: false, isPressed: true))
        XCTAssertTrue(ButtonInteractionPresentation.isActive(isHovered: true, isPressed: true))
    }
}
