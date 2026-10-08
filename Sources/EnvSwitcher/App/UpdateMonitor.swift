import AppKit
import EnvCore
import Observation

/// Checks GitHub for a newer release once a day (spec 2026-10-08, section 7.2).
@MainActor
@Observable
final class UpdateMonitor {
    private(set) var available: AvailableUpdate?
    /// CFBundleShortVersionString, for the "Version" menu line.
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
            message: String(localized: "The app copied the install command to the clipboard. Paste it into Terminal.")
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
