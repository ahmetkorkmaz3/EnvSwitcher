# GitHub ile Dağıtım — Uygulama Planı

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Kullanıcı EnvSwitcher uygulamasını tek bir `curl … | sh` komutu ile GitHub Releases üzerinden kurar ve Keychain izin sorusu görmez.

**Architecture:** Gizli değerler tek bir Keychain kaydına (`vault`) taşınır. Yeni `VaultSecretStore` sınıfı var olan `SecretStore` protokolünü uygular, bu nedenle diğer kod değişmez. Tüm sürümler aynı kendinden imzalı sertifika ile imzalanır. GitHub Actions bir `v*` etiketinde evrensel binary derler, imzalar ve release yayınlar. Uygulama günde bir kez GitHub'dan son sürümü okur.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, Security.framework, POSIX `sh`, GitHub Actions, `codesign`, LibreSSL (`/usr/bin/openssl`).

**Spec:** `docs/superpowers/specs/2026-10-08-github-release-design.md`

## Global Constraints

- macOS 14 ve üstü. `Package.swift` değişmez (`swift-tools-version:6.0`, `.macOS(.v14)`).
- Yeni bağımlılık yok.
- Bundle kimliği: `com.ahmetkorkmaz.envswitcher`. Keychain servis adı: `EnvSwitcher`. Kasa hesap adı: `vault`.
- Kasa biçimi: UTF-8 JSON `{"version": 1, "secrets": {"<hesap>": "<değer>"}}`.
- Hesap adı `SecretAccount.make` çıktısıdır ve değişmez.
- İmza kimliği adı: `EnvSwitcher Self-Signed`.
- GitHub secret adları: `SIGNING_CERT_P12_BASE64`, `SIGNING_CERT_PASSWORD`.
- Repo: `ahmetkorkmaz3/env-management`. Kurulum komutu: `curl -fsSL https://raw.githubusercontent.com/ahmetkorkmaz3/env-management/main/install.sh | sh`
- Release dosyaları: `EnvSwitcher-X.Y.Z.zip` ve `EnvSwitcher-X.Y.Z.zip.sha256`.
- Kullanıcıya görünen metinler Türkçe. Kod yorumları İngilizce. Commit mesajları İngilizce, Conventional Commits.
- Her commit mesajı şu satırla biter: `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`
- `EnvSwitcher` hedefi Swift 5 dil modunda derlenir. `EnvCore` Swift 6 modunda derlenir.

## Spec'ten ayrılan noktalar

- **CI runner:** Spec `macos-15` yazar. Plan `macos-26` kullanır. Neden: yerel derleyici Swift 6.3. `macos-15` imajındaki Xcode 16 sürümleri bu kodu derlemeyebilir. Görev 12 ilk CI çalışmasını kontrol eder.
- **Sertifika betiği çıktısı:** Spec, base64 metnini ve şifreyi ekrana yazar. Plan bu değerleri `chmod 600` dosyalara yazar ve ekrana yalnızca dosya yollarını yazar. Neden: terminal geçmişi ve ekran kaydı şifreyi saklamaz.
- **Kurulum betiği sürüm okuma:** Spec GitHub API kullanır. Plan `https://github.com/<repo>/releases/latest` yönlendirmesini okur. Neden: GitHub API kimliksiz isteklerde saatte 60 istek sınırı koyar. Yönlendirmede bu sınır yoktur.
- **Bulunan güncellemeyi saklama:** Spec yalnızca son kontrol tarihini saklar. Bu durumda uygulama yeniden açılınca "Güncelleme var" satırı 24 saat kaybolur. Plan bulunan sürümü de `UserDefaults` içinde saklar (Görev 6).

## Review Focus

1. **Kasa okunamazken yazma:** Kullanıcı Keychain sorusunda "Reddet" seçer, sonra bir değer düzenler. Beklenen: kasa boş bir sözlük ile ezilmez. Görev 2 ve Görev 3 testleri bu durumu kapsar.
2. **Yarım kalan taşıma:** Taşıma kasayı yazar, ama bir eski kayıt silinemez. Sonraki açılışta eski değer kasadaki yeni değerin üzerine yazmaz. Görev 3 testi `vaultValueWinsOverLegacyValue` bu durumu kapsar.
3. **Saat geri alınır:** Son kontrol tarihi gelecekte kalır. Beklenen: kontrol yine çalışır, sonsuza kadar durmaz. Görev 5 testi `dueWhenClockMovedBack` bu durumu kapsar.
4. **Uygulama yeniden açılır:** Bulunan güncelleme menüde kalır. Kullanıcı yeni sürümü kurunca satır kaybolur. Görev 6 testleri `StoredUpdate` için bu durumu kapsar.
5. **`/Applications` yazılamaz veya uygulama çalışıyor:** Kurulum betiği `sudo` ister veya uygulamayı kapatır. Hash uymazsa hiçbir dosya değişmez. Görev 11 elle testleri bu durumu kapsar.

---

## Dosya haritası

| Dosya | Görev | Sorumluluk |
|---|---|---|
| `Sources/EnvCore/Secrets/SecretStore.swift` | 1 | Yeni hata durumları |
| `Sources/EnvCore/Secrets/KeychainBackend.swift` | 1 | `KeychainBackend` protokolü ve `SystemKeychainBackend` |
| `Tests/EnvCoreTests/Support/FakeKeychainBackend.swift` | 1 | Testler için bellekte çalışan Keychain |
| `Tests/EnvCoreTests/VaultKeychainTests.swift` | 1, 4 | Gerçek Keychain testleri (ortam değişkeni ile) |
| `Sources/EnvCore/Secrets/VaultSecretStore.swift` | 2, 3 | Tek kayıt kasası ve taşıma |
| `Tests/EnvCoreTests/VaultSecretStoreTests.swift` | 2, 3 | Kasa birim testleri |
| `Sources/EnvCore/Secrets/KeychainSecretStore.swift` | 4 | Silinir |
| `Sources/EnvSwitcher/App/AppState.swift` | 4, 7 | Kasa bağlantısı, hata metinleri, güncelleme izleyici |
| `Sources/EnvCore/Update/SemanticVersion.swift` | 5 | Sürüm ayrıştırma ve karşılaştırma |
| `Sources/EnvCore/Update/UpdateSchedule.swift` | 5 | 24 saat kuralı |
| `Sources/EnvCore/Update/UpdateChecker.swift` | 6 | GitHub isteği, `ReleaseInfo`, `StoredUpdate` |
| `Tests/EnvCoreTests/UpdateTests.swift` | 5, 6 | Güncelleme birim testleri |
| `Sources/EnvSwitcher/App/UpdateMonitor.swift` | 7 | Zamanlayıcı, `UserDefaults`, menü eylemi |
| `Sources/EnvSwitcher/MenuBar/MenuContent.swift` | 7 | "Güncelleme var" ve "Sürüm" satırları |
| `scripts/make-icon.swift`, `scripts/make-icon.sh`, `Resources/AppIcon.icns` | 8 | Uygulama ikonu |
| `scripts/bundle.sh` | 9 | Evrensel derleme, sürüm, ikon, imza |
| `scripts/make-signing-cert.sh` | 10 | Kendinden imzalı sertifika |
| `install.sh` | 11 | Kurulum ve güncelleme betiği |
| `scripts/changelog-section.sh` | 12 | Sürüm notlarını CHANGELOG'dan okuma |
| `.github/workflows/ci.yml`, `.github/workflows/release.yml` | 12 | CI ve release |
| `LICENSE`, `CHANGELOG.md`, `README.md`, `docs/release.md`, `docs/manual-test.md`, ana spec | 13 | Dokümanlar |

---

### Task 1: Keychain arka ucu

**Files:**
- Modify: `Sources/EnvCore/Secrets/SecretStore.swift:10-13`
- Create: `Sources/EnvCore/Secrets/KeychainBackend.swift`
- Create: `Tests/EnvCoreTests/Support/FakeKeychainBackend.swift`
- Create: `Tests/EnvCoreTests/VaultKeychainTests.swift`

**Interfaces:**
- Produces:
  - `public protocol KeychainBackend: Sendable` — `readItem(account: String) throws -> Data?`, `writeItem(_ data: Data, account: String) throws`, `deleteItem(account: String) throws`, `listAccounts() throws -> [String]`
  - `public struct SystemKeychainBackend: KeychainBackend` — `init(service: String = "EnvSwitcher")`
  - `SecretStoreError.vaultCorrupt`, `SecretStoreError.migrationFailed(status: Int32)`
  - Test: `final class FakeKeychainBackend` — `init(items: [String: Data] = [:])`, `failRead(of:status:)`, `failDelete(of:)`, `var failWrites: Int32?`, `var failList: Int32?`, `var accounts: [String]`, `func data(_:) -> Data?`, `var writeCount: Int`, `static func vault(_ secrets: [String: String]) -> Data`

- [ ] **Step 1: Hata durumlarını ekle**

`Sources/EnvCore/Secrets/SecretStore.swift` içinde `SecretStoreError` şu hali alır:

```swift
public enum SecretStoreError: Error, Equatable {
    case keychain(status: Int32)
    case simulatedFailure
    /// The vault item exists but does not hold valid JSON. The item is left unchanged.
    case vaultCorrupt
    /// A Keychain item from before version 0.2.0 could not be read, so the vault did not open.
    case migrationFailed(status: Int32)
}
```

- [ ] **Step 2: Gerçek Keychain testini yaz**

`Tests/EnvCoreTests/VaultKeychainTests.swift`:

```swift
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
```

- [ ] **Step 3: Testin derlenmediğini gör**

