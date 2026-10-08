# Dil Desteği Uygulama Planı

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Uygulama ve landing page İngilizce ve Türkçe gösterir. Varsayılan dil İngilizcedir.

**Architecture:** Koddaki metin anahtarı İngilizce metindir. Çeviriler `Resources/<dil>.lproj/Localizable.strings` dosyalarında durur. `bundle.sh` bu dosyaları `.app` içine kopyalar. Dil seçimi uygulamanın `AppleLanguages` değerine yazılır ve uygulama yeniden başlar. Landing page satır içi bir sözlük ve EN/TR düğmesi kullanır.

**Tech Stack:** Swift 6 araç zinciri (Swift 5 dil modu), SwiftUI, AppKit, Swift Testing, POSIX sh, düz HTML ve JavaScript.

**Spec:** `docs/superpowers/specs/2026-10-08-localization-design.md`

## Global Constraints

- Diller: `en` ve `tr`. `CFBundleDevelopmentRegion` = `en`.
- Kod anahtarı İngilizce metindir. Ayrı bir anahtar adı (`settings.title` gibi) kullanılmaz.
- `.xcstrings` kullanılmaz. Yalnızca `.strings` (UTF-8) kullanılır.
- `Package.swift` değişmez.
- Seçenek adları "English" ve "Türkçe" çevrilmez.
- `UserDefaults` anahtarı: `AppleLanguages`. Landing page `localStorage` anahtarı: `envswitcher-lang`.
- Yeni İngilizce metinler ASD-STE100 kurallarına uyar: etken çatı, kısa cümle, basit kelime.

## Review Focus

1. **Biçim belirteci uyuşmazlığı.** Türkçe çeviride `%@` veya `%lld` sayısı İngilizceden farklıysa uygulama yanlış metin gösterir veya çöker. `check-strings.sh` bu durumu yakalar (Görev 2).
2. **Çevrilmeyen metin.** Kodda Türkçe bir metin kalırsa İngilizce arayüzde Türkçe görünür. Görev 4 ve 5, `grep` ile Türkçe karakter taraması yapar.
3. **Çevirisi olmayan anahtar.** Koddaki bir anahtar `tr.lproj` içinde yoksa Türkçe arayüzde İngilizce görünür. Elle kontrol (Görev 7) ve `check-strings.sh` anahtar eşitliği bunu sınırlar.
4. **Yeniden başlatma başarısız.** Yeni kopya açılmazsa uygulama kapanmamalı. Görev 3 bu yolu kodlar ve uyarı gösterir.
5. **`localStorage` erişilemez.** Gizli pencerede sayfa yine İngilizce açılmalı ve düğme çalışmalı. Görev 6 her erişimi `try/catch` içine alır.

---

### Görev 1: `AppLanguage` ve `LanguagePreference`

**Files:**
- Create: `Sources/EnvCore/Settings/LanguagePreference.swift`
- Test: `Tests/EnvCoreTests/LanguagePreferenceTests.swift`

**Interfaces:**
- Produces:
  - `LanguagePreference(defaults:domain:)` — `domain` varsayılanı `Bundle.main.bundleIdentifier ?? "EnvSwitcher"`.
  - `public enum AppLanguage: String, CaseIterable, Identifiable, Sendable { case system, english, turkish }`, `var code: String?` (`nil`, `"en"`, `"tr"`).
  - `public struct LanguagePreference { init(defaults: UserDefaults = .standard); var current: AppLanguage { get nonmutating set } }`
  - `public static let defaultsKey = "AppleLanguages"`

- [ ] **Step 1: Write the failing test**

`UserDefaults.object(forKey:)` global alanı da okur. Bu yüzden global `AppleLanguages` değeri testi bozar. `LanguagePreference` okuma için yalnızca uygulamanın kendi alanını (`persistentDomain(forName:)`) kullanır. Test, her durum için yeni bir suite açar.

