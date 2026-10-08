import Foundation
import Security

/// The Keychain calls that VaultSecretStore needs. Tests use an in-memory fake.
public protocol KeychainBackend: Sendable {
    func readItem(account: String) throws -> Data?
    func writeItem(_ data: Data, account: String) throws
    /// Deleting an item that does not exist is not an error.
    func deleteItem(account: String) throws
    /// Returns the accounts of all items with the service name, without their data.
    func listAccounts() throws -> [String]
}

/// Generic password items in the file-based login keychain.
public struct SystemKeychainBackend: KeychainBackend {
    public let service: String

    public init(service: String = "EnvSwitcher") {
        self.service = service
    }

    private func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func readItem(account: String) throws -> Data? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw SecretStoreError.keychain(status: status)
        }
        return data
    }

    public func writeItem(_ data: Data, account: String) throws {
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query(account)
            add[kSecValueData as String] = data
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw SecretStoreError.keychain(status: addStatus) }
            return
        }
        guard status == errSecSuccess else { throw SecretStoreError.keychain(status: status) }
    }

    public func deleteItem(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.keychain(status: status)
        }
    }

    public func listAccounts() throws -> [String] {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            throw SecretStoreError.keychain(status: status)
        }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }
}
