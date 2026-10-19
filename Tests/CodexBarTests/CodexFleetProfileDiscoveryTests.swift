import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
@testable import CodexBarCore

struct CodexFleetProfileDiscoveryTests {
    private static let home = URL(fileURLWithPath: "/Users/fleet-fixture")

    private static func account(_ alias: String = "research") -> [String: Any] {
        let config = self.home.path + "/.codex-t3/" + alias
        return [
            "provider": "codex", "alias": alias, "store": "codex-file", "config_dir": config,
            "path": config + "/auth.json", "native_cli": "/usr/local/bin/codex", "metadata_path": NSNull(),
        ]
    }

    private static func binding(accounts: [[String: Any]]? = nil) -> [String: Any] {
        [
            "schema": "host-tooling.auth-fleet-binding/v1", "home": self.home.path,
            "host_id": "fixture-host", "role": "controller", "accounts": accounts ?? [self.account()],
        ]
    }

    private static func parse(_ value: [String: Any]) throws -> CodexFleetProfileDiscovery.Result {
        try CodexFleetProfileDiscovery.parse(data: JSONSerialization.data(withJSONObject: value), actualHome: self.home)
    }

    private static func isUnavailable(_ result: CodexFleetProfileDiscovery.Result) -> Bool {
        if case .unavailable = result { return true }
        return false
    }

