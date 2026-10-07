import EnvCore
import SwiftUI

struct Sidebar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        List(selection: $state.selection) {
            Section("Projeler") {
                ForEach(state.store.projects) { project in
                    DisclosureGroup {
                        OutlineGroup(FileTree.build(project.targets), children: \.children) { node in
                            FileRow(node: node, project: project)
                                .tag(node.targetId.map { SidebarSelection.target(project: project.id, target: $0) })
                        }
                    } label: {
                        Label {
                            HStack {
                                Text(project.name)
                                Spacer()
                                if state.hasDrift(project) {
                                    Image(systemName: "exclamationmark.triangle.fill").symbolRenderingMode(.multicolor)
                                }
                                Text(state.stateText(project)).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: state.rootExists(project) ? "folder" : "questionmark.folder")
                        }
                        .tag(SidebarSelection?.some(.project(project.id)))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Button { state.showAddProject = true } label: {
                Label("Proje Ekle", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            state.pendingAddURL = url
            state.showAddProject = true
            return true
        }
    }
}

private struct FileRow: View {
    @Environment(AppState.self) private var state
    let node: FileTreeNode
    let project: Project

    var body: some View {
        if let targetId = node.targetId, let target = project.targets.first(where: { $0.id == targetId }) {
            Label {
                HStack {
                    Text(node.name)
                    Spacer()
                    if state.driftByTarget[targetId] == .modified {
                        Image(systemName: "exclamationmark.triangle.fill").symbolRenderingMode(.multicolor)
                    }
                    if let environment = target.activeEnvironmentId.flatMap({ project.environment(id: $0) }) {
                        Circle().fill(environment.color.color).frame(width: 8, height: 8)
                            .help("Diskteki ortam: \(environment.name)")
                    }
                }
            } icon: {
                Image(systemName: "doc.text")
            }
        } else {
            Label(node.name, systemImage: "folder")
        }
    }
}
