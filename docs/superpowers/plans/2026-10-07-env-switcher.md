# EnvSwitcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bir projedeki `.env` dosyalarını menü çubuğundan ortamlar arasında değiştiren bir macOS uygulaması yapmak.

**Architecture:** Kod iki modüle ayrılır. `EnvCore` (Swift library) depo, Keychain, `.env` okuma ve yazma, tarama, fark hesabı ve geçiş işlemini yapar. Bu modülde arayüz kodu yoktur ve tüm mantık burada test edilir. `EnvSwitcher` (SwiftUI executable) menü çubuğunu ve düzenleme penceresini gösterir ve yalnızca `EnvCore` çağırır.

**Tech Stack:** Swift 6, SwiftUI (`MenuBarExtra`, `Window`, `NavigationSplitView`, `Table`), Security framework (Keychain), CryptoKit (SHA-256), Swift Testing, Swift Package Manager. Üçüncü taraf bağımlılık yok.

**Spec:** `docs/superpowers/specs/2026-10-07-env-switcher-design.md`

## Global Constraints

- Platform: macOS 14 (Sonoma) ve üstü. `Package.swift` içinde `platforms: [.macOS(.v14)]`.
- `swift-tools-version:6.0`. `EnvCore` ve testler Swift 6 dil modunda derlenir. `EnvSwitcher` hedefi `.swiftLanguageMode(.v5)` kullanır.
- Üçüncü taraf paket yok. Yalnızca Apple framework'leri.
- App Sandbox yok. Uygulama paketi `LSUIElement=true` kullanır (Dock simgesi yok).
- Depo dosyası: `~/Library/Application Support/EnvSwitcher/store.json`, yedek: `store.json.bak`.
- Keychain servis adı: `EnvSwitcher`. Hesap adı: `<projeId>/<hedefId>/<ortamId>/<ANAHTAR>` (UUID string'leri).
- Gizli bir değer hiçbir zaman `store.json` dosyasına yazılmaz (`EnvEntry.value == nil`).
- Varsayılan ortamlar: `local` (yeşil), `test` (turuncu), `canli` (kırmızı, korumalı).
- Üretilen dosya başlığı tam olarak şu iki satırdır:
  - `# EnvSwitcher tarafından üretildi — proje: <proje>, ortam: <ortam>`
  - `# Bu dosyayı elle düzenlerseniz, ortam değişirken uygulama sorar.`
- Taramada atlanan klasör adları: `node_modules`, `vendor`, `.git`, `dist`, `build`, `.next`, `.turbo`, `.claude`. Kendi `.git` girdisi olan alt klasörler de atlanır.
- Arayüz metinleri Türkçedir. Kod, tanımlayıcılar ve kod yorumları İngilizcedir.
- Testler: `swift test` (Xcode aktif olmalı: `xcode-select -p` çıktısı `/Applications/Xcode.app/Contents/Developer`).

## Review Focus

1. **BOM ile başlayan `.env` dosyası.** Windows'ta kaydedilen bir dosyanın ilk anahtarı kaybolmamalı. Test: Task 2, `ignoresByteOrderMark`.
2. **İçinde `#` olan URL değeri** (`URL=https://a.com/#/b`). Değer yorum sanılıp kesilmemeli. Test: Task 2, `keepsHashWithoutLeadingWhitespace`.
3. **Boşluk içeren proje yolu** (`~/work/my app`). Tarama ve göreli yol hesabı bozulmamalı. Test: Task 7, `scanFindsEnvFilesAndSkipsVendorAndRepos` içindeki `my app/.env.staging`.
4. **Ortamın adı değişti.** Gizli değerler okunmaya devam etmeli, çünkü Keychain hesabı ad değil kimlik kullanır. Test: Task 12, `renamingEnvironmentKeepsSecretsReadable`.
5. **Bir dosyada aktif olan ortam silindi.** Dosyanın aktif ortamı boşalmalı, değerler ve Keychain kayıtları silinmeli. Test: Task 12, `deletingEnvironmentClearsActiveStateAndSecrets`.

## Spec'ten sapmalar

- Spec 7.1, proje alt menüsündeki "Finder'da Aç / Terminal'de Aç / Editörde Aç" için ⌘O / ⌘T / ⌘E kısayollarını gösterir. Her proje alt menüsü aynı kısayolu tekrar ederdi ve macOS yalnızca ilkini çalıştırırdı. Bu nedenle bu üç komutta kısayol yok.
- Spec 7.1'de "Yönet…" ⌘, kullanır. HIG kurallarına göre ⌘, ayarlar penceresinin kısayoludur. Bu nedenle "Yönet…" ⌘M, yeni "Ayarlar…" öğesi ⌘, kullanır (Task 20).
- Spec 7.1'deki sağa hizalı durum metni (`karışık ›`) yerine `proje — karışık` biçimi kullanılır. NSMenu tabanlı SwiftUI menüleri sağa hizalı ikinci bir metin desteklemez.

## Dosya Yapısı

```
Package.swift
Sources/EnvCore/
  Model/Models.swift                 Project, EnvEnvironment, EnvTarget, EnvEntry, Store, AppSettings
  Parsing/DotEnvParser.swift         .env metnini DotEnvPair listesine çevirir
  Parsing/DotEnvSerializer.swift     DotEnvPair listesini .env metnine çevirir
  Diff/ContentHash.swift             SHA-256
  Diff/DriftDetector.swift           missing / clean / modified / unmanaged
  Diff/EnvDiffer.swift               added / changed / removed
  Secrets/SecretStore.swift          protokol, SecretAccount, InMemorySecretStore, SecretStoreError
  Secrets/KeychainSecretStore.swift  Security framework
  Secrets/SecretSuggester.swift      gizli anahtar önerisi
  Storage/StoreRepository.swift      store.json + .bak + bozuk dosya
  Support/Timestamp.swift            yyyyMMdd-HHmmss (UTC)
  Scanning/ProjectScanner.swift      .env* tarama
  Scanning/GitIgnoreChecker.swift    git check-ignore
  Import/ProjectImporter.swift       taramadan Project oluşturur
  Switching/FileWriter.swift         protokol + LocalFileWriter
  Switching/ValueResolver.swift      ortam değerlerini (gizliler dahil) çözer
  Switching/SwitchPlanner.swift      geçiş adım 1–4
  Switching/SwitchExecutor.swift     geçiş adım 5 (atomik yazma + geri dönüş)
  Switching/SwitchService.swift      geçiş adım 4–6
  Switching/DriftResolver.swift      "Mevcut ortama kaydet"
  Editing/EntryEditor.swift          anahtar/değer düzenleme
  Editing/ProjectEditor.swift        ortam, hedef dosya, proje düzenleme
  Tree/FileTree.swift                kenar çubuğu ağacı
Sources/EnvSwitcher/
  App/EnvSwitcherApp.swift  App/AppState.swift  App/Alerts.swift  App/EnvColor+UI.swift
  App/FolderOpener.swift    App/Panels.swift
  MenuBar/MenuContent.swift MenuBar/ProjectMenu.swift
  Drift/DriftView.swift
  Window/ManagerWindow.swift Window/Sidebar.swift Window/ProjectSettingsView.swift Window/TargetDetailView.swift
  Sheets/AddProjectSheet.swift
  Settings/SettingsView.swift
Tests/EnvCoreTests/
  Support/TestSupport.swift Support/ProjectFixture.swift Support/FakeFileWriter.swift
  <Birim>Tests.swift (her EnvCore birimi için bir dosya)
scripts/bundle.sh
docs/manual-test.md
README.md
```

---

### Task 1: Paket iskeleti ve veri modeli

**Files:**
- Create: `Package.swift`
- Create: `Sources/EnvCore/Model/Models.swift`
- Test: `Tests/EnvCoreTests/ModelsTests.swift`

**Interfaces:**
- Consumes: yok
- Produces:
  - `enum EnvColor: String, Codable, CaseIterable, Sendable { green, orange, red, blue, purple, gray }`
  - `struct EnvEnvironment { id: UUID; name: String; color: EnvColor; isProtected: Bool; static func defaults() -> [EnvEnvironment] }`
  - `struct EnvEntry { key: String; value: String?; isSecret: Bool }`
  - `struct EnvTarget { id; relativePath; activeEnvironmentId: UUID?; lastWrittenHash: String?; values: [String: [EnvEntry]]; func entries(for: UUID) -> [EnvEntry]; mutating func setEntries(_:for:) }`
  - `enum ProjectDisplayState: Equatable { none, single(UUID), mixed }`
  - `struct Project { id; name; rootPath: String; environments; targets; rootURL: URL; func url(for: EnvTarget) -> URL; func environment(id:) -> EnvEnvironment?; func targetIndex(id:) -> Int?; displayState }`
  - `struct AppSettings { editorAppPath: String?; terminalAppPath: String? }`
  - `struct Store { version: Int; projects: [Project]; settings: AppSettings; lastSwitchedProjectId: UUID?; static let currentVersion = 1; func projectIndex(id:) -> Int? }`

- [ ] **Step 1: Paket dosyasını yaz**

`Package.swift`:

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "EnvSwitcher",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EnvCore", targets: ["EnvCore"]),
    ],
    targets: [
        .target(name: "EnvCore"),
        .testTarget(name: "EnvCoreTests", dependencies: ["EnvCore"]),
    ]
)
```

- [ ] **Step 2: Başarısız testi yaz**

`Tests/EnvCoreTests/ModelsTests.swift`:

```swift
import Foundation
import Testing
@testable import EnvCore

struct ModelsTests {
    private let envs = EnvEnvironment.defaults()

    private func project(_ targets: [EnvTarget]) -> Project {
        Project(name: "p", rootPath: "/tmp/p", environments: envs, targets: targets)
    }

    @Test func defaultsMarkOnlyCanliAsProtected() {
        #expect(envs.map(\.name) == ["local", "test", "canli"])
        #expect(envs.map(\.isProtected) == [false, false, true])
        #expect(envs.map(\.color) == [.green, .orange, .red])
    }

    @Test func displayStateIsNoneWithoutActiveEnvironments() {
        #expect(project([EnvTarget(relativePath: ".env")]).displayState == .none)
    }

    @Test func displayStateIsSingleWhenAllTargetsMatch() {
        let p = project([
            EnvTarget(relativePath: "a/.env", activeEnvironmentId: envs[1].id),
            EnvTarget(relativePath: "b/.env", activeEnvironmentId: envs[1].id),
        ])
        #expect(p.displayState == .single(envs[1].id))
    }

    @Test func displayStateIsMixedWhenTargetsDiffer() {
        let p = project([
            EnvTarget(relativePath: "a/.env", activeEnvironmentId: envs[0].id),
            EnvTarget(relativePath: "b/.env", activeEnvironmentId: envs[2].id),
        ])
        #expect(p.displayState == .mixed)
    }

    @Test func displayStateIsMixedWhenOneTargetHasNoEnvironment() {
        let p = project([
            EnvTarget(relativePath: "a/.env", activeEnvironmentId: envs[0].id),
            EnvTarget(relativePath: "b/.env"),
        ])
        #expect(p.displayState == .mixed)
    }

    @Test func targetEntriesAreStoredPerEnvironment() {
        var target = EnvTarget(relativePath: ".env")
        target.setEntries([EnvEntry(key: "A", value: "1")], for: envs[0].id)
        #expect(target.entries(for: envs[0].id) == [EnvEntry(key: "A", value: "1")])
        #expect(target.entries(for: envs[1].id).isEmpty)
    }

    @Test func projectBuildsTargetURLFromRoot() {
        let target = EnvTarget(relativePath: "apps/cart/.env.local")
        #expect(project([target]).url(for: target).path == "/tmp/p/apps/cart/.env.local")
    }

    @Test func storeRoundTripsThroughJSON() throws {
        var target = EnvTarget(relativePath: ".env", activeEnvironmentId: envs[0].id, lastWrittenHash: "abc")
        target.setEntries([EnvEntry(key: "A", value: "1"), EnvEntry(key: "S", value: nil, isSecret: true)], for: envs[0].id)
        let store = Store(projects: [project([target])], settings: AppSettings(editorAppPath: "/Applications/Zed.app"))
        let data = try JSONEncoder().encode(store)
        #expect(try JSONDecoder().decode(Store.self, from: data) == store)
        #expect(store.version == 1)
    }
}
```

- [ ] **Step 3: Testin başarısız olduğunu gör**

Run: `swift test --filter ModelsTests`
Expected: FAIL, derleme hatası: `cannot find 'EnvEnvironment' in scope`.

- [ ] **Step 4: Modeli yaz**

`Sources/EnvCore/Model/Models.swift`:

```swift
import Foundation

public enum EnvColor: String, Codable, CaseIterable, Sendable {
    case green, orange, red, blue, purple, gray
}

public struct EnvEnvironment: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var color: EnvColor
    public var isProtected: Bool

    public init(id: UUID = UUID(), name: String, color: EnvColor, isProtected: Bool = false) {
        self.id = id
        self.name = name
        self.color = color
        self.isProtected = isProtected
    }

    public static func defaults() -> [EnvEnvironment] {
        [
            EnvEnvironment(name: "local", color: .green),
            EnvEnvironment(name: "test", color: .orange),
            EnvEnvironment(name: "canli", color: .red, isProtected: true),
        ]
    }
}

public struct EnvEntry: Codable, Equatable, Sendable {
    public var key: String
    /// Always nil when `isSecret` is true. The value then lives in the SecretStore.
    public var value: String?
    public var isSecret: Bool

    public init(key: String, value: String?, isSecret: Bool = false) {
        self.key = key
        self.value = value
        self.isSecret = isSecret
    }
}

public struct EnvTarget: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var relativePath: String
    public var activeEnvironmentId: UUID?
    public var lastWrittenHash: String?
    /// Keyed by environment id (`uuidString`). List order is the order in the written file.
    public var values: [String: [EnvEntry]]

    public init(
        id: UUID = UUID(),
        relativePath: String,
        activeEnvironmentId: UUID? = nil,
        lastWrittenHash: String? = nil,
        values: [String: [EnvEntry]] = [:]
    ) {
        self.id = id
        self.relativePath = relativePath
        self.activeEnvironmentId = activeEnvironmentId
        self.lastWrittenHash = lastWrittenHash
        self.values = values
    }

    public func entries(for environmentId: UUID) -> [EnvEntry] {
        values[environmentId.uuidString] ?? []
    }

    public mutating func setEntries(_ entries: [EnvEntry], for environmentId: UUID) {
        values[environmentId.uuidString] = entries
    }
}

public enum ProjectDisplayState: Equatable, Sendable {
    case none
    case single(UUID)
    case mixed
}

public struct Project: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var rootPath: String
    public var environments: [EnvEnvironment]
    public var targets: [EnvTarget]

    public init(
        id: UUID = UUID(),
        name: String,
        rootPath: String,
        environments: [EnvEnvironment],
        targets: [EnvTarget]
    ) {
        self.id = id
        self.name = name
        self.rootPath = rootPath
        self.environments = environments
        self.targets = targets
    }

    public var rootURL: URL { URL(fileURLWithPath: rootPath, isDirectory: true) }

    public func url(for target: EnvTarget) -> URL {
        rootURL.appendingPathComponent(target.relativePath)
    }

    public func environment(id: UUID) -> EnvEnvironment? {
        environments.first { $0.id == id }
    }

    public func targetIndex(id: UUID) -> Int? {
        targets.firstIndex { $0.id == id }
    }

    public var displayState: ProjectDisplayState {
        let ids = Set(targets.compactMap(\.activeEnvironmentId))
        guard let first = ids.first else { return .none }
        if ids.count == 1, targets.allSatisfy({ $0.activeEnvironmentId != nil }) {
            return .single(first)
        }
        return .mixed
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var editorAppPath: String?
    public var terminalAppPath: String?

    public init(editorAppPath: String? = nil, terminalAppPath: String? = nil) {
        self.editorAppPath = editorAppPath
        self.terminalAppPath = terminalAppPath
    }
}

public struct Store: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var projects: [Project]
    public var settings: AppSettings
    public var lastSwitchedProjectId: UUID?

    public init(
        version: Int = Store.currentVersion,
        projects: [Project] = [],
        settings: AppSettings = AppSettings(),
        lastSwitchedProjectId: UUID? = nil
    ) {
        self.version = version
        self.projects = projects
        self.settings = settings
        self.lastSwitchedProjectId = lastSwitchedProjectId
    }

    public func projectIndex(id: UUID) -> Int? {
        projects.firstIndex { $0.id == id }
    }
}
```

- [ ] **Step 5: Testin geçtiğini gör**

Run: `swift test --filter ModelsTests`
Expected: PASS, 8 test.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/EnvCore/Model Tests/EnvCoreTests/ModelsTests.swift
git commit -m "feat(core): add package skeleton and data model"
```

---

### Task 2: `.env` okuyucu (DotEnvParser)

**Files:**
- Create: `Sources/EnvCore/Parsing/DotEnvParser.swift`
- Test: `Tests/EnvCoreTests/DotEnvParserTests.swift`

**Interfaces:**
- Consumes: yok
- Produces:
  - `struct DotEnvPair: Equatable, Sendable { key: String; value: String }`
  - `enum DotEnvWarning: Equatable, Sendable { invalidLine(line: Int), unterminatedQuote(line: Int), duplicateKey(key: String, line: Int) }`
  - `struct ParsedDotEnv { pairs: [DotEnvPair]; warnings: [DotEnvWarning] }`
  - `enum DotEnvParser { static func parse(_ text: String) -> ParsedDotEnv; static func isValidKey(_ key: String) -> Bool }` (`isValidKey` internal, Task 12 kullanır)

- [ ] **Step 1: Başarısız testi yaz**

`Tests/EnvCoreTests/DotEnvParserTests.swift`:

```swift
import Testing
@testable import EnvCore

struct DotEnvParserTests {
    private func pairs(_ text: String) -> [DotEnvPair] { DotEnvParser.parse(text).pairs }
    private func pair(_ key: String, _ value: String) -> DotEnvPair { DotEnvPair(key: key, value: value) }

    @Test func readsSimplePairs() {
        #expect(pairs("A=1\nB=two\n") == [pair("A", "1"), pair("B", "two")])
    }

    @Test func readsExportPrefix() {
        #expect(pairs("export A=1") == [pair("A", "1")])
    }

    @Test func skipsCommentsAndBlankLines() {
        #expect(pairs("# comment\n\n   # indented\nA=1") == [pair("A", "1")])
    }

    @Test func keepsEqualsSignsInValue() {
        #expect(pairs("URL=a=b") == [pair("URL", "a=b")])
    }

    @Test func readsEmptyValue() {
        #expect(pairs("A=") == [pair("A", "")])
    }

    @Test func trimsSpacesAroundKeyAndValue() {
        #expect(pairs("  A =  1  ") == [pair("A", "1")])
    }

    @Test func stripsInlineCommentAfterWhitespace() {
        #expect(pairs("A=value # note") == [pair("A", "value")])
        #expect(pairs("A= # only comment") == [pair("A", "")])
    }

    @Test func keepsHashWithoutLeadingWhitespace() {
        #expect(pairs("URL=https://a.com/#/b") == [pair("URL", "https://a.com/#/b")])
        #expect(pairs("A=#abc") == [pair("A", "#abc")])
    }

    @Test func singleQuotedValueIsLiteral() {
        #expect(pairs(#"A='x\ny # z'"#) == [pair("A", #"x\ny # z"#)])
    }

    @Test func doubleQuotedValueResolvesEscapes() {
        #expect(pairs(#"A="line1\nline2 \"q\" \\ end""#) == [pair("A", "line1\nline2 \"q\" \\ end")])
    }

    @Test func doubleQuotedValueCanSpanLines() {
        #expect(pairs("A=\"first\nsecond\"\nB=2") == [pair("A", "first\nsecond"), pair("B", "2")])
    }

    @Test func reportsUnterminatedQuote() {
        let parsed = DotEnvParser.parse("A=\"open\nB=2")
        #expect(parsed.pairs.isEmpty)
        #expect(parsed.warnings == [.unterminatedQuote(line: 1)])
    }

    @Test func reportsInvalidLines() {
        let parsed = DotEnvParser.parse("not a pair\n1BAD=x\nGOOD=1")
        #expect(parsed.pairs == [pair("GOOD", "1")])
        #expect(parsed.warnings == [.invalidLine(line: 1), .invalidLine(line: 2)])
    }

    @Test func lastDuplicateWinsAndWarns() {
        let parsed = DotEnvParser.parse("A=1\nB=2\nA=3")
        #expect(parsed.pairs == [pair("A", "3"), pair("B", "2")])
        #expect(parsed.warnings == [.duplicateKey(key: "A", line: 3)])
    }

    @Test func handlesWindowsLineEndings() {
        #expect(pairs("A=1\r\nB=2\r\n") == [pair("A", "1"), pair("B", "2")])
    }

    @Test func ignoresByteOrderMark() {
        #expect(pairs("\u{FEFF}A=1\nB=2") == [pair("A", "1"), pair("B", "2")])
    }

    @Test func acceptsDotsAndDashesInKeys() {
        #expect(pairs("my.key-1=x") == [pair("my.key-1", "x")])
    }

    @Test func validatesKeys() {
        #expect(DotEnvParser.isValidKey("NEXT_PUBLIC_API"))
        #expect(DotEnvParser.isValidKey("_x"))
        #expect(!DotEnvParser.isValidKey("1A"))
        #expect(!DotEnvParser.isValidKey(""))
        #expect(!DotEnvParser.isValidKey("A B"))
        #expect(!DotEnvParser.isValidKey("ÇOK"))
    }
}
```

- [ ] **Step 2: Testin başarısız olduğunu gör**

Run: `swift test --filter DotEnvParserTests`
Expected: FAIL, `cannot find 'DotEnvParser' in scope`.

- [ ] **Step 3: Okuyucuyu yaz**

`Sources/EnvCore/Parsing/DotEnvParser.swift`:

