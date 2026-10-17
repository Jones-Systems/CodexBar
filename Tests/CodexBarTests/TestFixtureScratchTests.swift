import Foundation
import Testing
@testable import CodexBarCore

struct TestFixtureScratchTests {
    @Test
    func `rejects missing parents without allocating a fallback`() throws {
        #expect(throws: TestFixtureScratch.ConfigurationError.self) {
            try TestFixtureScratch.resolve(environment: [:])
        }
        #expect(throws: TestFixtureScratch.ConfigurationError.self) {
            try TestFixtureScratch.resolve(environment: [
                TestFixtureScratch.workspaceEnvironmentKey: TestFixtureScratch.root.path,
            ])
        }
    }

    @Test
    func `rejects missing files aliases and escapes before allocation`() throws {
        let workspace = TestFixtureScratch.root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let parent = workspace.appendingPathComponent("parent", isDirectory: true)
        let file = workspace.appendingPathComponent("file")
        let alias = workspace.appendingPathComponent("alias")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        try Data("sentinel".utf8).write(to: file)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: parent)
        let before = try FileManager.default.contentsOfDirectory(atPath: workspace.path).sorted()
        for invalid in [
            "", ".", workspace.path, TestFixtureScratch.root.path, file.path, alias.path,
            workspace.appendingPathComponent("missing").path,
            parent.path + "/../parent", parent.path + "/./", parent.path + "\n",
            workspace.path + "-sibling",
        ] {
            #expect(throws: TestFixtureScratch.ConfigurationError.self) {
                try TestFixtureScratch.resolve(environment: [
                    TestFixtureScratch.workspaceEnvironmentKey: workspace.path,
                    TestFixtureScratch.parentEnvironmentKey: invalid,
                ])
            }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: workspace.path).sorted() == before)
        #expect(try Data(contentsOf: file) == Data("sentinel".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: parent.path).isEmpty)
    }

    @Test
    func `borrows a canonical parent and preserves sibling fixtures after child cleanup`() throws {
        let workspace = TestFixtureScratch.root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let parent = workspace.appendingPathComponent("parent with spaces", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let resolved = try TestFixtureScratch.resolve(environment: [
            TestFixtureScratch.workspaceEnvironmentKey: workspace.path,
            TestFixtureScratch.parentEnvironmentKey: parent.path,
        ])
        #expect(resolved == parent)
        let sibling = parent.appendingPathComponent(UUID().uuidString)
        let child = resolved.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try Data("sibling".utf8).write(to: sibling)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
        try FileManager.default.removeItem(at: child)
        #expect(!FileManager.default.fileExists(atPath: child.path))
        #expect(try Data(contentsOf: sibling) == Data("sibling".utf8))
        #expect(FileManager.default.fileExists(atPath: parent.path))
    }

    @Test
    func `isolated defaults stay below the prepared parent`() {
        let parent = TestFixtureScratch.root.pathComponents
        let defaults = [
            ProviderSessionStoreFile.url(for: "fixture-session.json"),
            CodexPriorityDatabasePath.defaultURL(),
            FileManagedCodexAccountStore.defaultURL(),
            CodexOpenAIWorkspaceIdentityCache.defaultURL(),
            ClaudeStatusProbe.probeWorkingDirectoryURL(),
        ]
        for url in defaults {
            #expect(url.pathComponents.count > parent.count)
            #expect(url.pathComponents.starts(with: parent))
        }
    }

    @Test
    func `isolated Codex probe ignores an inherited external temporary directory`() throws {
        let support = try CodexStatusProbeIsolation.supportDirectory(environment: [
            "TMPDIR": "/synthetic-unread-external-temporary-directory",
        ])
        #expect(support.deletingLastPathComponent().deletingLastPathComponent() == TestFixtureScratch.root)
    }

    @Test
    func `isolated Codex probe preserves a canonical contained temporary override`() throws {
        let child = TestFixtureScratch.root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: child) }
        let support = try CodexStatusProbeIsolation.supportDirectory(environment: ["TMPDIR": child.path])
        #expect(support.deletingLastPathComponent().deletingLastPathComponent() == child)
    }

}
