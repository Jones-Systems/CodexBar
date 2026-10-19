import Foundation
import Testing
@testable import CodexBarCore

struct JonesStateRootTests {
    private static let identity = JonesStateRoot.Identity(
        bundleID: "com.example.fixture",
        groupID: "FIXTURE.com.example.fixture",
        teamID: "FIXTURE",
        iCloudID: "iCloud.com.example.fixture")

    private static var metadata: [String: Any] {
        [
            "JonesStateKey": "jones",
            "JonesAppBundleID": self.identity.bundleID,
            "JonesAppGroupID": self.identity.groupID,
            "CodexBarTeamID": self.identity.teamID,
            "JonesICloudID": self.identity.iCloudID,
        ]
    }

    @Test
    func `valid string marker survives packaged plist serialization`() throws {
        for format in [PropertyListSerialization.PropertyListFormat.xml, .binary] {
            let data = try PropertyListSerialization.data(fromPropertyList: Self.metadata, format: format, options: 0)
            let propertyList = try PropertyListSerialization.propertyList(from: data, format: nil)
            let info = try #require(propertyList as? [String: Any])
            #expect(JonesStateRoot.identity(info: info) == Self.identity)
        }
    }

    @Test
    func `other identity fields without a marker preserve absent legacy behavior`() {
        var info = Self.metadata
        info.removeValue(forKey: "JonesStateKey")
        #expect(JonesStateRoot.identity(info: info) == nil)
        #expect(JonesStateRoot.identity(info: [:]) == nil)
    }

    @Test
    func `app widget and bundled CLI resolve the same identity without state reads`() {
        var reads: [URL] = []
        let app = URL(fileURLWithPath: "/synthetic/Fixture.app")
        let plist = app.appendingPathComponent("Contents/Info.plist")
        let appIdentity = JonesStateRoot.resolveIdentity(
            info: Self.metadata,
            executableURL: app.appendingPathComponent("Contents/MacOS/CodexBar"),
            readInfo: { url in reads.append(url); return nil })
        let widgetIdentity = JonesStateRoot.resolveIdentity(
            info: Self.metadata,
            executableURL: app.appendingPathComponent("Contents/PlugIns/Widget.appex/Contents/MacOS/Widget"),
            readInfo: { url in reads.append(url); return nil })
        #expect(reads.isEmpty)
        let cliIdentity = JonesStateRoot.resolveIdentity(
            info: [:],
            executableURL: app.appendingPathComponent("Contents/Helpers/CodexBarCLI"),
            readInfo: { url in
                reads.append(url)
                return url == plist ? Self.metadata : nil
            })
        #expect(appIdentity == Self.identity)
        #expect(widgetIdentity == appIdentity)
        #expect(cliIdentity == appIdentity)
        #expect(reads == [plist])
    }