```swift
import Foundation

public struct DotEnvPair: Equatable, Sendable {
    public var key: String
    public var value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

public enum DotEnvWarning: Equatable, Sendable {
    case invalidLine(line: Int)
    case unterminatedQuote(line: Int)
    case duplicateKey(key: String, line: Int)
}

public struct ParsedDotEnv: Equatable, Sendable {
    public var pairs: [DotEnvPair]
    public var warnings: [DotEnvWarning]
}

public enum DotEnvParser {
    public static func parse(_ text: String) -> ParsedDotEnv {
        var text = text.replacingOccurrences(of: "\r\n", with: "\n")
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let lines = text.components(separatedBy: "\n")

        var pairs: [DotEnvPair] = []
        var indexByKey: [String: Int] = [:]
        var warnings: [DotEnvWarning] = []
        var i = 0

        while i < lines.count {
            let lineNumber = i + 1
            var line = Substring(lines[i]).drop(while: isBlank)
            i += 1

            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") {
                line = line.dropFirst("export ".count).drop(while: isBlank)
            }
            guard let eq = line.firstIndex(of: "=") else {
                warnings.append(.invalidLine(line: lineNumber))
                continue
            }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            guard isValidKey(key) else {
                warnings.append(.invalidLine(line: lineNumber))
                continue
            }

            let rawRest = line[line.index(after: eq)...]
            let rest = rawRest.drop(while: isBlank)
            let value: String
            if let quote = rest.first, quote == "\"" || quote == "'" {
                var body = String(rest.dropFirst())
                var closed = closeQuoted(body, quote: quote)
                while closed == nil, i < lines.count {
                    body += "\n" + lines[i]
                    i += 1
                    closed = closeQuoted(body, quote: quote)
                }
                guard let closedValue = closed else {
                    warnings.append(.unterminatedQuote(line: lineNumber))
                    continue
                }
                value = closedValue
            } else {
                value = stripInlineComment(String(rawRest))
            }

            if let existing = indexByKey[key] {
                pairs[existing].value = value
                warnings.append(.duplicateKey(key: key, line: lineNumber))
            } else {
                indexByKey[key] = pairs.count
                pairs.append(DotEnvPair(key: key, value: value))
            }
        }
        return ParsedDotEnv(pairs: pairs, warnings: warnings)
    }

    static func isValidKey(_ key: String) -> Bool {
        guard let first = key.first, first == "_" || (first.isASCII && first.isLetter) else { return false }
        return key.allSatisfy { c in
            c == "_" || c == "." || c == "-" || (c.isASCII && (c.isLetter || c.isNumber))
        }
    }

    private static func isBlank(_ c: Character) -> Bool { c == " " || c == "\t" }

    /// Returns the text before the closing quote, or nil when the quote does not close.
    private static func closeQuoted(_ body: String, quote: Character) -> String? {
        var result = ""
        var iterator = body.makeIterator()
        while let c = iterator.next() {
            if c == quote { return result }
            guard quote == "\"", c == "\\" else {
                result.append(c)
                continue
            }
            guard let next = iterator.next() else { return nil }
            switch next {
            case "n": result.append("\n")
            case "\"": result.append("\"")
            case "\\": result.append("\\")
            default:
                result.append(c)
                result.append(next)
            }
        }
        return nil
    }

    /// A `#` starts a comment only when a space or tab comes before it.
    private static func stripInlineComment(_ raw: String) -> String {
        var result = ""
        var previous: Character = "="
        for c in raw {
            if c == "#", isBlank(previous) { break }
            result.append(c)
            previous = c
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}
```

- [ ] **Step 4: Testin geçtiğini gör**

Run: `swift test --filter DotEnvParserTests`
Expected: PASS, 18 test.

- [ ] **Step 5: Commit**

```bash
git add Sources/EnvCore/Parsing/DotEnvParser.swift Tests/EnvCoreTests/DotEnvParserTests.swift
git commit -m "feat(core): add .env parser"
```

---

### Task 3: `.env` yazıcı (DotEnvSerializer)

**Files:**
- Create: `Sources/EnvCore/Parsing/DotEnvSerializer.swift`
- Test: `Tests/EnvCoreTests/DotEnvSerializerTests.swift`

**Interfaces:**
- Consumes: `DotEnvPair`, `DotEnvParser.parse` (Task 2)
- Produces: `enum DotEnvSerializer { static func serialize(_ pairs: [DotEnvPair], headerLines: [String] = []) -> String; static func encode(_ value: String) -> String }` (`encode` internal)

- [ ] **Step 1: Başarısız testi yaz**

`Tests/EnvCoreTests/DotEnvSerializerTests.swift`:

```swift
import Testing
@testable import EnvCore

struct DotEnvSerializerTests {
    @Test func writesPlainValuesWithoutQuotes() {
        let text = DotEnvSerializer.serialize([
            DotEnvPair(key: "A", value: "1"),
            DotEnvPair(key: "B", value: "https://x.com/a?b=c"),
        ])
        #expect(text == "A=1\nB=https://x.com/a?b=c\n")
    }

    @Test func writesHeaderAsComments() {
        let text = DotEnvSerializer.serialize([DotEnvPair(key: "A", value: "1")], headerLines: ["h1", "h2"])
        #expect(text == "# h1\n# h2\nA=1\n")
    }

    @Test func quotesValuesThatNeedIt() {
        #expect(DotEnvSerializer.encode("a b") == "\"a b\"")
        #expect(DotEnvSerializer.encode("x#y") == "\"x#y\"")
        #expect(DotEnvSerializer.encode("multi\nline") == "\"multi\\nline\"")
        #expect(DotEnvSerializer.encode(#"q"x"#) == #""q\"x""#)
        #expect(DotEnvSerializer.encode(#"c:\path"#) == #""c:\\path""#)
        #expect(DotEnvSerializer.encode("") == "")
    }

    @Test func roundTripsAwkwardValues() {
        let values = [
            "plain", "", "with space", " lead", "trail ", "a#b", "x #y", "q\"uote", "it's",
            "'single'", "back\\slash", "multi\nline", "url=a=b", "tab\there", "\\n literal",
        ]
        let pairs = values.enumerated().map { DotEnvPair(key: "K\($0.offset)", value: $0.element) }
        let text = DotEnvSerializer.serialize(pairs, headerLines: ["header"])
        #expect(DotEnvParser.parse(text).pairs == pairs)
    }
}
```

- [ ] **Step 2: Testin başarısız olduğunu gör**

Run: `swift test --filter DotEnvSerializerTests`
Expected: FAIL, `cannot find 'DotEnvSerializer' in scope`.

- [ ] **Step 3: Yazıcıyı yaz**

`Sources/EnvCore/Parsing/DotEnvSerializer.swift`:

```swift
import Foundation

public enum DotEnvSerializer {
    public static func serialize(_ pairs: [DotEnvPair], headerLines: [String] = []) -> String {
        let lines = headerLines.map { "# " + $0 } + pairs.map { "\($0.key)=\(encode($0.value))" }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Wraps the value in double quotes when the parser would otherwise change it.
    static func encode(_ value: String) -> String {
        let special: Set<Character> = [" ", "\t", "#", "\"", "'", "\n", "\\"]
        guard value.contains(where: special.contains) else { return value }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}
```

- [ ] **Step 4: Testin geçtiğini gör**

Run: `swift test --filter DotEnvSerializerTests`
Expected: PASS, 4 test.

- [ ] **Step 5: Commit**

```bash
git add Sources/EnvCore/Parsing/DotEnvSerializer.swift Tests/EnvCoreTests/DotEnvSerializerTests.swift
git commit -m "feat(core): add .env serializer"
```

---

### Task 4: Özet, elle değişiklik tespiti ve fark hesabı

**Files:**
- Create: `Sources/EnvCore/Diff/ContentHash.swift`
- Create: `Sources/EnvCore/Diff/DriftDetector.swift`
- Create: `Sources/EnvCore/Diff/EnvDiffer.swift`
- Test: `Tests/EnvCoreTests/DiffTests.swift`

**Interfaces:**
- Consumes: `DotEnvPair` (Task 2)
- Produces:
  - `enum ContentHash { static func sha256(_ data: Data) -> String }` (64 karakter, küçük harf hex)
  - `enum DriftStatus: Equatable, Sendable { missing, clean, modified, unmanaged }`
  - `enum DriftDetector { static func status(fileData: Data?, lastWrittenHash: String?) -> DriftStatus }`
  - `struct DotEnvChange: Equatable, Sendable { key: String; oldValue: String; newValue: String }`
  - `struct EnvDiff: Equatable, Sendable { added: [DotEnvPair]; changed: [DotEnvChange]; removed: [String]; isEmpty: Bool }`
  - `enum EnvDiffer { static func diff(old: [DotEnvPair], new: [DotEnvPair]) -> EnvDiff }`

- [ ] **Step 1: Başarısız testi yaz**

`Tests/EnvCoreTests/DiffTests.swift`:

```swift
import Foundation
import Testing
@testable import EnvCore

struct DiffTests {
    @Test func hashesKnownValue() {
        #expect(ContentHash.sha256(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test func driftIsMissingWithoutFile() {
        #expect(DriftDetector.status(fileData: nil, lastWrittenHash: "x") == .missing)
    }

    @Test func driftIsUnmanagedWithoutStoredHash() {
        #expect(DriftDetector.status(fileData: Data("A=1".utf8), lastWrittenHash: nil) == .unmanaged)
    }

    @Test func driftIsCleanWhenHashMatches() {
        let data = Data("A=1\n".utf8)
        #expect(DriftDetector.status(fileData: data, lastWrittenHash: ContentHash.sha256(data)) == .clean)
    }

    @Test func driftIsModifiedWhenHashDiffers() {
        let stored = ContentHash.sha256(Data("A=1\n".utf8))
        #expect(DriftDetector.status(fileData: Data("A=2\n".utf8), lastWrittenHash: stored) == .modified)
    }

    @Test func diffFindsAddedChangedAndRemovedKeys() {
        let old = [DotEnvPair(key: "A", value: "1"), DotEnvPair(key: "B", value: "2"), DotEnvPair(key: "C", value: "3")]
        let new = [DotEnvPair(key: "A", value: "1"), DotEnvPair(key: "B", value: "9"), DotEnvPair(key: "D", value: "4")]
        let diff = EnvDiffer.diff(old: old, new: new)
        #expect(diff.added == [DotEnvPair(key: "D", value: "4")])
        #expect(diff.changed == [DotEnvChange(key: "B", oldValue: "2", newValue: "9")])
        #expect(diff.removed == ["C"])
        #expect(!diff.isEmpty)
    }

    @Test func diffIsEmptyForSameValues() {
        let pairs = [DotEnvPair(key: "A", value: "1")]
        #expect(EnvDiffer.diff(old: pairs, new: pairs).isEmpty)
    }
}
```

- [ ] **Step 2: Testin başarısız olduğunu gör**

Run: `swift test --filter DiffTests`
Expected: FAIL, `cannot find 'ContentHash' in scope`.

- [ ] **Step 3: Kodu yaz**

`Sources/EnvCore/Diff/ContentHash.swift`:

```swift
import CryptoKit
import Foundation

public enum ContentHash {
    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
```

`Sources/EnvCore/Diff/DriftDetector.swift`:

```swift
import Foundation

public enum DriftStatus: Equatable, Sendable {
    /// The file does not exist on disk.
    case missing
    /// The file matches the last content the app wrote.
    case clean
    /// The file changed after the app wrote it.
    case modified
    /// The file exists, but the app has no record of writing it.
    case unmanaged
}

public enum DriftDetector {
    public static func status(fileData: Data?, lastWrittenHash: String?) -> DriftStatus {
        guard let fileData else { return .missing }
        guard let lastWrittenHash else { return .unmanaged }
        return ContentHash.sha256(fileData) == lastWrittenHash ? .clean : .modified
    }
}
```

`Sources/EnvCore/Diff/EnvDiffer.swift`:

```swift
import Foundation

public struct DotEnvChange: Equatable, Sendable {
    public var key: String
    public var oldValue: String
    public var newValue: String

    public init(key: String, oldValue: String, newValue: String) {
        self.key = key
        self.oldValue = oldValue
        self.newValue = newValue
    }
}

public struct EnvDiff: Equatable, Sendable {
    public var added: [DotEnvPair]
    public var changed: [DotEnvChange]
    public var removed: [String]

    public var isEmpty: Bool { added.isEmpty && changed.isEmpty && removed.isEmpty }
}

public enum EnvDiffer {
    public static func diff(old: [DotEnvPair], new: [DotEnvPair]) -> EnvDiff {
        let oldValues = Dictionary(old.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
        let newKeys = Set(new.map(\.key))
        let added = new.filter { oldValues[$0.key] == nil }
        let changed = new.compactMap { pair -> DotEnvChange? in
            guard let oldValue = oldValues[pair.key], oldValue != pair.value else { return nil }
            return DotEnvChange(key: pair.key, oldValue: oldValue, newValue: pair.value)
        }
        let removed = old.map(\.key).filter { !newKeys.contains($0) }
        return EnvDiff(added: added, changed: changed, removed: removed)
    }
}
```

- [ ] **Step 4: Testin geçtiğini gör**

Run: `swift test --filter DiffTests`
Expected: PASS, 7 test.

- [ ] **Step 5: Commit**

```bash
git add Sources/EnvCore/Diff Tests/EnvCoreTests/DiffTests.swift
git commit -m "feat(core): add content hash, drift detection and env diff"
```

---

### Task 5: Gizli değer deposu (SecretStore, Keychain, öneri)

**Files:**
- Create: `Sources/EnvCore/Secrets/SecretStore.swift`
- Create: `Sources/EnvCore/Secrets/KeychainSecretStore.swift`
- Create: `Sources/EnvCore/Secrets/SecretSuggester.swift`
- Test: `Tests/EnvCoreTests/SecretsTests.swift`

**Interfaces:**
- Consumes: yok
- Produces:
  - `protocol SecretStore: Sendable { func read(account: String) throws -> String?; func write(_ value: String, account: String) throws; func delete(account: String) throws }`
  - `enum SecretStoreError: Error, Equatable { keychain(status: Int32), simulatedFailure }`
  - `enum SecretAccount { static func make(projectId: UUID, targetId: UUID, environmentId: UUID, key: String) -> String }`
  - `final class InMemorySecretStore: SecretStore { init(values: [String: String] = [:]); var failReads: Bool; var snapshot: [String: String] }`
  - `struct KeychainSecretStore: SecretStore { init(service: String = "EnvSwitcher") }`
  - `enum SecretSuggester { static func isLikelySecret(_ key: String) -> Bool }`

- [ ] **Step 1: Başarısız testi yaz**

`Tests/EnvCoreTests/SecretsTests.swift`:

```swift
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
```

- [ ] **Step 2: Testin başarısız olduğunu gör**

Run: `swift test --filter SecretsTests`
Expected: FAIL, `cannot find 'SecretAccount' in scope`.

- [ ] **Step 3: Kodu yaz**

`Sources/EnvCore/Secrets/SecretStore.swift`:

```swift
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
```

`Sources/EnvCore/Secrets/KeychainSecretStore.swift`:

```swift
import Foundation
import Security

public struct KeychainSecretStore: SecretStore {
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

    public func read(account: String) throws -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw SecretStoreError.keychain(status: status)
        }
        return String(decoding: data, as: UTF8.self)
    }

    public func write(_ value: String, account: String) throws {
        let data = Data(value.utf8)
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

    public func delete(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.keychain(status: status)
        }
    }
}
```

`Sources/EnvCore/Secrets/SecretSuggester.swift`:

```swift
import Foundation

public enum SecretSuggester {
    /// `NEXT_PUBLIC_` values go to the browser, so they are never suggested as secrets.
    public static func isLikelySecret(_ key: String) -> Bool {
        let upper = key.uppercased()
        if upper.hasPrefix("NEXT_PUBLIC_") { return false }
        if upper.hasSuffix("_KEY") { return true }
        return ["SECRET", "PASSWORD", "TOKEN", "PRIVATE"].contains { upper.contains($0) }
    }
}
```

- [ ] **Step 4: Testin geçtiğini gör**

Run: `swift test --filter SecretsTests`
Expected: PASS, 12 test. Keychain testi "skipped" olarak görünür.

Run: `ENVSWITCHER_KEYCHAIN_TESTS=1 swift test --filter SecretsTests`
Expected: PASS, Keychain testi de çalışır. macOS bir izin sorusu gösterirse "İzin Ver" seçin.

- [ ] **Step 5: Commit**

```bash
git add Sources/EnvCore/Secrets Tests/EnvCoreTests/SecretsTests.swift
git commit -m "feat(core): add secret store with keychain backend and secret suggestion"
```

---

### Task 6: Depo dosyası (StoreRepository)

**Files:**
- Create: `Sources/EnvCore/Support/Timestamp.swift`
- Create: `Sources/EnvCore/Storage/StoreRepository.swift`
- Create: `Tests/EnvCoreTests/Support/TestSupport.swift`
- Test: `Tests/EnvCoreTests/StoreRepositoryTests.swift`

**Interfaces:**
- Consumes: `Store` (Task 1)
- Produces:
  - `enum Timestamp { static func string(_ date: Date) -> String }` (internal, biçim `yyyyMMdd-HHmmss`, UTC)
  - `enum StoreLoadNotice: Equatable, Sendable { restoredFromBackup, resetAfterCorruption(savedAs: URL) }`
  - `struct StoreLoadResult: Equatable, Sendable { store: Store; notice: StoreLoadNotice? }`
  - `struct StoreRepository: Sendable { init(directory: URL, now: @escaping @Sendable () -> Date = { Date() }); static var defaultDirectory: URL; directory: URL; storeURL: URL; backupURL: URL; func load() throws -> StoreLoadResult; func save(_ store: Store) throws }`
  - Test yardımcısı: `enum TempDir { static func make() throws -> URL; static func write(_ text: String, to relativePath: String, in root: URL) throws; static func read(_ relativePath: String, in root: URL) throws -> String }`

- [ ] **Step 1: Test yardımcısını yaz**

`Tests/EnvCoreTests/Support/TestSupport.swift`:

```swift
import Foundation

enum TempDir {
    /// Creates an empty folder. The path has symlinks resolved (/private/var/...).
    static func make() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("envswitcher-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.resolvingSymlinksInPath()
    }

    static func write(_ text: String, to relativePath: String, in root: URL) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    static func read(_ relativePath: String, in root: URL) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
```

- [ ] **Step 2: Başarısız testi yaz**

`Tests/EnvCoreTests/StoreRepositoryTests.swift`:

```swift
import Foundation
import Testing
@testable import EnvCore

struct StoreRepositoryTests {
    private let fixedDate = Date(timeIntervalSince1970: 1_791_400_000) // 2026-10-07 18:13:20 UTC

    private func sampleStore(name: String) -> Store {
        Store(projects: [Project(name: name, rootPath: "/tmp/x", environments: EnvEnvironment.defaults(), targets: [])])
    }

    @Test func loadReturnsEmptyStoreWhenFileIsMissing() throws {
        let repo = StoreRepository(directory: try TempDir.make())
        #expect(try repo.load() == StoreLoadResult(store: Store(), notice: nil))
    }

    @Test func saveThenLoadReturnsSameStore() throws {
        let repo = StoreRepository(directory: try TempDir.make().appendingPathComponent("nested"))
        let store = sampleStore(name: "karaca")
        try repo.save(store)
        #expect(try repo.load() == StoreLoadResult(store: store, notice: nil))
    }

    @Test func saveKeepsPreviousVersionAsBackup() throws {
        let repo = StoreRepository(directory: try TempDir.make())
        try repo.save(sampleStore(name: "first"))
        try repo.save(sampleStore(name: "second"))
        let backup = try JSONDecoder().decode(Store.self, from: Data(contentsOf: repo.backupURL))
        #expect(backup.projects.map(\.name) == ["first"])
    }

    @Test func loadUsesBackupWhenStoreIsCorrupt() throws {
        let repo = StoreRepository(directory: try TempDir.make())
        try repo.save(sampleStore(name: "first"))
        try repo.save(sampleStore(name: "second"))
        try Data("{ broken".utf8).write(to: repo.storeURL)
        let result = try repo.load()
        #expect(result.store.projects.map(\.name) == ["first"])
        #expect(result.notice == .restoredFromBackup)
    }

    @Test func loadResetsAndKeepsCorruptFileWhenBackupIsAlsoCorrupt() throws {
        let dir = try TempDir.make()
        let repo = StoreRepository(directory: dir, now: { [fixedDate] in fixedDate })
        try Data("{ broken".utf8).write(to: repo.storeURL)
        try Data("also broken".utf8).write(to: repo.backupURL)
        let result = try repo.load()
        let corrupt = dir.appendingPathComponent("store.json.corrupt-20261007-181320")
        #expect(result == StoreLoadResult(store: Store(), notice: .resetAfterCorruption(savedAs: corrupt)))
        #expect(FileManager.default.fileExists(atPath: corrupt.path))
        #expect(!FileManager.default.fileExists(atPath: repo.storeURL.path))
    }

    @Test func defaultDirectoryIsInApplicationSupport() {
        #expect(StoreRepository.defaultDirectory.path.hasSuffix("Library/Application Support/EnvSwitcher"))
    }
}
```

- [ ] **Step 3: Testin başarısız olduğunu gör**

Run: `swift test --filter StoreRepositoryTests`
Expected: FAIL, `cannot find 'StoreRepository' in scope`.

- [ ] **Step 4: Kodu yaz**

`Sources/EnvCore/Support/Timestamp.swift`:

```swift
import Foundation

enum Timestamp {
    static func string(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
```

`Sources/EnvCore/Storage/StoreRepository.swift`:

```swift
import Foundation

public enum StoreLoadNotice: Equatable, Sendable {
    case restoredFromBackup
    case resetAfterCorruption(savedAs: URL)
}

public struct StoreLoadResult: Equatable, Sendable {
    public var store: Store
    public var notice: StoreLoadNotice?

    public init(store: Store, notice: StoreLoadNotice?) {
        self.store = store
        self.notice = notice
    }
}

public struct StoreRepository: Sendable {
    public let directory: URL
    private let now: @Sendable () -> Date

    public init(directory: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.now = now
    }

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EnvSwitcher", isDirectory: true)
    }

    public var storeURL: URL { directory.appendingPathComponent("store.json") }
    public var backupURL: URL { directory.appendingPathComponent("store.json.bak") }

    public func load() throws -> StoreLoadResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: storeURL.path) else {
            return StoreLoadResult(store: Store(), notice: nil)
        }
        if let store = try? decode(storeURL) {
            return StoreLoadResult(store: store, notice: nil)
        }
        if let backup = try? decode(backupURL) {
            return StoreLoadResult(store: backup, notice: .restoredFromBackup)
        }
        let corrupt = directory.appendingPathComponent("store.json.corrupt-\(Timestamp.string(now()))")
        try fm.moveItem(at: storeURL, to: corrupt)
        return StoreLoadResult(store: Store(), notice: .resetAfterCorruption(savedAs: corrupt))
    }

    public func save(_ store: Store) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        if fm.fileExists(atPath: storeURL.path) {
            if fm.fileExists(atPath: backupURL.path) { try fm.removeItem(at: backupURL) }
            try fm.copyItem(at: storeURL, to: backupURL)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(store).write(to: storeURL, options: .atomic)
    }

    private func decode(_ url: URL) throws -> Store {
        try JSONDecoder().decode(Store.self, from: Data(contentsOf: url))
    }
}
```

- [ ] **Step 5: Testin geçtiğini gör**

Run: `swift test --filter StoreRepositoryTests`
Expected: PASS, 6 test.

- [ ] **Step 6: Commit**

```bash
git add Sources/EnvCore/Support Sources/EnvCore/Storage Tests/EnvCoreTests/Support/TestSupport.swift Tests/EnvCoreTests/StoreRepositoryTests.swift
git commit -m "feat(core): add store repository with backup and corruption recovery"
```

---

### Task 7: Proje tarama ve git ignore kontrolü

**Files:**
- Create: `Sources/EnvCore/Scanning/ProjectScanner.swift`
- Create: `Sources/EnvCore/Scanning/GitIgnoreChecker.swift`
- Test: `Tests/EnvCoreTests/ScanningTests.swift`

**Interfaces:**
- Consumes: `DotEnvParser.parse` (Task 2), `TempDir` (Task 6)
- Produces:
  - `struct ScannedFile: Equatable, Sendable { relativePath: String; keyCount: Int; isSelectedByDefault: Bool }`
  - `enum ProjectScanner { static let skippedDirectoryNames: Set<String>; static func scan(root: URL) -> [ScannedFile] }` (sonuç `relativePath` ile sıralı)
  - `enum GitIgnoreChecker { static func isIgnored(relativePath: String, root: URL) -> Bool? }` (`true` ignore ediliyor, `false` ignore edilmiyor, `nil` git deposu değil)

- [ ] **Step 1: Başarısız testi yaz**

`Tests/EnvCoreTests/ScanningTests.swift`:

```swift
import Foundation
import Testing
@testable import EnvCore

struct ScanningTests {
    @Test func scanFindsEnvFilesAndSkipsVendorAndRepos() throws {
        let root = try TempDir.make()
        try TempDir.write("A=1", to: ".env", in: root)
        try TempDir.write("A=1\nB=2", to: "apps/cart/.env.local", in: root)
        try TempDir.write("A=", to: "apps/cart/.env.example", in: root)
        try TempDir.write("# readme", to: "apps/cart/README.md", in: root)
        try TempDir.write("S=1", to: "my app/.env.staging", in: root)
        try TempDir.write("X=1", to: "node_modules/pkg/.env", in: root)
        try TempDir.write("X=1", to: "apps/cart/.next/.env", in: root)
        try TempDir.write("X=1", to: ".claude/worktrees/copy/apps/cart/.env.local", in: root)
        try TempDir.write("gitdir: /somewhere", to: "worktrees/feature/.git", in: root)
        try TempDir.write("X=1", to: "worktrees/feature/.env.local", in: root)
        try TempDir.write("[core]", to: "packages/nested/.git/config", in: root)
        try TempDir.write("X=1", to: "packages/nested/.env", in: root)

        #expect(ProjectScanner.scan(root: root) == [
            ScannedFile(relativePath: ".env", keyCount: 1, isSelectedByDefault: true),
            ScannedFile(relativePath: "apps/cart/.env.example", keyCount: 1, isSelectedByDefault: false),
            ScannedFile(relativePath: "apps/cart/.env.local", keyCount: 2, isSelectedByDefault: true),
            ScannedFile(relativePath: "my app/.env.staging", keyCount: 1, isSelectedByDefault: true),
        ])
    }

    @Test func scanMarksTemplatesAsNotSelected() throws {
        let root = try TempDir.make()
        try TempDir.write("A=", to: ".env.sample", in: root)
        try TempDir.write("A=", to: ".env.template", in: root)
        #expect(ProjectScanner.scan(root: root).map(\.isSelectedByDefault) == [false, false])
    }

    @Test func scanWorksWhenRootItselfIsAGitRepo() throws {
        let root = try TempDir.make()
        try TempDir.write("[core]", to: ".git/config", in: root)
        try TempDir.write("A=1", to: ".env", in: root)
        #expect(ProjectScanner.scan(root: root).map(\.relativePath) == [".env"])
    }

    @Test func gitIgnoreCheckerReportsIgnoredTrackedAndNonRepo() throws {
        let root = try TempDir.make()
        try runGit(["init", "-q"], in: root)
        try TempDir.write(".env.local\n", to: ".gitignore", in: root)
        try TempDir.write("A=1", to: "apps/cart/.env.local", in: root)
        try TempDir.write("A=1", to: ".env", in: root)
        #expect(GitIgnoreChecker.isIgnored(relativePath: "apps/cart/.env.local", root: root) == true)
        #expect(GitIgnoreChecker.isIgnored(relativePath: ".env", root: root) == false)
        #expect(GitIgnoreChecker.isIgnored(relativePath: ".env", root: try TempDir.make()) == nil)
    }

    private func runGit(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
    }
}
```

- [ ] **Step 2: Testin başarısız olduğunu gör**

Run: `swift test --filter ScanningTests`
Expected: FAIL, `cannot find 'ProjectScanner' in scope`.

- [ ] **Step 3: Kodu yaz**

`Sources/EnvCore/Scanning/ProjectScanner.swift`:

```swift
import Foundation

public struct ScannedFile: Equatable, Sendable {
    public var relativePath: String
    public var keyCount: Int
    public var isSelectedByDefault: Bool

    public init(relativePath: String, keyCount: Int, isSelectedByDefault: Bool) {
        self.relativePath = relativePath
        self.keyCount = keyCount
        self.isSelectedByDefault = isSelectedByDefault
    }
}

public enum ProjectScanner {
    public static let skippedDirectoryNames: Set<String> = [
        "node_modules", "vendor", ".git", "dist", "build", ".next", ".turbo", ".claude",
    ]
    static let templateSuffixes = [".example", ".sample", ".template"]

    public static func scan(root: URL) -> [ScannedFile] {
        let fm = FileManager.default
        let rootURL = root.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = rootURL.path
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]
        guard let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: keys) else { return [] }

        var results: [ScannedFile] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let name = url.lastPathComponent
            if values?.isDirectory == true {
                // A folder with its own .git entry is another repo or a git worktree copy.
                let isOtherRepo = fm.fileExists(atPath: url.appendingPathComponent(".git").path)
                if skippedDirectoryNames.contains(name) || isOtherRepo {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values?.isRegularFile == true, name.hasPrefix(".env") else { continue }
            let path = url.resolvingSymlinksInPath().path
            guard path.hasPrefix(rootPath + "/") else { continue }
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            results.append(ScannedFile(
                relativePath: String(path.dropFirst(rootPath.count + 1)),
                keyCount: DotEnvParser.parse(text).pairs.count,
                isSelectedByDefault: !templateSuffixes.contains { name.hasSuffix($0) }
            ))
        }
        return results.sorted { $0.relativePath < $1.relativePath }
    }
}
```

`Sources/EnvCore/Scanning/GitIgnoreChecker.swift`:

```swift
import Foundation

