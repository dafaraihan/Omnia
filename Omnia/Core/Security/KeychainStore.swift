//
//  KeychainStore.swift
//  Omnia
//

import Foundation
import Security

enum KeychainStore {
    nonisolated static let defaultService = "Dafa-Raihan.Omnia"
    nonisolated static let legacyService = "PrimeDeca.Omnia"

    nonisolated static func save(
        _ value: String,
        account: String,
        service: String = KeychainStore.defaultService
    ) throws {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        // Provider credentials are personal secrets. Keep them out of
        // UserDefaults, the app bundle, and cloud sync. iOS and iPadOS use a
        // device-only protection class, so an encrypted device backup cannot
        // migrate the secret. On macOS the item stays in the user's local
        // login Keychain; we never opt it into Keychain synchronisation.
        var attributes: [CFString: Any] = [kSecValueData: data]
        #if !os(macOS)
        attributes[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        #endif

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            if service == defaultService {
                try? deleteItem(account: account, service: legacyService)
            }
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.unhandled(updateStatus)
        }

        let addQuery = query.merging(attributes) { _, latest in latest }
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }

        if service == defaultService {
            try? deleteItem(account: account, service: legacyService)
        }
    }

    nonisolated static func value(
        account: String,
        service: String = KeychainStore.defaultService
    ) throws -> String? {
        if let value = try storedValue(account: account, service: service) {
            return value
        }
        guard service == defaultService,
              let legacyValue = try storedValue(account: account, service: legacyService)
        else { return nil }

        try save(legacyValue, account: account, service: defaultService)
        return legacyValue
    }

    nonisolated static func delete(
        account: String,
        service: String = KeychainStore.defaultService
    ) throws {
        try deleteItem(account: account, service: service)
        if service == defaultService {
            try deleteItem(account: account, service: legacyService)
        }
    }

    nonisolated private static func storedValue(account: String, service: String) throws -> String? {
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

    nonisolated private static func deleteItem(account: String, service: String) throws {
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
