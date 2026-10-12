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
        panel.prompt = String(localized: "Choose")
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
        panel.prompt = String(localized: "Choose")
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Any file type: .env files often have no extension.
    static func chooseEnvFile() -> URL? {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.message = String(localized: "Choose a .env file to import.")
        panel.prompt = String(localized: "Choose")
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func saveEnvFile(suggestedName: String) -> URL? {
        NSApp.activate()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.showsHiddenFiles = true
        panel.message = String(localized: "The file holds secret values in plain text. Send it only to people you trust.")
        panel.prompt = String(localized: "Export")
        return panel.runModal() == .OK ? panel.url : nil
    }
}