    @Test
    func `local Codex homes preserve account order and exclude Claude and remote targets`() throws {
        var binding = Self.binding(accounts: [Self.account("second"), ["provider": "claude"], Self.account("first")])
        binding["targets"] = [["home": "/remote/.codex-t3/other", "host_id": "remote"]]
        #expect(try Self.parse(binding) == .available([
            Self.home.path + "/.codex-t3/second", Self.home.path + "/.codex-t3/first",
        ]))
        #expect(try Self.parse(Self.binding(accounts: [["provider": "claude"]])) == .available([]))
    }

    @Test
    func `invalid binding identity and account shapes fail closed`() throws {
        for (key, value) in [
            ("schema", "future-schema"), ("home", "/Users/someone-else"),
            ("home", "/Users/fleet-fixture/../fleet-fixture"), ("role", "remote"), ("host_id", ""),
        ] {
            var binding = Self.binding()
            binding[key] = value
            #expect(try Self.isUnavailable(Self.parse(binding)))
        }
        var binding = Self.binding()
        binding["accounts"] = ["unexpected": Self.account()]
        #expect(try Self.isUnavailable(Self.parse(binding)))
        #expect(try Self.isUnavailable(Self.parse(Self.binding(accounts: []))))
        #expect(try Self.isUnavailable(Self.parse(Self.binding(accounts: [Self.account(), Self.account()]))))
    }

    @Test
    func `Codex records require safe alias file store and exact local auth path`() throws {
        for (key, value) in [
            ("provider", "other"), ("store", "file"), ("store", "claude-file"),
            ("alias", "../escape"), ("alias", "."), ("alias", "nested/alias"),
            ("config_dir", Self.home.path + "/.codex-t3/../research"),
            ("config_dir", "/remote/.codex-t3/research"),
            ("path", Self.home.path + "/.codex-t3/research/other.json"),
            ("native_cli", "codex"),
        ] {
            var account = Self.account()
            account[key] = value
            #expect(try Self.isUnavailable(Self.parse(Self.binding(accounts: [account]))))
        }
        for key in ["provider", "alias", "store", "config_dir", "path", "native_cli"] {
            var account = Self.account()
            account.removeValue(forKey: key)
            #expect(try Self.isUnavailable(Self.parse(Self.binding(accounts: [account]))))
        }
    }

    @Test
    func `malformed JSON duplicate keys and oversized binding fail closed`() throws {
        let valid = try JSONSerialization.data(withJSONObject: Self.binding(), options: [.sortedKeys])
        let text = try #require(String(data: valid, encoding: .utf8))
        for input in [
            "not json", "[]", "{\"schema\":1,\"schema\":2}",
            text.replacingOccurrences(
                of: "\"alias\":\"research\"", with: "\"alias\":\"research\",\"alias\":\"research\""),
            text.replacingOccurrences(
                of: "\"alias\":\"research\"", with: "\"alias\":\"research\",\"ali\\u0061s\":\"research\""),
        ] {
            #expect(Self.isUnavailable(CodexFleetProfileDiscovery.parse(data: Data(input.utf8), actualHome: Self.home)))
        }
        #expect(Self.isUnavailable(CodexFleetProfileDiscovery.parse(
            data: Data(repeating: 32, count: CodexFleetProfileDiscovery.maximumBytes + 1), actualHome: Self.home)))
    }

    @Test
    func `injected loader reads only the exact binding and distinguishes missing from unavailable`() throws {
        var calls = 0
        let data = try JSONSerialization.data(withJSONObject: Self.binding())
        let available = CodexFleetProfileDiscovery.discover(actualHome: Self.home) { url, limit in
            calls += 1
            #expect(url.path == Self.home.path + "/.local/share/host-tooling/runtime/auth-fleet-binding.json")
            #expect(limit == CodexFleetProfileDiscovery.maximumBytes)
            return data
        }
        #expect(calls == 1)
        #expect(available == .available([Self.home.path + "/.codex-t3/research"]))
        #expect(CodexFleetProfileDiscovery.discover(actualHome: Self.home, load: { _, _ in nil }) == .missing)
        struct FixtureError: Error {}
        #expect(Self.isUnavailable(CodexFleetProfileDiscovery.discover(actualHome: Self.home, load: { _, _ in
            throw FixtureError()
        })))
    }

    @Test
    func `secure reader rejects unsafe metadata fixtures without following symlinks`() throws {
        let manager = FileManager.default
        let fixture = TestFixtureScratch.root
            .appendingPathComponent("CodexFleetProfileDiscoveryTests-" + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(
            at: fixture, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer {
            do { try manager.removeItem(at: fixture) } catch { Issue.record(error, "Fixture cleanup failed") }
        }
        // Bind the existing fixture to its POSIX physical path; never normalize the reader's input.
        let physicalPath = try #require(realpath(fixture.path, nil), "Fixture realpath failed: errno=\(errno)")
        defer { free(physicalPath) }
        let root = URL(fileURLWithPath: String(cString: physicalPath), isDirectory: true)
        let file = root.appendingPathComponent("binding.json")
        let missingBinding = try CodexFleetProfileDiscovery.readBinding(url: file, maximumBytes: 10)
        #expect(missingBinding == nil, "Missing synthetic binding at \(file.path)")
        try Data("{}".utf8).write(to: file)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        var info = stat()
        let status = lstat(file.path, &info)
        try #require(status == 0, "Synthetic binding lstat failed: errno=\(errno)")
        #expect(info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG))
        #expect(info.st_mode & 0o7777 == 0o600)
        #expect(info.st_uid == getuid())
        #expect(info.st_nlink == 1)
        #expect(info.st_size == 2)
        let privateBinding = try CodexFleetProfileDiscovery.readBinding(url: file, maximumBytes: 10)
        #expect(privateBinding == Data("{}".utf8), "Private synthetic binding at \(file.path)")
        #expect(throws: (any Error).self) {
            try CodexFleetProfileDiscovery.readBinding(url: file, maximumBytes: 1)
        }
        try manager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        #expect(throws: (any Error).self) {
            try CodexFleetProfileDiscovery.readBinding(url: file, maximumBytes: 10)
        }
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let symlink = root.appendingPathComponent("link.json")
        try manager.createSymbolicLink(at: symlink, withDestinationURL: file)
        #expect(throws: (any Error).self) {
            try CodexFleetProfileDiscovery.readBinding(url: symlink, maximumBytes: 10)
        }
        let directoryLink = root.appendingPathComponent("redirect")
        try manager.createSymbolicLink(at: directoryLink, withDestinationURL: root)
        #expect(throws: (any Error).self) {
            try CodexFleetProfileDiscovery.readBinding(
                url: directoryLink.appendingPathComponent("binding.json"), maximumBytes: 10)
        }
        let hardlink = root.appendingPathComponent("hardlink.json")
        try manager.linkItem(at: file, to: hardlink)
        #expect(throws: (any Error).self) {
            try CodexFleetProfileDiscovery.readBinding(url: file, maximumBytes: 10)
        }
    }

    @Test
    func `ordinary tests disable production discovery before ambient metadata access`() {
        #expect(CodexFleetProfileDiscovery.discover() == .unavailable("Fleet discovery is disabled in tests"))
    }
}
