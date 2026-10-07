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