public enum GitIgnoreChecker {
    /// Returns true when git ignores the file, false when it does not, and nil when
    /// the folder is not a git repo or git cannot run.
    public static func isIgnored(relativePath: String, root: URL) -> Bool? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", root.path, "check-ignore", "-q", "--", relativePath]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        switch process.terminationStatus {
        case 0: return true
        case 1: return false
        default: return nil
        }
    }
}
```

- [ ] **Step 4: Testin geçtiğini gör**

Run: `swift test --filter ScanningTests`
Expected: PASS, 4 test.

- [ ] **Step 5: Commit**

```bash
git add Sources/EnvCore/Scanning Tests/EnvCoreTests/ScanningTests.swift
git commit -m "feat(core): add project scanner and git ignore checker"
```

---

### Task 8: Proje içe aktarma (ProjectImporter)

**Files:**
- Create: `Sources/EnvCore/Import/ProjectImporter.swift`
- Test: `Tests/EnvCoreTests/ProjectImporterTests.swift`

**Interfaces:**
- Consumes: `Project`, `EnvTarget`, `EnvEntry`, `EnvEnvironment` (Task 1), `DotEnvParser`, `DotEnvWarning` (Task 2), `ContentHash` (Task 4), `SecretStore`, `SecretAccount`, `SecretSuggester`, `InMemorySecretStore` (Task 5), `TempDir` (Task 6)
- Produces:
  - `struct ImportResult: Sendable { project: Project; warnings: [String: [DotEnvWarning]] }` (anahtar: göreli yol)
  - `struct ProjectImporter: Sendable { init(secrets: any SecretStore); func makeProject(name: String, root: URL, relativePaths: [String], environments: [EnvEnvironment], importInto environmentId: UUID) throws -> ImportResult }`

- [ ] **Step 1: Başarısız testi yaz**

`Tests/EnvCoreTests/ProjectImporterTests.swift`:

```swift
import Foundation
import Testing
@testable import EnvCore

struct ProjectImporterTests {
    @Test func importsFilesIntoChosenEnvironment() throws {
        let root = try TempDir.make()
        let text = "A=1\nAPI_TOKEN=s3cret\nbad line\n"
        try TempDir.write(text, to: "apps/cart/.env.local", in: root)
        try TempDir.write("B=2\n", to: "apps/shell/.env.local", in: root)
        let envs = EnvEnvironment.defaults()
        let secrets = InMemorySecretStore()

        let result = try ProjectImporter(secrets: secrets).makeProject(
            name: "karaca",
            root: root,
            relativePaths: ["apps/cart/.env.local", "apps/shell/.env.local"],
            environments: envs,
            importInto: envs[0].id
        )

        let project = result.project
        #expect(project.name == "karaca")
        #expect(project.rootPath == root.path)
        #expect(project.environments == envs)
        #expect(project.targets.map(\.relativePath) == ["apps/cart/.env.local", "apps/shell/.env.local"])

        let cart = project.targets[0]
        #expect(cart.activeEnvironmentId == envs[0].id)
        #expect(cart.lastWrittenHash == ContentHash.sha256(Data(text.utf8)))
        #expect(cart.entries(for: envs[0].id) == [
            EnvEntry(key: "A", value: "1"),
            EnvEntry(key: "API_TOKEN", value: nil, isSecret: true),
        ])
        #expect(cart.entries(for: envs[1].id).isEmpty)

        let account = SecretAccount.make(projectId: project.id, targetId: cart.id, environmentId: envs[0].id, key: "API_TOKEN")
        #expect(secrets.snapshot == [account: "s3cret"])
        #expect(result.warnings == ["apps/cart/.env.local": [.invalidLine(line: 3)]])
    }

    @Test func throwsWhenFileIsMissing() throws {
        let root = try TempDir.make()
        let envs = EnvEnvironment.defaults()
        #expect(throws: (any Error).self) {
            try ProjectImporter(secrets: InMemorySecretStore()).makeProject(
                name: "x", root: root, relativePaths: [".env"], environments: envs, importInto: envs[0].id)
        }
    }
}
```

- [ ] **Step 2: Testin başarısız olduğunu gör**

Run: `swift test --filter ProjectImporterTests`
Expected: FAIL, `cannot find 'ProjectImporter' in scope`.

- [ ] **Step 3: Kodu yaz**

`Sources/EnvCore/Import/ProjectImporter.swift`:

```swift
import Foundation

public struct ImportResult: Sendable {
    public var project: Project
    /// Keyed by relative path. Only files with warnings appear.
    public var warnings: [String: [DotEnvWarning]]
}

public struct ProjectImporter: Sendable {
    let secrets: any SecretStore

    public init(secrets: any SecretStore) {
        self.secrets = secrets
    }

    public func makeProject(
        name: String,
        root: URL,
        relativePaths: [String],
        environments: [EnvEnvironment],
        importInto environmentId: UUID
    ) throws -> ImportResult {
        var project = Project(name: name, rootPath: root.standardizedFileURL.path, environments: environments, targets: [])
        var warnings: [String: [DotEnvWarning]] = [:]

        for path in relativePaths {
            let data = try Data(contentsOf: root.appendingPathComponent(path))
            let parsed = DotEnvParser.parse(String(decoding: data, as: UTF8.self))
            if !parsed.warnings.isEmpty { warnings[path] = parsed.warnings }

            var target = EnvTarget(relativePath: path, activeEnvironmentId: environmentId, lastWrittenHash: ContentHash.sha256(data))
            var entries: [EnvEntry] = []
            for pair in parsed.pairs {
                if SecretSuggester.isLikelySecret(pair.key) {
                    let account = SecretAccount.make(projectId: project.id, targetId: target.id, environmentId: environmentId, key: pair.key)
                    try secrets.write(pair.value, account: account)
                    entries.append(EnvEntry(key: pair.key, value: nil, isSecret: true))
                } else {
                    entries.append(EnvEntry(key: pair.key, value: pair.value))
                }
            }
            target.setEntries(entries, for: environmentId)
            project.targets.append(target)
        }
        return ImportResult(project: project, warnings: warnings)
    }
}
```

- [ ] **Step 4: Testin geçtiğini gör**

Run: `swift test --filter ProjectImporterTests`
Expected: PASS, 2 test.

- [ ] **Step 5: Commit**

```bash
git add Sources/EnvCore/Import Tests/EnvCoreTests/ProjectImporterTests.swift
git commit -m "feat(core): add project importer"
```

---

### Task 9: Geçiş planlama (FileWriter, ValueResolver, SwitchPlanner)

**Files:**
- Create: `Sources/EnvCore/Switching/FileWriter.swift`
- Create: `Sources/EnvCore/Switching/ValueResolver.swift`
- Create: `Sources/EnvCore/Switching/SwitchPlanner.swift`
- Create: `Tests/EnvCoreTests/Support/ProjectFixture.swift`
- Test: `Tests/EnvCoreTests/SwitchPlannerTests.swift`

**Interfaces:**
- Consumes: Task 1–5 tipleri, `TempDir` (Task 6)
- Produces:
  - `protocol FileWriter: Sendable { func read(_ url: URL) throws -> Data?; func write(_ data: Data, to url: URL) throws; func remove(_ url: URL) throws; func directoryExists(_ url: URL) -> Bool }`
  - `struct LocalFileWriter: FileWriter { init() }` (`write` atomik yazar)
  - `struct ValueResolver: Sendable { init(secrets: any SecretStore); func resolve(project: Project, target: EnvTarget, environmentId: UUID) throws -> [DotEnvPair] }` (eksik gizli değer `""` olur)
  - `enum SwitchScope: Hashable, Sendable { project, target(UUID) }`
  - `enum SwitchError: Error, Equatable { unknownEnvironment, unknownTarget, directoryMissing([String]), writeFailed(path: String, reason: String), rollbackFailed(paths: [String], recoveryFolder: URL) }`
  - `struct DriftedTarget: Equatable, Sendable { targetId: UUID; relativePath: String; status: DriftStatus; diff: EnvDiff; fileContents: String }`
  - `struct SwitchPreflight: Equatable, Sendable { environment: EnvEnvironment; targetIds: [UUID]; missingDirectories: [String]; drifted: [DriftedTarget]; needsProtectedConfirmation: Bool }`
  - `struct PreparedWrite: Equatable, Sendable { targetId: UUID; relativePath: String; url: URL; data: Data }`
  - `struct SwitchPlanner: Sendable { init(secrets: any SecretStore, files: any FileWriter = LocalFileWriter()); func preflight(project:scope:environmentId:) throws -> SwitchPreflight; func prepare(project:scope:environmentId:) throws -> [PreparedWrite]; static func header(project: Project, environment: EnvEnvironment) -> [String] }`
  - Test yardımcısı: `struct ProjectFixture { root: URL; envs: [EnvEnvironment]; secrets: InMemorySecretStore; project: Project; local/test/canli: UUID; cart/shell: EnvTarget; mutating func setEntries(_:target:env:); mutating func update(_ target: EnvTarget, _ change: (inout EnvTarget) -> Void); func account(_ target: EnvTarget, _ env: UUID, _ key: String) -> String }`. Not: `update` kapanışı `f` değişkenini yakalayamaz (Swift exclusive access kuralı). Gereken değeri önce bir `let` içine alın.

- [ ] **Step 1: Test yardımcısını yaz**

`Tests/EnvCoreTests/Support/ProjectFixture.swift`:

```swift
import Foundation
@testable import EnvCore

/// A project with two targets (apps/cart/.env.local, apps/shell/.env.local) in a temp folder.
/// The target folders exist. The files do not.
struct ProjectFixture {
    let root: URL
    let envs = EnvEnvironment.defaults()
    let secrets = InMemorySecretStore()
    var project: Project

    init() throws {
        root = try TempDir.make()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("apps/cart"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("apps/shell"), withIntermediateDirectories: true)
        project = Project(
            name: "karaca",
            rootPath: root.path,
            environments: envs,
            targets: [EnvTarget(relativePath: "apps/cart/.env.local"), EnvTarget(relativePath: "apps/shell/.env.local")]
        )
    }

    var local: UUID { envs[0].id }
    var test: UUID { envs[1].id }
    var canli: UUID { envs[2].id }
    var cart: EnvTarget { project.targets[0] }
    var shell: EnvTarget { project.targets[1] }

    mutating func setEntries(_ entries: [EnvEntry], target: EnvTarget, env: UUID) {
        let index = project.targetIndex(id: target.id)!
        project.targets[index].setEntries(entries, for: env)
    }

    mutating func update(_ target: EnvTarget, _ change: (inout EnvTarget) -> Void) {
        let index = project.targetIndex(id: target.id)!
        change(&project.targets[index])
    }

    func account(_ target: EnvTarget, _ env: UUID, _ key: String) -> String {
        SecretAccount.make(projectId: project.id, targetId: target.id, environmentId: env, key: key)
    }
}
```

- [ ] **Step 2: Başarısız testi yaz**

`Tests/EnvCoreTests/SwitchPlannerTests.swift`:

```swift
import Foundation
import Testing
@testable import EnvCore

struct SwitchPlannerTests {
    private let header = "# EnvSwitcher tarafından üretildi — proje: karaca, ortam: test\n# Bu dosyayı elle düzenlerseniz, ortam değişirken uygulama sorar.\n"

    @Test func prepareBuildsHeaderAndResolvesSecrets() throws {
        var f = try ProjectFixture()
        f.setEntries([EnvEntry(key: "A", value: "2"), EnvEntry(key: "TOKEN", value: nil, isSecret: true)], target: f.cart, env: f.test)
        try f.secrets.write("xyz", account: f.account(f.cart, f.test, "TOKEN"))

        let writes = try SwitchPlanner(secrets: f.secrets).prepare(project: f.project, scope: .target(f.cart.id), environmentId: f.test)

        #expect(writes.count == 1)
        #expect(writes[0].targetId == f.cart.id)
        #expect(writes[0].relativePath == "apps/cart/.env.local")
        #expect(writes[0].url == f.root.appendingPathComponent("apps/cart/.env.local"))
        #expect(String(decoding: writes[0].data, as: UTF8.self) == header + "A=2\nTOKEN=xyz\n")
    }

    @Test func prepareWritesHeaderOnlyForEmptyEnvironment() throws {
        let f = try ProjectFixture()
        let writes = try SwitchPlanner(secrets: f.secrets).prepare(project: f.project, scope: .project, environmentId: f.test)
        #expect(writes.map { String(decoding: $0.data, as: UTF8.self) } == [header, header])
    }

    @Test func prepareThrowsWhenDirectoryIsMissing() throws {
        let f = try ProjectFixture()
        try FileManager.default.removeItem(at: f.root.appendingPathComponent("apps/shell"))
        #expect(throws: SwitchError.directoryMissing(["apps/shell/.env.local"])) {
            try SwitchPlanner(secrets: f.secrets).prepare(project: f.project, scope: .project, environmentId: f.test)
        }
    }

    @Test func prepareStopsWhenSecretReadFails() throws {
        var f = try ProjectFixture()
        f.setEntries([EnvEntry(key: "TOKEN", value: nil, isSecret: true)], target: f.cart, env: f.test)
        f.secrets.failReads = true
        #expect(throws: SecretStoreError.simulatedFailure) {
            try SwitchPlanner(secrets: f.secrets).prepare(project: f.project, scope: .project, environmentId: f.test)
        }
    }

    @Test func prepareThrowsForUnknownEnvironmentOrTarget() throws {
        let f = try ProjectFixture()
        let planner = SwitchPlanner(secrets: f.secrets)
        #expect(throws: SwitchError.unknownEnvironment) {
            try planner.prepare(project: f.project, scope: .project, environmentId: UUID())
        }
        #expect(throws: SwitchError.unknownTarget) {
            try planner.prepare(project: f.project, scope: .target(UUID()), environmentId: f.test)
        }
    }

    @Test func preflightReportsMissingDirectory() throws {
        let f = try ProjectFixture()
        try FileManager.default.removeItem(at: f.root.appendingPathComponent("apps/cart"))
        let result = try SwitchPlanner(secrets: f.secrets).preflight(project: f.project, scope: .project, environmentId: f.test)
        #expect(result.missingDirectories == ["apps/cart/.env.local"])
        #expect(result.targetIds == [f.cart.id, f.shell.id])
    }

    @Test func preflightIgnoresMissingAndCleanFiles() throws {
        var f = try ProjectFixture()
        try TempDir.write("A=1\n", to: "apps/cart/.env.local", in: f.root)
        f.update(f.cart) { $0.lastWrittenHash = ContentHash.sha256(Data("A=1\n".utf8)) }
        let result = try SwitchPlanner(secrets: f.secrets).preflight(project: f.project, scope: .project, environmentId: f.test)
        #expect(result.drifted.isEmpty)
        #expect(result.missingDirectories.isEmpty)
    }

    @Test func preflightReportsModifiedFileWithDiffAgainstActiveEnvironment() throws {
        var f = try ProjectFixture()
        f.setEntries([EnvEntry(key: "A", value: "1"), EnvEntry(key: "C", value: "3")], target: f.cart, env: f.local)
        let local = f.local // read before the mutating call: the closure cannot capture `f`
        f.update(f.cart) {
            $0.activeEnvironmentId = local
            $0.lastWrittenHash = "stale"
        }
        try TempDir.write("A=9\nB=2\n", to: "apps/cart/.env.local", in: f.root)

        let result = try SwitchPlanner(secrets: f.secrets).preflight(project: f.project, scope: .project, environmentId: f.test)

        #expect(result.drifted == [DriftedTarget(
            targetId: f.cart.id,
            relativePath: "apps/cart/.env.local",
            status: .modified,
            diff: EnvDiff(
                added: [DotEnvPair(key: "B", value: "2")],
                changed: [DotEnvChange(key: "A", oldValue: "1", newValue: "9")],
                removed: ["C"]
            ),
            fileContents: "A=9\nB=2\n"
        )])
    }

    @Test func preflightReportsUnmanagedFileWithAllKeysAdded() throws {
        let f = try ProjectFixture()
        try TempDir.write("A=1\n", to: "apps/shell/.env.local", in: f.root)
        let result = try SwitchPlanner(secrets: f.secrets).preflight(project: f.project, scope: .project, environmentId: f.test)
        #expect(result.drifted.map(\.status) == [.unmanaged])
        #expect(result.drifted.first?.diff.added == [DotEnvPair(key: "A", value: "1")])
    }

    @Test func preflightAsksConfirmationOnlyForProtectedEnvironment() throws {
        let f = try ProjectFixture()
        let planner = SwitchPlanner(secrets: f.secrets)
        #expect(try planner.preflight(project: f.project, scope: .project, environmentId: f.canli).needsProtectedConfirmation)
        #expect(try !planner.preflight(project: f.project, scope: .project, environmentId: f.test).needsProtectedConfirmation)
    }

    @Test func targetScopeLimitsPreflightToOneFile() throws {
        let f = try ProjectFixture()
        let result = try SwitchPlanner(secrets: f.secrets).preflight(project: f.project, scope: .target(f.shell.id), environmentId: f.test)
        #expect(result.targetIds == [f.shell.id])
    }
}
```

- [ ] **Step 3: Testin başarısız olduğunu gör**

Run: `swift test --filter SwitchPlannerTests`
Expected: FAIL, `cannot find 'SwitchPlanner' in scope`.

- [ ] **Step 4: Kodu yaz**

`Sources/EnvCore/Switching/FileWriter.swift`:

```swift
import Foundation

