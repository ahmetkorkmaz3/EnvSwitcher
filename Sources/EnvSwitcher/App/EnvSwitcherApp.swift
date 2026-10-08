import SwiftUI

@main
struct EnvSwitcherApp: App {
    @State private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environment(state)
        } label: {
            Image(nsImage: state.menuBarDot)
            Text(state.menuBarTitle)
        }
        .menuBarExtraStyle(.menu)

        Window("EnvSwitcher", id: WindowID.manager) {
            ManagerWindow()
                .environment(state)
        }
        .defaultSize(width: 920, height: 580)

        Window("Changes", id: WindowID.drift) {
            DriftView()
                .environment(state)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environment(state)
        }
    }
}
