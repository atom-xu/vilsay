//
//  KeychainTokenStore.swift
//  vilsay
//

import Foundation
import Security

/// 存储后端 JWT（Week 4）；勿将 Token 写入可同步的 UserDefaults。
enum KeychainTokenStore {
    private static let service = "com.vilsay.app"
    private static let account = "auth_access_token"
    private static let refreshAccount = "auth_refresh_token"

    static func save(_ token: String) throws {
        try saveGeneric(account: account, token: token)
    }

    static func loadToken() -> String? {
        loadGeneric(account: account)
    }

    static func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        let rq: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: refreshAccount,
        ]
        SecItemDelete(rq as CFDictionary)
    }

    static func saveRefreshToken(_ token: String) throws {
        try saveGeneric(account: refreshAccount, token: token)
    }

    static func loadRefreshToken() -> String? {
        loadGeneric(account: refreshAccount)
    }

    private static func saveGeneric(account: String, token: String) throws {
        let data = Data(token.utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    private static func loadGeneric(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data, let s = String(data: data, encoding: .utf8), !s.isEmpty else {
            return nil
        }
        return s
    }

    enum KeychainError: Error {
        case unhandledStatus(OSStatus)
    }
}