public protocol FileWriter: Sendable {
    /// Returns nil when the file does not exist.
    func read(_ url: URL) throws -> Data?
    /// Writes to a temporary file in the same folder, then renames it over the target.
    func write(_ data: Data, to url: URL) throws
    /// Removing a file that does not exist is not an error.
    func remove(_ url: URL) throws
    func directoryExists(_ url: URL) -> Bool
}

public struct LocalFileWriter: FileWriter {
    public init() {}

    public func read(_ url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    public func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    public func remove(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    public func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
```

`Sources/EnvCore/Switching/ValueResolver.swift`:

```swift
import Foundation

public struct ValueResolver: Sendable {
    let secrets: any SecretStore

    public init(secrets: any SecretStore) {
        self.secrets = secrets
    }

    /// Returns the key/value pairs of one environment, with secrets read from the SecretStore.
    /// A secret with no stored value becomes an empty string.
    public func resolve(project: Project, target: EnvTarget, environmentId: UUID) throws -> [DotEnvPair] {
        try target.entries(for: environmentId).map { entry in
            guard entry.isSecret else { return DotEnvPair(key: entry.key, value: entry.value ?? "") }
            let account = SecretAccount.make(projectId: project.id, targetId: target.id, environmentId: environmentId, key: entry.key)
            return DotEnvPair(key: entry.key, value: try secrets.read(account: account) ?? "")
        }
    }
}
```

`Sources/EnvCore/Switching/SwitchPlanner.swift`:

```swift
import Foundation

public enum SwitchScope: Hashable, Sendable {
    case project
    case target(UUID)
}

public enum SwitchError: Error, Equatable {
    case unknownEnvironment
    case unknownTarget
    case directoryMissing([String])
    case writeFailed(path: String, reason: String)
    case rollbackFailed(paths: [String], recoveryFolder: URL)
}

public struct DriftedTarget: Equatable, Sendable {
    public var targetId: UUID
    public var relativePath: String
    public var status: DriftStatus
    public var diff: EnvDiff
    public var fileContents: String

    public init(targetId: UUID, relativePath: String, status: DriftStatus, diff: EnvDiff, fileContents: String) {
        self.targetId = targetId
        self.relativePath = relativePath
        self.status = status
        self.diff = diff
        self.fileContents = fileContents
    }
}

public struct SwitchPreflight: Equatable, Sendable {
    public var environment: EnvEnvironment
    public var targetIds: [UUID]
    public var missingDirectories: [String]
    public var drifted: [DriftedTarget]

    public var needsProtectedConfirmation: Bool { environment.isProtected }
}

public struct PreparedWrite: Equatable, Sendable {
    public var targetId: UUID
    public var relativePath: String
    public var url: URL
    public var data: Data
}

public struct SwitchPlanner: Sendable {
    let secrets: any SecretStore
    let files: any FileWriter

    public init(secrets: any SecretStore, files: any FileWriter = LocalFileWriter()) {
        self.secrets = secrets
        self.files = files
    }

    /// Steps 1–3 of the switch flow: protected check data, missing folders and drift.
    public func preflight(project: Project, scope: SwitchScope, environmentId: UUID) throws -> SwitchPreflight {
        guard let environment = project.environment(id: environmentId) else { throw SwitchError.unknownEnvironment }
        let targets = try targets(in: project, scope: scope)
        let resolver = ValueResolver(secrets: secrets)
        var missing: [String] = []
        var drifted: [DriftedTarget] = []

        for target in targets {
            let url = project.url(for: target)
            guard files.directoryExists(url.deletingLastPathComponent()) else {
                missing.append(target.relativePath)
                continue
            }
            let data = try files.read(url)
            let status = DriftDetector.status(fileData: data, lastWrittenHash: target.lastWrittenHash)
            guard status == .modified || status == .unmanaged, let data else { continue }

            let text = String(decoding: data, as: UTF8.self)
            var stored: [DotEnvPair] = []
            if status == .modified, let active = target.activeEnvironmentId {
                stored = try resolver.resolve(project: project, target: target, environmentId: active)
            }
            drifted.append(DriftedTarget(
                targetId: target.id,
                relativePath: target.relativePath,
                status: status,
                diff: EnvDiffer.diff(old: stored, new: DotEnvParser.parse(text).pairs),
                fileContents: text
            ))
        }
        return SwitchPreflight(environment: environment, targetIds: targets.map(\.id), missingDirectories: missing, drifted: drifted)
    }

    /// Step 4: builds the new file contents in memory. Writes nothing to disk.
    public func prepare(project: Project, scope: SwitchScope, environmentId: UUID) throws -> [PreparedWrite] {
        guard let environment = project.environment(id: environmentId) else { throw SwitchError.unknownEnvironment }
        let targets = try targets(in: project, scope: scope)
        let missing = targets.filter { !files.directoryExists(project.url(for: $0).deletingLastPathComponent()) }
        guard missing.isEmpty else { throw SwitchError.directoryMissing(missing.map(\.relativePath)) }

        let resolver = ValueResolver(secrets: secrets)
        let header = Self.header(project: project, environment: environment)
        return try targets.map { target in
            let pairs = try resolver.resolve(project: project, target: target, environmentId: environmentId)
            let text = DotEnvSerializer.serialize(pairs, headerLines: header)
            return PreparedWrite(targetId: target.id, relativePath: target.relativePath, url: project.url(for: target), data: Data(text.utf8))
        }
    }

    public static func header(project: Project, environment: EnvEnvironment) -> [String] {
        [
            "EnvSwitcher tarafından üretildi — proje: \(project.name), ortam: \(environment.name)",
            "Bu dosyayı elle düzenlerseniz, ortam değişirken uygulama sorar.",
        ]
    }

    private func targets(in project: Project, scope: SwitchScope) throws -> [EnvTarget] {
        switch scope {
        case .project:
            return project.targets
        case .target(let id):
            guard let target = project.targets.first(where: { $0.id == id }) else { throw SwitchError.unknownTarget }
            return [target]
        }
    }
}
```

- [ ] **Step 5: Testin geçtiğini gör**

Run: `swift test --filter SwitchPlannerTests`
Expected: PASS, 11 test.

- [ ] **Step 6: Commit**

```bash
git add Sources/EnvCore/Switching Tests/EnvCoreTests/Support/ProjectFixture.swift Tests/EnvCoreTests/SwitchPlannerTests.swift
git commit -m "feat(core): add switch planner with drift preflight"
```

---

### Task 10: Atomik yazma ve geri dönüş (SwitchExecutor)

**Files:**
- Create: `Sources/EnvCore/Switching/SwitchExecutor.swift`
- Create: `Tests/EnvCoreTests/Support/FakeFileWriter.swift`
- Test: `Tests/EnvCoreTests/SwitchExecutorTests.swift`

**Interfaces:**
- Consumes: `FileWriter`, `PreparedWrite`, `SwitchError` (Task 9), `ContentHash` (Task 4), `Timestamp` (Task 6), `TempDir` (Task 6)
- Produces:
  - `struct SwitchExecutor: Sendable { init(files: any FileWriter = LocalFileWriter(), recoveryDirectory: URL, now: @escaping @Sendable () -> Date = { Date() }); func execute(_ writes: [PreparedWrite]) throws -> [UUID: String] }` (dönüş: hedef id → yazılan içeriğin SHA-256 özeti)
  - Kurtarma dosyası adı: göreli yoldaki `/` karakteri `__` olur. Klasör: `<recoveryDirectory>/<yyyyMMdd-HHmmss>/`.
  - Test yardımcısı: `final class FakeFileWriter: FileWriter { contents: [URL: Data]; failingURL: URL?; failEverythingAfterFirstFailure: Bool }`

- [ ] **Step 1: Sahte yazıcıyı yaz**

`Tests/EnvCoreTests/Support/FakeFileWriter.swift`:

```swift
import Foundation
@testable import EnvCore

/// In-memory FileWriter. A write to `failingURL` throws. With
/// `failEverythingAfterFirstFailure`, every later write and remove also throws.
final class FakeFileWriter: FileWriter, @unchecked Sendable {
    struct Failure: Error {}

    var contents: [URL: Data] = [:]
    var failingURL: URL?
    var failEverythingAfterFirstFailure = false
    private var broken = false

    func read(_ url: URL) throws -> Data? { contents[url] }

    func write(_ data: Data, to url: URL) throws {
        if broken { throw Failure() }
        if url == failingURL {
            broken = failEverythingAfterFirstFailure
            throw Failure()
        }
        contents[url] = data
    }

    func remove(_ url: URL) throws {
        if broken { throw Failure() }
        contents[url] = nil
    }

    func directoryExists(_ url: URL) -> Bool { true }
}
```

- [ ] **Step 2: Başarısız testi yaz**

`Tests/EnvCoreTests/SwitchExecutorTests.swift`:

```swift
import Foundation
import Testing
@testable import EnvCore

struct SwitchExecutorTests {
    private let a = URL(fileURLWithPath: "/p/apps/a/.env.local")
    private let b = URL(fileURLWithPath: "/p/apps/b/.env.local")
    private let idA = UUID()
    private let idB = UUID()
    private let fixedDate = Date(timeIntervalSince1970: 1_791_400_000) // 20261007-181320 UTC

    private func writes() -> [PreparedWrite] {
        [
            PreparedWrite(targetId: idA, relativePath: "apps/a/.env.local", url: a, data: Data("A=new\n".utf8)),
            PreparedWrite(targetId: idB, relativePath: "apps/b/.env.local", url: b, data: Data("B=new\n".utf8)),
        ]
    }

    @Test func writesAllFilesAndReturnsHashes() throws {
        let files = FakeFileWriter()
        let hashes = try SwitchExecutor(files: files, recoveryDirectory: try TempDir.make()).execute(writes())
        #expect(files.contents == [a: Data("A=new\n".utf8), b: Data("B=new\n".utf8)])
        #expect(hashes == [
            idA: ContentHash.sha256(Data("A=new\n".utf8)),
            idB: ContentHash.sha256(Data("B=new\n".utf8)),
        ])
    }

    @Test func restoresEarlierFilesWhenALaterWriteFails() throws {
        let files = FakeFileWriter()
        files.contents = [a: Data("A=old\n".utf8), b: Data("B=old\n".utf8)]
        files.failingURL = b
        #expect(throws: SwitchError.writeFailed(path: "apps/b/.env.local", reason: "Failure()")) {
            try SwitchExecutor(files: files, recoveryDirectory: try TempDir.make()).execute(writes())
        }
        #expect(files.contents == [a: Data("A=old\n".utf8), b: Data("B=old\n".utf8)])
    }

    @Test func removesNewFilesWhenALaterWriteFails() throws {
        let files = FakeFileWriter()
        files.failingURL = b
        #expect(throws: SwitchError.self) {
            try SwitchExecutor(files: files, recoveryDirectory: try TempDir.make()).execute(writes())
        }
        #expect(files.contents.isEmpty)
    }

    @Test func savesRecoveryCopyWhenRollbackFails() throws {
        let files = FakeFileWriter()
        files.contents = [a: Data("A=old\n".utf8)]
        files.failingURL = b
        files.failEverythingAfterFirstFailure = true
        let recovery = try TempDir.make()
        let folder = recovery.appendingPathComponent("20261007-181320", isDirectory: true)

        #expect(throws: SwitchError.rollbackFailed(paths: ["apps/a/.env.local"], recoveryFolder: folder)) {
            try SwitchExecutor(files: files, recoveryDirectory: recovery, now: { [fixedDate] in fixedDate }).execute(writes())
        }
        #expect(try TempDir.read("apps__a__.env.local", in: folder) == "A=old\n")
    }
}
```

- [ ] **Step 3: Testin başarısız olduğunu gör**

Run: `swift test --filter SwitchExecutorTests`
Expected: FAIL, `cannot find 'SwitchExecutor' in scope`.

- [ ] **Step 4: Kodu yaz**

`Sources/EnvCore/Switching/SwitchExecutor.swift`:

```swift
import Foundation

public struct SwitchExecutor: Sendable {
    let files: any FileWriter
    let recoveryDirectory: URL
    private let now: @Sendable () -> Date

    public init(files: any FileWriter = LocalFileWriter(), recoveryDirectory: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.files = files
        self.recoveryDirectory = recoveryDirectory
        self.now = now
    }

    /// Step 5: writes every file or none. Returns the SHA-256 hash of each written file by target id.
    public func execute(_ writes: [PreparedWrite]) throws -> [UUID: String] {
        let originals = try writes.map { try files.read($0.url) }
        for (index, write) in writes.enumerated() {
            do {
                try files.write(write.data, to: write.url)
            } catch {
                try rollback(Array(zip(writes[..<index], originals[..<index])))
                throw SwitchError.writeFailed(path: write.relativePath, reason: String(describing: error))
            }
        }
        return Dictionary(uniqueKeysWithValues: writes.map { ($0.targetId, ContentHash.sha256($0.data)) })
    }

    /// Puts back the old content. A file with no old content is removed.
    /// When this also fails, the old content goes to the recovery folder.
    private func rollback(_ written: [(PreparedWrite, Data?)]) throws {
        var failed: [(PreparedWrite, Data?)] = []
        for (write, original) in written {
            do {
                if let original {
                    try files.write(original, to: write.url)
                } else {
                    try files.remove(write.url)
                }
            } catch {
                failed.append((write, original))
            }
        }
        guard !failed.isEmpty else { return }

        let folder = recoveryDirectory.appendingPathComponent(Timestamp.string(now()), isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (write, original) in failed {
            let name = write.relativePath.replacingOccurrences(of: "/", with: "__")
            try? (original ?? Data()).write(to: folder.appendingPathComponent(name))
        }
        throw SwitchError.rollbackFailed(paths: failed.map { $0.0.relativePath }, recoveryFolder: folder)
    }
}
```

- [ ] **Step 5: Testin geçtiğini gör**

Run: `swift test --filter SwitchExecutorTests`
Expected: PASS, 4 test.

- [ ] **Step 6: Commit**

```bash
git add Sources/EnvCore/Switching/SwitchExecutor.swift Tests/EnvCoreTests/Support/FakeFileWriter.swift Tests/EnvCoreTests/SwitchExecutorTests.swift
git commit -m "feat(core): add switch executor with atomic writes and rollback"
```

---

### Task 11: Geçişi tamamlama ve elle değişikliği kaydetme

**Files:**
- Create: `Sources/EnvCore/Switching/SwitchService.swift`
- Create: `Sources/EnvCore/Switching/DriftResolver.swift`
- Test: `Tests/EnvCoreTests/SwitchServiceTests.swift`

**Interfaces:**
- Consumes: `SwitchPlanner`, `SwitchScope`, `SwitchError` (Task 9), `SwitchExecutor` (Task 10), `ProjectFixture` (Task 9)
- Produces:
  - `struct SwitchService: Sendable { init(planner: SwitchPlanner, executor: SwitchExecutor); func commit(project: Project, scope: SwitchScope, environmentId: UUID) throws -> Project }` (adım 4–6, güncellenmiş proje döner)
  - `struct DriftResolver: Sendable { init(secrets: any SecretStore); func saveFile(_ contents: String, into environmentId: UUID, targetId: UUID, project: Project) throws -> Project }`

- [ ] **Step 1: Başarısız testi yaz**

`Tests/EnvCoreTests/SwitchServiceTests.swift`:

```swift
import Foundation
import Testing
@testable import EnvCore

struct SwitchServiceTests {
    private func service(_ f: ProjectFixture) -> SwitchService {
        SwitchService(
            planner: SwitchPlanner(secrets: f.secrets),
            executor: SwitchExecutor(recoveryDirectory: f.root.appendingPathComponent("recovery"))
        )
    }

    @Test func commitWritesFilesAndUpdatesActiveEnvironmentAndHash() throws {
        var f = try ProjectFixture()
        f.setEntries([EnvEntry(key: "A", value: "local")], target: f.cart, env: f.local)
        f.setEntries([EnvEntry(key: "B", value: "local")], target: f.shell, env: f.local)

        let updated = try service(f).commit(project: f.project, scope: .project, environmentId: f.local)

        for target in updated.targets {
            let data = try Data(contentsOf: updated.url(for: target))
            #expect(target.activeEnvironmentId == f.local)
            #expect(target.lastWrittenHash == ContentHash.sha256(data))
        }
        #expect(try TempDir.read("apps/cart/.env.local", in: f.root).hasSuffix("A=local\n"))
        #expect(updated.displayState == .single(f.local))
    }

    @Test func targetScopeChangesOnlyOneFile() throws {
        let f = try ProjectFixture()
        let updated = try service(f).commit(project: f.project, scope: .target(f.shell.id), environmentId: f.canli)
        #expect(updated.targets.map(\.activeEnvironmentId) == [nil, f.canli])
        #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("apps/cart/.env.local").path))
    }

    @Test func commitLeavesProjectUnchangedWhenDirectoryIsMissing() throws {
        let f = try ProjectFixture()
        try FileManager.default.removeItem(at: f.root.appendingPathComponent("apps/shell"))
        #expect(throws: SwitchError.directoryMissing(["apps/shell/.env.local"])) {
            try service(f).commit(project: f.project, scope: .project, environmentId: f.test)
        }
        #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("apps/cart/.env.local").path))
    }

    @Test func saveFileUpdatesChangedAddsNewAndRemovesMissingKeys() throws {
        var f = try ProjectFixture()
        f.setEntries([
            EnvEntry(key: "A", value: "1"),
            EnvEntry(key: "DB_PASSWORD", value: nil, isSecret: true),
            EnvEntry(key: "GONE", value: "x"),
            EnvEntry(key: "GONE_TOKEN", value: nil, isSecret: true),
        ], target: f.cart, env: f.local)
        try f.secrets.write("old-pass", account: f.account(f.cart, f.local, "DB_PASSWORD"))
        try f.secrets.write("old-token", account: f.account(f.cart, f.local, "GONE_TOKEN"))

        let file = "A=2\nDB_PASSWORD=new-pass\nNEW=3\nNEW_SECRET=s\n"
        let updated = try DriftResolver(secrets: f.secrets).saveFile(file, into: f.local, targetId: f.cart.id, project: f.project)

        #expect(updated.targets[0].entries(for: f.local) == [
            EnvEntry(key: "A", value: "2"),
            EnvEntry(key: "DB_PASSWORD", value: nil, isSecret: true),
            EnvEntry(key: "NEW", value: "3"),
            EnvEntry(key: "NEW_SECRET", value: nil, isSecret: true),
        ])
        #expect(f.secrets.snapshot == [
            f.account(f.cart, f.local, "DB_PASSWORD"): "new-pass",
            f.account(f.cart, f.local, "NEW_SECRET"): "s",
        ])
        #expect(updated.targets[1] == f.shell)
    }

    @Test func saveFileThrowsForUnknownTarget() throws {
        let f = try ProjectFixture()
        #expect(throws: SwitchError.unknownTarget) {
            try DriftResolver(secrets: f.secrets).saveFile("A=1", into: f.local, targetId: UUID(), project: f.project)
        }
    }
}
```

- [ ] **Step 2: Testin başarısız olduğunu gör**

Run: `swift test --filter SwitchServiceTests`
Expected: FAIL, `cannot find 'SwitchService' in scope`.

- [ ] **Step 3: Kodu yaz**

`Sources/EnvCore/Switching/SwitchService.swift`:

```swift
import Foundation

public struct SwitchService: Sendable {
    public let planner: SwitchPlanner
    public let executor: SwitchExecutor

    public init(planner: SwitchPlanner, executor: SwitchExecutor) {
        self.planner = planner
        self.executor = executor
    }

    /// Steps 4–6: prepares the contents, writes the files, and returns the project
    /// with the new active environment and hash for each written target.
    public func commit(project: Project, scope: SwitchScope, environmentId: UUID) throws -> Project {
        let writes = try planner.prepare(project: project, scope: scope, environmentId: environmentId)
        let hashes = try executor.execute(writes)
        var project = project
        for (targetId, hash) in hashes {
            guard let index = project.targetIndex(id: targetId) else { continue }
            project.targets[index].activeEnvironmentId = environmentId
            project.targets[index].lastWrittenHash = hash
        }
        return project
    }
}
```

`Sources/EnvCore/Switching/DriftResolver.swift`:

```swift
import Foundation

public struct DriftResolver: Sendable {
    let secrets: any SecretStore

    public init(secrets: any SecretStore) {
        self.secrets = secrets
    }

