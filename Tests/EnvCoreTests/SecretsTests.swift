import Foundation
import Testing
@testable import EnvCore

struct SecretsTests {
    @Test func accountUsesIdsInFixedOrder() {
        let p = UUID(), t = UUID(), e = UUID()
        #expect(SecretAccount.make(projectId: p, targetId: t, environmentId: e, key: "API_TOKEN")
            == "\(p.uuidString)/\(t.uuidString)/\(e.uuidString)/API_TOKEN")
    }

    @Test func inMemoryStoreReadsWritesAndDeletes() throws {
        let store = InMemorySecretStore()
        #expect(try store.read(account: "a") == nil)
        try store.write("1", account: "a")
        try store.write("2", account: "a")
        #expect(try store.read(account: "a") == "2")
        try store.delete(account: "a")
        try store.delete(account: "a")
        #expect(try store.read(account: "a") == nil)
    }

    @Test func inMemoryStoreCanSimulateReadFailure() {
        let store = InMemorySecretStore(values: ["a": "1"])
        store.failReads = true
        #expect(throws: SecretStoreError.simulatedFailure) { try store.read(account: "a") }
    }

    @Test(arguments: [
        ("DB_PASSWORD", true),
        ("TURNSTILE_SECRET_KEY", true),
        ("API_TOKEN", true),
        ("STRIPE_KEY", true),
        ("PRIVATE_PEM", true),
        ("NEXT_PUBLIC_ACCESS_TOKEN_COOKIE", false),
        ("NEXT_PUBLIC_TURNSTILE_SITE_KEY", false),
        ("API_TIMEOUT_MS", false),
        ("KEYBOARD_LAYOUT", false),
    ])
    func suggestsSecrets(key: String, expected: Bool) {
        #expect(SecretSuggester.isLikelySecret(key) == expected)
    }

    /// Uses the real login keychain. Run with: ENVSWITCHER_KEYCHAIN_TESTS=1 swift test --filter SecretsTests
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ENVSWITCHER_KEYCHAIN_TESTS"] == "1"))
    func keychainStoreReadsWritesAndDeletes() throws {
        let store = KeychainSecretStore(service: "EnvSwitcher.tests")
        let account = "test/\(UUID().uuidString)"
        defer { try? store.delete(account: account) }
        #expect(try store.read(account: account) == nil)
        try store.write("first", account: account)
        try store.write("second ğüşİ", account: account)
        #expect(try store.read(account: account) == "second ğüşİ")
        try store.delete(account: account)
        #expect(try store.read(account: account) == nil)
    }
}
