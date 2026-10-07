import Foundation
import Testing
@testable import EnvCore

struct FileTreeTests {
    @Test func buildsTreeAndMergesSingleFileFolders() {
        let cart = EnvTarget(relativePath: "apps/cart/.env.local")
        let shellLocal = EnvTarget(relativePath: "apps/shell/.env.local")
        let shellExample = EnvTarget(relativePath: "apps/shell/.env.example")
        let rootEnv = EnvTarget(relativePath: ".env")

        let tree = FileTree.build([shellLocal, rootEnv, cart, shellExample])

        #expect(tree == [
            FileTreeNode(id: "apps", name: "apps", targetId: nil, children: [
                FileTreeNode(id: "apps/cart/.env.local", name: "cart/.env.local", targetId: cart.id, children: nil),
                FileTreeNode(id: "apps/shell", name: "shell", targetId: nil, children: [
                    FileTreeNode(id: "apps/shell/.env.example", name: ".env.example", targetId: shellExample.id, children: nil),
                    FileTreeNode(id: "apps/shell/.env.local", name: ".env.local", targetId: shellLocal.id, children: nil),
                ]),
            ]),
            FileTreeNode(id: ".env", name: ".env", targetId: rootEnv.id, children: nil),
        ])
    }

    @Test func emptyTargetsGiveEmptyTree() {
        #expect(FileTree.build([]).isEmpty)
    }
}