```swift
import Foundation
import Testing
@testable import EnvCore

struct LanguagePreferenceTests {
    private func make() -> (UserDefaults, LanguagePreference, String) {
        let name = "LanguagePreferenceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, LanguagePreference(defaults: defaults, domain: name), name)
    }

    @Test func systemWhenNothingIsStored() {
        #expect(make().1.current == .system)
    }

    @Test(arguments: [AppLanguage.english, .turkish])
    func storesTheChosenLanguage(language: AppLanguage) {
        let (defaults, preference, name) = make()
        preference.current = language
        #expect(defaults.persistentDomain(forName: name)?["AppleLanguages"] as? [String] == [language.code!])
        #expect(LanguagePreference(defaults: defaults, domain: name).current == language)
    }

    @Test func systemRemovesTheStoredValue() {
        let (defaults, preference, name) = make()
        preference.current = .turkish
        preference.current = .system
        #expect(defaults.persistentDomain(forName: name)?["AppleLanguages"] == nil)
        #expect(preference.current == .system)
    }

    @Test func unknownStoredLanguageReadsAsSystem() {
        let (defaults, preference, _) = make()
        defaults.set(["de"], forKey: LanguagePreference.defaultsKey)
        #expect(preference.current == .system)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LanguagePreferenceTests`
Expected: FAIL, `cannot find 'LanguagePreference' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// The language choice in Settings. `system` follows the macOS language list.
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system, english, turkish

    public var id: String { rawValue }

    /// The value for AppleLanguages. Nil means "follow the system".
    public var code: String? {
        switch self {
        case .system: nil
        case .english: "en"
        case .turkish: "tr"
        }
    }
}

/// Reads and writes the app's AppleLanguages value (spec 2026-10-08 localization, section 2.4).
/// macOS reads this value at launch, so a change needs a restart.
public struct LanguagePreference {
    public static let defaultsKey = "AppleLanguages"

    private let defaults: UserDefaults
    private let domain: String

    /// `domain` is the app's own defaults domain. Reads use only this domain,
    /// because `object(forKey:)` also returns the global AppleLanguages list.
    public init(defaults: UserDefaults = .standard, domain: String = Bundle.main.bundleIdentifier ?? "EnvSwitcher") {
        self.defaults = defaults
        self.domain = domain
    }

    public var current: AppLanguage {
        get {
            let codes = defaults.persistentDomain(forName: domain)?[Self.defaultsKey] as? [String]
            return AppLanguage.allCases.first { $0.code != nil && $0.code == codes?.first } ?? .system
        }
        nonmutating set {
            if let code = newValue.code {
                defaults.set([code], forKey: Self.defaultsKey)
            } else {
                defaults.removeObject(forKey: Self.defaultsKey)
            }
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter LanguagePreferenceTests`
Expected: PASS, 5 test.

- [ ] **Step 5: Commit**

```bash
git add Sources/EnvCore/Settings/LanguagePreference.swift Tests/EnvCoreTests/LanguagePreferenceTests.swift
git commit -m "feat(core): add a language preference that reads and writes AppleLanguages"
```

### Görev 2: Çeviri dosyaları, paketleme ve kontrol betiği

**Files:**
- Create: `Resources/en.lproj/Localizable.strings`, `Resources/tr.lproj/Localizable.strings`
- Create: `scripts/check-strings.sh`
- Modify: `scripts/bundle.sh` (kopyalama ve `Info.plist`)
- Modify: `.github/workflows/ci.yml` (yeni adım)

**Interfaces:**
- Produces: `scripts/check-strings.sh` sıfır dışı kodla çıkarsa dosyalar bozuktur. Görev 3–5 her yeni anahtarı iki dosyaya da ekler.

- [ ] **Step 1: Başlangıç dosyalarını yaz** (Görev 3–5 bu dosyaları doldurur)

`Resources/en.lproj/Localizable.strings`:
```
/* Settings */
"Language" = "Language";
```

`Resources/tr.lproj/Localizable.strings`:
```
/* Settings */
"Language" = "Dil";
```

