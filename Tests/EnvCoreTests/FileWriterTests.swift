import Foundation
import Testing
@testable import EnvCore

struct FileWriterTests {
    @Test func writeKeepsTheFilePermissions() throws {
        let root = try TempDir.make()
        try TempDir.write("A=1\n", to: ".env", in: root)
        let url = root.appendingPathComponent(".env")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)

        try LocalFileWriter().write(Data("A=2\n".utf8), to: url)

        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
        #expect(try TempDir.read(".env", in: root) == "A=2\n")
    }

    @Test func writeGoesThroughASymlink() throws {
        let root = try TempDir.make()
        try TempDir.write("A=1\n", to: "shared/.env", in: root)
        let link = root.appendingPathComponent(".env")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.appendingPathComponent("shared/.env"))

        try LocalFileWriter().write(Data("A=2\n".utf8), to: link)

        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path).hasSuffix("shared/.env"))
        #expect(try TempDir.read("shared/.env", in: root) == "A=2\n")
    }
}
