import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct NetdataConfigurationTests {
    @Test
    func `absent corrupt unsupported and invalid records load disabled`() throws {
        var unsupported = netdataTestConfiguration()
        unsupported.version = 2
        var invalid = netdataTestConfiguration()
        invalid.host?.environmentID = "local"
        let records: [Data?] = try [
            nil,
            Data("not JSON".utf8),
            JSONEncoder().encode(unsupported),
            JSONEncoder().encode(invalid),
        ]
        for record in records {
            let defaults = InMemoryUserDefaults()
            defaults.set(record, forKey: SettingsStore.netdataConfigurationKey)
            #expect(SettingsStore.loadNetdataConfiguration(userDefaults: defaults) == NetdataConfiguration())
            #expect(defaults.data(forKey: SettingsStore.netdataConfigurationKey) == record)
        }
    }

    @Test
    func `Apply validates before saving and draft typing cannot reconfigure`() throws {
        let fixture = try NetdataAppTestFixture()
        defer { fixture.close() }
        let providerBytes = try Data(contentsOf: fixture.settings.configStore.fileURL)
        var draft = NetdataConfigurationDraft(configuration: fixture.settings.netdataConfiguration)
        draft = NetdataConfigurationDraft(configuration: netdataTestConfiguration())
        #expect(!fixture.settings.netdataConfiguration.enabled)
        #expect(fixture.defaults.data(forKey: SettingsStore.netdataConfigurationKey) == nil)
        try fixture.settings.applyNetdataConfiguration(draft.configuration)
        let savedBytes = fixture.defaults.data(forKey: SettingsStore.netdataConfigurationKey)
        #expect(SettingsStore.loadNetdataConfiguration(userDefaults: fixture.defaults) == draft.configuration)
        draft.origin = "http://127.0.0.1:19999/"
        #expect(throws: (any Error).self) { try fixture.settings.applyNetdataConfiguration(draft.configuration) }
        #expect(fixture.defaults.data(forKey: SettingsStore.netdataConfigurationKey) == savedBytes)
        #expect(fixture.settings.netdataConfiguration == netdataTestConfiguration())
        #expect(try Data(contentsOf: fixture.settings.configStore.fileURL) == providerBytes)
        #expect(fixture.defaults.object(forKey: AppGroupSupport.migrationVersionKey) == nil)
    }

    @Test
    func `target and navigation validation retain existing loopback boundaries`() throws {
        for origin in [
            "http://127.0.0.1:19999/", "https://localhost:19999", "http://example.invalid",
            "http://user@localhost", "http://localhost?x=1", "http://localhost#x", "http://localhost/path",
        ] {
            var configuration = netdataTestConfiguration()
            configuration.host?.origin = origin
            #expect(throws: (any Error).self) { try configuration.validate() }
        }
        for id in ["local", "", " bad", "bad\n", String(repeating: "x", count: 129)] {
            var configuration = netdataTestConfiguration()
            configuration.host?.environmentID = id
            #expect(throws: (any Error).self) { try configuration.validate() }
        }
        var configuration = netdataTestConfiguration()
        configuration.host?.expectedMachineGUID = "not-a-guid"
        #expect(throws: (any Error).self) { try configuration.validate() }
        configuration = netdataTestConfiguration()
        configuration.host?.label = String(repeating: "x", count: 33)
        #expect(throws: (any Error).self) { try configuration.validate() }
        configuration = netdataTestConfiguration()
        configuration.dashboardURL = "https://dashboard.example.invalid?token=not-allowed"
        #expect(throws: (any Error).self) { try configuration.validate() }
        configuration.dashboardURL = "https://dashboard.example.invalid/netdata"
        try configuration.validate()
        #expect(configuration.dashboardDestination?.host == "dashboard.example.invalid")
    }
}

func netdataTestConfiguration(environmentID: String = "vps-a") -> NetdataConfiguration {
    NetdataConfiguration(
        enabled: true,
        host: .init(
            environmentID: environmentID,
            label: "VPS",
            origin: "http://127.0.0.1:19999",
            expectedMachineGUID: "11111111-2222-3333-4444-555555555555"))
}

/// All settings dependencies are synthetic; ordinary settings fixtures never run app-group migration.
@MainActor
final class NetdataAppTestFixture {
    let root: URL
    let defaults: InMemoryUserDefaults
    let settings: SettingsStore

    init(defaults: InMemoryUserDefaults = InMemoryUserDefaults()) throws {
        try #require(SettingsStore.isRunningTests)
        self.defaults = defaults
        self.root = TestFixtureScratch.root.appendingPathComponent("NetdataApp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        let configStore = CodexBarConfigStore(fileURL: self.root.appendingPathComponent("config.json"))
        do {
            try configStore.save(testConfigWithAllProvidersDisabled())
        } catch {
            try FileManager.default.removeItem(at: self.root)
            throw error
        }
        self.settings = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore(),
            codexCookieStore: InMemoryCookieHeaderStore(),
            claudeCookieStore: InMemoryCookieHeaderStore(),
            cursorCookieStore: InMemoryCookieHeaderStore(),
            opencodeCookieStore: InMemoryCookieHeaderStore(),
            factoryCookieStore: InMemoryCookieHeaderStore(),
            minimaxCookieStore: InMemoryMiniMaxCookieStore(),
            minimaxAPITokenStore: InMemoryMiniMaxAPITokenStore(),
            kimiTokenStore: InMemoryKimiTokenStore(),
            augmentCookieStore: InMemoryCookieHeaderStore(),
            ampCookieStore: InMemoryCookieHeaderStore(),
            copilotTokenStore: InMemoryCopilotTokenStore(),
            tokenAccountStore: InMemoryTokenAccountStore(fileURL: self.root.appendingPathComponent("accounts.json")),
            antigravityOAuthCredentialsStore: AntigravityOAuthCredentialsStore(
                fileURL: self.root.appendingPathComponent("antigravity.json")),
            keychainAccessPolicy: SettingsStoreKeychainAccessPolicy(
                setDisabled: { _ in }, isExplicitlyDisabled: { true }),
            performInitialProviderDetection: false)
    }

    func close() {
        self.settings.configFileWatcher?.stop()
        do {
            try FileManager.default.removeItem(at: self.root)
        } catch {
            Issue.record("Could not remove synthetic Netdata fixture: \(error)")
        }
    }
}
