import EnvCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @State private var language = LanguagePreference().current
    /// The choice at launch. It is static, so the restart button stays after the window closes and opens again.
    private static let launchLanguage = LanguagePreference().current

    var body: some View {
        Form {
            Section {
                Picker("Language", selection: $language) {
                    Text("System").tag(AppLanguage.system)
                    Text(verbatim: "English").tag(AppLanguage.english)
                    Text(verbatim: "Türkçe").tag(AppLanguage.turkish)
                }
                .onChange(of: language) { _, newValue in LanguagePreference().current = newValue }
                if language != Self.launchLanguage {
                    LabeledContent {
                        Button("Restart Now") { AppRelauncher.relaunch() }
                    } label: {
                        Text("EnvSwitcher uses the new language after a restart.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                applicationRow(
                    title: "Editor",
                    path: state.store.settings.editorAppPath,
                    placeholder: "The app that opens .env files"
                ) { path in state.updateSettings { $0.editorAppPath = path } }
                applicationRow(
                    title: "Terminal",
                    path: state.store.settings.terminalAppPath,
                    placeholder: "Terminal"
                ) { path in state.updateSettings { $0.terminalAppPath = path } }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }

    private func applicationRow(title: LocalizedStringKey, path: String?, placeholder: LocalizedStringKey, onChange: @escaping (String?) -> Void) -> some View {
        LabeledContent(title) {
            HStack {
                Group {
                    if let path {
                        Text(verbatim: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
                    } else {
                        Text(placeholder)
                    }
                }
                .foregroundStyle(.secondary)
                Button("Choose…") {
                    if let url = Panels.chooseApplication() { onChange(url.path) }
                }
                if path != nil {
                    Button("Reset") { onChange(nil) }
                }
            }
        }
    }
}
