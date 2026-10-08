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