Run: `ENVSWITCHER_KEYCHAIN_TESTS=1 swift test --filter VaultKeychainTests`
Expected: FAIL, "cannot find 'SystemKeychainBackend' in scope".

- [ ] **Step 4: `KeychainBackend.swift` dosyasını yaz**

```swift
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
```

- [ ] **Step 5: Sahte arka ucu yaz**

`Tests/EnvCoreTests/Support/FakeKeychainBackend.swift`:

```swift
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
```

- [ ] **Step 6: Testleri çalıştır**

Run: `ENVSWITCHER_KEYCHAIN_TESTS=1 swift test --filter VaultKeychainTests`
Expected: PASS. Test binary'si kaydı kendisi oluşturur, bu nedenle Keychain sorusu çıkmaz.

Run: `swift test`
Expected: PASS (tüm eski testler).

- [ ] **Step 7: Commit**

```bash
git add Sources/EnvCore/Secrets/SecretStore.swift Sources/EnvCore/Secrets/KeychainBackend.swift Tests/EnvCoreTests/Support/FakeKeychainBackend.swift Tests/EnvCoreTests/VaultKeychainTests.swift
git commit -m "feat(core): add a keychain backend protocol with a system and a fake implementation"
```

---

### Task 2: `VaultSecretStore` (taşıma olmadan)

**Files:**
- Create: `Sources/EnvCore/Secrets/VaultSecretStore.swift`
- Create: `Tests/EnvCoreTests/VaultSecretStoreTests.swift`

**Interfaces:**
- Consumes: `KeychainBackend`, `SystemKeychainBackend`, `SecretStoreError` (Task 1)
- Produces: `public final class VaultSecretStore: SecretStore` — `init(backend: any KeychainBackend = SystemKeychainBackend())`, `func open() throws`, `static let vaultAccount = "vault"`

- [ ] **Step 1: Testleri yaz**

`Tests/EnvCoreTests/VaultSecretStoreTests.swift`:

```swift
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
```

- [ ] **Step 2: Testlerin derlenmediğini gör**

Run: `swift test --filter VaultSecretStoreTests`
Expected: FAIL, "cannot find 'VaultSecretStore' in scope".

- [ ] **Step 3: `VaultSecretStore.swift` dosyasını yaz**

```swift
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

    private func load() throws -> [String: String] {
        try readVault()
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
```

- [ ] **Step 4: Testleri çalıştır**

Run: `swift test --filter VaultSecretStoreTests`
Expected: PASS, 9 test.

- [ ] **Step 5: Commit**

```bash
git add Sources/EnvCore/Secrets/VaultSecretStore.swift Tests/EnvCoreTests/VaultSecretStoreTests.swift
git commit -m "feat(core): keep all secrets in one keychain item"
```

---

### Task 3: Eski kayıtları kasaya taşıma

**Files:**
- Modify: `Sources/EnvCore/Secrets/VaultSecretStore.swift` (`load()` fonksiyonu)
- Modify: `Tests/EnvCoreTests/VaultSecretStoreTests.swift`

**Interfaces:**
- Consumes: `VaultSecretStore`, `FakeKeychainBackend` (Task 1–2)
- Produces: `VaultSecretStore.open()` artık taşımayı da yapar. Hata: `SecretStoreError.migrationFailed(status:)`.

- [ ] **Step 1: Testleri ekle**

`VaultSecretStoreTests` içine ekle:

```swift
    // MARK: Migration (spec 3.4)

    @Test func movesLegacyItemsIntoTheVaultAndDeletesThem() throws {
        let backend = FakeKeychainBackend(items: ["p/t/e/A": Data("1".utf8), "p/t/e/B": Data("ğ".utf8)])
        let store = VaultSecretStore(backend: backend)
        try store.open()
        #expect(backend.accounts == ["vault"])
        #expect(try decode(backend.data("vault")) == ["p/t/e/A": "1", "p/t/e/B": "ğ"])
        #expect(try store.read(account: "p/t/e/B") == "ğ")
    }

    @Test func vaultValueWinsOverLegacyValue() throws {
        let backend = FakeKeychainBackend(items: [
            "vault": FakeKeychainBackend.vault(["p/t/e/A": "new"]),
            "p/t/e/A": Data("old".utf8),
        ])
        // A legacy item that the vault already holds is not read, so it causes no prompt.
        backend.failRead(of: "p/t/e/A", status: -128)
        let store = VaultSecretStore(backend: backend)
        #expect(try store.read(account: "p/t/e/A") == "new")
        #expect(backend.accounts == ["vault"])
        #expect(backend.writeCount == 0)
    }

    @Test func unreadableLegacyItemStopsTheMigrationAndChangesNothing() throws {
        let backend = FakeKeychainBackend(items: [
            "vault": FakeKeychainBackend.vault(["x": "1"]),
            "p/t/e/A": Data("1".utf8),
            "p/t/e/B": Data("2".utf8),
        ])
        backend.failRead(of: "p/t/e/B", status: -128)
        let store = VaultSecretStore(backend: backend)
        #expect(throws: SecretStoreError.migrationFailed(status: -128)) { try store.open() }
        #expect(throws: SecretStoreError.migrationFailed(status: -128)) { try store.write("y", account: "x") }
        #expect(backend.writeCount == 0)
        #expect(backend.accounts == ["p/t/e/A", "p/t/e/B", "vault"])
    }

    @Test func failedVaultWriteKeepsTheLegacyItems() throws {
        let backend = FakeKeychainBackend(items: ["p/t/e/A": Data("1".utf8)])
        backend.failWrites = -25299
        let store = VaultSecretStore(backend: backend)
        #expect(throws: SecretStoreError.keychain(status: -25299)) { try store.open() }
        #expect(backend.accounts == ["p/t/e/A"])
    }

    @Test func failedDeleteDoesNotStopTheMigration() throws {
        let backend = FakeKeychainBackend(items: ["p/t/e/A": Data("1".utf8), "p/t/e/B": Data("2".utf8)])
        backend.failDelete(of: "p/t/e/A")
        let store = VaultSecretStore(backend: backend)
        try store.open()
        #expect(backend.accounts == ["p/t/e/A", "vault"])
        #expect(try store.read(account: "p/t/e/B") == "2")

        // The next launch deletes the item that was left.
        let next = FakeKeychainBackend(items: [
            "vault": try #require(backend.data("vault")),
            "p/t/e/A": Data("1".utf8),
        ])
        try VaultSecretStore(backend: next).open()
        #expect(next.accounts == ["vault"])
        #expect(next.writeCount == 0)
    }

    @Test func listFailureBlocksTheVault() throws {
        let backend = FakeKeychainBackend()
        backend.failList = -25293
        let store = VaultSecretStore(backend: backend)
        #expect(throws: SecretStoreError.keychain(status: -25293)) { try store.read(account: "a") }
        #expect(throws: SecretStoreError.keychain(status: -25293)) { try store.write("1", account: "a") }
        #expect(backend.writeCount == 0)
    }
```

- [ ] **Step 2: Testlerin başarısız olduğunu gör**

Run: `swift test --filter VaultSecretStoreTests`
Expected: FAIL. `movesLegacyItemsIntoTheVaultAndDeletesThem`, `unreadableLegacyItemStopsTheMigrationAndChangesNothing`, `failedVaultWriteKeepsTheLegacyItems`, `failedDeleteDoesNotStopTheMigration`, `listFailureBlocksTheVault` başarısız olur.

- [ ] **Step 3: `load()` fonksiyonunu değiştir**

`VaultSecretStore.swift` içinde `load()` şu hali alır:

```swift
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
```

`do/catch` yalnızca `SecretStoreError.keychain` yakalar. `readItem` başka bir hata fırlatırsa hata olduğu gibi çıkar. Swift bu `catch` bloğunu kabul eder, çünkü fonksiyon zaten `throws` olarak işaretli.

- [ ] **Step 4: Testleri çalıştır**

Run: `swift test --filter VaultSecretStoreTests`
Expected: PASS, 15 test.

- [ ] **Step 5: Commit**

```bash
git add Sources/EnvCore/Secrets/VaultSecretStore.swift Tests/EnvCoreTests/VaultSecretStoreTests.swift
git commit -m "feat(core): move per-key keychain items into the vault on first launch"
```

---

### Task 4: Kasayı uygulamaya bağla ve eski sınıfı sil

**Files:**
- Delete: `Sources/EnvCore/Secrets/KeychainSecretStore.swift`
- Modify: `Sources/EnvSwitcher/App/AppState.swift:57` (varsayılan değer), `:62-69` (init), `:341-342` (hata metinleri)
- Modify: `Tests/EnvCoreTests/SecretsTests.swift` (son test silinir)
- Modify: `Tests/EnvCoreTests/VaultKeychainTests.swift`

**Interfaces:**
- Consumes: `VaultSecretStore`, `SystemKeychainBackend` (Task 1–3)

- [ ] **Step 1: Gerçek Keychain kasa testini ekle**

`VaultKeychainTests` içine ekle:

```swift
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
```

Not: Bu test `EnvSwitcherTests` servisindeki tüm kayıtları eski kayıt sayar. Bu servis yalnızca testler içindir.

- [ ] **Step 2: Eski sınıfı ve testini sil**

```bash
git rm Sources/EnvCore/Secrets/KeychainSecretStore.swift
```

`Tests/EnvCoreTests/SecretsTests.swift` içinden `keychainStoreReadsWritesAndDeletes` testini ve üstündeki `///` yorumunu sil.

- [ ] **Step 3: `AppState` varsayılan değerini değiştir**

