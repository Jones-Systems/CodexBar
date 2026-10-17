import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
@testable import CodexBarCore

struct ClaudeFleetProfileDiscoveryTests {
    static let home = URL(fileURLWithPath: "/Users/claude-fleet-fixture")

    static func account(_ alias: String, store: String = "claude-file") -> [String: Any] {
        let config = alias == "default" ? nil : self.home.path + "/.claude-t3/" + alias
        return [
            "provider": "claude", "alias": alias, "store": store,
            "config_dir": config as Any? ?? NSNull(),
            "native_cli": "/fixture/bin/claude",
            "path": (config ?? self.home.path + "/.claude") + "/.credentials.json",
            "metadata_path": (config ?? self.home.path) + "/.claude.json",
        ]
    }

    static func binding(accounts: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "schema": "host-tooling.auth-fleet-binding/v1", "home": self.home.path,
            "accounts": accounts, "host_id": "private-fixture-host", "role": "controller",
            "targets": [["home": "/private/remote-target"]],
        ], options: .sortedKeys)
    }

    static func discovery() throws -> ClaudeFleetProfileDiscovery.Result {
        try ClaudeFleetProfileDiscovery.parse(
            data: self.binding(accounts: [self.account("default"), self.account("jace", store: "claude-keychain")]),
            actualHome: self.home)
    }

    private func unavailable(_ result: ClaudeFleetProfileDiscovery.Result) -> Bool {
        if case .unavailable = result { return true }
        return false
    }

    @Test
    func `projects enrolled references without identity or readiness claims`() throws {
        let result = try Self.discovery()
        #expect(result.profiles.map(\.alias) == ["default", "jace"])
        #expect(result.profiles[0].configDirectory == nil)
        #expect(result.profiles[1].configDirectory == Self.home.path + "/.claude-t3/jace")
        #expect(result.profiles[1].store == "claude-keychain")
        let data = try Self.binding(accounts: [["provider": "codex"], Self.account("default")])
        #expect(ClaudeFleetProfileDiscovery.parse(data: data, actualHome: Self.home).profiles.count == 1)
    }

    @Test
    func `rejects noncanonical alias mismatched home and duplicate aliases`() throws {
        for aliases in [["malcolm"], ["../jace"], ["jace", "jace"]] {
            let data = try Self.binding(accounts: aliases.map { Self.account($0) })
            #expect(self.unavailable(ClaudeFleetProfileDiscovery.parse(data: data, actualHome: Self.home)))
        }
        let data = try Self.binding(accounts: [Self.account("default")])
        #expect(self.unavailable(ClaudeFleetProfileDiscovery.parse(
            data: data, actualHome: URL(fileURLWithPath: "/Users/different"))))
    }

    @Test
    func `rejects explicit default directory malformed native fields and credential path escape`() throws {
        let mutations: [(String, String, Any)] = [
            ("default", "config_dir", Self.home.path + "/.claude"),
            ("jace", "config_dir", NSNull()),
            ("jace", "config_dir", Self.home.path + "/.claude-t3/../jace"),
            ("jace", "path", "/foreign/.credentials.json"),
            ("jace", "metadata_path", "/foreign/.claude.json"),
            ("jace", "native_cli", "claude"),
            ("jace", "native_cli", "/bin/../claude"),
            ("jace", "store", "codex-file"),
        ]
        for (alias, key, value) in mutations {
            var account = Self.account(alias)
            account[key] = value
            let data = try Self.binding(accounts: [account])
            #expect(self.unavailable(ClaudeFleetProfileDiscovery.parse(data: data, actualHome: Self.home)))
        }
    }

    @Test
    func `missing default config field remains unset and optional metadata may be absent`() throws {
        var account = Self.account("default", store: "claude-keychain")
        for key in ["config_dir", "metadata_path", "path"] {
            account.removeValue(forKey: key)
        }
        let result = try ClaudeFleetProfileDiscovery.parse(
            data: Self.binding(accounts: [account]), actualHome: Self.home)
        #expect(result.profiles.count == 1)
        #expect(result.profiles.first?.configDirectory == nil)
    }

    @Test
    func `malformed duplicate escaped keys and oversized data fail closed`() throws {
        let data = try Self.binding(accounts: [Self.account("jace")])
        let text = try #require(String(data: data, encoding: .utf8))
        let duplicate = text.replacingOccurrences(
            of: "\"alias\":\"jace\"", with: "\"alias\":\"jace\",\"ali\\u0061s\":\"default\"")
        for value in ["not-json", "[]", duplicate] {
            #expect(self.unavailable(ClaudeFleetProfileDiscovery.parse(data: Data(value.utf8), actualHome: Self.home)))
        }
        #expect(self.unavailable(ClaudeFleetProfileDiscovery.parse(
            data: Data(repeating: 32, count: ClaudeFleetProfileDiscovery.maximumBytes + 1), actualHome: Self.home)))
    }

    @Test
    func `loader reads only bounded enrollment metadata and distinguishes missing unreadable`() throws {
        let data = try Self.binding(accounts: [Self.account("default")])
        let result = ClaudeFleetProfileDiscovery.discover(actualHome: Self.home) { url, limit in
            #expect(url.path == Self.home.path + "/.local/share/host-tooling/runtime/auth-fleet-binding.json")
            #expect(limit == ClaudeFleetProfileDiscovery.maximumBytes)
            return data
        }
        #expect(result.profiles.count == 1)
        #expect(ClaudeFleetProfileDiscovery.discover(actualHome: Self.home, load: { _, _ in nil }) == .missing)
        struct Unreadable: Error {}
        #expect(self.unavailable(ClaudeFleetProfileDiscovery.discover(actualHome: Self.home, load: { _, _ in
            throw Unreadable()
        })))
    }

    @Test
    func `safe reader accepts only bounded owner private regular metadata files`() throws {
        let manager = FileManager.default
        let fixture = manager.temporaryDirectory
            .appendingPathComponent("ClaudeFleetBindingFixture-" + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(
            at: fixture, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer {
            do { try manager.removeItem(at: fixture) } catch { Issue.record(error, "Fixture cleanup failed") }
        }
        // Foundation's resolver may strip /private on macOS, reintroducing a symlinked ancestor.
        // Resolve only our existing fixture with POSIX realpath; never normalize the reader's input.
        let physicalPath = try #require(realpath(fixture.path, nil), "Fixture realpath failed: errno=\(errno)")
        defer { free(physicalPath) }
        let root = URL(fileURLWithPath: String(cString: physicalPath), isDirectory: true)
        let binding = root.appendingPathComponent("binding.json")
        #expect(throws: Never.self, "Missing synthetic binding at \(binding.path)") {
            #expect(try ClaudeFleetProfileDiscovery.readBinding(url: binding, maximumBytes: 2) == nil)
        }
        try Data("{}".utf8).write(to: binding)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: binding.path)
        var info = stat()
        let status = lstat(binding.path, &info)
        try #require(status == 0, "Synthetic binding lstat failed: errno=\(errno)")
        #expect(info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG))
        #expect(info.st_mode & 0o7777 == 0o600)
        #expect(info.st_uid == getuid())
        #expect(info.st_nlink == 1)
        #expect(info.st_size == 2)
        #expect(throws: Never.self, "Private synthetic binding at \(binding.path)") {
            #expect(try ClaudeFleetProfileDiscovery.readBinding(url: binding, maximumBytes: 2) == Data("{}".utf8))
        }
        #expect(throws: (any Error).self) {
            try ClaudeFleetProfileDiscovery.readBinding(url: binding, maximumBytes: 1)
        }
        try manager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: binding.path)
        #expect(throws: (any Error).self) {
            try ClaudeFleetProfileDiscovery.readBinding(url: binding, maximumBytes: 2)
        }
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: binding.path)
        let link = root.appendingPathComponent("link.json")
        try manager.createSymbolicLink(at: link, withDestinationURL: binding)
        #expect(throws: (any Error).self) {
            try ClaudeFleetProfileDiscovery.readBinding(url: link, maximumBytes: 2)
        }
        let directoryLink = root.appendingPathComponent("directory-link")
        try manager.createSymbolicLink(at: directoryLink, withDestinationURL: root)
        #expect(throws: (any Error).self) {
            try ClaudeFleetProfileDiscovery.readBinding(
                url: directoryLink.appendingPathComponent("binding.json"), maximumBytes: 2)
        }
        try manager.linkItem(at: binding, to: root.appendingPathComponent("hardlink.json"))
        #expect(throws: (any Error).self) {
            try ClaudeFleetProfileDiscovery.readBinding(url: binding, maximumBytes: 2)
        }
    }
}
