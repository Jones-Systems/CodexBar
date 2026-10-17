import CodexBarCore
import Foundation
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
struct ClaudeNativeProfileIntegrationTests {
    private func withFixture(_ body: (SettingsStore, UsageStore, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeNativeProfileIntegrationTests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configStore = CodexBarConfigStore(fileURL: root.appendingPathComponent("config.json"))
        try configStore.save(testConfigWithAllProvidersDisabled())
        let settings = SettingsStore(
            userDefaults: InMemoryUserDefaults(), configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(), syntheticTokenStore: NoopSyntheticTokenStore(),
            codexCookieStore: InMemoryCookieHeaderStore(), claudeCookieStore: InMemoryCookieHeaderStore(),
            cursorCookieStore: InMemoryCookieHeaderStore(), opencodeCookieStore: InMemoryCookieHeaderStore(),
            factoryCookieStore: InMemoryCookieHeaderStore(), minimaxCookieStore: InMemoryMiniMaxCookieStore(),
            minimaxAPITokenStore: InMemoryMiniMaxAPITokenStore(), kimiTokenStore: InMemoryKimiTokenStore(),
            augmentCookieStore: InMemoryCookieHeaderStore(), ampCookieStore: InMemoryCookieHeaderStore(),
            copilotTokenStore: InMemoryCopilotTokenStore(),
            tokenAccountStore: InMemoryTokenAccountStore(fileURL: root.appendingPathComponent("accounts.json")),
            antigravityOAuthCredentialsStore: AntigravityOAuthCredentialsStore(
                fileURL: root.appendingPathComponent("antigravity.json")),
            keychainAccessPolicy: SettingsStoreKeychainAccessPolicy(
                setDisabled: { _ in }, isExplicitlyDisabled: { true }),
            performInitialProviderDetection: false)
        defer { settings.configFileWatcher?.stop() }
        let environment = [
            "HOME": root.path,
            "CLAUDE_CONFIG_DIR": root.appendingPathComponent("ambient").path,
            "ANTHROPIC_AUTH_TOKEN": "synthetic-automation",
        ]
        let store = UsageStore(
            fetcher: UsageFetcher(environment: environment), browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings, startupBehavior: .testing, environmentBase: environment,
            widgetSnapshotURL: root.appendingPathComponent("widget.json"), widgetTimelineReloader: {})
        try body(settings, store, root)
    }

    @Test
    func `registry preserves ambient without selection and scopes explicit enrollment in separately launched GUI`() throws {
        try self.withFixture { settings, store, _ in
            let original = store.claudeNativeProfileFetchEnvironment()
            #expect(!ClaudeNativeProfileSelection.isSelected(environment: original))
            settings.claudeNativeProfileAlias = "jace"
            try ClaudeFleetProfileDiscovery.$discoveryOverride.withValue(ClaudeFleetProfileDiscoveryTests.discovery()) {
                let environment = store.claudeNativeProfileFetchEnvironment()
                #expect(environment["CLAUDE_CONFIG_DIR"] == ClaudeFleetProfileDiscoveryTests.home
                    .path + "/.claude-t3/jace")
                #expect(environment["ANTHROPIC_AUTH_TOKEN"] == nil)
                #expect(try settings.configStore.load()?.providerConfig(for: .claude)?
                    .claudeNativeProfileAlias == "jace")
            }
        }
    }

    @Test
    func `registry keeps selected token API and web authorities independent of saved native selection`() throws {
        try self.withFixture { settings, store, _ in
            settings.claudeNativeProfileAlias = "jace"
            settings.claudeAdminAPIKey = "synthetic-admin"
            #expect(!ClaudeNativeProfileSelection.isSelected(environment: store.claudeNativeProfileFetchEnvironment()))
            settings.claudeAdminAPIKey = ""
            settings.claudeUsageDataSource = .web
            #expect(!ClaudeNativeProfileSelection.isSelected(environment: store.claudeNativeProfileFetchEnvironment()))
            settings.claudeUsageDataSource = .auto
            settings.addTokenAccount(provider: .claude, label: "Independent", token: "sk-ant-oat-synthetic")
            let environment = store.claudeNativeProfileFetchEnvironment()
            #expect(!ClaudeNativeProfileSelection.isSelected(environment: environment))
            #expect(environment[ClaudeOAuthCredentialsStore.environmentTokenKey] == "sk-ant-oat-synthetic")
        }
    }

    @Test
    func `profile transitions retire live identity usage resets widgets and fallback while preserving history data`() throws {
        try self.withFixture { settings, store, _ in
            try ClaudeFleetProfileDiscovery.$discoveryOverride.withValue(ClaudeFleetProfileDiscoveryTests.discovery()) {
                settings.claudeNativeProfileAlias = "default"
                let first = store.claudeNativeProfileFetchEnvironment()
                store.reconcileClaudeNativeProfileEnvironment(first)
                let snapshot = UsageSnapshot(
                    primary: RateWindow(usedPercent: 42, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
                    secondary: nil, updatedAt: Date())
                store._setSnapshotForTesting(snapshot, provider: .claude)
                store.lastKnownResetSnapshots[.claude] = snapshot
                store.claudeHistoryFallbackEligible = true
                var history = PlanUtilizationHistoryBuckets()
                history.preferredAccountKey = "previous-native-owner"
                store.planUtilizationHistory[.claude] = history
                let originalHistory = store.planUtilizationHistory
                settings.claudeNativeProfileAlias = "jace"
                #expect(!store.claudeNativeProfileEnvironmentIsCurrent(first))
                #expect(store.snapshot(for: .claude) == nil)
                #expect(store.lastKnownResetSnapshots[.claude] == nil)
                #expect(!store.claudeHistoryFallbackEligible)
                #expect(store.widgetUsagePreservationBlockedProviders.contains(.claude))
                #expect(store.planUtilizationHistory == originalHistory)
                #expect(store.shouldWithholdClaudeNativeProfileHistory())
                #expect(store.planUtilizationHistorySelection(for: .claude).histories.isEmpty)
                #expect(store.claudeNativeProfileEnvironmentIsCurrent(store.claudeNativeProfileFetchEnvironment()))
            }
        }
    }

    @Test
    func `removed enrollment invalidates in-flight authority without changing saved selection`() throws {
        try self.withFixture { settings, store, _ in
            settings.claudeNativeProfileAlias = "jace"
            let original = try ClaudeFleetProfileDiscovery.$discoveryOverride.withValue(
                ClaudeFleetProfileDiscoveryTests.discovery()) { store.claudeNativeProfileFetchEnvironment() }
            store.reconcileClaudeNativeProfileEnvironment(original)
            ClaudeFleetProfileDiscovery.$discoveryOverride.withValue(.missing) {
                #expect(!store.claudeNativeProfileEnvironmentIsCurrent(original))
                #expect(settings.claudeNativeProfileAlias == "jace")
                #expect(ClaudeNativeProfileSelection
                    .isUnavailable(environment: store.claudeNativeProfileFetchEnvironment()))
            }
        }
    }

    @Test
    func `native selected debug stops before browser native or credential probes`() async {
        let environment = ClaudeNativeProfileSelection.environment(base: [:], alias: "jace", discovery: .missing)
        let message = await UsageStore.debugClaudeLog(
            browserDetection: BrowserDetection(cacheTTL: 0),
            configuration: UsageStore.ClaudeDebugLogConfiguration(
                runtime: .app, sourceMode: .auto, environment: environment, webExtrasEnabled: true,
                usageDataSource: .auto, cookieSource: .auto, cookieHeader: "", keepCLISessionsAlive: false))
        #expect(message == ClaudeNativeProfileSelectionError.unavailable.localizedDescription)
    }

    @Test
    func `settings picker labels enrollment preserves missing selection and never starts login`() throws {
        try self.withFixture { settings, store, _ in
            let context = ProviderSettingsContext(
                provider: .claude, settings: settings, store: store,
                boolBinding: { key in Binding(get: { settings[keyPath: key] }, set: { settings[keyPath: key] = $0 }) },
                stringBinding: { key in
                    Binding(get: { settings[keyPath: key] }, set: { settings[keyPath: key] = $0 })
                },
                statusText: { _ in nil }, setStatusText: { _, _ in },
                lastAppActiveRunAt: { _ in nil }, setLastAppActiveRunAt: { _, _ in },
                requestConfirmation: { _ in Issue.record("No enrollment selection confirmation or login") })
            try ClaudeFleetProfileDiscovery.$discoveryOverride.withValue(ClaudeFleetProfileDiscoveryTests.discovery()) {
                let picker = ClaudeProviderImplementation().nativeProfilePicker(context: context)
                #expect(picker.options.map(\.id) == ["", "default", "jace"])
                #expect(picker.options.dropFirst().allSatisfy { $0.title.contains("enrolled") })
                picker.binding.wrappedValue = "jace"
                #expect(settings.claudeNativeProfileAlias == "jace")
            }
            ClaudeFleetProfileDiscovery.$discoveryOverride.withValue(.missing) {
                let picker = ClaudeProviderImplementation().nativeProfilePicker(context: context)
                #expect(picker.options.contains { $0.id == "jace" && $0.title == "Unavailable saved profile" })
                #expect(picker.dynamicSubtitle?()?.contains("unavailable") == true)
                let action = ClaudeProviderImplementation().loginMenuAction(context: ProviderMenuLoginContext(
                    provider: .claude, store: store, settings: settings,
                    account: AccountInfo(email: nil, plan: nil), hasAccount: false))
                #expect(action?.label == "Manage selected native profile in Claude Settings…")
                picker.binding.wrappedValue = ""
                #expect(settings.claudeNativeProfileAlias == nil)
            }
        }
    }
}
