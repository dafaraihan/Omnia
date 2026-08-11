import XCTest
@testable import Omnia

final class SettingsConfirmationTests: XCTestCase {
    private enum Action: Equatable {
        case signOut
        case replaceImport
    }

    func testConfirmDoesNothingWithoutPendingAction() {
        var confirmation = SettingsConfirmation<Action>()

        XCTAssertNil(confirmation.confirm())
    }

    func testConfirmReturnsAndClearsRequestedAction() {
        var confirmation = SettingsConfirmation<Action>()
        confirmation.request(.signOut)

        XCTAssertEqual(confirmation.confirm(), .signOut)
        XCTAssertNil(confirmation.pending)
    }

    func testCancelClearsRequestedAction() {
        var confirmation = SettingsConfirmation<Action>()
        confirmation.request(.replaceImport)
        confirmation.cancel()

        XCTAssertNil(confirmation.pending)
        XCTAssertNil(confirmation.confirm())
    }
}