    /// "Mevcut ortama kaydet": copies the file contents into one environment of the target.
    /// Changed keys get the new value, new keys go to the end, and missing keys are removed.
    public func saveFile(_ contents: String, into environmentId: UUID, targetId: UUID, project: Project) throws -> Project {
        guard let index = project.targetIndex(id: targetId) else { throw SwitchError.unknownTarget }
        let projectId = project.id
        let account = { (key: String) in
            SecretAccount.make(projectId: projectId, targetId: targetId, environmentId: environmentId, key: key)
        }
        let filePairs = DotEnvParser.parse(contents).pairs
        let fileValues = Dictionary(filePairs.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
        let existing = project.targets[index].entries(for: environmentId)

        var entries: [EnvEntry] = []
        for entry in existing {
            guard let newValue = fileValues[entry.key] else {
                if entry.isSecret { try secrets.delete(account: account(entry.key)) }
                continue
            }
            if entry.isSecret {
                try secrets.write(newValue, account: account(entry.key))
                entries.append(entry)
            } else {
                entries.append(EnvEntry(key: entry.key, value: newValue))
            }
        }
        let existingKeys = Set(existing.map(\.key))
        for pair in filePairs where !existingKeys.contains(pair.key) {
            if SecretSuggester.isLikelySecret(pair.key) {
                try secrets.write(pair.value, account: account(pair.key))
                entries.append(EnvEntry(key: pair.key, value: nil, isSecret: true))
            } else {
                entries.append(EnvEntry(key: pair.key, value: pair.value))
            }
        }

        var project = project
        project.targets[index].setEntries(entries, for: environmentId)
        return project
    }
}
```

- [ ] **Step 4: Testin geçtiğini gör**

Run: `swift test --filter SwitchServiceTests`
Expected: PASS, 5 test.

- [ ] **Step 5: Commit**

```bash
git add Sources/EnvCore/Switching/SwitchService.swift Sources/EnvCore/Switching/DriftResolver.swift Tests/EnvCoreTests/SwitchServiceTests.swift
git commit -m "feat(core): add switch service and drift resolver"
```

---

### Task 12: Düzenleme işlemleri (EntryEditor, ProjectEditor)

**Files:**
- Create: `Sources/EnvCore/Editing/EntryEditor.swift`
- Create: `Sources/EnvCore/Editing/ProjectEditor.swift`
- Test: `Tests/EnvCoreTests/EntryEditorTests.swift`
- Test: `Tests/EnvCoreTests/ProjectEditorTests.swift`

**Interfaces:**
- Consumes: Task 1, 2 (`DotEnvParser.isValidKey`), 5, 9 (`ValueResolver`, `ProjectFixture`)
- Produces:
  - `struct EntryEditor: Sendable`
    - `enum EditError: Error, Equatable { unknownTarget, unknownKey(String), duplicateKey(String), invalidKey(String) }`
    - `enum CopyMode: Sendable { overwrite, skipExisting }`
    - `init(secrets: any SecretStore)`
    - `func readValue(key:in:targetId:environmentId:) throws -> String`
    - `func addEntry(key:in:targetId:environmentId:) throws -> Project`
    - `func removeEntry(key:in:targetId:environmentId:) throws -> Project`
    - `func setValue(_ value: String, key:in:targetId:environmentId:) throws -> Project`
    - `func setSecret(_ isSecret: Bool, key:in:targetId:environmentId:) throws -> Project`
    - `func renameKey(_ oldKey: String, to newKey: String, in:targetId:environmentId:) throws -> Project`
    - `func copyEntries(from source: UUID, to destination: UUID, targetId: UUID, mode: CopyMode, in project: Project) throws -> Project`
  - `struct ProjectEditor: Sendable`
    - `enum EditError: Error, Equatable { lastEnvironment, unknownEnvironment, unknownTarget, duplicateTarget(String) }`
    - `init(secrets: any SecretStore)`
    - `func addEnvironment(named: String, color: EnvColor, to: Project) -> Project`
    - `func updateEnvironment(_ environment: EnvEnvironment, in: Project) throws -> Project`
    - `func deleteEnvironment(id: UUID, from: Project) throws -> Project`
    - `func addTarget(relativePath: String, to: Project) throws -> Project`
    - `func removeTarget(id: UUID, from: Project) throws -> Project`
    - `func relocate(_ project: Project, to root: URL) -> Project`
    - `func deleteAllSecrets(of project: Project) throws`

- [ ] **Step 1: EntryEditor için başarısız testi yaz**

`Tests/EnvCoreTests/EntryEditorTests.swift`:

```swift
import Foundation
import Testing
@testable import EnvCore

struct EntryEditorTests {
    private func setUp() throws -> (ProjectFixture, EntryEditor) {
        var f = try ProjectFixture()
        f.setEntries([EnvEntry(key: "A", value: "1"), EnvEntry(key: "TOKEN", value: nil, isSecret: true)], target: f.cart, env: f.local)
        try f.secrets.write("t0", account: f.account(f.cart, f.local, "TOKEN"))
        return (f, EntryEditor(secrets: f.secrets))
    }

    @Test func readsPlainAndSecretValues() throws {
        let (f, editor) = try setUp()
        #expect(try editor.readValue(key: "A", in: f.project, targetId: f.cart.id, environmentId: f.local) == "1")
        #expect(try editor.readValue(key: "TOKEN", in: f.project, targetId: f.cart.id, environmentId: f.local) == "t0")
        #expect(throws: EntryEditor.EditError.unknownKey("X")) {
            try editor.readValue(key: "X", in: f.project, targetId: f.cart.id, environmentId: f.local)
        }
    }

    @Test func addsEntryAtEndAndRejectsDuplicateOrInvalidKey() throws {
        let (f, editor) = try setUp()
        let p = try editor.addEntry(key: "B", in: f.project, targetId: f.cart.id, environmentId: f.local)
        #expect(p.targets[0].entries(for: f.local).map(\.key) == ["A", "TOKEN", "B"])
        #expect(p.targets[0].entries(for: f.local).last == EnvEntry(key: "B", value: ""))
        #expect(throws: EntryEditor.EditError.duplicateKey("A")) {
            try editor.addEntry(key: "A", in: f.project, targetId: f.cart.id, environmentId: f.local)
        }
        #expect(throws: EntryEditor.EditError.invalidKey("1X")) {
            try editor.addEntry(key: "1X", in: f.project, targetId: f.cart.id, environmentId: f.local)
        }
    }

    @Test func setValueWritesPlainToStoreAndSecretToSecretStore() throws {
        let (f, editor) = try setUp()
        var p = try editor.setValue("2", key: "A", in: f.project, targetId: f.cart.id, environmentId: f.local)
        p = try editor.setValue("t1", key: "TOKEN", in: p, targetId: f.cart.id, environmentId: f.local)
        #expect(p.targets[0].entries(for: f.local) == [EnvEntry(key: "A", value: "2"), EnvEntry(key: "TOKEN", value: nil, isSecret: true)])
        #expect(f.secrets.snapshot[f.account(f.cart, f.local, "TOKEN")] == "t1")
    }

    @Test func setSecretMovesValueBetweenStores() throws {
        let (f, editor) = try setUp()
        var p = try editor.setSecret(true, key: "A", in: f.project, targetId: f.cart.id, environmentId: f.local)
        #expect(p.targets[0].entries(for: f.local)[0] == EnvEntry(key: "A", value: nil, isSecret: true))
        #expect(f.secrets.snapshot[f.account(f.cart, f.local, "A")] == "1")

        p = try editor.setSecret(false, key: "TOKEN", in: p, targetId: f.cart.id, environmentId: f.local)
        #expect(p.targets[0].entries(for: f.local)[1] == EnvEntry(key: "TOKEN", value: "t0"))
        #expect(f.secrets.snapshot[f.account(f.cart, f.local, "TOKEN")] == nil)
    }

    @Test func renameKeyMovesSecretAccount() throws {
        let (f, editor) = try setUp()
        let p = try editor.renameKey("TOKEN", to: "API_TOKEN", in: f.project, targetId: f.cart.id, environmentId: f.local)
        #expect(p.targets[0].entries(for: f.local).map(\.key) == ["A", "API_TOKEN"])
        #expect(f.secrets.snapshot == [f.account(f.cart, f.local, "API_TOKEN"): "t0"])
        #expect(throws: EntryEditor.EditError.duplicateKey("A")) {
            try editor.renameKey("API_TOKEN", to: "A", in: p, targetId: f.cart.id, environmentId: f.local)
        }
    }

    @Test func removeEntryDeletesSecret() throws {
        let (f, editor) = try setUp()
        let p = try editor.removeEntry(key: "TOKEN", in: f.project, targetId: f.cart.id, environmentId: f.local)
        #expect(p.targets[0].entries(for: f.local).map(\.key) == ["A"])
        #expect(f.secrets.snapshot.isEmpty)
    }

    @Test func copyEntriesOverwritesOrSkipsExistingKeys() throws {
        var (f, editor) = try setUp()
        f.setEntries([EnvEntry(key: "A", value: "test-a"), EnvEntry(key: "ONLY_TEST", value: "x")], target: f.cart, env: f.test)

        let skipped = try editor.copyEntries(from: f.local, to: f.test, targetId: f.cart.id, mode: .skipExisting, in: f.project)
        #expect(skipped.targets[0].entries(for: f.test) == [
            EnvEntry(key: "A", value: "test-a"),
            EnvEntry(key: "ONLY_TEST", value: "x"),
            EnvEntry(key: "TOKEN", value: nil, isSecret: true),
        ])
        #expect(f.secrets.snapshot[f.account(f.cart, f.test, "TOKEN")] == "t0")

        let overwritten = try editor.copyEntries(from: f.local, to: f.test, targetId: f.cart.id, mode: .overwrite, in: f.project)
        #expect(overwritten.targets[0].entries(for: f.test)[0] == EnvEntry(key: "A", value: "1"))
    }
}
```

- [ ] **Step 2: ProjectEditor için başarısız testi yaz**

`Tests/EnvCoreTests/ProjectEditorTests.swift`:

```swift
import Foundation
import Testing
@testable import EnvCore

struct ProjectEditorTests {
    @Test func addsEnvironment() throws {
        let f = try ProjectFixture()
        let p = ProjectEditor(secrets: f.secrets).addEnvironment(named: "staging", color: .blue, to: f.project)
        #expect(p.environments.map(\.name) == ["local", "test", "canli", "staging"])
        #expect(p.environments.last?.color == .blue)
        #expect(p.environments.last?.isProtected == false)
    }

    @Test func renamingEnvironmentKeepsSecretsReadable() throws {
        var f = try ProjectFixture()
        f.setEntries([EnvEntry(key: "TOKEN", value: nil, isSecret: true)], target: f.cart, env: f.test)
        try f.secrets.write("t", account: f.account(f.cart, f.test, "TOKEN"))
        var renamed = f.envs[1]
        renamed.name = "staging"
        renamed.isProtected = true

        let p = try ProjectEditor(secrets: f.secrets).updateEnvironment(renamed, in: f.project)

        #expect(p.environment(id: f.test)?.name == "staging")
        #expect(p.environment(id: f.test)?.isProtected == true)
        let pairs = try ValueResolver(secrets: f.secrets).resolve(project: p, target: p.targets[0], environmentId: f.test)
        #expect(pairs == [DotEnvPair(key: "TOKEN", value: "t")])
    }

    @Test func deletingEnvironmentClearsActiveStateAndSecrets() throws {
        var f = try ProjectFixture()
        let test = f.test
        f.setEntries([EnvEntry(key: "TOKEN", value: nil, isSecret: true)], target: f.cart, env: test)
        f.update(f.cart) { $0.activeEnvironmentId = test }
        try f.secrets.write("t", account: f.account(f.cart, test, "TOKEN"))

        let p = try ProjectEditor(secrets: f.secrets).deleteEnvironment(id: test, from: f.project)

        #expect(p.environments.map(\.name) == ["local", "canli"])
        #expect(p.targets[0].activeEnvironmentId == nil)
        #expect(p.targets[0].values[test.uuidString] == nil)
        #expect(f.secrets.snapshot.isEmpty)
    }

    @Test func refusesToDeleteLastEnvironment() throws {
        let f = try ProjectFixture()
        let editor = ProjectEditor(secrets: f.secrets)
        var p = try editor.deleteEnvironment(id: f.local, from: f.project)
        p = try editor.deleteEnvironment(id: f.test, from: p)
        #expect(throws: ProjectEditor.EditError.lastEnvironment) {
            try editor.deleteEnvironment(id: f.canli, from: p)
        }
    }

    @Test func addsAndRemovesTargets() throws {
        var f = try ProjectFixture()
        let local = f.local
        f.setEntries([EnvEntry(key: "TOKEN", value: nil, isSecret: true)], target: f.cart, env: local)
        try f.secrets.write("t", account: f.account(f.cart, local, "TOKEN"))
        let editor = ProjectEditor(secrets: f.secrets)

        var p = try editor.addTarget(relativePath: "apps/plp/.env.local", to: f.project)
        #expect(p.targets.map(\.relativePath) == ["apps/cart/.env.local", "apps/shell/.env.local", "apps/plp/.env.local"])
        #expect(throws: ProjectEditor.EditError.duplicateTarget("apps/plp/.env.local")) {
            try editor.addTarget(relativePath: "apps/plp/.env.local", to: p)
        }

        p = try editor.removeTarget(id: f.cart.id, from: p)
        #expect(p.targets.map(\.relativePath) == ["apps/shell/.env.local", "apps/plp/.env.local"])
        #expect(f.secrets.snapshot.isEmpty)
    }

    @Test func relocateChangesRootPath() throws {
        let f = try ProjectFixture()
        let p = ProjectEditor(secrets: f.secrets).relocate(f.project, to: URL(fileURLWithPath: "/tmp/moved/"))
        #expect(p.rootPath == "/tmp/moved")
    }

    @Test func deleteAllSecretsRemovesEverySecretOfProject() throws {
        var f = try ProjectFixture()
        f.setEntries([EnvEntry(key: "T1", value: nil, isSecret: true)], target: f.cart, env: f.local)
        f.setEntries([EnvEntry(key: "T2", value: nil, isSecret: true)], target: f.shell, env: f.canli)
        try f.secrets.write("1", account: f.account(f.cart, f.local, "T1"))
        try f.secrets.write("2", account: f.account(f.shell, f.canli, "T2"))
        try f.secrets.write("other", account: "other-project")

        try ProjectEditor(secrets: f.secrets).deleteAllSecrets(of: f.project)

        #expect(f.secrets.snapshot == ["other-project": "other"])
    }
}
```

- [ ] **Step 3: Testlerin başarısız olduğunu gör**

Run: `swift test --filter "EntryEditorTests|ProjectEditorTests"`
Expected: FAIL, `cannot find 'EntryEditor' in scope`.

- [ ] **Step 4: EntryEditor kodunu yaz**

`Sources/EnvCore/Editing/EntryEditor.swift`:

```swift
import Foundation

public struct EntryEditor: Sendable {
    public enum EditError: Error, Equatable {
        case unknownTarget
        case unknownKey(String)
        case duplicateKey(String)
        case invalidKey(String)
    }

    public enum CopyMode: Sendable {
        case overwrite
        case skipExisting
    }

    let secrets: any SecretStore

    public init(secrets: any SecretStore) {
        self.secrets = secrets
    }

    public func readValue(key: String, in project: Project, targetId: UUID, environmentId: UUID) throws -> String {
        guard let target = project.targets.first(where: { $0.id == targetId }) else { throw EditError.unknownTarget }
        guard let entry = target.entries(for: environmentId).first(where: { $0.key == key }) else {
            throw EditError.unknownKey(key)
        }
        guard entry.isSecret else { return entry.value ?? "" }
        return try secrets.read(account: account(project, targetId, environmentId, key)) ?? ""
    }

    public func addEntry(key: String, in project: Project, targetId: UUID, environmentId: UUID) throws -> Project {
        guard DotEnvParser.isValidKey(key) else { throw EditError.invalidKey(key) }
        return try mutate(project, targetId, environmentId) { entries in
            guard !entries.contains(where: { $0.key == key }) else { throw EditError.duplicateKey(key) }
            entries.append(EnvEntry(key: key, value: ""))
        }
    }

    public func removeEntry(key: String, in project: Project, targetId: UUID, environmentId: UUID) throws -> Project {
        try mutate(project, targetId, environmentId) { entries in
            let i = try index(of: key, in: entries)
            if entries[i].isSecret { try secrets.delete(account: account(project, targetId, environmentId, key)) }
            entries.remove(at: i)
        }
    }

    public func setValue(_ value: String, key: String, in project: Project, targetId: UUID, environmentId: UUID) throws -> Project {
        try mutate(project, targetId, environmentId) { entries in
            let i = try index(of: key, in: entries)
            if entries[i].isSecret {
                try secrets.write(value, account: account(project, targetId, environmentId, key))
            } else {
                entries[i].value = value
            }
        }
    }

    public func setSecret(_ isSecret: Bool, key: String, in project: Project, targetId: UUID, environmentId: UUID) throws -> Project {
        try mutate(project, targetId, environmentId) { entries in
            let i = try index(of: key, in: entries)
            guard entries[i].isSecret != isSecret else { return }
            let secretAccount = account(project, targetId, environmentId, key)
            if isSecret {
                try secrets.write(entries[i].value ?? "", account: secretAccount)
                entries[i].value = nil
            } else {
                entries[i].value = try secrets.read(account: secretAccount) ?? ""
                try secrets.delete(account: secretAccount)
            }
            entries[i].isSecret = isSecret
        }
    }

    public func renameKey(_ oldKey: String, to newKey: String, in project: Project, targetId: UUID, environmentId: UUID) throws -> Project {
        guard DotEnvParser.isValidKey(newKey) else { throw EditError.invalidKey(newKey) }
        guard oldKey != newKey else { return project }
        return try mutate(project, targetId, environmentId) { entries in
            let i = try index(of: oldKey, in: entries)
            guard !entries.contains(where: { $0.key == newKey }) else { throw EditError.duplicateKey(newKey) }
            if entries[i].isSecret {
                let oldAccount = account(project, targetId, environmentId, oldKey)
                try secrets.write(try secrets.read(account: oldAccount) ?? "", account: account(project, targetId, environmentId, newKey))
                try secrets.delete(account: oldAccount)
            }
            entries[i].key = newKey
        }
    }

    public func copyEntries(from source: UUID, to destination: UUID, targetId: UUID, mode: CopyMode, in project: Project) throws -> Project {
        guard let target = project.targets.first(where: { $0.id == targetId }) else { throw EditError.unknownTarget }
        let sourceEntries = target.entries(for: source)
        return try mutate(project, targetId, destination) { entries in
            for entry in sourceEntries {
                let existing = entries.firstIndex { $0.key == entry.key }
                if existing != nil, mode == .skipExisting { continue }

                let value = try entry.isSecret
                    ? (secrets.read(account: account(project, targetId, source, entry.key)) ?? "")
                    : (entry.value ?? "")
                let destinationAccount = account(project, targetId, destination, entry.key)
                if let existing, entries[existing].isSecret, !entry.isSecret {
                    try secrets.delete(account: destinationAccount)
                }
                if entry.isSecret { try secrets.write(value, account: destinationAccount) }

                let copied = EnvEntry(key: entry.key, value: entry.isSecret ? nil : value, isSecret: entry.isSecret)
                if let existing {
                    entries[existing] = copied
                } else {
                    entries.append(copied)
                }
            }
        }
    }

    private func account(_ project: Project, _ targetId: UUID, _ environmentId: UUID, _ key: String) -> String {
        SecretAccount.make(projectId: project.id, targetId: targetId, environmentId: environmentId, key: key)
    }

    private func index(of key: String, in entries: [EnvEntry]) throws -> Int {
        guard let i = entries.firstIndex(where: { $0.key == key }) else { throw EditError.unknownKey(key) }
        return i
    }

    private func mutate(
        _ project: Project,
        _ targetId: UUID,
        _ environmentId: UUID,
        _ change: (inout [EnvEntry]) throws -> Void
    ) throws -> Project {
        guard let targetIndex = project.targetIndex(id: targetId) else { throw EditError.unknownTarget }
        var updated = project
        var entries = updated.targets[targetIndex].entries(for: environmentId)
        try change(&entries)
        updated.targets[targetIndex].setEntries(entries, for: environmentId)
        return updated
    }
}
```

- [ ] **Step 5: ProjectEditor kodunu yaz**

`Sources/EnvCore/Editing/ProjectEditor.swift`:

```swift
import Foundation

public struct ProjectEditor: Sendable {
    public enum EditError: Error, Equatable {
        case lastEnvironment
        case unknownEnvironment
        case unknownTarget
        case duplicateTarget(String)
    }

    let secrets: any SecretStore

    public init(secrets: any SecretStore) {
        self.secrets = secrets
    }

    public func addEnvironment(named name: String, color: EnvColor, to project: Project) -> Project {
        var updated = project
        updated.environments.append(EnvEnvironment(name: name, color: color))
        return updated
    }

    /// Changes name, color or protection. Secrets stay readable because accounts use ids.
    public func updateEnvironment(_ environment: EnvEnvironment, in project: Project) throws -> Project {
        guard let i = project.environments.firstIndex(where: { $0.id == environment.id }) else {
            throw EditError.unknownEnvironment
        }
        var updated = project
        updated.environments[i] = environment
        return updated
    }

    public func deleteEnvironment(id: UUID, from project: Project) throws -> Project {
        guard project.environments.contains(where: { $0.id == id }) else { throw EditError.unknownEnvironment }
        guard project.environments.count > 1 else { throw EditError.lastEnvironment }
        var updated = project
        updated.environments.removeAll { $0.id == id }
        for i in updated.targets.indices {
            try deleteSecrets(project: project, target: updated.targets[i], environmentId: id)
            updated.targets[i].values[id.uuidString] = nil
            if updated.targets[i].activeEnvironmentId == id {
                updated.targets[i].activeEnvironmentId = nil
            }
        }
        return updated
    }

    public func addTarget(relativePath: String, to project: Project) throws -> Project {
        guard !project.targets.contains(where: { $0.relativePath == relativePath }) else {
            throw EditError.duplicateTarget(relativePath)
        }
        var updated = project
        updated.targets.append(EnvTarget(relativePath: relativePath))
        return updated
    }

    public func removeTarget(id: UUID, from project: Project) throws -> Project {
        guard let target = project.targets.first(where: { $0.id == id }) else { throw EditError.unknownTarget }
        for environment in project.environments {
            try deleteSecrets(project: project, target: target, environmentId: environment.id)
        }
        var updated = project
        updated.targets.removeAll { $0.id == id }
        return updated
    }

    public func relocate(_ project: Project, to root: URL) -> Project {
        var updated = project
        updated.rootPath = root.standardizedFileURL.path
        return updated
    }

    public func deleteAllSecrets(of project: Project) throws {
        for target in project.targets {
            for environment in project.environments {
                try deleteSecrets(project: project, target: target, environmentId: environment.id)
            }
        }
    }

