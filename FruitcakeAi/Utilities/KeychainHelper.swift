//
//  KeychainHelper.swift
//  FruitcakeAi
//
//  Keychain read/write utility. All JWT tokens and server credentials
//  are stored here — never in UserDefaults or SwiftData.
//

import Foundation
import Security

enum KeychainHelper {

    static let service = "com.fruitcakeai.app"

    // MARK: - Save

    @discardableResult
    static func save(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        // Delete any existing item first so we can re-add cleanly
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData] = data

        let status = SecItemAdd(attributes as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - Read

    static func read(forKey key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Delete

    @discardableResult
    static func delete(forKey key: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Convenience keys

    enum Keys {
        static let accessToken  = "access_token"
        static let refreshToken = "refresh_token"
        static let serverURL    = "server_url"
    }
}
