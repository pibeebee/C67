import Foundation
import C67Domain
#if canImport(Security)
    import Security
#endif

/// A synchronous, atomic local store. Implementations must be safe across callers.
public protocol SessionStore: Sendable {
    func read() throws -> Data?
    func write(_ data: Data?) throws
}

#if canImport(Security)
    /// One item per backend and app. Tokens do not migrate to other devices or sync via iCloud.
    public struct KeychainSessionStore: SessionStore {
        private let service: String
        public init(namespace: String, baseURL: URL) {
            service = namespace + ".traveller-session." + baseURL.absoluteString
        }
        private var query: [String: Any] {
            [kSecClass as String: kSecClassGenericPassword,
             kSecAttrService as String: service, kSecAttrAccount as String: "traveller",
             kSecAttrSynchronizable as String: false]
        }
        public func read() throws -> Data? {
            var query = query
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound { return nil }
            guard status == errSecSuccess, let data = result as? Data else {
                throw AuthenticationError.storageUnavailable
            }
            return data
        }
        public func write(_ data: Data?) throws {
            guard let data else {
                let status = SecItemDelete(query as CFDictionary)
                guard status == errSecSuccess || status == errSecItemNotFound else {
                    throw AuthenticationError.storageUnavailable
                }
                return
            }
            let attributes: [String: Any] = [kSecValueData as String: data,
                                             kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if status == errSecItemNotFound {
                var item = query
                item.merge(attributes) { _, new in new }
                guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                    throw AuthenticationError.storageUnavailable
                }
            } else if status != errSecSuccess { throw AuthenticationError.storageUnavailable }
        }
    }
#endif
