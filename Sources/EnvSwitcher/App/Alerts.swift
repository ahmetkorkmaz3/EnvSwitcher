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

    /// Asks before a switch writes files that have no values in the chosen environment.
    static func confirmEmpty(environmentName: String, paths: [String]) -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(environmentName) ortamında bu dosyalar için değer yok."
        alert.informativeText = """
            Geçerseniz bu dosyalar boş yazılır: \(paths.joined(separator: ", ")).
            Değerleri girmek için düzenleme penceresini açın veya "Diğer ortamdan kopyala" düğmesini kullanın.
            """
        alert.addButton(withTitle: "Vazgeç")
        alert.addButton(withTitle: "Yine de geç")
        return alert.runModal() == .alertSecondButtonReturn
    }

    static func showImportWarnings(_ warnings: [String: [DotEnvWarning]]) {
        guard !warnings.isEmpty else { return }
        let text = warnings.keys.sorted().map { path in
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
        showInfo(title: "Bazı satırlar okunamadı", message: text)
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

    /// Asks what to do when pasted keys already have other values. Returns nil when the user cancels.
    static func choosePasteMode(environmentName: String, plan: EntryEditor.PastePlan) -> EntryEditor.CopyMode? {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "\(plan.conflicts.count) anahtarın \(environmentName) ortamında başka bir değeri var."
        var lines = ["Değeri değişecek anahtarlar: \(plan.conflicts.joined(separator: ", "))"]
        if !plan.added.isEmpty { lines.append("Eklenecek anahtarlar: \(plan.added.joined(separator: ", "))") }
        if !plan.filled.isEmpty { lines.append("Boş değeri doldurulacak anahtarlar: \(plan.filled.joined(separator: ", "))") }
        alert.informativeText = lines.joined(separator: "\n\n")
        alert.addButton(withTitle: "Üzerine yaz")
        alert.addButton(withTitle: "Yalnızca eksikleri ekle")
        alert.addButton(withTitle: "Vazgeç")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .overwrite
        case .alertSecondButtonReturn: return .skipExisting
        default: return nil
        }
    }
}
