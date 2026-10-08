import AppKit
import EnvCore

/// Native NSAlert dialogs. They also work from the menu bar menu, where SwiftUI sheets cannot open.
@MainActor
enum Alerts {
    static func confirmProtected(projectName: String, environmentName: String, fileCount: Int) -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = String(localized: "Project \(projectName) switches to the \(environmentName.uppercased()) environment.")
        alert.informativeText = String(localized: "Files to change: \(fileCount)")
        alert.addButton(withTitle: String(localized: "Switch"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func showError(_ message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "The Action Did Not Complete")
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }

    static func showInfo(title: String, message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }

    /// Returns true when the user chooses to remove the files from the project.
    static func offerRemoveMissing(_ message: String) -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "The Switch Did Not Start")
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "OK"))
        alert.addButton(withTitle: String(localized: "Remove from Project"))
        return alert.runModal() == .alertSecondButtonReturn
    }

    /// Asks before a switch writes files that have no values in the chosen environment.
    static func confirmEmpty(environmentName: String, paths: [String]) -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "The \(environmentName) environment has no values for these files.")
        alert.informativeText = String(localized: """
            If you switch, the app writes these files empty: \(paths.joined(separator: ", ")).
            To enter the values, open the edit window or use the "Copy from Another Environment" button.
            """)
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.addButton(withTitle: String(localized: "Switch Anyway"))
        return alert.runModal() == .alertSecondButtonReturn
    }

    static func showImportWarnings(_ warnings: [String: [DotEnvWarning]]) {
        guard !warnings.isEmpty else { return }
        let text = warnings.keys.sorted().map { path in
            let lines = warnings[path]!.map { warning -> String in
                switch warning {
                case .invalidLine(let line): String(localized: "line \(line): cannot read")
                case .unterminatedQuote(let line): String(localized: "line \(line): the quote does not close")
                case .duplicateKey(let key, let line): String(localized: "line \(line): \(key) occurs two times. The app uses the last value.")
                }
            }
            return "\(path)\n  " + lines.joined(separator: "\n  ")
        }
        .joined(separator: "\n\n")
        showInfo(title: String(localized: "Some Lines Cannot Be Read"), message: text)
    }

    /// Returns nil when the user cancels.
    static func chooseCopyMode() -> EntryEditor.CopyMode? {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = String(localized: "What should the app do when the same key is also in this environment?")
        alert.addButton(withTitle: String(localized: "Overwrite"))
        alert.addButton(withTitle: String(localized: "Skip"))
        alert.addButton(withTitle: String(localized: "Cancel"))
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
        alert.messageText = String(localized: "Keys with a different value in the \(environmentName) environment: \(plan.conflicts.count)")
        var lines = [String(localized: "Keys that get a new value: \(plan.conflicts.joined(separator: ", "))")]
        if !plan.added.isEmpty { lines.append(String(localized: "Keys to add: \(plan.added.joined(separator: ", "))")) }
        if !plan.filled.isEmpty { lines.append(String(localized: "Empty keys to fill: \(plan.filled.joined(separator: ", "))")) }
        alert.informativeText = lines.joined(separator: "\n\n")
        alert.addButton(withTitle: String(localized: "Overwrite"))
        alert.addButton(withTitle: String(localized: "Add Only Missing Keys"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .overwrite
        case .alertSecondButtonReturn: return .skipExisting
        default: return nil
        }
    }

    /// Asks before every missing key is copied. `sourceName` is nil when each key uses its first filled environment.
    static func confirmFillAll(keyCount: Int, sourceName: String?) -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = String(localized: "Missing keys to add to the other environments: \(keyCount)")
        alert.informativeText = sourceName.map { String(localized: "The values come from the \($0) environment. Existing values do not change.") }
            ?? String(localized: "Each key gets its value from the first environment that has the key. Existing values do not change.")
        alert.addButton(withTitle: String(localized: "Add"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}