- [ ] **Step 2: Kontrol betiğini yaz**

```sh
#!/bin/sh
# Checks the translation files (spec 2026-10-08 localization, section 4).
# 1. Each file is a valid .strings file. 2. Both files have the same keys.
# 3. Each translation has the same format specifiers as its key.
set -eu
cd "$(dirname "$0")/.."

EN="Resources/en.lproj/Localizable.strings"
TR="Resources/tr.lproj/Localizable.strings"

plutil -lint -s "$EN" "$TR"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
plutil -convert json -o "$TMP/en.json" "$EN"
plutil -convert json -o "$TMP/tr.json" "$TR"

/usr/bin/python3 - "$TMP/en.json" "$TMP/tr.json" <<'PY'
import json, re, sys
en = json.load(open(sys.argv[1]))
tr = json.load(open(sys.argv[2]))
spec = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|@|f)")
def specs(text):
    return sorted(re.sub(r"\d+\$", "", s) for s in spec.findall(text))
errors = []
for key in sorted(set(en) ^ set(tr)):
    errors.append(f"key only in {'en' if key in en else 'tr'}: {key!r}")
for key in sorted(set(en) & set(tr)):
    for lang, text in (("en", en[key]), ("tr", tr[key])):
        if specs(text) != specs(key):
            errors.append(f"format specifiers differ ({lang}): {key!r}")
for line in errors:
    print(line, file=sys.stderr)
sys.exit(1 if errors else 0)
PY
echo "Translations OK ($(grep -c '^"' "$EN") keys)"
```

`chmod +x scripts/check-strings.sh`

- [ ] **Step 3: Betiğin hatayı yakaladığını doğrula**

Run: `printf '"Files: %%lld" = "Dosya: %%@";\n' >> Resources/tr.lproj/Localizable.strings && scripts/check-strings.sh; echo "exit=$?"; git checkout Resources/tr.lproj/Localizable.strings 2>/dev/null || sed -i '' '$d' Resources/tr.lproj/Localizable.strings`
Expected: `key only in tr: 'Files: %lld'`, `format specifiers differ (tr)`, `exit=1`.

Run: `scripts/check-strings.sh`
Expected: `Translations OK (1 keys)`.

- [ ] **Step 4: `bundle.sh` güncelle**

`cp Resources/AppIcon.icns …` satırından sonra:
```sh
cp -R Resources/en.lproj Resources/tr.lproj "$APP/Contents/Resources/"
```
`Info.plist` içinde `CFBundleIconFile` satırından sonra:
```
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>en</string><string>tr</string></array>
```

- [ ] **Step 5: CI adımını ekle** (`Test` adımından sonra)

```yaml
      - name: Check the translations
        run: scripts/check-strings.sh
```

- [ ] **Step 6: Doğrula**

Run: `scripts/bundle.sh && ls build/EnvSwitcher.app/Contents/Resources && plutil -p build/EnvSwitcher.app/Contents/Info.plist | grep -A3 Localizations && shellcheck scripts/check-strings.sh scripts/bundle.sh`
Expected: `en.lproj tr.lproj AppIcon.icns`, iki dil, shellcheck çıktısı yok.

- [ ] **Step 7: Commit**

```bash
git add Resources scripts/check-strings.sh scripts/bundle.sh .github/workflows/ci.yml
git commit -m "build: bundle English and Turkish translation files and check them in CI"
```

### Görev 3: Ayarlar ekranında dil seçimi ve yeniden başlatma

**Files:**
- Create: `Sources/EnvSwitcher/App/AppRelauncher.swift`
- Modify: `Sources/EnvSwitcher/Settings/SettingsView.swift`
- Modify: iki `.strings` dosyası

**Interfaces:**
- Consumes: `AppLanguage`, `LanguagePreference` (Görev 1).
- Produces: `AppRelauncher.relaunch()` (`@MainActor`).