    @Test
    func `absent identity preserves upstream and unbundled CLI behavior`() {
        #expect(JonesStateRoot.identity(info: ["CFBundleIdentifier": "com.steipete.codexbar"]) == nil)
        var reads: [URL] = []
        #expect(JonesStateRoot.resolveIdentity(
            info: [:],
            executableURL: URL(fileURLWithPath: "/synthetic/bin/codexbar"),
            readInfo: { url in reads.append(url); return Self.metadata }) == nil)
        #expect(reads.isEmpty)
        #expect(JonesStateRoot.resolveIdentity(
            info: [:],
            executableURL: URL(fileURLWithPath: "/synthetic/Stock.app/Contents/Helpers/CodexBarCLI"),
            readInfo: { _ in ["CFBundleIdentifier": "com.steipete.codexbar"] }) == nil)
    }

    @Test
    func `owned relative paths preserve suffixes and isolate all root families`() {
        let cases = [
            (".codexbar/antigravity/oauth_creds.json", ".codexbar-jones/antigravity/oauth_creds.json"),
            (".codexbar/antigravity/agy-session.json", ".codexbar-jones/antigravity/agy-session.json"),
            (".codexbar/antigravity/agy-session.lock", ".codexbar-jones/antigravity/agy-session.lock"),
            (".codexbar/claude-oauth-cache.lock", ".codexbar-jones/claude-oauth-cache.lock"),
            ("CodexBar/managed-codex-homes", "CodexBar Jones/managed-codex-homes"),
            ("CodexBar/managed-codex-accounts.json", "CodexBar Jones/managed-codex-accounts.json"),
            ("CodexBar/codex-account-snapshots.json", "CodexBar Jones/codex-account-snapshots.json"),
            ("CodexBar/codex-openai-workspaces.json", "CodexBar Jones/codex-openai-workspaces.json"),
            ("CodexBar/token-accounts.json", "CodexBar Jones/token-accounts.json"),
            ("CodexBar/usage-history.jsonl", "CodexBar Jones/usage-history.jsonl"),
            ("CodexBar/cookie-cache.lock", "CodexBar Jones/cookie-cache.lock"),
            ("CodexBar/ClaudeProbe", "CodexBar Jones/ClaudeProbe"),
            ("CodexBar/CodexStatusProbe", "CodexBar Jones/CodexStatusProbe"),
            ("CodexBar/widget-snapshot.json", "CodexBar Jones/widget-snapshot.json"),
            ("com.steipete.codexbar/openai-dashboard.json", "CodexBar Jones/openai-dashboard.json"),
            ("com.steipete.codexbar/history", "CodexBar Jones/history"),
            ("com.steipete.codexbar/sync/engine-state.json", "CodexBar Jones/sync/engine-state.json"),
            ("CodexBar/cost-usage", "CodexBar Jones/cost-usage"),
            ("CodexBar/model-pricing", "CodexBar Jones/model-pricing"),
            ("CodexBar/opencodex-usage", "CodexBar Jones/opencodex-usage"),
            ("Library/Caches/CodexBar/plugins", "Library/Caches/CodexBar Jones/plugins"),
            (".config/codexbar/providers", ".config/codexbar-jones/providers"),
            ("Library/Logs/CodexBar/CodexBar.log", "Library/Logs/CodexBar Jones/CodexBar.log"),
        ]
        for (legacy, expected) in cases {
            #expect(JonesStateRoot.path(legacy, identity: nil) == legacy)
            #expect(JonesStateRoot.path(legacy, identity: Self.identity) == expected)
        }
        for providerPath in [".codex", ".claude", ".authfleet", "CodexBar-other", "/synthetic//unchanged/"] {
            #expect(JonesStateRoot.path(providerPath, identity: Self.identity) == providerPath)
        }
    }

    @Test
    func `credential namespaces are injective and upstream services remain exact without overlay`() {
        let services = [
            "com.steipete.CodexBar", "com.steipete.codexbar", "com.steipete.codexbar.cache",
            "com.steipete.CodexBar.cache", "cache", "service.cache", "",
        ]
        let forkServices = services.map { JonesStateRoot.namespace($0, identity: Self.identity) }
        #expect(Set(forkServices).count == services.count)
        for (legacy, fork) in zip(services, forkServices) {
            #expect(JonesStateRoot.namespace(legacy, identity: nil) == legacy)
            #expect(fork == Self.identity.bundleID + ".service." + legacy)
            #expect(!services.contains(fork))
        }
        let domains = ["com.steipete.codexbar", "com.steipete.codexbar.debug"]
        #expect(JonesStateRoot.defaultsDomains(domains, identity: nil) == domains)
        #expect(JonesStateRoot.defaultsDomains(domains, identity: Self.identity) == [Self.identity.bundleID])
    }

    @Test
    func `explicit config wins and fork resolution never probes old configuration`() {
        let fm = JonesRecordingFileManager()
        let home = fm.homeDirectoryForCurrentUser
        let environment = ["CODEXBAR_CONFIG": " /synthetic/explicit.json ", "XDG_CONFIG_HOME": "/synthetic/xdg"]
        for identity in [nil, Self.identity] {
            #expect(CodexBarConfigStore.defaultURL(
                home: home, environment: environment, fileManager: fm, forkIdentity: identity)
                .path == "/synthetic/explicit.json")
        }
        #expect(CodexBarConfigStore.defaultURL(
            home: home,
            environment: ["XDG_CONFIG_HOME": "/synthetic/xdg"],
            fileManager: fm,
            forkIdentity: Self.identity).path == home.path + "/.codexbar-jones/config.json")
        #expect(fm.operations.isEmpty)
    }

    @Test
    func `no overlay keeps XDG existing legacy and fresh config precedence`() {
        let fm = JonesRecordingFileManager()
        let home = fm.homeDirectoryForCurrentUser
        let xdg = home.path + "/.config/codexbar/config.json"
        let legacy = home.path + "/.codexbar/config.json"
        #expect(CodexBarConfigStore.defaultURL(
            home: home,
            environment: ["XDG_CONFIG_HOME": "/synthetic/xdg"],
            fileManager: fm,
            forkIdentity: nil).path == "/synthetic/xdg/codexbar/config.json")
        #expect(fm.operations.isEmpty)
        for (existing, expected) in [([xdg, legacy], xdg), ([legacy], legacy), ([], xdg)] {
            fm.existing = Set(existing)
            #expect(CodexBarConfigStore.defaultURL(
                home: home, environment: [:], fileManager: fm, forkIdentity: nil).path == expected)
        }
    }

    @Test
    func `fork app group skips migration without defaults or filesystem mutation`() {
        let fm = JonesRecordingFileManager()
        let standard = InMemoryUserDefaults()
        let current = InMemoryUserDefaults()
        let legacy = InMemoryUserDefaults(values: ["widgetSelectedProvider": "codex"])
        let result = AppGroupSupport.migrateLegacyDataIfNeeded(
            bundleID: Self.identity.bundleID,
            standardDefaults: standard,
            fileManager: fm,
            homeDirectory: fm.homeDirectoryForCurrentUser,
            currentDefaultsOverride: current,
            legacyDefaultsOverride: legacy,
            currentSnapshotURLOverride: fm.root.appendingPathComponent("current/widget-snapshot.json"),
            legacySnapshotURLOverride: fm.root.appendingPathComponent("legacy/widget-snapshot.json"),
            forkIdentity: Self.identity)
        #expect(result.status == .noChangesNeeded)
        #expect(!result.copiedSnapshot)
        #expect(result.copiedDefaults == 0)
        #expect(fm.operations.isEmpty)
        #expect(standard.dictionaryRepresentation().isEmpty)
        #expect(current.dictionaryRepresentation().isEmpty)
        #expect(legacy.string(forKey: "widgetSelectedProvider") == "codex")
        #expect(AppGroupSupport.currentGroupID(for: Self.identity.bundleID, forkIdentity: Self.identity)
            == Self.identity.groupID)
        #expect(AppGroupSupport.resolvedTeamID(infoDictionaryOverride: Self.metadata, bundleURLOverride: nil)
            == Self.identity.teamID)
    }
}

