import EnvCore
import SwiftUI

struct ManagerWindow: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            detail
        }
        .sheet(isPresented: $state.showAddProject) {
            AddProjectSheet()
        }
        .onAppear { state.refreshDrift() }
    }

    @ViewBuilder
    private var detail: some View {
        switch state.selection {
        case .project(let id)?:
            if let project = state.project(id: id) {
                ProjectSettingsView(project: project).id(project.id)
            }
        case .target(let projectId, let targetId)?:
            if let project = state.project(id: projectId), let target = project.targets.first(where: { $0.id == targetId }) {
                TargetDetailView(project: project, target: target).id(target.id)
            }
        case nil:
            ContentUnavailableView(
                "Bir dosya seçin",
                systemImage: "doc.text",
                description: Text("Soldaki listeden bir proje veya .env dosyası seçin.")
            )
        }
    }
}