- [ ] **Step 1: `AppRelauncher` yaz**

```swift
import AppKit

/// Opens a new copy of the app and quits this one. A language change needs a new process.
@MainActor
enum AppRelauncher {
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            Task { @MainActor in
                if let error {
                    Alerts.showError(String(localized: "EnvSwitcher could not restart. Quit the app and open it again.\n\(error.localizedDescription)"))
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }
}
```

- [ ] **Step 2: `SettingsView` içine dil satırını ekle**

`Form` içinde en üste:
```swift
Section {
    Picker("Language", selection: $language) {
        Text("System").tag(AppLanguage.system)
        Text(verbatim: "English").tag(AppLanguage.english)
        Text(verbatim: "Türkçe").tag(AppLanguage.turkish)
    }
    .onChange(of: language) { _, newValue in LanguagePreference().current = newValue }
    if language != launchLanguage {
        LabeledContent {
            Button("Restart Now") { AppRelauncher.relaunch() }
        } label: {
            Text("EnvSwitcher uses the new language after a restart.")
                .foregroundStyle(.secondary)
        }
    }
}
```
Özellikler:
```swift
@State private var language = LanguagePreference().current
/// The choice at launch. The app shows the restart button only when the choice changes.
private let launchLanguage = LanguagePreference().current
```
Not: `launchLanguage` her `SettingsView` oluşumunda yeniden okunur. Kullanıcı Ayarlar penceresini kapatıp açarsa düğme kaybolur. Bunu önlemek için değeri `static let` yapın: `private static let launchLanguage = LanguagePreference().current`.

Mevcut metinleri de çevir: "Editör" → "Editor", ".env dosyalarını açan uygulama" → "The app that opens .env files", "Seç…" → "Choose…", "Sıfırla" → "Reset". `applicationRow` imzasındaki `title` ve `placeholder` tipini `LocalizedStringKey` yap. `Text(path.map { … } ?? placeholder)` satırını şöyle yaz: `if let path { Text(verbatim: name(path)) } else { Text(placeholder) }`.

- [ ] **Step 3: Anahtarları iki dosyaya ekle**

| en | tr |
|---|---|
| System | Sistem |
| Restart Now | Şimdi Yeniden Başlat |
| EnvSwitcher uses the new language after a restart. | EnvSwitcher yeni dili yeniden başladıktan sonra kullanır. |
| EnvSwitcher could not restart. Quit the app and open it again.\n%@ | EnvSwitcher yeniden başlatılamadı. Uygulamayı kapatıp yeniden açın.\n%@ |
| Editor | Editör |
| The app that opens .env files | .env dosyalarını açan uygulama |
| Choose… | Seç… |
| Reset | Sıfırla |
| Terminal | Terminal |

- [ ] **Step 4: Doğrula**

Run: `swift build && scripts/check-strings.sh`
Expected: derleme başarılı, `Translations OK`.

- [ ] **Step 5: Commit**

```bash
git add Sources/EnvSwitcher/App/AppRelauncher.swift Sources/EnvSwitcher/Settings/SettingsView.swift Resources
git commit -m "feat(app): let the user choose the app language in Settings"
```

### Görev 4: `App/` ve `MenuBar/` metinleri

**Files:**
- Modify: `Sources/EnvSwitcher/App/{Alerts,AppState,UpdateMonitor,EnvSwitcherApp,Panels}.swift`
- Modify: `Sources/EnvSwitcher/MenuBar/{MenuContent,ProjectMenu}.swift`
- Modify: iki `.strings` dosyası