/// Virtual filesystem: no fixture directories or real home access, even on an unexpected call.
private final class JonesRecordingFileManager: FileManager, @unchecked Sendable {
    let root = URL(fileURLWithPath: "/synthetic/JonesStateRootTests-\(UUID().uuidString)")
    var operations: [String] = []
    var existing: Set<String> = []

    override var homeDirectoryForCurrentUser: URL {
        self.root.appendingPathComponent("home")
    }

    override var temporaryDirectory: URL {
        self.root.appendingPathComponent("scratch")
    }

    override func fileExists(atPath path: String) -> Bool {
        self.operations.append("exists: \(path)")
        #expect(path.hasPrefix(self.root.path + "/"))
        return self.existing.contains(path)
    }

    override func urls(for _: SearchPathDirectory, in _: SearchPathDomainMask) -> [URL] {
        self.operations.append("search paths")
        return [self.root.appendingPathComponent("support")]
    }

    #if os(macOS)
    override func containerURL(forSecurityApplicationGroupIdentifier _: String) -> URL? {
        self.operations.append("container")
        return nil
    }
    #endif

    override func createDirectory(
        at url: URL, withIntermediateDirectories _: Bool, attributes _: [FileAttributeKey: Any]? = nil) throws
    {
        self.operations.append("create: \(url.path)")
        throw CocoaError(.fileWriteNoPermission)
    }

    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        self.operations.append("copy: \(srcURL.path) -> \(dstURL.path)")
        throw CocoaError(.fileWriteNoPermission)
    }
}
