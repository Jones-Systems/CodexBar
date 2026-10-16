import Foundation
import Testing
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
        let root = manager.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("CodexFleetProfileDiscoveryTests-" + UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let file = root.appendingPathComponent("binding.json")
        #expect(try CodexFleetProfileDiscovery.readBinding(url: file, maximumBytes: 10) == nil)
        try Data("{}".utf8).write(to: file)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        #expect(try CodexFleetProfileDiscovery.readBinding(url: file, maximumBytes: 10) == Data("{}".utf8))
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