`Sources/EnvSwitcher/App/AppState.swift:57`:

```swift
        secrets: any SecretStore = VaultSecretStore(),
```

- [ ] **Step 4: Açılışta kasayı aç**

`AppState.init` içinde `load()` satırından hemen sonra ekle:

```swift
        openVault()
```

`// MARK: Store` bölümünde `load()` fonksiyonundan sonra ekle:

```swift
    /// Spec 2026-10-08, 3.4: opens the vault at launch, so a failed migration shows its alert at once.
    private func openVault() {
        guard let vault = secrets as? VaultSecretStore else { return }
        do {
            try vault.open()
        } catch {
            let text = message(for: error)
            DispatchQueue.main.async { Alerts.showError(text) }
        }
    }
```

- [ ] **Step 5: Hata metinlerini ekle**

`message(for:)` içinde `case SecretStoreError.keychain` satırından sonra ekle:

```swift
        case SecretStoreError.vaultCorrupt:
            return "Keychain'deki EnvSwitcher kaydı bozuk. Gizli değerler okunamıyor. Uygulama bu kaydı değiştirmedi."
        case SecretStoreError.migrationFailed:
            return "Keychain'deki gizli değerler taşınamadı. Uygulamayı yeniden açın ve izin verin."
```

- [ ] **Step 6: Eski adın kaldığı yerleri bul**