**Kurallar (Görev 5 için de geçerli):**
1. Her Türkçe metni İngilizceye çevir. İngilizce metin anahtar olur.
2. SwiftUI başlık parametreleri (`Text`, `Button`, `Section`, `Window`, `Toggle`, `Label`, `LabeledContent`, `.help`, `.navigationTitle`) zaten `LocalizedStringKey` alır. Yalnızca metni değiştir.
3. `String` isteyen yerler (`NSAlert`, `panel.prompt`, `AppState.message(for:)`, `stateText`) `String(localized: "…")` kullanır.
4. Yalnızca veri gösteren metin `Text(verbatim:)` kullanır. Örnek: `Text(verbatim: "\(target.relativePath) — \(name)")`. Böylece gereksiz `%@ — %@` anahtarı oluşmaz.
5. Bir `String` değişkeni gösteren `Text(x)` çevrilmez. Bu doğru davranıştır.
6. Anahtardaki belirteçler: `String` → `%@`, `Int` → `%lld`. `.strings` dosyasında anahtarı bu belirteçlerle yaz.
7. Sayı içeren metinlerde tekil ve çoğul biçim için İngilizcede `(s)` kullanılmaz. Cümleyi sayıdan bağımsız kur: "Files to change: %lld".
8. Türkçe çeviri, mevcut Türkçe metnin kendisidir. Metni yeniden yazma.
9. `.strings` dosyasında her dosya için bir `/* Dosya adı */` başlığı kullan.

- [ ] **Step 1:** `Alerts.swift` metinlerini çevir ve anahtarları ekle.
- [ ] **Step 2:** `AppState.swift` metinlerini çevir (`message(for:)`, `describe`, `stateText`, uyarı başlıkları).
- [ ] **Step 3:** `UpdateMonitor.swift`, `EnvSwitcherApp.swift` ("Değişiklikler" → "Changes"), `Panels.swift` ("Seç" → "Choose") metinlerini çevir.
- [ ] **Step 4:** `MenuContent.swift`, `ProjectMenu.swift` metinlerini çevir.
- [ ] **Step 5: Doğrula**

Run: `grep -nE '[çğıöşüÇĞİÖŞÜ]' Sources/EnvSwitcher/App Sources/EnvSwitcher/MenuBar -r | grep -v '^\s*//' ; swift build && scripts/check-strings.sh`
Expected: `grep` yalnızca kod yorumlarını gösterir (`//` satırları). Derleme başarılı, `Translations OK`.

- [ ] **Step 6: Commit**

```bash
git add Sources/EnvSwitcher/App Sources/EnvSwitcher/MenuBar Resources
git commit -m "feat(app): show the menu and the alerts in English and Turkish"
```

### Görev 5: `Window/`, `Sheets/` ve `Drift/` metinleri

**Files:**
- Modify: `Sources/EnvSwitcher/Window/{CompareView,ManagerWindow,ProjectSettingsView,Sidebar,TargetDetailView}.swift`
- Modify: `Sources/EnvSwitcher/Sheets/AddProjectSheet.swift`, `Sources/EnvSwitcher/Drift/DriftView.swift`
- Modify: `Sources/EnvSwitcher/App/EnvColor+UI.swift` (renk adları varsa)
- Modify: iki `.strings` dosyası

Görev 4'teki 9 kural geçerlidir.

- [ ] **Step 1:** `Sidebar.swift`, `ManagerWindow.swift`, `ProjectSettingsView.swift` metinlerini çevir.
- [ ] **Step 2:** `TargetDetailView.swift`, `CompareView.swift` metinlerini çevir.
- [ ] **Step 3:** `AddProjectSheet.swift`, `DriftView.swift`, `EnvColor+UI.swift` metinlerini çevir.
- [ ] **Step 4: Doğrula**

Run: `grep -rnE '[çğıöşüÇĞİÖŞÜ]' Sources/EnvSwitcher | grep -vE '//|"Türkçe"'; swift build && scripts/check-strings.sh`
Expected: `grep` çıktısı yok. Derleme başarılı, `Translations OK`.

- [ ] **Step 5: Commit**

```bash
git add Sources/EnvSwitcher Resources
git commit -m "feat(app): show the windows and the sheets in English and Turkish"
```

### Görev 6: İngilizce `.env` başlığı