    private func deleteSecrets(project: Project, target: EnvTarget, environmentId: UUID) throws {
        for entry in target.entries(for: environmentId) where entry.isSecret {
            try secrets.delete(account: SecretAccount.make(
                projectId: project.id, targetId: target.id, environmentId: environmentId, key: entry.key))
        }
    }
}
```

- [ ] **Step 6: Testlerin geçtiğini gör**

Run: `swift test --filter "EntryEditorTests|ProjectEditorTests"`
Expected: PASS, 14 test.

`relocateChangesRootPath` başarısız olursa: `standardizedFileURL.path` sonda `/` bırakmaz. `/tmp` macOS'ta `/private/tmp` için bir symlink'tir, ama `standardizedFileURL` symlink çözmez. Beklenen değer `/tmp/moved` kalır.

- [ ] **Step 7: Commit**

```bash
git add Sources/EnvCore/Editing Tests/EnvCoreTests/EntryEditorTests.swift Tests/EnvCoreTests/ProjectEditorTests.swift
git commit -m "feat(core): add entry and project editors"
```

---

### Task 13: Kenar çubuğu ağacı (FileTree)

**Files:**
- Create: `Sources/EnvCore/Tree/FileTree.swift`
- Test: `Tests/EnvCoreTests/FileTreeTests.swift`

**Interfaces:**
- Consumes: `EnvTarget` (Task 1)
- Produces:
  - `struct FileTreeNode: Identifiable, Equatable, Sendable { id: String; name: String; targetId: UUID?; children: [FileTreeNode]? }` (dosya düğümünde `children == nil`)
  - `enum FileTree { static func build(_ targets: [EnvTarget]) -> [FileTreeNode] }`
  - Kural: klasörler önce, dosyalar sonra, ikisi de ada göre sıralı. İçinde yalnızca bir dosya olan ve alt klasörü olmayan bir klasör, `klasör/dosya` adıyla tek bir dosya düğümüne dönüşür.

- [ ] **Step 1: Başarısız testi yaz**

`Tests/EnvCoreTests/FileTreeTests.swift`:

```swift
import Foundation
import Testing
@testable import EnvCore

struct FileTreeTests {
    @Test func buildsTreeAndMergesSingleFileFolders() {
        let cart = EnvTarget(relativePath: "apps/cart/.env.local")
        let shellLocal = EnvTarget(relativePath: "apps/shell/.env.local")
        let shellExample = EnvTarget(relativePath: "apps/shell/.env.example")
        let rootEnv = EnvTarget(relativePath: ".env")

        let tree = FileTree.build([shellLocal, rootEnv, cart, shellExample])

        #expect(tree == [
            FileTreeNode(id: "apps", name: "apps", targetId: nil, children: [
                FileTreeNode(id: "apps/cart/.env.local", name: "cart/.env.local", targetId: cart.id, children: nil),
                FileTreeNode(id: "apps/shell", name: "shell", targetId: nil, children: [
                    FileTreeNode(id: "apps/shell/.env.example", name: ".env.example", targetId: shellExample.id, children: nil),
                    FileTreeNode(id: "apps/shell/.env.local", name: ".env.local", targetId: shellLocal.id, children: nil),
                ]),
            ]),
            FileTreeNode(id: ".env", name: ".env", targetId: rootEnv.id, children: nil),
        ])
    }

    @Test func emptyTargetsGiveEmptyTree() {
        #expect(FileTree.build([]).isEmpty)
    }
}
```

- [ ] **Step 2: Testin başarısız olduğunu gör**

Run: `swift test --filter FileTreeTests`
Expected: FAIL, `cannot find 'FileTree' in scope`.

- [ ] **Step 3: Kodu yaz**

`Sources/EnvCore/Tree/FileTree.swift`:

```swift
import Foundation

public struct FileTreeNode: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var targetId: UUID?
    /// nil for a file node.
    public var children: [FileTreeNode]?

    public init(id: String, name: String, targetId: UUID?, children: [FileTreeNode]?) {
        self.id = id
        self.name = name
        self.targetId = targetId
        self.children = children
    }
}

public enum FileTree {
    private final class Folder {
        var folders: [String: Folder] = [:]
        var files: [(name: String, id: UUID)] = []
    }

    public static func build(_ targets: [EnvTarget]) -> [FileTreeNode] {
        let root = Folder()
        for target in targets {
            var parts = target.relativePath.split(separator: "/").map(String.init)
            guard let fileName = parts.popLast() else { continue }
            var folder = root
            for part in parts {
                let next = folder.folders[part] ?? Folder()
                folder.folders[part] = next
                folder = next
            }
            folder.files.append((fileName, target.id))
        }
        return nodes(of: root, prefix: "")
    }

    private static func nodes(of folder: Folder, prefix: String) -> [FileTreeNode] {
        var result: [FileTreeNode] = []
        for name in folder.folders.keys.sorted() {
            let child = folder.folders[name]!
            let path = prefix + name
            if child.folders.isEmpty, child.files.count == 1 {
                let file = child.files[0]
                result.append(FileTreeNode(id: path + "/" + file.name, name: name + "/" + file.name, targetId: file.id, children: nil))
            } else {
                result.append(FileTreeNode(id: path, name: name, targetId: nil, children: nodes(of: child, prefix: path + "/")))
            }
        }
        for file in folder.files.sorted(by: { $0.name < $1.name }) {
            result.append(FileTreeNode(id: prefix + file.name, name: file.name, targetId: file.id, children: nil))
        }
        return result
    }
}
```

- [ ] **Step 4: Testin geçtiğini gör**

Run: `swift test --filter FileTreeTests`
Expected: PASS, 2 test.

- [ ] **Step 5: Tüm `EnvCore` testlerini çalıştır**

Run: `swift test`
Expected: PASS. Keychain testi "skipped" olur. Diğer tüm testler geçer.

- [ ] **Step 6: Commit**

```bash
git add Sources/EnvCore/Tree Tests/EnvCoreTests/FileTreeTests.swift
git commit -m "feat(core): add sidebar file tree builder"
```

---

## Arayüz görevleri (Task 14–21)

Bu görevlerde birim testi yok (spec 10.3). Her görevin doğrulaması iki adımdır:

1. `swift build` hatasız biter.
2. `scripts/bundle.sh && open build/EnvSwitcher.app` ile uygulama açılır ve görevdeki elle kontrol maddeleri doğru çalışır.

Her görevden sonra `swift test` yine geçmelidir.

---

### Task 14: Uygulama iskeleti, AppState ve paketleme

**Files:**
- Modify: `Package.swift`
- Modify: `.gitignore`
- Create: `Sources/EnvSwitcher/App/EnvSwitcherApp.swift`
- Create: `Sources/EnvSwitcher/App/AppState.swift`
- Create: `Sources/EnvSwitcher/App/Alerts.swift`
- Create: `Sources/EnvSwitcher/App/EnvColor+UI.swift`
- Create: `Sources/EnvSwitcher/MenuBar/MenuContent.swift`
- Create: `scripts/bundle.sh`

**Interfaces:**
- Consumes: tüm `EnvCore` (Task 1–13)
- Produces (sonraki arayüz görevleri bunları kullanır):
  - `enum WindowID { static let manager = "manager"; static let drift = "drift" }`
  - `enum SidebarSelection: Hashable { project(UUID), target(project: UUID, target: UUID) }`
  - `enum SwitchOutcome { completed, needsDriftReview, stopped }`
  - `enum DriftChoice { saveToCurrent(environmentIdByTarget: [UUID: UUID]), discard, cancel }`
  - `struct PendingDrift { projectId; scope: SwitchScope; environmentId; drifted: [DriftedTarget] }`
  - `@MainActor @Observable final class AppState`:
    - durum: `store: Store`, `driftByTarget: [UUID: DriftStatus]`, `pendingDrift: PendingDrift?`, `selection: SidebarSelection?`, `showAddProject: Bool`, `pendingAddURL: URL?`
    - bağımlılıklar: `repository`, `secrets: any SecretStore`, `files: any FileWriter`
    - servisler: `planner`, `switchService`, `entryEditor`, `projectEditor`
    - depo: `save()`, `project(id:) -> Project?`, `replace(_:)`, `apply(_ change: () throws -> Project)`, `updateSettings(_:)`, `deleteProject(_:)`
    - görünüm: `environmentName(_:in:) -> String`, `stateText(_:) -> String`, `stateColor(_:) -> NSColor`, `hasDrift(_:) -> Bool`, `rootExists(_:) -> Bool`, `menuBarTitle: String`, `menuBarDot: NSImage`, `refreshDrift()`
    - geçiş: `requestSwitch(projectId:scope:environmentId:) -> SwitchOutcome`, `resolveDrift(_ choice: DriftChoice)`
    - hata: `report(_ error: Error)`, `message(for:) -> String`
  - `@MainActor enum Alerts { confirmProtected(projectName:environmentName:fileCount:) -> Bool; showError(_:); showInfo(title:message:); offerRemoveMissing(_:) -> Bool; chooseCopyMode() -> EntryEditor.CopyMode? }`
  - `extension EnvColor { nsColor: NSColor; color: Color; title: String }`, `enum DotImage { static func make(_ color: NSColor, size: CGFloat = 8) -> NSImage }`

- [ ] **Step 1: Paket dosyasına uygulama hedefini ekle**

`Package.swift` dosyasının tamamını şu içerikle değiştir:

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "EnvSwitcher",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EnvCore", targets: ["EnvCore"]),
        .executable(name: "EnvSwitcher", targets: ["EnvSwitcher"]),
    ],
    targets: [
        .target(name: "EnvCore"),
        .executableTarget(
            name: "EnvSwitcher",
            dependencies: ["EnvCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "EnvCoreTests", dependencies: ["EnvCore"]),
    ]
)
```

`.gitignore` dosyasının sonuna şu satırı ekle:

```
build/
```

- [ ] **Step 2: Renk ve uyarı yardımcılarını yaz**

`Sources/EnvSwitcher/App/EnvColor+UI.swift`:

```swift
import AppKit
import EnvCore
import SwiftUI

extension EnvColor {
    var nsColor: NSColor {
        switch self {
        case .green: .systemGreen
        case .orange: .systemOrange
        case .red: .systemRed
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .gray: .systemGray
        }
    }

    var color: Color { Color(nsColor: nsColor) }

    var title: String {
        switch self {
        case .green: "Yeşil"
        case .orange: "Turuncu"
        case .red: "Kırmızı"
        case .blue: "Mavi"
        case .purple: "Mor"
        case .gray: "Gri"
        }
    }
}

/// A colored dot that keeps its color in the menu bar and in menus (not a template image).
enum DotImage {
    static func make(_ color: NSColor, size: CGFloat = 8) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
```

`Sources/EnvSwitcher/App/Alerts.swift`:

```swift
import AppKit
import EnvCore

/// Native NSAlert dialogs. They also work from the menu bar menu, where SwiftUI sheets cannot open.
@MainActor
enum Alerts {
    static func confirmProtected(projectName: String, environmentName: String, fileCount: Int) -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "\(projectName) projesi \(environmentName.uppercased()) ortamına geçecek."
        alert.informativeText = "\(fileCount) dosya değişecek."
        alert.addButton(withTitle: "Geç")
        alert.addButton(withTitle: "Vazgeç")
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func showError(_ message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "İşlem tamamlanmadı"
        alert.informativeText = message
        alert.addButton(withTitle: "Tamam")
        alert.runModal()
    }

    static func showInfo(title: String, message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Tamam")
        alert.runModal()
    }

    /// Returns true when the user chooses to remove the files from the project.
    static func offerRemoveMissing(_ message: String) -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Geçiş başlamadı"
        alert.informativeText = message
        alert.addButton(withTitle: "Tamam")
        alert.addButton(withTitle: "Dosyayı projeden çıkar")
        return alert.runModal() == .alertSecondButtonReturn
    }

    /// Returns nil when the user cancels.
    static func chooseCopyMode() -> EntryEditor.CopyMode? {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Aynı anahtar bu ortamda da varsa ne olsun?"
        alert.addButton(withTitle: "Üzerine yaz")
        alert.addButton(withTitle: "Atla")
        alert.addButton(withTitle: "Vazgeç")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .overwrite
        case .alertSecondButtonReturn: return .skipExisting
        default: return nil
        }
    }
}
```

- [ ] **Step 3: AppState yaz**

`Sources/EnvSwitcher/App/AppState.swift`:

```swift
import AppKit
import EnvCore
import SwiftUI

enum WindowID {
    static let manager = "manager"
    static let drift = "drift"
}

enum SidebarSelection: Hashable {
    case project(UUID)
    case target(project: UUID, target: UUID)
}

enum SwitchOutcome {
    case completed
    /// The caller must open the drift window.
    case needsDriftReview
    case stopped
}

enum DriftChoice {
    case saveToCurrent(environmentIdByTarget: [UUID: UUID])
    case discard
    case cancel
}

struct PendingDrift {
    let projectId: UUID
    let scope: SwitchScope
    let environmentId: UUID
    let drifted: [DriftedTarget]
}

@MainActor
@Observable
final class AppState {
    var store = Store()
    var driftByTarget: [UUID: DriftStatus] = [:]
    var pendingDrift: PendingDrift?
    var selection: SidebarSelection?
    var showAddProject = false
    var pendingAddURL: URL?

    let repository: StoreRepository
    let secrets: any SecretStore
    let files: any FileWriter

    init(
        repository: StoreRepository = StoreRepository(directory: StoreRepository.defaultDirectory),
        secrets: any SecretStore = KeychainSecretStore(),
        files: any FileWriter = LocalFileWriter()
    ) {
        self.repository = repository
        self.secrets = secrets
        self.files = files
        load()
        // Spec 6.1: check drift when the user opens the menu.
        NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDrift() }
        }
    }

    // MARK: Services

    var planner: SwitchPlanner { SwitchPlanner(secrets: secrets, files: files) }

    var switchService: SwitchService {
        SwitchService(
            planner: planner,
            executor: SwitchExecutor(files: files, recoveryDirectory: repository.directory.appendingPathComponent("recovery", isDirectory: true))
        )
    }

    var entryEditor: EntryEditor { EntryEditor(secrets: secrets) }
    var projectEditor: ProjectEditor { ProjectEditor(secrets: secrets) }

    // MARK: Store

    private func load() {
        do {
            let result = try repository.load()
            store = result.store
            if let notice = result.notice {
                DispatchQueue.main.async { Alerts.showInfo(title: "Depo geri yüklendi", message: Self.describe(notice)) }
            }
        } catch {
            report(error)
        }
    }

    func save() {
        do {
            try repository.save(store)
        } catch {
            report(error)
        }
    }

    func project(id: UUID) -> Project? {
        store.projects.first { $0.id == id }
    }

    func replace(_ project: Project) {
        if let i = store.projectIndex(id: project.id) {
            store.projects[i] = project
        } else {
            store.projects.append(project)
        }
        save()
    }

    func apply(_ change: () throws -> Project) {
        do {
            replace(try change())
        } catch {
            report(error)
        }
    }

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        change(&store.settings)
        save()
    }

    func deleteProject(_ project: Project) {
        do {
            try projectEditor.deleteAllSecrets(of: project)
        } catch {
            report(error)
            return
        }
        store.projects.removeAll { $0.id == project.id }
        if store.lastSwitchedProjectId == project.id { store.lastSwitchedProjectId = nil }
        selection = nil
        save()
    }

    // MARK: Display

    func environmentName(_ id: UUID?, in project: Project) -> String {
        id.flatMap { project.environment(id: $0) }?.name ?? "—"
    }

    func stateText(_ project: Project) -> String {
        switch project.displayState {
        case .none: "—"
        case .mixed: "karışık"
        case .single(let id): environmentName(id, in: project)
        }
    }

    func stateColor(_ project: Project) -> NSColor {
        if case .single(let id) = project.displayState, let environment = project.environment(id: id) {
            return environment.color.nsColor
        }
        return .systemGray
    }

    func hasDrift(_ project: Project) -> Bool {
        project.targets.contains { driftByTarget[$0.id] == .modified }
    }

    func rootExists(_ project: Project) -> Bool {
        files.directoryExists(project.rootURL)
    }

    private var labelProject: Project? {
        store.lastSwitchedProjectId.flatMap { project(id: $0) } ?? store.projects.first
    }

    var menuBarTitle: String {
        guard let project = labelProject else { return "EnvSwitcher" }
        return "\(project.name) · \(stateText(project))"
    }

    var menuBarDot: NSImage {
        DotImage.make(labelProject.map { stateColor($0) } ?? .systemGray)
    }

    func refreshDrift() {
        var result: [UUID: DriftStatus] = [:]
        for project in store.projects {
            for target in project.targets {
                let data = try? files.read(project.url(for: target))
                result[target.id] = DriftDetector.status(fileData: data, lastWrittenHash: target.lastWrittenHash)
            }
        }
        if result != driftByTarget { driftByTarget = result }
    }

    // MARK: Switching (spec section 6)

    @discardableResult
    func requestSwitch(projectId: UUID, scope: SwitchScope, environmentId: UUID) -> SwitchOutcome {
        guard let project = project(id: projectId) else { return .stopped }
        do {
            let preflight = try planner.preflight(project: project, scope: scope, environmentId: environmentId)
            if !preflight.missingDirectories.isEmpty {
                // Spec 8: the error names the files and offers "Dosyayı projeden çıkar".
                if Alerts.offerRemoveMissing(message(for: SwitchError.directoryMissing(preflight.missingDirectories))) {
                    let missing = Set(preflight.missingDirectories)
                    apply {
                        var updated = project
                        for target in project.targets where missing.contains(target.relativePath) {
                            updated = try projectEditor.removeTarget(id: target.id, from: updated)
                        }
                        return updated
                    }
                }
                return .stopped
            }
            if preflight.needsProtectedConfirmation,
               !Alerts.confirmProtected(projectName: project.name, environmentName: preflight.environment.name, fileCount: preflight.targetIds.count) {
                return .stopped
            }
            if !preflight.drifted.isEmpty {
                pendingDrift = PendingDrift(projectId: projectId, scope: scope, environmentId: environmentId, drifted: preflight.drifted)
                return .needsDriftReview
            }
            return commitSwitch(projectId: projectId, scope: scope, environmentId: environmentId)
        } catch {
            report(error)
            return .stopped
        }
    }

    func resolveDrift(_ choice: DriftChoice) {
        guard let pending = pendingDrift else { return }
        pendingDrift = nil
        switch choice {
        case .cancel:
            return
        case .discard:
            break
        case .saveToCurrent(let environmentIdByTarget):
            guard var project = project(id: pending.projectId) else { return }
            do {
                let resolver = DriftResolver(secrets: secrets)
                for drifted in pending.drifted {
                    guard let environmentId = environmentIdByTarget[drifted.targetId] else { continue }
                    project = try resolver.saveFile(drifted.fileContents, into: environmentId, targetId: drifted.targetId, project: project)
                }
                replace(project)
            } catch {
                report(error)
                return
            }
        }
        commitSwitch(projectId: pending.projectId, scope: pending.scope, environmentId: pending.environmentId)
    }

    @discardableResult
    private func commitSwitch(projectId: UUID, scope: SwitchScope, environmentId: UUID) -> SwitchOutcome {
        guard let project = project(id: projectId) else { return .stopped }
        do {
            let updated = try switchService.commit(project: project, scope: scope, environmentId: environmentId)
            store.lastSwitchedProjectId = projectId
            replace(updated)
            refreshDrift()
            return .completed
        } catch {
            report(error)
            return .stopped
        }
    }

    // MARK: Errors

    func report(_ error: Error) {
        Alerts.showError(message(for: error))
    }

    func message(for error: Error) -> String {
        switch error {
        case SwitchError.directoryMissing(let paths):
            return "Şu dosyaların klasörü yok: \(paths.joined(separator: ", ")). Dosyalar değişmedi."
        case SwitchError.writeFailed(let path, let reason):
            return "\(path) dosyası yazılamadı. Tüm dosyalar eski içeriğe döndü.\n\(reason)"
        case SwitchError.rollbackFailed(let paths, let folder):
            return "Şu dosyalar eski içeriğe dönemedi: \(paths.joined(separator: ", ")). Eski içerikler şu klasörde: \(folder.path)"
        case SwitchError.unknownEnvironment, SwitchError.unknownTarget:
            return "Ortam veya dosya bulunamadı. Pencereyi kapatıp yeniden açın."
        case SecretStoreError.keychain(let status):
            return "Keychain erişimi başarısız oldu (kod \(status))."
        case EntryEditor.EditError.duplicateKey(let key):
            return "\(key) anahtarı zaten var."
        case EntryEditor.EditError.invalidKey(let key):
            return "\"\(key)\" geçerli bir anahtar adı değil. Ad bir harf veya _ ile başlamalı."
        case ProjectEditor.EditError.lastEnvironment:
            return "Bir projede en az bir ortam olmalı."
        case ProjectEditor.EditError.duplicateTarget(let path):
            return "\(path) zaten projede var."
        default:
            return error.localizedDescription
        }
    }

    static func describe(_ notice: StoreLoadNotice) -> String {
        switch notice {
        case .restoredFromBackup:
            "store.json okunamadı. Uygulama son yedeği (store.json.bak) yükledi."
        case .resetAfterCorruption(let url):
            "store.json ve yedeği okunamadı. Uygulama boş bir depo ile açıldı. Bozuk dosya: \(url.path)"
        }
    }
}
```

- [ ] **Step 4: Uygulama girişini ve geçici menüyü yaz**

`Sources/EnvSwitcher/MenuBar/MenuContent.swift` (Task 15 bu dosyayı tamamen değiştirir):

```swift
import SwiftUI

struct MenuContent: View {
    var body: some View {
        Button("Çık") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
```

`Sources/EnvSwitcher/App/EnvSwitcherApp.swift`:

```swift
import SwiftUI

@main
struct EnvSwitcherApp: App {
    @State private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environment(state)
        } label: {
            Image(nsImage: state.menuBarDot)
            Text(state.menuBarTitle)
        }
        .menuBarExtraStyle(.menu)
    }
}
```

- [ ] **Step 5: Paketleme betiğini yaz**

`scripts/bundle.sh`:

```sh
#!/bin/sh
# Builds build/EnvSwitcher.app. Set CODESIGN_IDENTITY to sign with your own certificate
# (spec 2.2). Without it, the app gets an ad-hoc signature.
set -eu
cd "$(dirname "$0")/.."

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="build/EnvSwitcher.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/EnvSwitcher" "$APP/Contents/MacOS/EnvSwitcher"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.ahmetkorkmaz.envswitcher</string>
    <key>CFBundleName</key><string>EnvSwitcher</string>
    <key>CFBundleExecutable</key><string>EnvSwitcher</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign "${CODESIGN_IDENTITY:--}" "$APP"
echo "$APP"
```

Run: `chmod +x scripts/bundle.sh`

- [ ] **Step 6: Derle ve çalıştır**

Run: `swift build`
Expected: `Build complete!`

Run: `scripts/bundle.sh && open build/EnvSwitcher.app`
Expected, elle kontrol:
- Menü çubuğunda gri bir nokta ve `EnvSwitcher` metni görünür.
- Dock'ta simge yok.
- Menüde yalnızca "Çık" var. "Çık" uygulamayı kapatır.

- [ ] **Step 7: Commit**

```bash
git add Package.swift .gitignore Sources/EnvSwitcher scripts/bundle.sh
git commit -m "feat(app): add menu bar app shell, app state and bundling script"
```

---

### Task 15: Menü çubuğu menüsü