Run: `grep -rn "KeychainSecretStore" Sources Tests`
Expected: çıktı yok. (`README.md` Görev 13'te değişir.)

- [ ] **Step 7: Testleri ve derlemeyi çalıştır**

Run: `swift test && ENVSWITCHER_KEYCHAIN_TESTS=1 swift test --filter VaultKeychainTests && swift build`
Expected: PASS ve derleme hatası yok.

- [ ] **Step 8: Elle kontrol (geliştirici makinesi)**

1. `security find-generic-password -s EnvSwitcher 2>&1 | head -3` ile eski kayıtları gör.
2. `scripts/bundle.sh && open build/EnvSwitcher.app`. Her eski kayıt için Keychain sorusu çıkabilir. "Her Zaman İzin Ver" seçin. Bu, bölüm 3.4 notundaki durumdur.
3. `security dump-keychain 2>/dev/null | grep -A1 '"svce"<blob>="EnvSwitcher"' | grep acct` ile yalnızca `vault` hesabının kaldığını kontrol et.
4. Menüden bir ortam geçişi yap. Gizli değerlerin dosyaya doğru yazıldığını kontrol et.

- [ ] **Step 9: Commit**

```bash
git add -A Sources/EnvCore/Secrets Sources/EnvSwitcher/App/AppState.swift Tests/EnvCoreTests/SecretsTests.swift Tests/EnvCoreTests/VaultKeychainTests.swift
git commit -m "feat(app): store secrets in the keychain vault and show migration errors"
```

---

### Task 5: Sürüm ayrıştırma ve zamanlama kuralı

**Files:**
- Create: `Sources/EnvCore/Update/SemanticVersion.swift`
- Create: `Sources/EnvCore/Update/UpdateSchedule.swift`
- Create: `Tests/EnvCoreTests/UpdateTests.swift`

**Interfaces:**
- Produces:
  - `public struct SemanticVersion: Comparable, Hashable, Sendable, Codable, CustomStringConvertible` — `init(major: Int, minor: Int, patch: Int)`, `init?(_ text: String)`, `description` → `"1.2.3"`
  - `public enum UpdateSchedule` — `static let interval: TimeInterval`, `static func isDue(lastCheck: Date?, now: Date) -> Bool`

- [ ] **Step 1: Testleri yaz**

`Tests/EnvCoreTests/UpdateTests.swift`:

```swift
import Foundation
import Testing
@testable import EnvCore

struct SemanticVersionTests {
    @Test(arguments: ["1.2.3", "v1.2.3"])
    func parses(text: String) {
        #expect(SemanticVersion(text) == SemanticVersion(major: 1, minor: 2, patch: 3))
    }

    @Test(arguments: ["", "1.2", "1.2.3.4", "0.0.0-dev", "1..3", "a.b.c", "+1.2.3", "1.2.3 ", "V1.2.3", "1.2.٣"])
    func rejects(text: String) {
        #expect(SemanticVersion(text) == nil)
    }

    @Test func compares() throws {
        let v = { (s: String) in SemanticVersion(s)! }
        #expect(v("0.2.0") < v("0.2.1"))
        #expect(v("0.2.9") < v("0.10.0"))
        #expect(v("0.99.99") < v("1.0.0"))
        #expect(!(v("1.0.0") < v("1.0.0")))
        #expect(v("v2.0.0").description == "2.0.0")
    }
}

struct UpdateScheduleTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func dueWithoutAnEarlierCheck() {
        #expect(UpdateSchedule.isDue(lastCheck: nil, now: now))
    }

    @Test func notDueAfter23Hours() {
        #expect(!UpdateSchedule.isDue(lastCheck: now.addingTimeInterval(-23 * 3600), now: now))
    }

    @Test func dueAfter25Hours() {
        #expect(UpdateSchedule.isDue(lastCheck: now.addingTimeInterval(-25 * 3600), now: now))
    }

    @Test func dueWhenClockMovedBack() {
        #expect(UpdateSchedule.isDue(lastCheck: now.addingTimeInterval(3600), now: now))
    }
}
```

- [ ] **Step 2: Testlerin derlenmediğini gör**

Run: `swift test --filter "SemanticVersionTests|UpdateScheduleTests"`
Expected: FAIL, "cannot find 'SemanticVersion' in scope".

- [ ] **Step 3: `SemanticVersion.swift` dosyasını yaz**

```swift
import Foundation

/// A release version in the form X.Y.Z (spec 2026-10-08, section 7.1).
public struct SemanticVersion: Comparable, Hashable, Sendable, Codable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Accepts "1.2.3" and "v1.2.3". Returns nil for anything else, such as the local build "0.0.0-dev".
    public init?(_ text: String) {
        var rest = Substring(text)
        if rest.first == "v" { rest = rest.dropFirst() }
        let parts = rest.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(part) else {
                return nil
            }
            numbers.append(number)
        }
        self.init(major: numbers[0], minor: numbers[1], patch: numbers[2])
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
```

- [ ] **Step 4: `UpdateSchedule.swift` dosyasını yaz**

```swift
import Foundation

/// The app checks for a new release at most once a day (spec 2026-10-08, section 7.1).
public enum UpdateSchedule {
    public static let interval: TimeInterval = 24 * 60 * 60

    /// A last check in the future means the clock moved back. The check then runs, so it never stops.
    public static func isDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        return lastCheck > now || now.timeIntervalSince(lastCheck) >= interval
    }
}
```

- [ ] **Step 5: Testleri çalıştır**

Run: `swift test --filter "SemanticVersionTests|UpdateScheduleTests"`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/EnvCore/Update Tests/EnvCoreTests/UpdateTests.swift
git commit -m "feat(core): parse release versions and decide when to check for updates"
```

---

### Task 6: GitHub güncelleme kontrolü

**Files:**
- Create: `Sources/EnvCore/Update/UpdateChecker.swift`
- Modify: `Tests/EnvCoreTests/UpdateTests.swift`

**Interfaces:**
- Consumes: `SemanticVersion` (Task 5)
- Produces:
  - `public enum ReleaseInfo` — `static let repository: String`, `static let latestReleaseAPI: URL`, `static let installCommand: String`
  - `public protocol HTTPClient: Sendable` — `func get(_ url: URL) async throws -> (Data, Int)`
  - `public struct URLSessionHTTPClient: HTTPClient` — `init()`
  - `public struct AvailableUpdate: Equatable, Sendable, Codable` — `version: SemanticVersion`, `url: URL`
  - `public enum UpdateResult: Equatable, Sendable` — `.upToDate`, `.available(AvailableUpdate)`
  - `public enum UpdateError: Error, Equatable` — `.badStatus(Int)`, `.invalidResponse`
  - `public struct UpdateChecker: Sendable` — `init(client: any HTTPClient = URLSessionHTTPClient(), url: URL = ReleaseInfo.latestReleaseAPI)`, `func check(current: SemanticVersion) async throws -> UpdateResult`
  - `public struct StoredUpdate: Codable, Equatable, Sendable` — `var lastCheck: Date?`, `var found: AvailableUpdate?`, `init(lastCheck: Date? = nil, found: AvailableUpdate? = nil)`, `func available(current: SemanticVersion) -> AvailableUpdate?`

- [ ] **Step 1: Testleri ekle**

`UpdateTests.swift` sonuna ekle:

```swift
private struct StubHTTPClient: HTTPClient {
    let body: String
    var status = 200
    func get(_ url: URL) async throws -> (Data, Int) { (Data(body.utf8), status) }
}

private struct FailingHTTPClient: HTTPClient {
    func get(_ url: URL) async throws -> (Data, Int) { throw URLError(.notConnectedToInternet) }
}

struct UpdateCheckerTests {
    let current = SemanticVersion("0.2.0")!
    let page = "https://github.com/ahmetkorkmaz3/env-management/releases/tag/v0.3.0"

    private func body(tag: String) -> String {
        #"{"tag_name":"\#(tag)","html_url":"\#(page)","name":"x","assets":[]}"#
    }

    @Test func reportsANewerRelease() async throws {
        let checker = UpdateChecker(client: StubHTTPClient(body: body(tag: "v0.3.0")))
        let result = try await checker.check(current: current)
        #expect(result == .available(AvailableUpdate(version: SemanticVersion("0.3.0")!, url: URL(string: page)!)))
    }

    @Test(arguments: ["v0.2.0", "v0.1.9"])
    func reportsUpToDateForTheSameOrAnOlderRelease(tag: String) async throws {
        let checker = UpdateChecker(client: StubHTTPClient(body: body(tag: tag)))
        #expect(try await checker.check(current: current) == .upToDate)
    }

    @Test func rejectsABadStatus() async {
        let checker = UpdateChecker(client: StubHTTPClient(body: "{}", status: 404))
        await #expect(throws: UpdateError.badStatus(404)) { try await checker.check(current: current) }
    }

    @Test(arguments: ["not json", #"{"html_url":"https://x"}"#, #"{"tag_name":"latest","html_url":"https://x"}"#])
    func rejectsAnInvalidBody(body: String) async {
        let checker = UpdateChecker(client: StubHTTPClient(body: body))
        await #expect(throws: UpdateError.invalidResponse) { try await checker.check(current: current) }
    }

    @Test func passesNetworkErrorsThrough() async {
        let checker = UpdateChecker(client: FailingHTTPClient())
        await #expect(throws: URLError.self) { try await checker.check(current: current) }
    }
}

struct StoredUpdateTests {
    let found = AvailableUpdate(version: SemanticVersion("0.3.0")!, url: URL(string: "https://example.com")!)

    @Test func showsAStoredNewerVersion() {
        #expect(StoredUpdate(found: found).available(current: SemanticVersion("0.2.0")!) == found)
    }

    @Test func hidesTheStoredVersionAfterTheUserInstallsIt() {
        #expect(StoredUpdate(found: found).available(current: SemanticVersion("0.3.0")!) == nil)
        #expect(StoredUpdate(found: found).available(current: SemanticVersion("0.4.0")!) == nil)
    }

    @Test func roundTripsThroughJSON() throws {
        let stored = StoredUpdate(lastCheck: Date(timeIntervalSince1970: 1_800_000_000), found: found)
        let data = try JSONEncoder().encode(stored)
        #expect(try JSONDecoder().decode(StoredUpdate.self, from: data) == stored)
    }
}
```

- [ ] **Step 2: Testlerin derlenmediğini gör**

Run: `swift test --filter "UpdateCheckerTests|StoredUpdateTests"`
Expected: FAIL, "cannot find type 'HTTPClient' in scope".

- [ ] **Step 3: `UpdateChecker.swift` dosyasını yaz**

```swift
import Foundation

/// Where releases live. install.sh uses the same repository and command.
public enum ReleaseInfo {
    public static let repository = "ahmetkorkmaz3/env-management"
    public static let latestReleaseAPI = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    public static let installCommand = "curl -fsSL https://raw.githubusercontent.com/\(repository)/main/install.sh | sh"
}

public protocol HTTPClient: Sendable {
    /// Returns the body and the HTTP status code.
    func get(_ url: URL) async throws -> (Data, Int)
}

public struct URLSessionHTTPClient: HTTPClient {
    public init() {}

    public func get(_ url: URL) async throws -> (Data, Int) {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("EnvSwitcher", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

public struct AvailableUpdate: Equatable, Sendable, Codable {
    public let version: SemanticVersion
    /// The release page on GitHub.
    public let url: URL

    public init(version: SemanticVersion, url: URL) {
        self.version = version
        self.url = url
    }
}

public enum UpdateResult: Equatable, Sendable {
    case upToDate
    case available(AvailableUpdate)
}

public enum UpdateError: Error, Equatable {
    case badStatus(Int)
    case invalidResponse
}

/// Reads the latest GitHub release (spec 2026-10-08, section 7.1).
public struct UpdateChecker: Sendable {
    let client: any HTTPClient
    let url: URL

    public init(client: any HTTPClient = URLSessionHTTPClient(), url: URL = ReleaseInfo.latestReleaseAPI) {
        self.client = client
        self.url = url
    }

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    public func check(current: SemanticVersion) async throws -> UpdateResult {
        let (data, status) = try await client.get(url)
        guard status == 200 else { throw UpdateError.badStatus(status) }
        guard let release = try? JSONDecoder().decode(Release.self, from: data),
              let latest = SemanticVersion(release.tagName)
        else { throw UpdateError.invalidResponse }
        return latest > current ? .available(AvailableUpdate(version: latest, url: release.htmlURL)) : .upToDate
    }
}

/// The last check and the update it found. It lives in UserDefaults, so the menu still shows the update after a restart.
public struct StoredUpdate: Codable, Equatable, Sendable {
    public var lastCheck: Date?
    public var found: AvailableUpdate?

    public init(lastCheck: Date? = nil, found: AvailableUpdate? = nil) {
        self.lastCheck = lastCheck
        self.found = found
    }

    /// Returns the stored update only while it is newer than the running version.
    public func available(current: SemanticVersion) -> AvailableUpdate? {
        guard let found, found.version > current else { return nil }
        return found
    }
}
```

- [ ] **Step 4: Testleri çalıştır**

Run: `swift test --filter "UpdateCheckerTests|StoredUpdateTests"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/EnvCore/Update/UpdateChecker.swift Tests/EnvCoreTests/UpdateTests.swift
git commit -m "feat(core): check GitHub for a newer release"
```

---

### Task 7: Menüde güncelleme ve sürüm satırları

**Files:**
- Create: `Sources/EnvSwitcher/App/UpdateMonitor.swift`
- Modify: `Sources/EnvSwitcher/App/AppState.swift` (yeni özellik ve `init` içinde `start()`)
- Modify: `Sources/EnvSwitcher/MenuBar/MenuContent.swift:23-25`

**Interfaces:**
- Consumes: `SemanticVersion`, `UpdateSchedule`, `UpdateChecker`, `StoredUpdate`, `AvailableUpdate`, `ReleaseInfo` (Task 5–6), `Alerts.showInfo(title:message:)`
- Produces: `@MainActor @Observable final class UpdateMonitor` — `var available: AvailableUpdate?`, `let versionText: String`, `func start()`, `func installAvailableUpdate()`. `AppState.updates: UpdateMonitor`.

Bu görevde birim testi yoktur. Mantık Görev 5–6'da test edildi. Bu görev elle kontrol edilir.

- [ ] **Step 1: `UpdateMonitor.swift` dosyasını yaz**

```swift
import AppKit
import EnvCore
import Observation

/// Checks GitHub for a newer release once a day (spec 2026-10-08, section 7.2).
@MainActor
@Observable
final class UpdateMonitor {
    private(set) var available: AvailableUpdate?
    /// CFBundleShortVersionString, for the "Sürüm" menu line.
    let versionText: String

    @ObservationIgnored private let current: SemanticVersion?
    @ObservationIgnored private let checker: UpdateChecker
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var isChecking = false
    private static let defaultsKey = "storedUpdate"

    init(bundle: Bundle = .main, checker: UpdateChecker = UpdateChecker(), defaults: UserDefaults = .standard) {
        versionText = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0-dev"
        current = SemanticVersion(versionText)
        self.checker = checker
        self.defaults = defaults
        if let current {
            available = stored.available(current: current)
        }
    }

    /// A local build such as "0.0.0-dev" has no release version, so it never checks.
    func start() {
        guard current != nil, timer == nil else { return }
        checkIfDue()
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
    }

    func installAvailableUpdate() {
        guard let available else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ReleaseInfo.installCommand, forType: .string)
        NSWorkspace.shared.open(available.url)
        Alerts.showInfo(
            title: "EnvSwitcher \(available.version)",
            message: "Kurulum komutu panoya kopyalandı. Terminale yapıştırın."
        )
    }

    private var stored: StoredUpdate {
        get {
            guard let data = defaults.data(forKey: Self.defaultsKey) else { return StoredUpdate() }
            return (try? JSONDecoder().decode(StoredUpdate.self, from: data)) ?? StoredUpdate()
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Self.defaultsKey)
        }
    }

    private func checkIfDue() {
        guard let current, !isChecking, UpdateSchedule.isDue(lastCheck: stored.lastCheck, now: Date()) else { return }
        isChecking = true
        Task {
            defer { isChecking = false }
            // A network error or a bad response is ignored. The next hourly tick tries again.
            guard let result = try? await checker.check(current: current) else { return }
            var found: AvailableUpdate?
            if case .available(let update) = result { found = update }
            stored = StoredUpdate(lastCheck: Date(), found: found)
            available = found
        }
    }
}
```

- [ ] **Step 2: `AppState` içine ekle**

`AppState` özelliklerinin sonuna (`let files: any FileWriter` satırından sonra) ekle:

```swift
    let updates = UpdateMonitor()
```

`init` içinde `openVault()` satırından sonra ekle:

```swift
        updates.start()
```

- [ ] **Step 3: Menü satırlarını ekle**

`MenuContent.swift` içinde son `Divider()` ve "Çık" bölümü şu hali alır:

```swift
        Divider()
        if let update = state.updates.available {
            Button("Güncelleme var: \(update.version)") { state.updates.installAvailableUpdate() }
        }
        Button("Çık") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
        Text("Sürüm \(state.updates.versionText)")
```

`.menu` stilinde `Text` seçilemeyen gri bir satır olarak görünür.

- [ ] **Step 4: Derle**

Run: `swift build`
Expected: hata yok.

- [ ] **Step 5: Elle kontrol**

1. `scripts/bundle.sh && open build/EnvSwitcher.app`. Menünün altında "Sürüm 0.0.0-dev" görünür. "Güncelleme var" satırı görünmez.
2. Uygulamayı kapat. Sahte bir eski sürüm ile dene: `VERSION=0.0.1 scripts/bundle.sh && open build/EnvSwitcher.app`. Henüz release yoksa API `404` döner. Beklenen: menüde hata yok ve "Güncelleme var" satırı yok. (Release çıktıktan sonra bu adım "Güncelleme var" satırını gösterir. Bu kontrol `docs/manual-test.md` bölüm 9'da durur.)
3. `defaults read com.ahmetkorkmaz.envswitcher storedUpdate` çalıştır. 404 durumunda kayıt yoktur, çünkü son kontrol tarihi yalnızca başarılı bir yanıtta değişir.

- [ ] **Step 6: Commit**

```bash
git add Sources/EnvSwitcher/App/UpdateMonitor.swift Sources/EnvSwitcher/App/AppState.swift Sources/EnvSwitcher/MenuBar/MenuContent.swift
git commit -m "feat(app): show a new release and the app version in the menu"
```

---

### Task 8: Uygulama ikonu

**Files:**
- Create: `scripts/make-icon.swift`
- Create: `scripts/make-icon.sh`
- Create: `Resources/AppIcon.icns`

- [ ] **Step 1: `scripts/make-icon.swift` dosyasını yaz**

```swift
// Draws the 1024 px app icon PNG. Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let side = 1024
let output = URL(fileURLWithPath: CommandLine.arguments[1])

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("Could not create the bitmap.") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icon grid: an 824 px rounded square in a 1024 px canvas.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
let top = NSColor(srgbRed: 0.24, green: 0.60, blue: 0.98, alpha: 1)
let bottom = NSColor(srgbRed: 0.11, green: 0.32, blue: 0.80, alpha: 1)
NSGradient(starting: top, ending: bottom)!.draw(in: shape, angle: -90)

let config = NSImage.SymbolConfiguration(pointSize: 420, weight: .semibold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
if let symbol = NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let size = symbol.size
    symbol.draw(in: NSRect(x: (1024 - size.width) / 2, y: (1024 - size.height) / 2, width: size.width, height: size.height))
}

NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: output)
```

- [ ] **Step 2: `scripts/make-icon.sh` dosyasını yaz**

```sh
#!/bin/sh
# Builds Resources/AppIcon.icns from scripts/make-icon.swift (spec 2026-10-08, section 4.2).
set -eu
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

swift scripts/make-icon.swift "$WORK/icon-1024.png"
ICONSET="$WORK/AppIcon.iconset"
mkdir "$ICONSET"
for size in 16 32 128 256 512; do
    double=$((size * 2))
    sips -z "$size" "$size" "$WORK/icon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z "$double" "$double" "$WORK/icon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
mkdir -p Resources
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo Resources/AppIcon.icns
```

- [ ] **Step 3: İkonu üret ve kontrol et**

Run: `chmod +x scripts/make-icon.sh && scripts/make-icon.sh`
Expected: `Resources/AppIcon.icns` yazılır.

Run: `sips -s format png Resources/AppIcon.icns --out "$TMPDIR/icon-check.png" && open "$TMPDIR/icon-check.png"`
Expected: mavi yuvarlak kare üzerinde beyaz iki yönlü ok. Ok ortada durur ve kenarlara değmez.

- [ ] **Step 4: Commit**

```bash
git add scripts/make-icon.swift scripts/make-icon.sh Resources/AppIcon.icns
git commit -m "feat(app): add an app icon and the script that draws it"
```

---

### Task 9: `bundle.sh` — evrensel derleme, sürüm, ikon, imza

**Files:**
- Modify: `scripts/bundle.sh` (tamamı)

**Interfaces:**
- Consumes: `Resources/AppIcon.icns` (Task 8)
- Produces: `VERSION` ve `CODESIGN_IDENTITY` ortam değişkenleri. Çıktı: `build/EnvSwitcher.app`. Görev 11 ve 12 bu sözleşmeyi kullanır.

- [ ] **Step 1: `scripts/bundle.sh` dosyasını yeniden yaz**

```sh
#!/bin/sh
# Builds build/EnvSwitcher.app as a universal binary (spec 2026-10-08, section 4.1).
# VERSION sets the version (CI passes it from the tag). Without it, an exact v* tag gives the version,
# or the version is 0.0.0-dev. CODESIGN_IDENTITY names the certificate. Without it, the app gets an
# ad-hoc signature, and the Keychain asks for permission after every build.
set -eu
cd "$(dirname "$0")/.."

if [ -z "${VERSION:-}" ]; then
    TAG="$(git describe --tags --exact-match 2>/dev/null || true)"
    case "$TAG" in
        v[0-9]*) VERSION="${TAG#v}" ;;
        *) VERSION="0.0.0-dev" ;;
    esac
fi
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
IDENTITY="${CODESIGN_IDENTITY:--}"

swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
APP="build/EnvSwitcher.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/EnvSwitcher" "$APP/Contents/MacOS/EnvSwitcher"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.ahmetkorkmaz.envswitcher</string>
    <key>CFBundleName</key><string>EnvSwitcher</string>
    <key>CFBundleExecutable</key><string>EnvSwitcher</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Ahmet Korkmaz. MIT License.</string>
</dict>
</plist>
PLIST

if [ "$IDENTITY" = "-" ]; then
    echo "Uyarı: Ad-hoc imza. Keychain her derlemeden sonra izin sorar. Bkz. README → Derleme." >&2
fi
# Hardened runtime now, because notarization needs it later (spec section 9).
codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
echo "$APP ($VERSION)"
```

- [ ] **Step 2: Derle ve kontrol et**

Run: `scripts/bundle.sh`
Expected: son satır `build/EnvSwitcher.app (0.0.0-dev)`. Ad-hoc uyarısı stderr'de görünür.

Run: `lipo -archs build/EnvSwitcher.app/Contents/MacOS/EnvSwitcher`
Expected: `x86_64 arm64`

Run: `VERSION=1.2.3 scripts/bundle.sh >/dev/null && plutil -extract CFBundleShortVersionString raw build/EnvSwitcher.app/Contents/Info.plist`
Expected: `1.2.3`

Run: `codesign -dvv build/EnvSwitcher.app 2>&1 | grep -E "flags|Identifier"`
Expected: `flags=0x10002(adhoc,runtime)` ve `Identifier=com.ahmetkorkmaz.envswitcher`.

Run: `open build/EnvSwitcher.app`
Expected: uygulama açılır. Finder'da ikon görünür. Menü "Sürüm 1.2.3" gösterir.

- [ ] **Step 3: Commit**

```bash
git add scripts/bundle.sh
git commit -m "build: produce a universal, versioned app bundle with an icon and hardened runtime"
```

---

### Task 10: Kendinden imzalı sertifika betiği

**Files:**
- Create: `scripts/make-signing-cert.sh`

**Interfaces:**
- Produces: `EnvSwitcher Self-Signed` kimliği. Çıktı klasöründe: `EnvSwitcher-signing.p12`, `p12.base64`, `password.txt`, `cert.pem`. `ENVSWITCHER_KEYCHAIN` ortam değişkeni hedef Keychain'i değiştirir (yalnızca test için).

Bilinen davranış (2026-10-08 tarihinde bu makinede test edildi): Güvenilir olarak işaretlenmemiş kendinden imzalı bir sertifika `codesign` ile imza atar. Koşul: sertifikanın Keychain'i kullanıcı arama listesinde olmalı. DR değeri `identifier "…" and certificate leaf = H"…"` olur.

- [ ] **Step 1: Betiği yaz**

```sh
#!/bin/sh
# Creates the self-signed code signing certificate once (spec 2026-10-08, section 4.3).
# Usage: scripts/make-signing-cert.sh [output-folder]
# The certificate goes into the login keychain. ENVSWITCHER_KEYCHAIN names another keychain (tests only).
set -eu

NAME="EnvSwitcher Self-Signed"
OUT="${1:-$HOME/EnvSwitcher-signing}"
KEYCHAIN="${ENVSWITCHER_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
OPENSSL=/usr/bin/openssl

fail() { printf 'Hata: %s\n' "$1" >&2; exit 1; }

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    fail "\"$NAME\" sertifikası $KEYCHAIN içinde zaten var. Betik bu sertifikanın üzerine yazmaz. Var olan sertifikayı kullanın."
fi
[ -e "$OUT" ] && fail "$OUT zaten var. Başka bir klasör verin: scripts/make-signing-cert.sh <klasör>"

mkdir -m 700 "$OUT"
PASSWORD="$("$OPENSSL" rand -base64 24)"

cat > "$OUT/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$OUT/cert.cnf" \
    -keyout "$OUT/key.pem" -out "$OUT/cert.pem" 2>/dev/null
# 3DES and SHA-1: the macOS security tool cannot import the newer PKCS#12 formats.
"$OPENSSL" pkcs12 -export -inkey "$OUT/key.pem" -in "$OUT/cert.pem" -name "$NAME" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
    -passout "pass:$PASSWORD" -out "$OUT/EnvSwitcher-signing.p12"
rm "$OUT/key.pem" "$OUT/cert.cnf"

security import "$OUT/EnvSwitcher-signing.p12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign >/dev/null
base64 -i "$OUT/EnvSwitcher-signing.p12" > "$OUT/p12.base64"
printf '%s\n' "$PASSWORD" > "$OUT/password.txt"
chmod 600 "$OUT"/*

cat <<EOF
Sertifika oluşturuldu: $NAME
Dosyalar: $OUT

1. GitHub → repo → Settings → Secrets and variables → Actions sayfasını açın.
2. SIGNING_CERT_P12_BASE64 adında bir secret ekleyin. Değer: pbcopy < "$OUT/p12.base64"
3. SIGNING_CERT_PASSWORD adında bir secret ekleyin. Değer: pbcopy < "$OUT/password.txt"
4. EnvSwitcher-signing.p12 dosyasını ve şifreyi parola yöneticinize kaydedin.
5. Sonra $OUT klasörünü silin: rm -rf "$OUT"

Yerel derleme: CODESIGN_IDENTITY="$NAME" scripts/bundle.sh
EOF
```

- [ ] **Step 2: Geçici bir Keychain ile test et**

Bu test kullanıcının giriş Keychain'ini değiştirmez. **zsh değişkenleri kelimelere bölmez.** Arama listesini değiştiren komutları bu nedenle `bash` ile çalıştır.

```bash
bash -euc '
S="$TMPDIR/certtest"; rm -rf "$S"; mkdir -p "$S"
KC="$S/test.keychain-db"
security create-keychain -p pw "$KC"; security unlock-keychain -p pw "$KC"
OLD=$(security list-keychains -d user | tr -d "\"")
ENVSWITCHER_KEYCHAIN="$KC" scripts/make-signing-cert.sh "$S/out"
security set-key-partition-list -S apple-tool:,apple: -s -k pw "$KC" >/dev/null
security list-keychains -d user -s "$KC" $OLD
CODESIGN_IDENTITY="EnvSwitcher Self-Signed" scripts/bundle.sh || true
codesign -dr - build/EnvSwitcher.app 2>&1 | tail -1
ENVSWITCHER_KEYCHAIN="$KC" scripts/make-signing-cert.sh "$S/out2" || echo "SECOND_RUN_REFUSED"
security list-keychains -d user -s $OLD
security delete-keychain "$KC"
security list-keychains -d user
'
```

Expected:
- İlk çalıştırma "Sertifika oluşturuldu" yazar.
- DR satırı `certificate leaf = H"…"` içerir.
- İkinci çalıştırma "zaten var" hatası verir ve `SECOND_RUN_REFUSED` yazar.
- Son komut arama listesini testten önceki haliyle gösterir. Liste değişmiş ise testi durdur ve listeyi elle düzelt.

- [ ] **Step 3: shellcheck**

Run: `brew install shellcheck` (yoksa), sonra `shellcheck scripts/*.sh`
Expected: uyarı yok.

- [ ] **Step 4: Commit**

```bash
chmod +x scripts/make-signing-cert.sh
git add scripts/make-signing-cert.sh
git commit -m "build: add a script that creates the self-signed signing certificate"
```

---

### Task 11: Kurulum betiği

**Files:**
- Create: `install.sh`

**Interfaces:**
- Consumes: release dosya adları (Global Constraints). `ReleaseInfo.installCommand` aynı URL'yi kullanır.
- Produces: `ENVSWITCHER_VERSION` (kullanıcı için). `ENVSWITCHER_DOWNLOAD_BASE` ve `ENVSWITCHER_INSTALL_DIR` (yalnızca test için).

- [ ] **Step 1: `install.sh` dosyasını yaz**

```sh
#!/bin/sh
# Installs or updates EnvSwitcher from GitHub Releases (spec 2026-10-08, section 6).
#   curl -fsSL https://raw.githubusercontent.com/ahmetkorkmaz3/env-management/main/install.sh | sh
# ENVSWITCHER_VERSION=0.2.0 installs that version.
# ENVSWITCHER_DOWNLOAD_BASE and ENVSWITCHER_INSTALL_DIR are for tests only.
set -eu

REPO="ahmetkorkmaz3/env-management"
APP_NAME="EnvSwitcher"
DEST_DIR="${ENVSWITCHER_INSTALL_DIR:-/Applications}"

fail() { printf 'Hata: %s\n' "$1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "EnvSwitcher yalnızca macOS üzerinde çalışır."
MACOS="$(sw_vers -productVersion)"
[ "${MACOS%%.*}" -ge 14 ] || fail "EnvSwitcher macOS 14 veya üstünü ister. Bu Mac: macOS $MACOS."

if [ -n "${ENVSWITCHER_VERSION:-}" ]; then
    VERSION="${ENVSWITCHER_VERSION#v}"
else
    # The redirect of /releases/latest names the tag. It has no API rate limit.
    LATEST="https://github.com/$REPO/releases/latest"
    URL="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "$LATEST")" \
        || fail "Son sürüm okunamadı: $LATEST. İnternet bağlantısını kontrol edin ve komutu yeniden çalıştırın."
    case "$URL" in
        */tag/v*) VERSION="${URL##*/tag/v}" ;;
        *) fail "Henüz bir sürüm yayınlanmadı: $LATEST" ;;
    esac
