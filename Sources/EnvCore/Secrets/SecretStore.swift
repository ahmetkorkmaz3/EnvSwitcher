import Foundation

public protocol SecretStore: Sendable {
    func read(account: String) throws -> String?
    func write(_ value: String, account: String) throws
    /// Deleting an account that does not exist is not an error.
    func delete(account: String) throws
}

public enum SecretStoreError: Error, Equatable {
    case keychain(status: Int32)
    case simulatedFailure
    /// The vault item exists but does not hold valid JSON. The item is left unchanged.
    case vaultCorrupt
    /// A Keychain item from before version 0.2.0 could not be read, so the vault did not open.
    case migrationFailed(status: Int32)
}

public enum SecretAccount {
    public static func make(projectId: UUID, targetId: UUID, environmentId: UUID, key: String) -> String {
        "\(projectId.uuidString)/\(targetId.uuidString)/\(environmentId.uuidString)/\(key)"
    }
}

/// Used by tests and SwiftUI previews.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String]
    private var shouldFailReads = false

    public init(values: [String: String] = [:]) {
        self.values = values
    }

    public var failReads: Bool {
        get { lock.withLock { shouldFailReads } }
        set { lock.withLock { shouldFailReads = newValue } }
    }

    public var snapshot: [String: String] { lock.withLock { values } }

    public func read(account: String) throws -> String? {
        try lock.withLock {
            if shouldFailReads { throw SecretStoreError.simulatedFailure }
            return values[account]
        }
    }

    public func write(_ value: String, account: String) throws {
        lock.withLock { values[account] = value }
    }

    public func delete(account: String) throws {
        lock.withLock { values[account] = nil }
    }
}