**Files:**
- Modify: `Sources/EnvSwitcher/MenuBar/MenuContent.swift` (tamamını değiştir)
- Create: `Sources/EnvSwitcher/MenuBar/ProjectMenu.swift`
- Create: `Sources/EnvSwitcher/App/FolderOpener.swift`
- Create: `Sources/EnvSwitcher/App/Panels.swift`

**Interfaces:**
- Consumes: `AppState`, `WindowID`, `SwitchOutcome`, `DotImage`, `Alerts` (Task 14), `SwitchScope` (Task 9), `ProjectEditor.relocate` (Task 12)
- Produces:
  - `@MainActor enum FolderOpener { static func finder(_ url: URL); static func reveal(_ fileURL: URL); static func terminal(_ url: URL, settings: AppSettings); static func editor(_ url: URL, settings: AppSettings, sampleFile: URL?) }`
  - `@MainActor enum Panels { static func chooseFolder() -> URL?; static func chooseApplication() -> URL? }`
  - `struct EnvironmentLabel: View { let environment: EnvEnvironment }`

- [ ] **Step 1: Klasör açıcı ve panelleri yaz**

`Sources/EnvSwitcher/App/FolderOpener.swift`:

```swift
import AppKit
import EnvCore

@MainActor
enum FolderOpener {
    static func finder(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func reveal(_ fileURL: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    static func terminal(_ url: URL, settings: AppSettings) {
        let app = settings.terminalAppPath.map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        open(url, with: app)
    }

    /// Without a setting, uses the app that opens .env files (spec 7.3).
    static func editor(_ url: URL, settings: AppSettings, sampleFile: URL?) {
        let app = settings.editorAppPath.map { URL(fileURLWithPath: $0) }
            ?? sampleFile.flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
            ?? URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        open(url, with: app)
    }

    private static func open(_ url: URL, with app: URL) {
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            guard let error else { return }
            Task { @MainActor in Alerts.showError(error.localizedDescription) }
        }
    }
}
```

`Sources/EnvSwitcher/App/Panels.swift`:

```swift
import AppKit
import UniformTypeIdentifiers

@MainActor
enum Panels {
    static func chooseFolder() -> URL? {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Seç"
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseApplication() -> URL? {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Seç"
        return panel.runModal() == .OK ? panel.url : nil
    }
}
```

- [ ] **Step 2: Proje alt menüsünü yaz**

`Sources/EnvSwitcher/MenuBar/ProjectMenu.swift`:

```swift
import EnvCore
import SwiftUI

struct EnvironmentLabel: View {
    let environment: EnvEnvironment

    var body: some View {
        Image(nsImage: DotImage.make(environment.color.nsColor))
        Text(environment.isProtected ? "\(environment.name) 🔒" : environment.name)
    }
}

struct ProjectMenu: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    let project: Project

    var body: some View {
        if state.rootExists(project) {
            Menu {
                Section("Tüm dosyalar") {
                    ForEach(project.environments) { environment in
                        Toggle(isOn: binding(environment, scope: .project)) {
                            EnvironmentLabel(environment: environment)
                        }
                    }
                }
                Section("Dosyalar") {
                    ForEach(project.targets) { target in
                        Menu {
                            ForEach(project.environments) { environment in
                                Toggle(isOn: binding(environment, scope: .target(target.id))) {
                                    EnvironmentLabel(environment: environment)
                                }
                            }
                        } label: {
                            Text("\(target.relativePath) — \(state.environmentName(target.activeEnvironmentId, in: project))")
                        }
                    }
                }
                Divider()
                Button("Finder'da Aç") { FolderOpener.finder(project.rootURL) }
                Button("Terminal'de Aç") { FolderOpener.terminal(project.rootURL, settings: state.store.settings) }
                Button("Editörde Aç") {
                    FolderOpener.editor(project.rootURL, settings: state.store.settings, sampleFile: project.targets.first.map { project.url(for: $0) })
                }
            } label: {
                Image(nsImage: DotImage.make(state.stateColor(project)))
                Text("\(project.name)\(state.hasDrift(project) ? " ⚠︎" : "") — \(state.stateText(project))")
            }
        } else {
            Menu {
                Button("Klasörü yeniden seç…") {
                    guard let url = Panels.chooseFolder() else { return }
                    state.apply { state.projectEditor.relocate(project, to: url) }
                }
            } label: {
                Text("\(project.name) — Klasör bulunamadı")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func binding(_ environment: EnvEnvironment, scope: SwitchScope) -> Binding<Bool> {
        Binding(
            get: { isActive(environment.id, scope: scope) },
            set: { _ in
                let outcome = state.requestSwitch(projectId: project.id, scope: scope, environmentId: environment.id)
                if outcome == .needsDriftReview {
                    openWindow(id: WindowID.drift)
                    NSApp.activate()
                }
            }
        )
    }

    private func isActive(_ environmentId: UUID, scope: SwitchScope) -> Bool {
        switch scope {
        case .project:
            return project.displayState == .single(environmentId)
        case .target(let targetId):
            return project.targets.first { $0.id == targetId }?.activeEnvironmentId == environmentId
        }
    }
}
```

- [ ] **Step 3: Menüyü yaz**

`Sources/EnvSwitcher/MenuBar/MenuContent.swift` dosyasının tamamını değiştir:

```swift
import SwiftUI

struct MenuContent: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ForEach(state.store.projects) { project in
            ProjectMenu(project: project)
        }
        if !state.store.projects.isEmpty {
            Divider()
        }
        Button("Proje Ekle…") {
            state.showAddProject = true
            openManager()
        }
        .keyboardShortcut("n")
        Button("Yönet…") { openManager() }
            .keyboardShortcut(",")
        Divider()
        Button("Çık") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func openManager() {
        openWindow(id: WindowID.manager)
        NSApp.activate()
    }
}
```

- [ ] **Step 4: Derle ve çalıştır**

Run: `swift build`
Expected: `Build complete!`

Run: `scripts/bundle.sh && open build/EnvSwitcher.app`
Expected, elle kontrol (henüz proje yok):
- Menüde "Proje Ekle…", "Yönet…" ve "Çık" var.
- "Proje Ekle…" ve "Yönet…" şimdilik bir pencere açmaz. Pencere Task 19'da gelir.

- [ ] **Step 5: Commit**

```bash
git add Sources/EnvSwitcher
git commit -m "feat(app): add menu bar menu with project and file switching"
```

---

### Task 16: Elle değişiklik penceresi

**Files:**
- Create: `Sources/EnvSwitcher/Drift/DriftView.swift`
- Modify: `Sources/EnvSwitcher/App/EnvSwitcherApp.swift` (tamamını değiştir)

**Interfaces:**
- Consumes: `AppState.pendingDrift`, `AppState.resolveDrift(_:)`, `DriftChoice`, `WindowID.drift` (Task 14), `DriftedTarget`, `EnvDiff` (Task 4, 9)
- Produces: `struct DriftView: View`

- [ ] **Step 1: Fark görünümünü yaz**

`Sources/EnvSwitcher/Drift/DriftView.swift`:

```swift
import EnvCore
import SwiftUI

struct DriftView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var environmentByTarget: [UUID: UUID] = [:]

    var body: some View {
        if let pending = state.pendingDrift, let project = state.project(id: pending.projectId) {
            VStack(alignment: .leading, spacing: 16) {
                Label("Elle değiştirilmiş dosyalar var", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .symbolRenderingMode(.multicolor)
                Text("Ortam değişmeden önce bu değişiklikler için bir seçim yapın. Değerler gösterilmez, yalnızca anahtarlar gösterilir.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(pending.drifted, id: \.targetId) { drifted in
                            DriftCard(drifted: drifted, project: project, environmentId: selection(for: drifted.targetId))
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button("İptal", role: .cancel) { finish(.cancel) }
                        .keyboardShortcut(.cancelAction)
                    Button("At ve geç", role: .destructive) { finish(.discard) }
                    Button("Mevcut ortama kaydet") { finish(.saveToCurrent(environmentIdByTarget: environmentByTarget)) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!pending.drifted.allSatisfy { environmentByTarget[$0.targetId] != nil })
                }
            }
            .padding(20)
            .frame(width: 560, height: 480)
            .onAppear { seed(pending, project: project) }
        } else {
            ContentUnavailableView("Bekleyen değişiklik yok", systemImage: "checkmark.circle")
                .frame(width: 400, height: 240)
        }
    }

    /// A modified file saves into its active environment by default. An unmanaged file has no default.
    private func seed(_ pending: PendingDrift, project: Project) {
        environmentByTarget = [:]
        for drifted in pending.drifted where drifted.status == .modified {
            if let active = project.targets.first(where: { $0.id == drifted.targetId })?.activeEnvironmentId {
                environmentByTarget[drifted.targetId] = active
            }
        }
    }

    private func selection(for targetId: UUID) -> Binding<UUID?> {
        Binding(
            get: { environmentByTarget[targetId] },
            set: { environmentByTarget[targetId] = $0 }
        )
    }

    private func finish(_ choice: DriftChoice) {
        dismissWindow(id: WindowID.drift)
        state.resolveDrift(choice)
    }
}

private struct DriftCard: View {
    let drifted: DriftedTarget
    let project: Project
    @Binding var environmentId: UUID?

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(drifted.diff.added, id: \.key) { Text("+ \($0.key)").foregroundStyle(.green) }
                ForEach(drifted.diff.changed, id: \.key) { Text("~ \($0.key)").foregroundStyle(.orange) }
                ForEach(drifted.diff.removed, id: \.self) { Text("− \($0)").foregroundStyle(.red) }
                if drifted.diff.isEmpty {
                    Text("Yalnızca biçim veya yorum satırları değişti.").foregroundStyle(.secondary)
                }
                Picker("Kaydedilecek ortam", selection: $environmentId) {
                    Text("Seçin").tag(UUID?.none)
                    ForEach(project.environments) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                .font(.body)
                .padding(.top, 6)
            }
            .font(.system(.body, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(drifted.relativePath).font(.headline)
        }
    }
}
```

- [ ] **Step 2: Pencereyi uygulamaya ekle**

`Sources/EnvSwitcher/App/EnvSwitcherApp.swift` dosyasının tamamını değiştir:

```swift
import SwiftUI

@main
struct EnvSwitcherApp: App {
    @State private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environment(state)
        } label: {
            Image(nsImage: state.menuBarDot)
            Text(state.menuBarTitle)
        }
        .menuBarExtraStyle(.menu)

        Window("Değişiklikler", id: WindowID.drift) {
            DriftView()
                .environment(state)
        }
        .windowResizability(.contentSize)
    }
}
```

- [ ] **Step 3: Derle**

Run: `swift build`
Expected: `Build complete!`

Elle kontrol bu görevde yapılamaz, çünkü henüz proje eklemenin bir yolu yok. Bu pencere Task 21'deki uçtan uca testte kontrol edilir.

- [ ] **Step 4: Commit**

```bash
git add Sources/EnvSwitcher
git commit -m "feat(app): add drift review window"
```

---

### Task 17: Dosya düzenleme görünümü (TargetDetailView)

**Files:**
- Create: `Sources/EnvSwitcher/Window/TargetDetailView.swift`

**Interfaces:**
- Consumes: `AppState` (`apply`, `entryEditor`, `project(id:)`, `requestSwitch`, `environmentName`), `Alerts.chooseCopyMode`, `FolderOpener.reveal`, `WindowID` (Task 14–15), `EntryEditor` (Task 12), `SwitchPlanner.header`, `DotEnvSerializer` (Task 3, 9)
- Produces: `struct TargetDetailView: View { init(project: Project, target: EnvTarget) }`

- [ ] **Step 1: Görünümü yaz**

`Sources/EnvSwitcher/Window/TargetDetailView.swift`:

```swift
import EnvCore
import SwiftUI

private struct EditableRow: Identifiable, Equatable {
    var id: String { key }
    var key: String
    var value: String
    var isSecret: Bool
    var isRevealed = false
}

private struct ReloadKey: Hashable {
    let targetId: UUID
    let environmentId: UUID
}

struct TargetDetailView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    let project: Project
    let target: EnvTarget

    @State private var editingEnvironmentId: UUID?
    @State private var rows: [EditableRow] = []
    @State private var selectedKeys = Set<String>()
    @State private var showPreview = false

    /// The project and target from the store. The init values can be one edit old.
    private var currentProject: Project { state.project(id: project.id) ?? project }
    private var currentTarget: EnvTarget { currentProject.targets.first { $0.id == target.id } ?? target }

    /// The edited environment. Falls back to the disk environment, then the first one,
    /// when the chosen environment no longer exists.
    private var environmentId: UUID {
        let project = currentProject
        for candidate in [editingEnvironmentId, currentTarget.activeEnvironmentId] {
            if let id = candidate, project.environment(id: id) != nil { return id }
        }
        return project.environments[0].id
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Table(rows, selection: $selectedKeys) {
                TableColumn("Anahtar") { row in
                    KeyField(key: row.key) { rename(row.key, to: $0) }
                }
                TableColumn("Değer") { row in
                    ValueField(
                        row: row,
                        onChange: { setValue($0, for: row.key) },
                        onReveal: { toggleReveal(row.key) }
                    )
                }
                TableColumn("Gizli") { row in
                    Toggle("", isOn: Binding(get: { row.isSecret }, set: { setSecret($0, for: row.key) }))
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                        .help("Değeri Keychain'de sakla")
                }
                .width(44)
            }
            .font(.system(.body, design: .monospaced))
            Divider()
            bottomBar
        }
        .navigationTitle(currentTarget.relativePath)
        .navigationSubtitle("\(currentProject.name) · diskte: \(state.environmentName(currentTarget.activeEnvironmentId, in: currentProject))")
        .toolbar { toolbar }
        .task(id: ReloadKey(targetId: target.id, environmentId: environmentId)) { reload() }
        .sheet(isPresented: $showPreview) { preview }
    }

    // MARK: Parts

    private var header: some View {
        HStack {
            Picker("Düzenlenen ortam", selection: Binding(get: { environmentId }, set: { editingEnvironmentId = $0 })) {
                ForEach(currentProject.environments) { environment in
                    Text(environment.isProtected ? "\(environment.name) 🔒" : environment.name).tag(environment.id)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer()
            if environmentId == currentTarget.activeEnvironmentId {
                Label("Değişiklikleri diske yazmak için Bu ortama geç düğmesine basın.", systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { FolderOpener.reveal(currentProject.url(for: currentTarget)) } label: {
                Label("Finder'da göster", systemImage: "folder")
            }
            Button { showPreview = true } label: {
                Label(".env önizle", systemImage: "eye")
            }
            Button {
                let outcome = state.requestSwitch(projectId: project.id, scope: .target(target.id), environmentId: environmentId)
                if outcome == .needsDriftReview { openWindow(id: WindowID.drift) }
            } label: {
                Label("Bu ortama geç", systemImage: "arrow.triangle.2.circlepath")
            }
            .help("Yalnızca bu dosyayı seçili ortama geçirir")
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Button { addRow() } label: { Image(systemName: "plus") }
                .help("Anahtar ekle")
            Button { removeSelected() } label: { Image(systemName: "minus") }
                .disabled(selectedKeys.isEmpty)
                .help("Seçili anahtarları sil")
            Spacer()
            Menu("Diğer ortamdan kopyala") {
                ForEach(currentProject.environments.filter { $0.id != environmentId }) { environment in
                    Button(environment.name) { copy(from: environment.id) }
                }
            }
            .fixedSize()
        }
        .buttonStyle(.borderless)
        .padding(8)
    }

    private var preview: some View {
        let environment = currentProject.environment(id: environmentId)!
        let pairs = rows.map { DotEnvPair(key: $0.key, value: $0.isSecret ? "••••••••" : $0.value) }
        let text = DotEnvSerializer.serialize(pairs, headerLines: SwitchPlanner.header(project: currentProject, environment: environment))
        return VStack(alignment: .leading, spacing: 12) {
            Text("\(currentTarget.relativePath) · \(environment.name)").font(.headline)
            ScrollView {
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("Kapat") { showPreview = false }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560, height: 420)
    }

    // MARK: Actions

    private func reload() {
        let project = currentProject
        rows = currentTarget.entries(for: environmentId).map { entry in
            let value = (try? state.entryEditor.readValue(key: entry.key, in: project, targetId: target.id, environmentId: environmentId)) ?? ""
            return EditableRow(key: entry.key, value: value, isSecret: entry.isSecret)
        }
        selectedKeys = []
    }

    private func setValue(_ value: String, for key: String) {
        if let i = rows.firstIndex(where: { $0.key == key }) { rows[i].value = value }
        state.apply { try state.entryEditor.setValue(value, key: key, in: currentProject, targetId: target.id, environmentId: environmentId) }
    }

    private func setSecret(_ isSecret: Bool, for key: String) {
        state.apply { try state.entryEditor.setSecret(isSecret, key: key, in: currentProject, targetId: target.id, environmentId: environmentId) }
        reload()
    }

    private func rename(_ oldKey: String, to newKey: String) {
        state.apply { try state.entryEditor.renameKey(oldKey, to: newKey, in: currentProject, targetId: target.id, environmentId: environmentId) }
        reload()
    }

    private func toggleReveal(_ key: String) {
        if let i = rows.firstIndex(where: { $0.key == key }) { rows[i].isRevealed.toggle() }
    }

    private func addRow() {
        let existing = Set(rows.map(\.key))
        var n = 1
        while existing.contains("YENI_ANAHTAR_\(n)") { n += 1 }
        let key = "YENI_ANAHTAR_\(n)"
        state.apply { try state.entryEditor.addEntry(key: key, in: currentProject, targetId: target.id, environmentId: environmentId) }
        reload()
    }

    private func removeSelected() {
        let keys = selectedKeys
        state.apply {
            var project = currentProject
            for key in keys {
                project = try state.entryEditor.removeEntry(key: key, in: project, targetId: target.id, environmentId: environmentId)
            }
            return project
        }
        reload()
    }

    private func copy(from source: UUID) {
        guard let mode = Alerts.chooseCopyMode() else { return }
        state.apply { try state.entryEditor.copyEntries(from: source, to: environmentId, targetId: target.id, mode: mode, in: currentProject) }
        reload()
    }
}

/// Renames the key on Return, so a half-typed key never reaches the store.
private struct KeyField: View {
    let key: String
    let onCommit: (String) -> Void
    @State private var draft = ""

    var body: some View {
        TextField("ANAHTAR", text: $draft)
            .onSubmit { if draft != key { onCommit(draft) } }
            .onAppear { draft = key }
            .onChange(of: key) { draft = key }
    }
}

/// Saves the value on every change.
private struct ValueField: View {
    let row: EditableRow
    let onChange: (String) -> Void
    let onReveal: () -> Void
    @State private var draft = ""

    var body: some View {
        HStack(spacing: 4) {
            if row.isSecret && !row.isRevealed {
                SecureField("", text: $draft)
            } else {
                TextField("", text: $draft)
            }
            if row.isSecret {
                Button(action: onReveal) {
                    Image(systemName: row.isRevealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(row.isRevealed ? "Değeri gizle" : "Değeri göster")
            }
        }
        .onAppear { draft = row.value }
        .onChange(of: row.value) { draft = row.value }
        .onChange(of: draft) { if draft != row.value { onChange(draft) } }
    }
}
```

- [ ] **Step 2: Derle**

Run: `swift build`
Expected: `Build complete!` Görünüm Task 19'da pencereye bağlanır ve orada elle kontrol edilir.

- [ ] **Step 3: Commit**

```bash
git add Sources/EnvSwitcher/Window/TargetDetailView.swift
git commit -m "feat(app): add target detail editor"
```

---

### Task 18: Proje ekleme sheet'i

**Files:**
- Create: `Sources/EnvSwitcher/Sheets/AddProjectSheet.swift`

**Interfaces:**
- Consumes: `AppState` (`pendingAddURL`, `replace`, `selection`, `secrets`, `report`), `Panels.chooseFolder`, `Alerts.showInfo` (Task 14–15), `ProjectScanner`, `ScannedFile`, `GitIgnoreChecker` (Task 7), `ProjectImporter`, `ImportResult` (Task 8), `DotEnvWarning` (Task 2)
- Produces: `struct AddProjectSheet: View`

- [ ] **Step 1: Sheet'i yaz**

`Sources/EnvSwitcher/Sheets/AddProjectSheet.swift`:

