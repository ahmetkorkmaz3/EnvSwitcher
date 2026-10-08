import Foundation
import Testing
@testable import EnvCore

struct VaultSecretStoreTests {
    private func decode(_ data: Data?) throws -> [String: String] {
        let object = try JSONSerialization.jsonObject(with: try #require(data)) as? [String: Any]
        #expect(object?["version"] as? Int == 1)
        return try #require(object?["secrets"] as? [String: String])
    }

    @Test func startsEmptyWhenTheItemDoesNotExist() throws {
        let backend = FakeKeychainBackend()
        let store = VaultSecretStore(backend: backend)
        #expect(try store.read(account: "a") == nil)
        #expect(backend.writeCount == 0)
    }

    @Test func writesReadsAndDeletesThroughOneItem() throws {
        let backend = FakeKeychainBackend()
        let store = VaultSecretStore(backend: backend)
        try store.write("1", account: "a")
        try store.write("ğüş", account: "b")
        #expect(try store.read(account: "a") == "1")
        #expect(backend.accounts == ["vault"])
        #expect(try decode(backend.data("vault")) == ["a": "1", "b": "ğüş"])

        try store.delete(account: "a")
        #expect(try store.read(account: "a") == nil)
        #expect(try decode(backend.data("vault")) == ["b": "ğüş"])
    }

    @Test func readsAnExistingVault() throws {
        let backend = FakeKeychainBackend(items: ["vault": FakeKeychainBackend.vault(["a": "1"])])
        #expect(try VaultSecretStore(backend: backend).read(account: "a") == "1")
    }

    @Test func deletingAMissingAccountDoesNotWrite() throws {
        let backend = FakeKeychainBackend()
        let store = VaultSecretStore(backend: backend)
        try store.delete(account: "missing")
        #expect(backend.writeCount == 0)
    }

    @Test func writingTheSameValueDoesNotWrite() throws {
        let backend = FakeKeychainBackend(items: ["vault": FakeKeychainBackend.vault(["a": "1"])])
        let store = VaultSecretStore(backend: backend)
        try store.write("1", account: "a")
        #expect(backend.writeCount == 0)
    }

    @Test func failedWriteKeepsTheOldValueInMemory() throws {
        let backend = FakeKeychainBackend(items: ["vault": FakeKeychainBackend.vault(["a": "1"])])
        let store = VaultSecretStore(backend: backend)
        backend.failWrites = -25299
        #expect(throws: SecretStoreError.keychain(status: -25299)) { try store.write("2", account: "a") }
        #expect(throws: SecretStoreError.keychain(status: -25299)) { try store.delete(account: "a") }
        backend.failWrites = nil
        #expect(try store.read(account: "a") == "1")
    }

    @Test func readFailureBlocksEveryLaterCallAndNeverWrites() throws {
        let backend = FakeKeychainBackend(items: ["vault": FakeKeychainBackend.vault(["a": "1"])])
        backend.failRead(of: "vault", status: -128)
        let store = VaultSecretStore(backend: backend)
        #expect(throws: SecretStoreError.keychain(status: -128)) { try store.open() }
        #expect(throws: SecretStoreError.keychain(status: -128)) { try store.read(account: "a") }
        #expect(throws: SecretStoreError.keychain(status: -128)) { try store.write("x", account: "b") }
        #expect(throws: SecretStoreError.keychain(status: -128)) { try store.delete(account: "a") }
        #expect(backend.writeCount == 0)
        #expect(try decode(backend.data("vault")) == ["a": "1"])
    }

    @Test func corruptVaultBlocksEveryLaterCallAndNeverWrites() throws {
        let backend = FakeKeychainBackend(items: ["vault": Data("not json".utf8)])
        let store = VaultSecretStore(backend: backend)
        #expect(throws: SecretStoreError.vaultCorrupt) { try store.read(account: "a") }
        #expect(throws: SecretStoreError.vaultCorrupt) { try store.write("x", account: "a") }
        #expect(backend.writeCount == 0)
        #expect(backend.data("vault") == Data("not json".utf8))
    }

    @Test func loadsTheItemOnlyOnce() throws {
        let backend = FakeKeychainBackend(items: ["vault": FakeKeychainBackend.vault(["a": "1"])])
        let store = VaultSecretStore(backend: backend)
        try store.open()
        backend.failRead(of: "vault", status: -128)
        #expect(try store.read(account: "a") == "1")
    }
}
