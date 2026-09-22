import Foundation
import Security

/// The TypeSafe API key, in the login keychain.
///
/// Not UserDefaults: this is a credential, and an open-source app should not
/// leave one in a plist that syncs and backs up in the clear.
enum Credentials {
    private static let service = "ai.jev.control"
    private static let account = "typesafe-api-key"
    private static let modelKey = "ai.jev.control.jevModel"

    static var apiKey: String? {
        get {
            // An environment variable wins, so a developer can run against a
            // different key without touching the keychain.
            if let fromEnv = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"],
               !fromEnv.isEmpty {
                return fromEnv
            }
            var query: [String: Any] = baseQuery
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne

            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data,
                  let value = String(data: data, encoding: .utf8),
                  !value.isEmpty
            else { return nil }
            return value
        }
        set {
            SecItemDelete(baseQuery as CFDictionary)
            guard let newValue, !newValue.isEmpty else { return }
            var query = baseQuery
            query[kSecValueData as String] = Data(newValue.utf8)
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    static var hasAPIKey: Bool { apiKey?.isEmpty == false }

    static var model: String {
        get { UserDefaults.standard.string(forKey: modelKey) ?? JevClient.defaultModel }
        set { UserDefaults.standard.set(newValue, forKey: modelKey) }
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