fi
case "$VERSION" in
    "" | *[!0-9.]*) fail "Geçersiz sürüm: \"$VERSION\". Örnek: ENVSWITCHER_VERSION=0.2.0" ;;
esac

ZIP="$APP_NAME-$VERSION.zip"
BASE="${ENVSWITCHER_DOWNLOAD_BASE:-https://github.com/$REPO/releases/download/v$VERSION}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "EnvSwitcher $VERSION indiriliyor..."
for FILE in "$ZIP" "$ZIP.sha256"; do
    curl -fsSL -o "$WORK/$FILE" "$BASE/$FILE" \
        || fail "İndirme başarısız: $BASE/$FILE. İnternet bağlantısını kontrol edin ve komutu yeniden çalıştırın."
done
(cd "$WORK" && shasum -a 256 -c "$ZIP.sha256" >/dev/null 2>&1) \
    || fail "SHA-256 kontrolü başarısız. Dosya bozuk veya değişmiş. Hiçbir dosya değişmedi. Komutu yeniden çalıştırın."

ditto -x -k "$WORK/$ZIP" "$WORK/unpacked" || fail "Zip dosyası açılamadı: $ZIP."
[ -d "$WORK/unpacked/$APP_NAME.app" ] || fail "Zip dosyasında $APP_NAME.app yok."

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "Çalışan EnvSwitcher kapatılıyor..."
    osascript -e "quit app \"$APP_NAME\"" >/dev/null 2>&1 || true
    i=0
    while pgrep -x "$APP_NAME" >/dev/null 2>&1 && [ "$i" -lt 5 ]; do
        sleep 1
        i=$((i + 1))
    done
    pkill -x "$APP_NAME" 2>/dev/null || true
