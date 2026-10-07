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
        Button("Proje Ekle…") {
            state.showAddProject = true
            openManager()
        }
        .keyboardShortcut("n")
        Button("Yönet…") { openManager() }
            .keyboardShortcut(",")
        Divider()
        Button("Çık") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func openManager() {
        openWindow(id: WindowID.manager)
        NSApp.activate()
    }
}
