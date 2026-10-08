import EnvCore
import SwiftUI

/// One row of the sidebar tree. Its `id` is also the List selection value.
private struct SidebarNode: Identifiable, Hashable {
    enum Kind: Hashable {
        case project(UUID)
        case target(project: UUID, target: UUID)
        case folder
    }

    let id: String
    let kind: Kind
    let name: String
    var children: [SidebarNode]?

    var selection: SidebarSelection? {
        switch kind {
        case .project(let id): .project(id)
        case .target(let project, let target): .target(project: project, target: target)
        case .folder: nil
        }
    }

    static func id(for selection: SidebarSelection) -> String {
        switch selection {
        case .project(let id): "project:\(id.uuidString)"
        case .target(let project, let target): "target:\(project.uuidString):\(target.uuidString)"
        }
    }

    static func tree(for projects: [Project]) -> [SidebarNode] {
        projects.map { project in
            SidebarNode(
                id: id(for: .project(project.id)),
                kind: .project(project.id),
                name: project.name,
                children: FileTree.build(project.targets).map { node(from: $0, project: project.id) }
            )
        }
    }

    private static func node(from file: FileTreeNode, project: UUID) -> SidebarNode {
        if let targetId = file.targetId {
            return SidebarNode(
                id: id(for: .target(project: project, target: targetId)),
                kind: .target(project: project, target: targetId),
                name: file.name,
                children: nil
            )
        }
        return SidebarNode(
            id: "folder:\(project.uuidString):\(file.id)",
            kind: .folder,
            name: file.name,
            children: file.children?.map { node(from: $0, project: project) }
        )
    }
}

struct Sidebar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        List(SidebarNode.tree(for: state.store.projects), children: \.children, selection: selectedNodeId) { node in
            row(for: node)
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Button { state.showAddProject = true } label: {
                Label("Add Project", systemImage: "plus")
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

    /// Maps the row id to AppState.selection. A folder row keeps the current selection.
    private var selectedNodeId: Binding<String?> {
        Binding(
            get: { state.selection.map(SidebarNode.id(for:)) },
            set: { newId in
                guard let newId else {
                    state.selection = nil
                    return
                }
                let nodes = SidebarNode.tree(for: state.store.projects)
                if let selection = Self.find(newId, in: nodes)?.selection {
                    state.selection = selection
                }
            }
        )
    }

    private static func find(_ id: String, in nodes: [SidebarNode]) -> SidebarNode? {
        for node in nodes {
            if node.id == id { return node }
            if let found = find(id, in: node.children ?? []) { return found }
        }
        return nil
    }

    @ViewBuilder
    private func row(for node: SidebarNode) -> some View {
        switch node.kind {
        case .project(let id):
            if let project = state.project(id: id) {
                ProjectRow(project: project)
            }
        case .target(let projectId, let targetId):
            if let project = state.project(id: projectId),
               let target = project.targets.first(where: { $0.id == targetId }) {
                FileRow(name: node.name, target: target, project: project)
            }
        case .folder:
            Label(node.name, systemImage: "folder")
        }
    }
}

private struct ProjectRow: View {
    @Environment(AppState.self) private var state
    let project: Project

    var body: some View {
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
    }
}

private struct FileRow: View {
    @Environment(AppState.self) private var state
    let name: String
    let target: EnvTarget
    let project: Project

    var body: some View {
        Label {
            HStack {
                Text(name)
                Spacer()
                if state.driftByTarget[target.id] == .modified {
                    Image(systemName: "exclamationmark.triangle.fill").symbolRenderingMode(.multicolor)
                }
                if let environment = target.activeEnvironmentId.flatMap({ project.environment(id: $0) }) {
                    Circle().fill(environment.color.color).frame(width: 8, height: 8)
                        .help("Environment on disk: \(environment.name)")
                }
            }
        } icon: {
            Image(systemName: "doc.text")
        }
    }
}
