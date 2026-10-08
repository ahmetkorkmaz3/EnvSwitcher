import Foundation

/// Keeps all secrets in one Keychain item (spec 2026-10-08, section 3).
/// One item means at most one permission prompt when the code signature changes.
public final class VaultSecretStore: SecretStore, @unchecked Sendable {
    public static let vaultAccount = "vault"

    private struct Payload: Codable {
        var version: Int
        var secrets: [String: String]
    }

    private enum State {
        case notLoaded
        case loaded([String: String])
        /// The vault could not be read. Writing now would replace the user's secrets with an empty vault.
        case failed(any Error)
    }

    private let backend: any KeychainBackend
    private let lock = NSLock()
    private var state = State.notLoaded

    public init(backend: any KeychainBackend = SystemKeychainBackend()) {
        self.backend = backend
    }

    /// Loads the vault. The other methods also load it on first use.
    public func open() throws {
        try lock.withLock { _ = try loadedSecrets() }
    }

    public func read(account: String) throws -> String? {
        try lock.withLock { try loadedSecrets()[account] }
    }

    public func write(_ value: String, account: String) throws {
        try lock.withLock {
            var secrets = try loadedSecrets()
            guard secrets[account] != value else { return }
            secrets[account] = value
            try save(secrets)
        }
    }

    public func delete(account: String) throws {
        try lock.withLock {
            var secrets = try loadedSecrets()
            guard secrets.removeValue(forKey: account) != nil else { return }
            try save(secrets)
        }
    }

    // MARK: Private. Call these with the lock held.

    private func loadedSecrets() throws -> [String: String] {
        switch state {
        case .loaded(let secrets):
            return secrets
        case .failed(let error):
            throw error
        case .notLoaded:
            do {
                let secrets = try load()
                state = .loaded(secrets)
                return secrets
            } catch {
                state = .failed(error)
                throw error
            }
        }
    }

    /// Reads the vault, then moves items from before version 0.2.0 into it (spec 3.4).
    /// A vault value wins over a legacy value, so a half-done migration finishes on the next launch.
    private func load() throws -> [String: String] {
        var secrets = try readVault()
        let legacy = try backend.listAccounts().filter { $0 != Self.vaultAccount }
        guard !legacy.isEmpty else { return secrets }

        var added = false
        for account in legacy where secrets[account] == nil {
            let data: Data?
            do {
                data = try backend.readItem(account: account)
            } catch SecretStoreError.keychain(let status) {
                throw SecretStoreError.migrationFailed(status: status)
            }
            guard let data else { continue }
            secrets[account] = String(decoding: data, as: UTF8.self)
            added = true
        }
        if added {
            try backend.writeItem(try encode(secrets), account: Self.vaultAccount)
        }
        for account in legacy {
            // A failed delete is tried again on the next launch.
            try? backend.deleteItem(account: account)
        }
        return secrets
    }

    private func readVault() throws -> [String: String] {
        guard let data = try backend.readItem(account: Self.vaultAccount) else { return [:] }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw SecretStoreError.vaultCorrupt
        }
        return payload.secrets
    }

    /// Writes the whole vault first. Memory changes only when the write succeeds.
    private func save(_ secrets: [String: String]) throws {
        try backend.writeItem(try encode(secrets), account: Self.vaultAccount)
        state = .loaded(secrets)
    }

    private func encode(_ secrets: [String: String]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Payload(version: 1, secrets: secrets))
    }
}
