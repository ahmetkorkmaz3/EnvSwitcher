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
    public init(defaults: UserDefaults = .standard, domain: String = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName) {
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
