import SwiftUI

struct MenuContent: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ForEach(state.store.projects) { project in
            ProjectMenu(project: project)
        }
        if !state.store.projects.isEmpty {
            Divider()
        }
        Button("Add Project…") {
            state.showAddProject = true
            openManager()
        }
        .keyboardShortcut("n")
        Button("Manage…") { openManager() }
            .keyboardShortcut("m")
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Divider()
        if let update = state.updates.available {
            Button("Update Available: \(update.version.description)") { state.updates.installAvailableUpdate() }
        }
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
        Text("Version \(state.updates.versionText)")
    }

    private func openManager() {
        openWindow(id: WindowID.manager)
        NSApp.activate()
    }
}
