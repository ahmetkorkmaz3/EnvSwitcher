import Foundation
import Testing
@testable import EnvCore

struct ScanningTests {
    @Test func scanFindsEnvFilesAndSkipsVendorAndRepos() throws {
        let root = try TempDir.make()
        try TempDir.write("A=1", to: ".env", in: root)
        try TempDir.write("A=1\nB=2", to: "apps/cart/.env.local", in: root)
        try TempDir.write("A=", to: "apps/cart/.env.example", in: root)
        try TempDir.write("# readme", to: "apps/cart/README.md", in: root)
        try TempDir.write("S=1", to: "my app/.env.staging", in: root)
        try TempDir.write("X=1", to: "node_modules/pkg/.env", in: root)
        try TempDir.write("X=1", to: "apps/cart/.next/.env", in: root)
        try TempDir.write("X=1", to: ".claude/worktrees/copy/apps/cart/.env.local", in: root)
        try TempDir.write("gitdir: /somewhere", to: "worktrees/feature/.git", in: root)
        try TempDir.write("X=1", to: "worktrees/feature/.env.local", in: root)
        try TempDir.write("[core]", to: "packages/nested/.git/config", in: root)
        try TempDir.write("X=1", to: "packages/nested/.env", in: root)

        #expect(ProjectScanner.scan(root: root) == [
            ScannedFile(relativePath: ".env", keyCount: 1, isSelectedByDefault: true),
            ScannedFile(relativePath: "apps/cart/.env.example", keyCount: 1, isSelectedByDefault: false),
            ScannedFile(relativePath: "apps/cart/.env.local", keyCount: 2, isSelectedByDefault: true),
            ScannedFile(relativePath: "my app/.env.staging", keyCount: 1, isSelectedByDefault: true),
        ])
    }

    @Test func scanSkipsFilesThatOnlyStartWithEnv() throws {
        let root = try TempDir.make()
        try TempDir.write("A=1", to: ".env", in: root)
        try TempDir.write("use flake", to: ".envrc", in: root)
        try TempDir.write("A=1", to: "apps/cart/.environment", in: root)
        #expect(ProjectScanner.scan(root: root).map(\.relativePath) == [".env"])
    }

    @Test func scanMarksTemplatesAsNotSelected() throws {
        let root = try TempDir.make()
        try TempDir.write("A=", to: ".env.sample", in: root)
        try TempDir.write("A=", to: ".env.template", in: root)
        #expect(ProjectScanner.scan(root: root).map(\.isSelectedByDefault) == [false, false])
    }

    @Test func scanWorksWhenRootItselfIsAGitRepo() throws {
        let root = try TempDir.make()
        try TempDir.write("[core]", to: ".git/config", in: root)
        try TempDir.write("A=1", to: ".env", in: root)
        #expect(ProjectScanner.scan(root: root).map(\.relativePath) == [".env"])
    }

    @Test func gitIgnoreCheckerReportsIgnoredTrackedAndNonRepo() throws {
        let root = try TempDir.make()
        try runGit(["init", "-q"], in: root)
        try TempDir.write(".env.local\n", to: ".gitignore", in: root)
        try TempDir.write("A=1", to: "apps/cart/.env.local", in: root)
        try TempDir.write("A=1", to: ".env", in: root)
        #expect(GitIgnoreChecker.isIgnored(relativePath: "apps/cart/.env.local", root: root) == true)
        #expect(GitIgnoreChecker.isIgnored(relativePath: ".env", root: root) == false)
        #expect(GitIgnoreChecker.isIgnored(relativePath: ".env", root: try TempDir.make()) == nil)
    }

    private func runGit(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
    }
}
