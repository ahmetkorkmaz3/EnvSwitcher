import Foundation
import Testing
@testable import EnvCore

/// Uses the real login keychain. Run with: ENVSWITCHER_KEYCHAIN_TESTS=1 swift test --filter VaultKeychainTests
/// Serialized, because the vault test moves every item of the test service.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["ENVSWITCHER_KEYCHAIN_TESTS"] == "1"))
struct VaultKeychainTests {
    let backend = SystemKeychainBackend(service: "EnvSwitcherTests")

    @Test func systemBackendReadsWritesListsAndDeletes() throws {
        let account = "test/\(UUID().uuidString)"
        defer { try? backend.deleteItem(account: account) }
        #expect(try backend.readItem(account: account) == nil)
        try backend.writeItem(Data("first".utf8), account: account)
        try backend.writeItem(Data("second ğüşİ".utf8), account: account)
        #expect(try backend.readItem(account: account) == Data("second ğüşİ".utf8))
        #expect(try backend.listAccounts().contains(account))
        try backend.deleteItem(account: account)
        try backend.deleteItem(account: account)
        #expect(try backend.readItem(account: account) == nil)
        #expect(try !backend.listAccounts().contains(account))
    }

    @Test func vaultMovesLegacyItemsInTheRealKeychain() throws {
        let legacy = "test/\(UUID().uuidString)"
        defer {
            try? backend.deleteItem(account: legacy)
            try? backend.deleteItem(account: VaultSecretStore.vaultAccount)
        }
        try backend.writeItem(Data("legacy value".utf8), account: legacy)

        let store = VaultSecretStore(backend: backend)
        #expect(try store.read(account: legacy) == "legacy value")
        try store.write("new", account: "other")
        #expect(try backend.listAccounts().contains(legacy) == false)

        let reopened = VaultSecretStore(backend: backend)
        #expect(try reopened.read(account: "other") == "new")
        #expect(try reopened.read(account: legacy) == "legacy value")
    }
}
