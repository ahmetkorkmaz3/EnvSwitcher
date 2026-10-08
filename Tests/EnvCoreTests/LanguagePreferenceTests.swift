import Foundation
import Testing
@testable import EnvCore

struct LanguagePreferenceTests {
    /// Each test uses its own suite, so the global AppleLanguages list and other tests do not change the result.
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