```swift
import EnvCore
import SwiftUI

struct AddProjectSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var root: URL?
    @State private var name = ""
    @State private var files: [ScannedFile] = []
    @State private var selected = Set<String>()
    @State private var environments = EnvEnvironment.defaults()
    @State private var importEnvironmentId: UUID?
    @State private var newEnvironmentName = ""
    @State private var trackedFiles: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Proje Ekle").font(.title2.bold())
            Text("Bir klasörü buraya sürükleyin veya seçin. Uygulama .env dosyalarını otomatik bulur.")
                .foregroundStyle(.secondary)
            dropZone
            if root != nil {
                fileList
                form
            }
            if !trackedFiles.isEmpty {
                Label(
                    "Bu dosyalar git tarafından izleniyor. canli değerler commit'e girebilir: \(trackedFiles.joined(separator: ", "))",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .symbolRenderingMode(.multicolor)
                .font(.callout)
            }
            HStack {
                Spacer()
                Button("Vazgeç", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Ekle") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdd)
            }
        }
        .padding(20)
        .frame(width: 540)
        .onAppear {
            importEnvironmentId = environments.first?.id
            if let url = state.pendingAddURL {
                state.pendingAddURL = nil
                choose(url)
            }
        }
        .onChange(of: selected) { checkGitIgnore() }
    }

    // MARK: Parts

    private var dropZone: some View {
        HStack {
            Image(systemName: "folder")
            Text(root?.path(percentEncoded: false) ?? "Klasör seçilmedi")
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button(root == nil ? "Seç…" : "Değiştir…") {
                if let url = Panels.chooseFolder() { choose(url) }
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .foregroundStyle(.tertiary)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            choose(url)
            return true
        }
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Bulunan dosyalar (\(files.count))").font(.headline)
            List(files, id: \.relativePath) { file in
                Toggle(isOn: selectionBinding(file.relativePath)) {
                    HStack {
                        Text(file.relativePath).font(.system(.body, design: .monospaced))
                        Spacer()
                        Text("\(file.keyCount) anahtar").foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(height: 200)
        }
    }

    private var form: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                Text("Proje adı").gridColumnAlignment(.trailing)
                TextField("", text: $name)
            }
            GridRow {
                Text("Ortamlar")
                HStack(spacing: 6) {
                    ForEach(environments) { environment in
                        Text(environment.isProtected ? "\(environment.name) 🔒" : environment.name)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(environment.color.color.opacity(0.18), in: Capsule())
                            .contextMenu {
                                Button("Sil", role: .destructive) { removeEnvironment(environment.id) }
                                    .disabled(environments.count == 1)
                            }
                    }
                    TextField("yeni ortam", text: $newEnvironmentName)
                        .frame(width: 100)
                        .onSubmit(addEnvironment)
                }
            }
            GridRow {
                Text("Mevcut içerik")
                HStack {
                    Picker("", selection: $importEnvironmentId) {
                        ForEach(environments) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Text("ortamına aktarılsın")
                }
            }
        }
    }

    // MARK: Logic

    private var canAdd: Bool {
        root != nil && !selected.isEmpty && importEnvironmentId != nil
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func selectionBinding(_ path: String) -> Binding<Bool> {
        Binding(
            get: { selected.contains(path) },
            set: { isOn in
                if isOn { selected.insert(path) } else { selected.remove(path) }
            }
        )
    }

    private func choose(_ url: URL) {
        root = url
        name = url.lastPathComponent
        files = ProjectScanner.scan(root: url)
        selected = Set(files.filter(\.isSelectedByDefault).map(\.relativePath))
        checkGitIgnore()
    }

    private func checkGitIgnore() {
        guard let root else { trackedFiles = []; return }
        trackedFiles = files.map(\.relativePath)
            .filter { selected.contains($0) && GitIgnoreChecker.isIgnored(relativePath: $0, root: root) == false }
    }

    private func addEnvironment() {
        let trimmed = newEnvironmentName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !environments.contains(where: { $0.name == trimmed }) else { return }
        environments.append(EnvEnvironment(name: trimmed, color: .blue))
        newEnvironmentName = ""
    }

    private func removeEnvironment(_ id: UUID) {
        guard environments.count > 1 else { return }
        environments.removeAll { $0.id == id }
        if importEnvironmentId == id { importEnvironmentId = environments.first?.id }
    }

    private func add() {
        guard let root, let environmentId = importEnvironmentId else { return }
        let paths = files.map(\.relativePath).filter(selected.contains)
        do {
            let result = try ProjectImporter(secrets: state.secrets).makeProject(
                name: name.trimmingCharacters(in: .whitespaces),
                root: root,
                relativePaths: paths,
                environments: environments,
                importInto: environmentId
            )
            state.replace(result.project)
            state.selection = .project(result.project.id)
            dismiss()
            if !result.warnings.isEmpty {
                Alerts.showInfo(title: "Bazı satırlar okunamadı", message: Self.describe(result.warnings))
            }
        } catch {
            state.report(error)
        }
    }

    private static func describe(_ warnings: [String: [DotEnvWarning]]) -> String {
        warnings.keys.sorted().map { path in
            let lines = warnings[path]!.map { warning -> String in
                switch warning {
                case .invalidLine(let line): "satır \(line): okunamadı"
                case .unterminatedQuote(let line): "satır \(line): tırnak kapanmıyor"
                case .duplicateKey(let key, let line): "satır \(line): \(key) iki kez var, son değer kullanıldı"
                }
            }
            return "\(path)\n  " + lines.joined(separator: "\n  ")
        }
        .joined(separator: "\n\n")
    }
}
```

- [ ] **Step 2: Derle**

Run: `swift build`
Expected: `Build complete!` Sheet Task 19'da pencereye bağlanır ve orada elle kontrol edilir.

- [ ] **Step 3: Commit**

```bash
git add Sources/EnvSwitcher/Sheets
git commit -m "feat(app): add project import sheet with scan and git ignore warning"
```

---

### Task 19: Düzenleme penceresi (kenar çubuğu ve proje ayarları)

**Files:**
- Create: `Sources/EnvSwitcher/Window/ManagerWindow.swift`
- Create: `Sources/EnvSwitcher/Window/Sidebar.swift`
- Create: `Sources/EnvSwitcher/Window/ProjectSettingsView.swift`
- Modify: `Sources/EnvSwitcher/App/EnvSwitcherApp.swift` (tamamını değiştir)

**Interfaces:**
- Consumes: `AppState`, `SidebarSelection`, `Panels`, `EnvColor+UI` (Task 14–15), `TargetDetailView` (Task 17), `AddProjectSheet` (Task 18), `FileTree` (Task 13), `ProjectEditor` (Task 12), `ProjectScanner` (Task 7)
- Produces: `struct ManagerWindow: View`, `struct Sidebar: View`, `struct ProjectSettingsView: View { init(project: Project) }`

- [ ] **Step 1: Kenar çubuğunu yaz**

`Sources/EnvSwitcher/Window/Sidebar.swift`:

```swift
import EnvCore
import SwiftUI

struct Sidebar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        List(selection: $state.selection) {
            Section("Projeler") {
                ForEach(state.store.projects) { project in
                    DisclosureGroup {
                        OutlineGroup(FileTree.build(project.targets), children: \.children) { node in
                            FileRow(node: node, project: project)
                                .tag(node.targetId.map { SidebarSelection.target(project: project.id, target: $0) })
                        }
                    } label: {
                        Label {
                            HStack {
                                Text(project.name)
                                Spacer()
                                if state.hasDrift(project) {
                                    Image(systemName: "exclamationmark.triangle.fill").symbolRenderingMode(.multicolor)
                                }
                                Text(state.stateText(project)).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: state.rootExists(project) ? "folder" : "questionmark.folder")
                        }
                        .tag(SidebarSelection?.some(.project(project.id)))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Button { state.showAddProject = true } label: {
                Label("Proje Ekle", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            state.pendingAddURL = url
            state.showAddProject = true
            return true
        }
    }
}

private struct FileRow: View {
    @Environment(AppState.self) private var state
    let node: FileTreeNode
    let project: Project

    var body: some View {
        if let targetId = node.targetId, let target = project.targets.first(where: { $0.id == targetId }) {
            Label {
                HStack {
                    Text(node.name)
                    Spacer()
                    if state.driftByTarget[targetId] == .modified {
                        Image(systemName: "exclamationmark.triangle.fill").symbolRenderingMode(.multicolor)
                    }
                    if let environment = target.activeEnvironmentId.flatMap({ project.environment(id: $0) }) {
                        Circle().fill(environment.color.color).frame(width: 8, height: 8)
                            .help("Diskteki ortam: \(environment.name)")
                    }
                }
            } icon: {
                Image(systemName: "doc.text")
            }
        } else {
            Label(node.name, systemImage: "folder")
        }
    }
}
```

- [ ] **Step 2: Proje ayarları görünümünü yaz**

`Sources/EnvSwitcher/Window/ProjectSettingsView.swift`:

```swift
import EnvCore
import SwiftUI

struct ProjectSettingsView: View {
    @Environment(AppState.self) private var state
    let project: Project
    @State private var newFiles: [ScannedFile] = []
    @State private var confirmDelete = false

    private var current: Project { state.project(id: project.id) ?? project }

    var body: some View {
        Form {
            Section("Proje") {
                TextField("Ad", text: Binding(
                    get: { current.name },
                    set: { name in state.apply { var p = current; p.name = name; return p } }
                ))
                LabeledContent("Kök klasör") {
                    HStack {
                        Text(current.rootPath)
                            .foregroundStyle(state.rootExists(current) ? .secondary : Color.red)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button(state.rootExists(current) ? "Değiştir…" : "Klasörü yeniden seç…") {
                            guard let url = Panels.chooseFolder() else { return }
                            state.apply { state.projectEditor.relocate(current, to: url) }
                        }
                    }
                }
            }

            Section("Ortamlar") {
                ForEach(current.environments) { environment in
                    EnvironmentRow(project: current, environment: environment)
                }
                Button {
                    state.apply { state.projectEditor.addEnvironment(named: "yeni", color: .blue, to: current) }
                } label: {
                    Label("Ortam ekle", systemImage: "plus")
                }
            }

            Section("Hedef dosyalar") {
                ForEach(current.targets) { target in
                    HStack {
                        Text(target.relativePath).font(.system(.body, design: .monospaced))
                        Spacer()
                        Button(role: .destructive) {
                            state.apply { try state.projectEditor.removeTarget(id: target.id, from: current) }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Dosyayı projeden çıkar. Diskteki dosya değişmez.")
                    }
                }
                Menu("Dosya ekle") {
                    if newFiles.isEmpty {
                        Text("Eklenecek yeni .env dosyası yok")
                    }
                    ForEach(newFiles, id: \.relativePath) { file in
                        Button(file.relativePath) {
                            state.apply { try state.projectEditor.addTarget(relativePath: file.relativePath, to: current) }
                            loadNewFiles()
                        }
                    }
                }
                .fixedSize()
            }

            Section {
                Button("Projeyi sil", role: .destructive) { confirmDelete = true }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(current.name)
        .task(id: project.id) { loadNewFiles() }
        .confirmationDialog("\(current.name) silinsin mi?", isPresented: $confirmDelete) {
            Button("Sil", role: .destructive) { state.deleteProject(current) }
        } message: {
            Text("Kayıtlı değerler ve Keychain kayıtları silinir. Diskteki .env dosyaları değişmez.")
        }
    }

    private func loadNewFiles() {
        let known = Set(current.targets.map(\.relativePath))
        newFiles = ProjectScanner.scan(root: current.rootURL).filter { !known.contains($0.relativePath) }
    }
}

private struct EnvironmentRow: View {
    @Environment(AppState.self) private var state
    let project: Project
    let environment: EnvEnvironment

    var body: some View {
        HStack {
            TextField("Ad", text: binding(\.name))
                .labelsHidden()
                .frame(maxWidth: 160)
            Picker("Renk", selection: binding(\.color)) {
                ForEach(EnvColor.allCases, id: \.self) { color in
                    Label { Text(color.title) } icon: { Image(nsImage: DotImage.make(color.nsColor)) }
                        .tag(color)
                }
            }
            .labelsHidden()
            .fixedSize()
            Toggle("Korumalı", isOn: binding(\.isProtected))
            Spacer()
            Button(role: .destructive) {
                state.apply { try state.projectEditor.deleteEnvironment(id: environment.id, from: project) }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Ortamı ve değerlerini sil")
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<EnvEnvironment, Value>) -> Binding<Value> {
        Binding(
            get: { environment[keyPath: keyPath] },
            set: { value in
                var updated = environment
                updated[keyPath: keyPath] = value
                state.apply { try state.projectEditor.updateEnvironment(updated, in: project) }
            }
        )
    }
}
```

- [ ] **Step 3: Pencereyi yaz**

`Sources/EnvSwitcher/Window/ManagerWindow.swift`:

```swift
import EnvCore
import SwiftUI

struct ManagerWindow: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            detail
        }
        .sheet(isPresented: $state.showAddProject) {
            AddProjectSheet()
        }
        .onAppear { state.refreshDrift() }
    }

    @ViewBuilder
    private var detail: some View {
        switch state.selection {
        case .project(let id)?:
            if let project = state.project(id: id) {
                ProjectSettingsView(project: project).id(project.id)
            }
        case .target(let projectId, let targetId)?:
            if let project = state.project(id: projectId), let target = project.targets.first(where: { $0.id == targetId }) {
                TargetDetailView(project: project, target: target).id(target.id)
            }
        case nil:
            ContentUnavailableView(
                "Bir dosya seçin",
                systemImage: "doc.text",
                description: Text("Soldaki listeden bir proje veya .env dosyası seçin.")
            )
        }
    }
}
```

- [ ] **Step 4: Pencereyi uygulamaya ekle**

`Sources/EnvSwitcher/App/EnvSwitcherApp.swift` dosyasının tamamını değiştir:

```swift
import SwiftUI

@main
struct EnvSwitcherApp: App {
    @State private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environment(state)
        } label: {
            Image(nsImage: state.menuBarDot)
            Text(state.menuBarTitle)
        }
        .menuBarExtraStyle(.menu)

        Window("EnvSwitcher", id: WindowID.manager) {
            ManagerWindow()
                .environment(state)
        }
        .defaultSize(width: 920, height: 580)

        Window("Değişiklikler", id: WindowID.drift) {
            DriftView()
                .environment(state)
        }
        .windowResizability(.contentSize)
    }
}
```

- [ ] **Step 5: Derle ve çalıştır**

Run: `swift build`
Expected: `Build complete!`

Run: `scripts/bundle.sh && open build/EnvSwitcher.app`
Expected, elle kontrol (geçici bir kopya kullanın, gerçek repoyu kullanmayın):
1. Bir test klasörü hazırlayın: `mkdir -p /tmp/envtest/apps/a /tmp/envtest/apps/b && printf 'A=1\nAPI_TOKEN=x\n' > /tmp/envtest/apps/a/.env.local && printf 'B=2\n' > /tmp/envtest/apps/b/.env.local`
2. Menüden "Proje Ekle…" seçin. Pencere ve sheet açılır.
3. `/tmp/envtest` klasörünü seçin. 2 dosya seçili gelir. "Ekle" düğmesine basın.
4. Kenar çubuğunda `envtest > apps > a/.env.local, b/.env.local` ağacı görünür.
5. `a/.env.local` seçin. `API_TOKEN` gizli ve maskeli görünür. Göz simgesi değeri gösterir.
6. `test` segmentini seçin, "＋" ile bir anahtar ekleyin, değerini yazın.
7. Proje satırını seçin. Ortam adı, rengi ve "Korumalı" ayarı değişir ve kaydedilir.

- [ ] **Step 6: Commit**

```bash
git add Sources/EnvSwitcher
git commit -m "feat(app): add manager window with sidebar tree and project settings"
```

---

### Task 20: Ayarlar penceresi

**Files:**
- Create: `Sources/EnvSwitcher/Settings/SettingsView.swift`
- Modify: `Sources/EnvSwitcher/App/EnvSwitcherApp.swift` (`Settings` sahnesini ekle)
- Modify: `Sources/EnvSwitcher/MenuBar/MenuContent.swift` ("Ayarlar…" bağlantısını ekle)

**Interfaces:**
- Consumes: `AppState.updateSettings`, `Panels.chooseApplication` (Task 14–15)
- Produces: `struct SettingsView: View`

- [ ] **Step 1: Ayarlar görünümünü yaz**

`Sources/EnvSwitcher/Settings/SettingsView.swift`:

```swift
import EnvCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Form {
            applicationRow(
                title: "Editör",
                path: state.store.settings.editorAppPath,
                placeholder: ".env dosyalarını açan uygulama"
            ) { path in state.updateSettings { $0.editorAppPath = path } }
            applicationRow(
                title: "Terminal",
                path: state.store.settings.terminalAppPath,
                placeholder: "Terminal"
            ) { path in state.updateSettings { $0.terminalAppPath = path } }
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }

    private func applicationRow(title: String, path: String?, placeholder: String, onChange: @escaping (String?) -> Void) -> some View {
        LabeledContent(title) {
            HStack {
                Text(path.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? placeholder)
                    .foregroundStyle(.secondary)
                Button("Seç…") {
                    if let url = Panels.chooseApplication() { onChange(url.path) }
                }
                if path != nil {
                    Button("Sıfırla") { onChange(nil) }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Ayarları uygulamaya ve menüye bağla**

`Sources/EnvSwitcher/App/EnvSwitcherApp.swift` içinde `Window("Değişiklikler", ...)` bloğundan sonra, `body` kapanmadan önce şunu ekle:

```swift

        Settings {
            SettingsView()
                .environment(state)
        }
```

`Sources/EnvSwitcher/MenuBar/MenuContent.swift` içinde şu satırları:

```swift
        Button("Yönet…") { openManager() }
            .keyboardShortcut(",")
```

şu satırlarla değiştir:

```swift
        Button("Yönet…") { openManager() }
            .keyboardShortcut("m")
        SettingsLink { Text("Ayarlar…") }
            .keyboardShortcut(",")
```

Not: Bu değişiklik plan başındaki "Spec'ten sapmalar" listesinde yazılıdır.

- [ ] **Step 3: Derle ve çalıştır**

Run: `swift build`
Expected: `Build complete!`

Run: `scripts/bundle.sh && open build/EnvSwitcher.app`
Expected, elle kontrol:
1. Menüde "Ayarlar…" var ve ayarlar penceresini açar.
2. Editör olarak bir uygulama seçin (örnek: VS Code). Menüden bir projenin "Editörde Aç" komutu klasörü o uygulamada açar.
3. "Sıfırla" seçimi kaldırır. Uygulamayı kapatıp açın: ayar korunur.

- [ ] **Step 4: Commit**

```bash
git add Sources/EnvSwitcher
git commit -m "feat(app): add settings for editor and terminal apps"
```

---

### Task 21: Elle test listesi, README ve uçtan uca kontrol

**Files:**
- Create: `docs/manual-test.md`
- Create: `README.md`

**Interfaces:**
- Consumes: tüm uygulama
- Produces: belgeler

- [ ] **Step 1: Elle test listesini yaz**

`docs/manual-test.md`:

````markdown
# EnvSwitcher elle test listesi

Her sürümden önce bu listeyi uygulayın. Gerçek bir repo yerine bir kopya kullanın.

## Hazırlık

```sh
rm -rf /tmp/karaca-copy
rsync -a --exclude node_modules --exclude .git --exclude .next --exclude .turbo \
  ~/work/karaca/karaca-storefront/ /tmp/karaca-copy/
scripts/bundle.sh && open build/EnvSwitcher.app
```

## 1. Uçtan uca geçiş (spec 10.3, ilk madde)

1. Menüden "Proje Ekle…" seçin ve `/tmp/karaca-copy` klasörünü seçin.
   - Beklenen: 9 `.env.local` dosyası seçili, `.env.example` dosyaları seçili değil.
   - Beklenen: `.claude/worktrees` altındaki dosyalar listede yok.
2. "Ekle" düğmesine basın. Menü çubuğu `karaca-copy · local` gösterir.
3. Pencerede `apps/cart/.env.local` seçin, `test` segmentine geçin, "Diğer ortamdan kopyala → local" seçin, sonra `NEXT_PUBLIC_APP_ENV` değerini `test` yapın. Diğer 8 dosya için de "Diğer ortamdan kopyala → local" uygulayın.
4. Menüden projeyi açın, "Tüm dosyalar → test" seçin.
   - Beklenen: 9 dosyanın hepsi yeniden yazılır. `apps/cart/.env.local` içinde `NEXT_PUBLIC_APP_ENV=test` var.
   - Beklenen: menü çubuğu `karaca-copy · test` gösterir.
5. Menüden "Dosyalar → apps/checkout/.env.local → canli" seçin.
   - Beklenen: Korumalı ortam onayı çıkar: "1 dosya değişecek." "Geç" düğmesine basın.
   - Beklenen: menü çubuğu `karaca-copy · karışık` gösterir.
6. Menüden "Tüm dosyalar → local" seçin.
   - Beklenen: tüm dosyalar `local` olur. Menü çubuğu `karaca-copy · local` gösterir.

## 2. Elle değişiklik

1. `apps/cart/.env.local` dosyasını bir editörde açın ve bir değeri değiştirin.
2. Menüyü açın. Beklenen: proje satırında ⚠︎ var.
3. "Tüm dosyalar → test" seçin. Beklenen: "Değişiklikler" penceresi açılır ve değişen anahtar `~` ile görünür.
4. "Mevcut ortama kaydet" seçin. Beklenen: geçiş tamamlanır. Pencerede `local` segmenti yeni değeri gösterir.
5. Aynı adımları "At ve geç" ve "İptal" için tekrarlayın. "İptal" sonrası dosya değişmez.

## 3. Hata durumları

1. `rm -rf /tmp/karaca-copy/apps/plp` çalıştırın ve "Tüm dosyalar → test" seçin.
   - Beklenen: hata mesajı `apps/plp/.env.local` dosyasını adıyla gösterir. Hiçbir dosya değişmez.
2. `mv /tmp/karaca-copy /tmp/karaca-moved` çalıştırın ve menüyü açın.
   - Beklenen: proje "Klasör bulunamadı" gösterir. "Klasörü yeniden seç…" ile `/tmp/karaca-moved` seçince proje yeniden çalışır.
3. Uygulamayı kapatın. `~/Library/Application Support/EnvSwitcher/store.json` dosyasının başına `x` yazın. Uygulamayı açın.
   - Beklenen: "Depo geri yüklendi" uyarısı çıkar ve projeler görünür.

## 4. Gizli değerler

1. `grep -c TURNSTILE_SECRET_KEY ~/Library/Application\ Support/EnvSwitcher/store.json` çalıştırın.
   - Beklenen: anahtar adı görünür, ama değeri görünmez (`"value"` alanı yok).
2. Pencerede bir değerin "Gizli" kutusunu kaldırın. Beklenen: değer görünür hale gelir ve `store.json` içine yazılır.

## 5. Arayüz

1. Sistem ayarlarından koyu moda geçin. Beklenen: pencere, menü ve sheet okunur kalır.
2. Menüdeki ortam noktaları ortam renklerini gösterir.
````

- [ ] **Step 2: README yaz**

`README.md`:

````markdown
# EnvSwitcher

Bir projedeki `.env` dosyalarını menü çubuğundan ortamlar arasında değiştiren bir macOS uygulaması.

- Tasarım: `docs/superpowers/specs/2026-10-07-env-switcher-design.md`
- Elle test listesi: `docs/manual-test.md`

## Gereksinimler

- macOS 14 veya üstü
- Xcode (aktif olmalı):

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
```

## Derleme ve çalıştırma

```sh
swift test                         # EnvCore testleri
scripts/bundle.sh                  # build/EnvSwitcher.app oluşturur
open build/EnvSwitcher.app
```

Gerçek Keychain testini çalıştırmak için:

```sh
ENVSWITCHER_KEYCHAIN_TESTS=1 swift test --filter SecretsTests
```

## Keychain izin sorusu

Ad-hoc imza her derlemede değişir. Bu nedenle macOS yeni bir derlemeden sonra Keychain izni sorabilir. Bu soruyu önlemek için kendinden imzalı bir sertifika oluşturun (Anahtar Zinciri Erişimi → Sertifika Asistanı → Sertifika Oluştur, tür: Kod İmzalama) ve şu komutu kullanın:

```sh
CODESIGN_IDENTITY="EnvSwitcher Dev" scripts/bundle.sh
```
````

- [ ] **Step 3: Tüm testleri ve derlemeyi çalıştır**

Run: `swift test`
Expected: PASS, tüm testler geçer (Keychain testi skipped).

Run: `scripts/bundle.sh`
Expected: son satır `build/EnvSwitcher.app`.

- [ ] **Step 4: Elle test listesini uygula**

`docs/manual-test.md` dosyasındaki 1–5 arası bölümleri uygulayın. Başarısız bir madde varsa, maddeyi ve gözlenen davranışı yazın. Sonra superpowers:systematic-debugging skill'ini kullanarak sorunu çözün.

- [ ] **Step 5: Commit**

```bash
git add docs/manual-test.md README.md
git commit -m "docs: add manual test checklist and README"
```
