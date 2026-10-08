import Foundation
@testable import EnvCore

/// In-memory KeychainBackend. It can fail reads, writes, deletes and the account list on request.
final class FakeKeychainBackend: KeychainBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data]
    private var readFailures: [String: Int32] = [:]
    private var deleteFailures: Set<String> = []
    private var writeFailure: Int32?
    private var listFailure: Int32?
    private var writes = 0

    init(items: [String: Data] = [:]) {
        self.items = items
    }

    /// The JSON that VaultSecretStore writes, for test setup.
    static func vault(_ secrets: [String: String]) -> Data {
        let object: [String: Any] = ["version": 1, "secrets": secrets]
        return try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    func failRead(of account: String, status: Int32) { lock.withLock { readFailures[account] = status } }
    func failDelete(of account: String) { lock.withLock { _ = deleteFailures.insert(account) } }

    var failWrites: Int32? {
        get { lock.withLock { writeFailure } }
        set { lock.withLock { writeFailure = newValue } }
    }

    var failList: Int32? {
        get { lock.withLock { listFailure } }
        set { lock.withLock { listFailure = newValue } }
    }

    var accounts: [String] { lock.withLock { items.keys.sorted() } }
    var writeCount: Int { lock.withLock { writes } }
    func data(_ account: String) -> Data? { lock.withLock { items[account] } }

    func readItem(account: String) throws -> Data? {
        try lock.withLock {
            if let status = readFailures[account] { throw SecretStoreError.keychain(status: status) }
            return items[account]
        }
    }

    func writeItem(_ data: Data, account: String) throws {
        try lock.withLock {
            if let status = writeFailure { throw SecretStoreError.keychain(status: status) }
            writes += 1
            items[account] = data
        }
    }

    func deleteItem(account: String) throws {
        try lock.withLock {
            if deleteFailures.contains(account) { throw SecretStoreError.keychain(status: -25244) }
            items[account] = nil
        }
    }

    func listAccounts() throws -> [String] {
        try lock.withLock {
            if let status = listFailure { throw SecretStoreError.keychain(status: status) }
            return items.keys.sorted()
        }
    }
}
