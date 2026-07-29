//
//  KeychainStore.swift
//  Omnia
//

import Foundation
import Security

enum KeychainStore {
    static func save(_ value: String, account: String, service: String = "PrimeDeca.Omnia") throws {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
        let addQuery = query.merging([kSecValueData: data]) { _, latest in latest }
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }

    static func value(account: String, service: String = "PrimeDeca.Omnia") throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.unhandled(status)
        }
        return value
    }

    enum KeychainError: Error {
        case unhandled(OSStatus)
    }
}
