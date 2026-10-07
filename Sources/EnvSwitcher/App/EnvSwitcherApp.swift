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
    }
}