**Files:**
- Modify: `Sources/EnvCore/Switching/SwitchPlanner.swift:127-132`
- Test: `Tests/EnvCoreTests/SwitchPlannerTests.swift:6`

- [ ] **Step 1: Testi güncelle (önce başarısız olur)**

```swift
private let header = "# Generated by EnvSwitcher — project: my-app, environment: test\n# If you edit this file by hand, the app asks before it switches the environment.\n"
```

- [ ] **Step 2:** Run: `swift test --filter SwitchPlannerTests` — Expected: FAIL (başlık uyuşmuyor).

- [ ] **Step 3: Kodu güncelle**

```swift
public static func header(project: Project, environment: EnvEnvironment) -> [String] {
    [
        "Generated by EnvSwitcher — project: \(project.name), environment: \(environment.name)",
        "If you edit this file by hand, the app asks before it switches the environment.",
    ]
}
```

- [ ] **Step 4:** Run: `swift test` — Expected: tüm testler PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/EnvCore/Switching/SwitchPlanner.swift Tests/EnvCoreTests/SwitchPlannerTests.swift
git commit -m "feat(core): write the .env header in English"
```

### Görev 7: Landing page

**Files:**
- Modify: `site/index.html`

- [ ] **Step 1:** `<html lang="en">` yap. Tüm görünür metinleri, `aria-label` değerlerini, `<title>` ve `<meta name="description">` değerini İngilizceye çevir.
- [ ] **Step 2:** Çevrilen her öğeye `data-i18n="<anahtar>"` ekle. Öznitelikler için `data-i18n-attr="aria-label:<anahtar>"` kullan. Anahtarlar kısa ve noktalı olur: `hero.title`, `nav.releases`.
- [ ] **Step 3:** Üst menüye düğme ekle:

```html
<button type="button" class="lang-toggle" id="lang-toggle" hidden aria-label="Türkçe göster" lang="tr">TR</button>
```
Düğme, aktif olmayan dili gösterir: İngilizcede "TR", Türkçede "EN". `aria-label` İngilizcede `Türkçe göster`, Türkçede `Show in English` olur.

- [ ] **Step 4:** Betiği yaz:

```js
var STORE_KEY = "envswitcher-lang";
var TR = { /* "hero.title": "…", … her data-i18n anahtarı için Türkçe metin */ };
var original = {};
function readLang() { try { return localStorage.getItem(STORE_KEY) === "tr" ? "tr" : "en"; } catch (e) { return "en"; } }
function saveLang(lang) { try { localStorage.setItem(STORE_KEY, lang); } catch (e) {} }
function t(key, fallback) { return currentLang === "tr" && TR[key] ? TR[key] : fallback; }
function apply(lang) {
  currentLang = lang;
  document.documentElement.lang = lang;
  document.querySelectorAll("[data-i18n]").forEach(function (el) {
    var key = el.dataset.i18n;
    if (!(key in original)) original[key] = el.innerHTML;
    el.innerHTML = lang === "tr" && TR[key] ? TR[key] : original[key];
  });
  document.querySelectorAll("[data-i18n-attr]").forEach(function (el) {
    var parts = el.dataset.i18nAttr.split(":"), attr = parts[0], key = parts[1];
    var store = "attr:" + key;
    if (!(store in original)) original[store] = el.getAttribute(attr);
    el.setAttribute(attr, lang === "tr" && TR[key] ? TR[key] : original[store]);
  });
  var toggle = document.getElementById("lang-toggle");
  toggle.textContent = lang === "tr" ? "EN" : "TR";
  toggle.lang = lang === "tr" ? "en" : "tr";
  toggle.setAttribute("aria-label", lang === "tr" ? "Show in English" : "Türkçe göster");
  toggle.setAttribute("aria-pressed", String(lang === "tr"));
}
var currentLang = "en";
apply(readLang());
var toggle = document.getElementById("lang-toggle");
toggle.hidden = false;
toggle.addEventListener("click", function () {
  var next = currentLang === "tr" ? "en" : "tr";
  saveLang(next);
  apply(next);
});
```
`<title>` öğesi de `data-i18n="meta.title"` taşır. Kopyala düğmesi metinleri `t("copy.done", "Copied")`, `t("copy.idle", "Copy")`, `t("copy.status", "Command copied to the clipboard.")` kullanır. `TR` sözlüğü bu üç anahtarı da içerir.

- [ ] **Step 5:** Düğmeye mevcut stil değişkenleriyle stil ver. Telefon genişliğinde (375 px) yatay kaydırma olmamalı.

- [ ] **Step 6: Doğrula** (Playwright ile)
  1. `python3 -m http.server -d site 8123` başlat. Sayfayı aç. Beklenen: İngilizce, `html[lang=en]`.
  2. TR düğmesine bas. Beklenen: tüm `data-i18n` öğeleri Türkçe. Konsolda hata yok.
  3. Sayfayı yenile. Beklenen: Türkçe kalır.
  4. EN düğmesine bas. Beklenen: İngilizce metin ilk haline döner.
  5. 375 px genişlikte ekran görüntüsü al. Beklenen: yatay kaydırma yok.
  6. Komut: `grep -c 'data-i18n' site/index.html` sayısı, `TR` sözlüğündeki anahtar sayısına yakındır. Eksik anahtar için betik konsola `console.warn` yazar (`apply` içinde, `lang === "tr" && !TR[key]` durumunda).

- [ ] **Step 7: Commit**

```bash
git add site/index.html
git commit -m "feat(site): show the landing page in English with a Turkish option"
```

### Görev 8: Elle test belgesi ve son doğrulama

**Files:**
- Modify: `docs/manual-test.md` (yeni bölüm "10. Dil")
- Modify: `CHANGELOG.md` (`Unreleased` bölümü)

- [ ] **Step 1:** `docs/manual-test.md` sonuna ekle:

```markdown
## 10. Dil

