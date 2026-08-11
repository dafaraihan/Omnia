import XCTest
@testable import Omnia

final class AppDestinationTests: XCTestCase {
    func testMacDestinationsRetainSettingsInMainNavigation() {
        XCTAssertTrue(AppDestination.visibleDestinations(for: .mac).contains(.settings))
    }

    func testMobileDestinationsRetainSettingsTab() {
        XCTAssertTrue(AppDestination.visibleDestinations(for: .mobile).contains(.settings))
    }
}
