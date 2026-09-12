import Security
import XCTest
@testable import Omnia

final class KeychainStoreTests: XCTestCase {
    func testSavingExistingValuePreservesKeychainItemCreationDate() throws {
        let service = "Dafa-Raihan.OmniaTests.\(UUID().uuidString)"
        let account = "credential"
        defer { try? KeychainStore.delete(account: account, service: service) }

        try KeychainStore.save("first", account: account, service: service)
        let originalCreationDate = try creationDate(account: account, service: service)
        Thread.sleep(forTimeInterval: 1.1)

        try KeychainStore.save("second", account: account, service: service)

        XCTAssertEqual(
            try creationDate(account: account, service: service),
            originalCreationDate,
            "Updating a credential must preserve the Keychain item and its access-control list."
        )
        XCTAssertEqual(try KeychainStore.value(account: account, service: service), "second")
    }

    private func creationDate(account: String, service: String) throws -> Date {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnAttributes: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let attributes = result as? [CFString: Any],
              let creationDate = attributes[kSecAttrCreationDate] as? Date else {
            throw KeychainStore.KeychainError.unhandled(status)
        }
        return creationDate
    }
}
