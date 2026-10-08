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
}
