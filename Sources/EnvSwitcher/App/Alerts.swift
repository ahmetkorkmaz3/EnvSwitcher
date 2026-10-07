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