fi

TARGET="$DEST_DIR/$APP_NAME.app"
SUDO=""
if [ ! -w "$DEST_DIR" ] || { [ -e "$TARGET" ] && [ ! -w "$TARGET" ]; }; then
    echo "$DEST_DIR klasörüne yazma izni yok. Kurulum yönetici şifresi ister."
    SUDO="sudo"
fi
$SUDO rm -rf "$TARGET"
$SUDO ditto "$WORK/unpacked/$APP_NAME.app" "$TARGET"
# curl sets no quarantine flag. A copy from a browser download can still carry one.
$SUDO xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true

open "$TARGET"
echo "EnvSwitcher $VERSION kuruldu: $TARGET"
```

- [ ] **Step 2: Yerel sahte release ile test et**

```bash
bash -euc '
S="$TMPDIR/installtest"; rm -rf "$S"; mkdir -p "$S/release" "$S/apps"
VERSION=9.9.9 scripts/bundle.sh >/dev/null
ditto -c -k --keepParent build/EnvSwitcher.app "$S/release/EnvSwitcher-9.9.9.zip"
(cd "$S/release" && shasum -a 256 EnvSwitcher-9.9.9.zip > EnvSwitcher-9.9.9.zip.sha256)
ENVSWITCHER_VERSION=9.9.9 ENVSWITCHER_DOWNLOAD_BASE="file://$S/release" ENVSWITCHER_INSTALL_DIR="$S/apps" sh install.sh
plutil -extract CFBundleShortVersionString raw "$S/apps/EnvSwitcher.app/Contents/Info.plist"
'
```

Expected: "EnvSwitcher 9.9.9 kuruldu" ve `9.9.9`. Uygulama açılır.
Not: Betik çalışan EnvSwitcher uygulamasını kapatır. Bu adım geliştiricinin açık uygulamasını da kapatır.

- [ ] **Step 3: Hata durumlarını test et**

1. Hash bozuk: `echo "0000000000000000000000000000000000000000000000000000000000000000  EnvSwitcher-9.9.9.zip" > "$TMPDIR/installtest/release/EnvSwitcher-9.9.9.zip.sha256"`. Step 2 komutunu yeniden çalıştır. Beklenen: "SHA-256 kontrolü başarısız" ve `$TMPDIR/installtest/apps/EnvSwitcher.app` değişmez.
2. Geçersiz sürüm: `ENVSWITCHER_VERSION="1.0; rm" sh install.sh`. Beklenen: "Geçersiz sürüm" hatası.
3. Release yok: `sh install.sh` (henüz release yokken). Beklenen: "Henüz bir sürüm yayınlanmadı" hatası. Repo private iken `curl` 404 alır ve "Son sürüm okunamadı" hatası çıkar. Bu da kabul edilir.

- [ ] **Step 4: shellcheck ve commit**

Run: `shellcheck install.sh`
Expected: uyarı yok. `$SUDO` için SC2086 uyarısı çıkarsa, `$SUDO` satırlarının üstüne `# shellcheck disable=SC2086` ekle. Neden: `SUDO` boş olunca komut adı olarak hiç görünmemeli.

```bash
chmod +x install.sh
git add install.sh
git commit -m "feat: add an install script that downloads, verifies and installs the latest release"
```

---

### Task 12: CI ve release iş akışları

