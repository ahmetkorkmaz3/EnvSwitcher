import EnvCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Form {
            applicationRow(
                title: "Editör",
                path: state.store.settings.editorAppPath,
                placeholder: ".env dosyalarını açan uygulama"
            ) { path in state.updateSettings { $0.editorAppPath = path } }
            applicationRow(
                title: "Terminal",
                path: state.store.settings.terminalAppPath,
                placeholder: "Terminal"
            ) { path in state.updateSettings { $0.terminalAppPath = path } }
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }

    private func applicationRow(title: String, path: String?, placeholder: String, onChange: @escaping (String?) -> Void) -> some View {
        LabeledContent(title) {
            HStack {
                Text(path.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? placeholder)
                    .foregroundStyle(.secondary)
                Button("Seç…") {
                    if let url = Panels.chooseApplication() { onChange(url.path) }
                }
                if path != nil {
                    Button("Sıfırla") { onChange(nil) }
                }
            }
        }
    }
}
