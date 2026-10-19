import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct CAAMEnvironmentSettingsTests {
    @Test
    func `codex pane starts with no configured CAAM environments`() {
        let suite = "CAAMEnvironmentSettingsTests-empty"
        let settings = Self.makeSettingsStore(suite: suite)
        defer { Self.clearSettingsStore(settings, suite: suite) }
        let store = Self.makeUsageStore(settings: settings)
        let pane = ProvidersPane(
            settings: settings,
            store: store,
            caamEnvironmentCoordinator: CAAMEnvironmentCoordinator())

        let state = pane._test_codexEnvironmentsSectionState()

        #expect(state.configurations.isEmpty)
        #expect(state.rows.isEmpty)
        #expect(state.canAddLocal)
    }

    @Test
    func `codex pane persists local and SSH environment configuration`() {
        let suite = "CAAMEnvironmentSettingsTests-save"
        let settings = Self.makeSettingsStore(suite: suite)
        defer { Self.clearSettingsStore(settings, suite: suite) }
        let store = Self.makeUsageStore(settings: settings)
        let pane = ProvidersPane(
            settings: settings,
            store: store,
            caamEnvironmentCoordinator: CAAMEnvironmentCoordinator())
        let configurations = [
            CAAMEnvironmentConfiguration(id: "vps", label: "VPS", connection: .ssh(destination: "vps")),
            CAAMEnvironmentConfiguration(id: "laptop", label: "Laptop", connection: .local()),
        ]

        let error = pane._test_saveCodexEnvironmentConfigurations(configurations)
        let state = pane._test_codexEnvironmentsSectionState()

        #expect(error == nil)
        #expect(settings.codexCAAMEnvironments == configurations)
        #expect(state.configurations == configurations)
        #expect(state.rows.map(\.id) == ["laptop", "vps"])
        #expect(state.rows.map(\.availability) == [.unavailable, .unavailable])
        #expect(state.canAddLocal == false)
    }

    @Test
    func `codex pane rejects unsafe SSH environment without changing config`() {
        let suite = "CAAMEnvironmentSettingsTests-invalid"
        let settings = Self.makeSettingsStore(suite: suite)
        defer { Self.clearSettingsStore(settings, suite: suite) }
        let store = Self.makeUsageStore(settings: settings)
        let pane = ProvidersPane(
            settings: settings,
            store: store,
            caamEnvironmentCoordinator: CAAMEnvironmentCoordinator())
        let unsafe = [
            CAAMEnvironmentConfiguration(
                id: "vps",
                label: "VPS",
                connection: .ssh(destination: "-oProxyCommand=unexpected")),
        ]

        let error = pane._test_saveCodexEnvironmentConfigurations(unsafe)

        #expect(error != nil)
        #expect(settings.codexCAAMEnvironments.isEmpty)
    }

    @Test
    func `coordinator refresh projects a bounded snapshot`() async throws {
        let runner = CAAMSettingsTestRunner(stdout: Self.snapshotJSON)
        let client = CAAMEnvironmentClient(
            runner: runner,
            resolveLocalGateway: { _ in "/usr/local/bin/caam-codexbar" })
        let observedAt = try CAAMEnvironmentContract.decodeSnapshot(
            Data(Self.snapshotJSON.utf8), expectedEnvironmentID: "laptop").observedAt
        let coordinator = CAAMEnvironmentCoordinator(client: client, now: { observedAt })
        let configuration = CAAMEnvironmentConfiguration(
            id: "laptop",
            label: "Laptop",
            connection: .local())

        await coordinator.refresh(configurations: [configuration])
        let state = coordinator.state(configurations: [configuration])

        #expect(state.notice == nil)
        #expect(state.rows.count == 1)
        #expect(state.rows.first?.availability == .ready)
        #expect(state.rows.first?.currentProfile == "primary")
    }

    private static func makeSettingsStore(suite: String) -> SettingsStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
    }

    private static func clearSettingsStore(_ settings: SettingsStore, suite: String) {
        settings.configPersistTask?.cancel()
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: settings.configStore.fileURL.deletingLastPathComponent())
    }

    private static func makeUsageStore(settings: SettingsStore) -> UsageStore {
        UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
    }

    private static let snapshotJSON = #"""
    {
      "schema":"caam.codexbar-control/v1",
      "kind":"snapshot",
      "environment_id":"laptop",
      "protocol_version":"1.0",
      "result":{
        "revision":"1",
        "observed_at":"2026-09-04T12:00:00Z",
        "caam_version":"0.0.0-fixture",
        "capabilities":["snapshot"],
        "reachability":"reachable",
        "host_default_profile":"primary",
        "fallback_profile":"primary",
        "profiles":[{
          "name":"primary",
          "active":true,
          "system":false,
          "eligible":true,
          "health":"healthy",
          "identity":null
        }],
        "runtime":{"state":"unknown","effective_profile":null,"reload_required":false},
        "pending_operation":null,
        "warnings":[]
      },
      "error":null
    }
    """#
}

private actor CAAMSettingsTestRunner: CAAMEnvironmentCommandRunning {
    let stdout: String

    init(stdout: String) {
        self.stdout = stdout
    }

    func run(command _: CAAMEnvironmentCommand, environment _: [String: String]) async throws -> SubprocessResult {
        SubprocessResult(stdout: self.stdout, stderr: "")
    }
}