**Files:**
- Create: `scripts/changelog-section.sh`
- Create: `.github/workflows/ci.yml`
- Create: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: `scripts/bundle.sh` (`VERSION`, `CODESIGN_IDENTITY`), secret adları (Global Constraints)

- [ ] **Step 1: `scripts/changelog-section.sh` dosyasını yaz**

```sh
#!/bin/sh
# Prints the CHANGELOG.md section of one version. Fails when the section is missing or empty.
# Usage: scripts/changelog-section.sh 0.2.0 [CHANGELOG.md]
set -eu
VERSION="$1"
FILE="${2:-CHANGELOG.md}"

SECTION="$(awk -v v="$VERSION" '
    index($0, "## [" v "]") == 1 { found = 1; next }
    found && /^## \[/ { exit }
    found { print }
' "$FILE")"

if [ -z "$(printf '%s' "$SECTION" | tr -d '[:space:]')" ]; then
    echo "Hata: $FILE içinde \"## [$VERSION]\" bölümü yok veya boş." >&2
    exit 1
fi
printf '%s\n' "$SECTION"
```

- [ ] **Step 2: Betiği test et**

```bash
chmod +x scripts/changelog-section.sh
printf '# Changelog\n\n## [0.3.0] - 2026-11-01\n\n- C\n\n## [0.2.0] - 2026-10-08\n\n- A\n- B\n\n## [0.2.01]\n' > "$TMPDIR/cl.md"
scripts/changelog-section.sh 0.2.0 "$TMPDIR/cl.md"
scripts/changelog-section.sh 0.4.0 "$TMPDIR/cl.md"; echo "exit=$?"
```

Expected: ilk komut `- A` ve `- B` satırlarını yazar, `- C` yazmaz. İkinci komut hata verir ve `exit=1` yazar.

