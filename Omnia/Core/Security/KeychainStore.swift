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
        // Provider credentials are personal secrets. Keep them out of
        // UserDefaults, the app bundle, and cloud sync. iOS and iPadOS use a
        // device-only protection class, so an encrypted device backup cannot
        // migrate the secret. On macOS the item stays in the user's local
        // login Keychain; we never opt it into Keychain synchronisation.
        var attributes: [CFString: Any] = [kSecValueData: data]
        #if !os(macOS)
        attributes[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        #endif
        let addQuery = query.merging(attributes) { _, latest in latest }
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

    static func delete(account: String, service: String = "PrimeDeca.Omnia") throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }

    enum KeychainError: Error {
        case unhandled(OSStatus)
    }
}