1. `open build/EnvSwitcher.app --args -AppleLanguages "(tr)"` çalıştırın.
   - Beklenen: menü, pencereler ve uyarılar Türkçe görünür.
2. `open build/EnvSwitcher.app --args -AppleLanguages "(de)"` çalıştırın.
   - Beklenen: tüm metinler İngilizce görünür.
3. Ayarlar'da **Language** değerini **Türkçe** yapın.
   - Beklenen: "Restart Now" düğmesi çıkar. Düğmeye basınca uygulama Türkçe açılır.
4. Ayarlar'da **Dil** değerini **Sistem** yapın ve yeniden başlatın.
   - Beklenen: uygulama sistem dilinde açılır.
5. Landing page'i açın.
   - Beklenen: sayfa İngilizce açılır. TR düğmesi sayfayı Türkçe yapar. Sayfa yenilenince seçim korunur.
```

- [ ] **Step 2:** `CHANGELOG.md` dosyasında `## [0.2.0]` satırının üstüne ekle (dosya Türkçedir):

```markdown
## [Yayımlanmadı]

### Eklenenler

- İngilizce ve Türkçe dil desteği. Uygulama ilk açılışta macOS dilini kullanır. Dil Ayarlar'dan değişir. Landing page İngilizce açılır ve TR düğmesi taşır.

### Değişenler

- `.env` dosyalarının başlık yorumu artık İngilizce.
```
- [ ] **Step 3: Son doğrulama**

Run: `swift test && scripts/check-strings.sh && scripts/bundle.sh && shellcheck scripts/*.sh install.sh`
Expected: tüm komutlar başarılı.

Run: `open build/EnvSwitcher.app --args -AppleLanguages "(tr)"` ve `"(en)"`. Menü ve Ayarlar ekranlarının görüntüsünü al. Beklenen: dil doğru, anahtar adı veya karışık dil yok.

- [ ] **Step 4: Commit**

```bash
git add docs/manual-test.md CHANGELOG.md
git commit -m "docs: add manual language tests and a changelog entry"
```