- [ ] **Step 3: `.github/workflows/ci.yml` dosyasını yaz**

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: Show the toolchain
        run: swift --version
      - name: Test
        run: swift test
      - name: Build the app bundle
        run: scripts/bundle.sh
      - name: Lint the shell scripts
        run: |
          brew install shellcheck
          shellcheck scripts/*.sh install.sh
```

- [ ] **Step 4: `.github/workflows/release.yml` dosyasını yaz**

```yaml
name: Release

on:
  push:
    tags: ["v*"]

permissions:
  contents: write

jobs:
  release:
    runs-on: macos-26
    env:
      KEYCHAIN: ${{ runner.temp }}/signing.keychain-db
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Read the version from the tag
        id: version
        run: |
          if ! printf '%s' "$GITHUB_REF_NAME" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
            echo "::error::Tag $GITHUB_REF_NAME is not in the form vX.Y.Z."
            exit 1
          fi
          echo "version=${GITHUB_REF_NAME#v}" >> "$GITHUB_OUTPUT"

      - name: Read the release notes from CHANGELOG.md
        run: scripts/changelog-section.sh "${{ steps.version.outputs.version }}" > "$RUNNER_TEMP/notes.md"

      - name: Test
        run: swift test

      - name: Import the signing certificate
        env:
          P12_BASE64: ${{ secrets.SIGNING_CERT_P12_BASE64 }}
          P12_PASSWORD: ${{ secrets.SIGNING_CERT_PASSWORD }}
        run: |
          if [ -z "$P12_BASE64" ] || [ -z "$P12_PASSWORD" ]; then
            echo "::error::SIGNING_CERT_P12_BASE64 or SIGNING_CERT_PASSWORD is missing. An ad-hoc release would make every user see Keychain prompts."
            exit 1
          fi
          KEYCHAIN_PASSWORD="$(openssl rand -base64 24)"
          printf '%s' "$P12_BASE64" | base64 --decode > "$RUNNER_TEMP/cert.p12"
          security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
          security set-keychain-settings -lut 3600 "$KEYCHAIN"
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
          security import "$RUNNER_TEMP/cert.p12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign
          security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" > /dev/null
          # codesign finds an untrusted self-signed identity only in a keychain on the search list.
          security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
          rm "$RUNNER_TEMP/cert.p12"

      - name: Build and sign
        env:
          VERSION: ${{ steps.version.outputs.version }}
          CODESIGN_IDENTITY: EnvSwitcher Self-Signed
        run: scripts/bundle.sh

      - name: Check the signature
        run: |
          codesign -dr - build/EnvSwitcher.app 2>&1 | tee "$RUNNER_TEMP/dr.txt"
          grep -q 'certificate leaf' "$RUNNER_TEMP/dr.txt"
          lipo -archs build/EnvSwitcher.app/Contents/MacOS/EnvSwitcher | grep -q 'x86_64 arm64'

      - name: Package
        run: |
          ZIP="EnvSwitcher-${{ steps.version.outputs.version }}.zip"
          ditto -c -k --keepParent build/EnvSwitcher.app "$ZIP"
          shasum -a 256 "$ZIP" > "$ZIP.sha256"

      - name: Publish the release
        env:
          GH_TOKEN: ${{ github.token }}
          VERSION: ${{ steps.version.outputs.version }}
        run: |
          gh release create "$GITHUB_REF_NAME" \
            --title "EnvSwitcher $VERSION" \
            --notes-file "$RUNNER_TEMP/notes.md" \
            "EnvSwitcher-$VERSION.zip" "EnvSwitcher-$VERSION.zip.sha256"

      - name: Delete the signing keychain
        if: always()
        run: security delete-keychain "$KEYCHAIN" || true
```

- [ ] **Step 5: YAML sözdizimini kontrol et**

Run: `ruby -ryaml -e 'ARGV.each { |f| YAML.load_file(f); puts "ok #{f}" }' .github/workflows/*.yml`
Expected: iki dosya için `ok`.

Run: `shellcheck scripts/*.sh install.sh`
Expected: uyarı yok.

- [ ] **Step 6: Commit**

```bash
git add scripts/changelog-section.sh .github/workflows/ci.yml .github/workflows/release.yml
git commit -m "ci: test every push and publish a signed release for each version tag"
```

- [ ] **Step 7: CI çalışmasını kontrol et**

Bu adım `main` dalına push ister. Push etmeden önce kullanıcıya sor. Kullanıcı izin verince:

Run: `git push origin main && sleep 20 && gh run watch --exit-status`
Expected: CI iş akışı başarılı. Başarısız olursa ve hata Swift sürümü ile ilgiliyse, `runs-on` değerini ve `swift --version` çıktısını kontrol et.

---

### Task 13: Dokümanlar

**Files:**
- Create: `LICENSE`, `CHANGELOG.md`, `docs/release.md`
- Modify: `README.md`, `docs/manual-test.md`, `docs/superpowers/specs/2026-10-07-env-switcher-design.md:67-69`

- [ ] **Step 1: `LICENSE` yaz**

```text
MIT License

Copyright (c) 2026 Ahmet Korkmaz

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 2: `CHANGELOG.md` yaz**

```markdown
# Değişiklikler

Bu dosya [Keep a Changelog](https://keepachangelog.com/tr-TR/1.1.0/) biçimini kullanır. Sürümler [Semantic Versioning](https://semver.org/lang/tr/) kurallarına uyar.

## [0.2.0] - 2026-10-08

İlk herkese açık sürüm.

### Eklenenler

- Menü çubuğundan bir projenin tüm `.env` dosyalarını veya tek bir dosyayı başka bir ortama geçirme.
- Proje ekleme: klasör tarama, `.gitignore` uyarısı, mevcut değerleri `local` ortamına aktarma.
- Düzenleme penceresi: değer düzenleme, `.env` önizleme, panodan `KEY=değer` yapıştırma.
- Karşılaştırma görünümü: bir dosyanın değerlerini ortamlar arasında yan yana görme, eksik anahtarları kopyalama.
- Güvenlik önlemleri: elle değişiklik kontrolü, boş ortam uyarısı, ya hep ya hiç yazma, korumalı ortam onayı.
- Gizli değerler macOS Keychain içinde tek bir kayıtta durur.
- Menüde yeni sürüm bildirimi ve sürüm satırı.
- Tek komutla kurulum ve güncelleme: `install.sh`.
- Apple Silicon ve Intel desteği.

### Değişenler

- 0.2.0'dan önceki derlemeler her gizli değeri ayrı bir Keychain kaydında tutar. Uygulama bu kayıtları ilk açılışta tek kayda taşır.
```

- [ ] **Step 3: `docs/release.md` yaz**

````markdown
# Sürüm çıkarma

## Bir kez: imza sertifikası

1. `scripts/make-signing-cert.sh` komutunu çalıştırın. Betik `~/EnvSwitcher-signing` klasörünü oluşturur.
2. Betiğin yazdığı adımları uygulayın: iki GitHub secret ekleyin ve `.p12` dosyasını parola yöneticisine kaydedin.
3. `~/EnvSwitcher-signing` klasörünü silin.

**Uyarı:** `.p12` dosyasını kaybederseniz yeni bir sertifika gerekir. Bu durumda her kullanıcı bir kez Keychain izin sorusu görür.

## Her sürüm

1. `CHANGELOG.md` dosyasının başına `## [X.Y.Z] - YYYY-MM-DD` bölümünü ekleyin.
2. Commit edin ve `main` dalına push edin.
3. Etiketi oluşturun ve push edin:

   ```sh
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

4. GitHub → Actions → Release iş akışının bitmesini bekleyin (yaklaşık 10 dk).
5. Kurulum komutunu deneyin:

   ```sh
   curl -fsSL https://raw.githubusercontent.com/ahmetkorkmaz3/env-management/main/install.sh | sh
   ```

6. `docs/manual-test.md` bölüm 9 adımlarını uygulayın.

İş akışı şu durumlarda durur: etiket `vX.Y.Z` biçiminde değil, CHANGELOG bölümü yok, testler başarısız, imza secret değerleri yok.

## İleride: Developer ID ve notarization

Apple Developer hesabı gelince şu adımları uygulayın:

1. Bir "Developer ID Application" sertifikası oluşturun. `.p12` dosyasını `SIGNING_CERT_P12_BASE64` ve `SIGNING_CERT_PASSWORD` secret değerlerine yazın.
2. `release.yml` içinde `CODESIGN_IDENTITY` değerini sertifika adı ile değiştirin.
3. `scripts/bundle.sh` içinde `--timestamp=none` yerine `--timestamp` kullanın.
4. Paketleme adımından sonra şu adımları ekleyin: `xcrun notarytool submit EnvSwitcher-X.Y.Z.zip --wait` ve `xcrun stapler staple build/EnvSwitcher.app`. Staple işleminden sonra zip dosyasını yeniden oluşturun.
5. Sürüm notlarına şu satırı ekleyin: "Bu sürümden sonra macOS bir kez Keychain izni sorar. Her Zaman İzin Ver seçin." Kasa tek bir kayıt olduğu için soru bir kez çıkar.
6. İsteğe bağlı: Data Protection Keychain. Bu geçiş `keychain-access-groups` yetkisi ve bir provisioning profile ister.
````

- [ ] **Step 4: `README.md` güncelle**

1. Başlık paragrafından sonra, "Hızlı başlangıç" bölümünden önce şu bölümü ekle:

````markdown
## Kurulum

Terminalde şu komutu çalıştırın:

```sh
curl -fsSL https://raw.githubusercontent.com/ahmetkorkmaz3/env-management/main/install.sh | sh
```

Komut son sürümü indirir, SHA-256 değerini kontrol eder, `/Applications` içine kurar ve uygulamayı açar. Gereksinim: macOS 14 veya üstü. Apple Silicon ve Intel desteklenir.

**Güncelleme:** Aynı komutu yeniden çalıştırın. Yeni bir sürüm çıkınca menüde "Güncelleme var" satırı görünür. Bu satır komutu panoya kopyalar.

**Belirli bir sürüm:** `curl -fsSL https://raw.githubusercontent.com/ahmetkorkmaz3/env-management/main/install.sh | ENVSWITCHER_VERSION=0.2.0 sh`

**Elle kurulum:**

1. [Releases](https://github.com/ahmetkorkmaz3/env-management/releases) sayfasından `EnvSwitcher-X.Y.Z.zip` dosyasını indirin.
2. Zip dosyasını açın. `EnvSwitcher.app` dosyasını `/Applications` içine taşıyın.
3. Uygulamayı açın. macOS "Apple doğrulayamadı" uyarısını gösterir. **Bitti** düğmesine basın.
4. Sistem Ayarları → Gizlilik ve Güvenlik sayfasını açın. Sayfanın altında **Yine de Aç** düğmesine basın.

Uygulama notarize edilmedi, bu nedenle tarayıcıdan indirilen dosyada bu uyarı çıkar. Kurulum komutu bu uyarıyı göstermez.

**Kaldırma:**

```sh
osascript -e 'quit app "EnvSwitcher"'
rm -rf /Applications/EnvSwitcher.app
rm -rf ~/Library/Application\ Support/EnvSwitcher
security delete-generic-password -s EnvSwitcher -a vault
defaults delete com.ahmetkorkmaz.envswitcher
```

Bu komutlar `.env` dosyalarınızı değiştirmez.
````

2. "Hızlı başlangıç" adım 1'i şu hale getir: `1. Uygulamayı kurun (bkz. [Kurulum](#kurulum)) ve açın. Menü çubuğunda `EnvSwitcher` yazısı görünür.`
3. "Veri konumu" tablosunda `Gizli değerler` satırı: `| Gizli değerler | Keychain, servis adı `EnvSwitcher`, hesap adı `vault` (tek kayıt) |`. Tabloya ekle: `| Güncelleme kontrolü | `defaults read com.ahmetkorkmaz.envswitcher storedUpdate` |`
4. "Derleme" bölümündeki `### Keychain izin sorusu` alt bölümünü şu metinle değiştir:

````markdown
### İmza ve Keychain izin sorusu

Keychain bir kaydı oluşturan uygulamayı imzası ile tanır. Ad-hoc imza her derlemede değişir. Bu nedenle ad-hoc bir derlemeden sonra macOS bir kez izin sorar. Tüm gizli değerler tek bir kayıtta durur, bu nedenle soru bir kez çıkar.

Bu soruyu önlemek için release sürümlerinin sertifikası ile imzalayın:

1. Sertifikayı bir kez oluşturun: `scripts/make-signing-cert.sh`. Sertifika zaten varsa ve `.p12` dosyası sizdeyse, dosyayı çift tıklayıp giriş Keychain'ine alın.
2. Derleyin: `CODESIGN_IDENTITY="EnvSwitcher Self-Signed" scripts/bundle.sh`

Sürüm çıkarma adımları: [`docs/release.md`](docs/release.md).
````

5. "Derleme ve çalıştırma" kod bloğundaki gerçek Keychain testi komutunu `ENVSWITCHER_KEYCHAIN_TESTS=1 swift test --filter VaultKeychainTests` yap.
6. "Proje yapısı" tablosuna ekle: `| `scripts/` | Derleme, ikon, sertifika ve CHANGELOG betikleri. |`, `| `install.sh` | Kurulum ve güncelleme betiği. |`, `| `.github/workflows/` | CI ve release iş akışları. |`, `| `docs/release.md` | Sürüm çıkarma adımları. |`
7. Dosyanın sonuna ekle: `## Lisans` ve altında `MIT. Bkz. [LICENSE](LICENSE).`

- [ ] **Step 5: `docs/manual-test.md` sonuna bölüm 9 ekle**

```markdown
## 9. Dağıtım (spec 2026-10-08, bölüm 10.3)

1. Eski Keychain kayıtları olan bir makinede yeni sürümü açın.
   - Beklenen: gizli değerler aynı kalır. `security dump-keychain | grep -A1 '"svce"<blob>="EnvSwitcher"' | grep acct` yalnızca `vault` gösterir.
2. Aynı sertifika ile iki farklı derleme yapın: `CODESIGN_IDENTITY="EnvSwitcher Self-Signed" scripts/bundle.sh`. Birini açın, kapatın, diğerini açın.
   - Beklenen: Keychain sorusu çıkmaz.
3. Temiz bir macOS kullanıcı hesabında kurulum komutunu çalıştırın.
   - Beklenen: uygulama Gatekeeper uyarısı olmadan açılır. Keychain sorusu çıkmaz.
4. Uygulama açıkken kurulum komutunu yeniden çalıştırın.
   - Beklenen: uygulama kapanır ve yeni sürümle açılır.
5. Eski bir sürüm kurun: `curl -fsSL …/install.sh | ENVSWITCHER_VERSION=<eski> sh`. `defaults delete com.ahmetkorkmaz.envswitcher storedUpdate` çalıştırın ve uygulamayı yeniden açın.
   - Beklenen: menüde "Güncelleme var: <son sürüm>" satırı çıkar. Satır seçilince release sayfası açılır ve komut panoya kopyalanır.
   - Uygulamayı yeniden açın. Beklenen: satır yine görünür.
```

- [ ] **Step 6: Ana spec bölüm 2.2'yi değiştir**

`docs/superpowers/specs/2026-10-07-env-switcher-design.md:67-69` şu hali alır:

```markdown
### 2.2 Keychain izinleri

Bu bölüm 2026-10-08 tarihinde değişti. Yeni düzen: tüm gizli değerler tek bir Keychain kaydında durur, sürümler aynı kendinden imzalı sertifika ile imzalanır. Ayrıntı: `2026-10-08-github-release-design.md`, bölüm 2–4.
```

Aynı dosyada bölüm 2'deki "Paket ad-hoc imzalanır." cümlesini şu hali ile değiştir: "Paket bir sertifika ile veya ad-hoc imzalanır (bölüm 2.2)."

- [ ] **Step 7: Dil denetimi**

Run: `python3 /Users/ahmetkorkmaz3/.agents/skills/asd-ste100/scripts/ste-lint.py --fail-over 2.5 README.md CHANGELOG.md docs/release.md docs/manual-test.md`
Expected: her dosya için `per100w` 2.5'ten küçük.

- [ ] **Step 8: Tüm testler ve commit**

Run: `swift test && shellcheck scripts/*.sh install.sh`
Expected: PASS ve uyarı yok.

```bash
git add LICENSE CHANGELOG.md README.md docs/release.md docs/manual-test.md docs/superpowers/specs/2026-10-07-env-switcher-design.md
git commit -m "docs: add install, release and license documents"
```

---

## Kullanıcının yapacağı adımlar (plan dışı)

Plan bittikten sonra Ahmet Korkmaz şu adımları yapar. Kod bu adımlar olmadan da derlenir ve test edilir.

1. `scripts/make-signing-cert.sh` çalıştırın ve iki GitHub secret ekleyin (5 dk).
2. Git geçmişinde gizli bilgi olmadığını kontrol edin, örnek: `git log -p | grep -iE "token|secret|password" | head` (10 dk). Sonra repoyu public yapın.
3. `git tag v0.2.0 && git push origin v0.2.0` (release yaklaşık 10 dk).
4. `docs/manual-test.md` bölüm 9 adımlarını uygulayın (20 dk).
