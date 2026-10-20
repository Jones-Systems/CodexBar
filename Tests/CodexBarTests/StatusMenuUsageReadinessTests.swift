import AppKit
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct StatusMenuUsageReadinessTests {
    private func withFixture(
        provider: UsageProvider,
        _ body: (StatusItemController) async throws -> Void) async throws
    {
        let root = TestFixtureScratch.root
            .appendingPathComponent("StatusMenuUsageReadinessTests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: root)
                #expect(!FileManager.default.fileExists(atPath: root.path))
            } catch {
                Issue.record("Could not remove owned fixture: \(error)")
            }
        }
        let configStore = CodexBarConfigStore(fileURL: root.appendingPathComponent("config.json"))
        try configStore.save(testConfigWithAllProvidersDisabled())
        let settings = SettingsStore(
            userDefaults: InMemoryUserDefaults(),
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
            tokenAccountStore: InMemoryTokenAccountStore(fileURL: root.appendingPathComponent("accounts.json")),
            antigravityOAuthCredentialsStore: AntigravityOAuthCredentialsStore(
                fileURL: root.appendingPathComponent("antigravity.json")),
            keychainAccessPolicy: SettingsStoreKeychainAccessPolicy(
                setDisabled: { _ in }, isExplicitlyDisabled: { true }),
            performInitialProviderDetection: false)
        defer { settings.configFileWatcher?.stop() }
        settings.setProviderEnabled(
            provider: provider,
            metadata: ProviderDescriptorRegistry.descriptor(for: provider).metadata,
            enabled: true)
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        settings.costUsageEnabled = false
        settings.mergeIcons = false
        settings.multiAccountMenuLayout = .segmented
        let environment = ["HOME": root.path, "CODEX_HOME": root.appendingPathComponent("codex").path]
        let store = UsageStore(
            fetcher: UsageFetcher(environment: environment),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: environment,
            widgetSnapshotURL: root.appendingPathComponent("widget.json"),
            widgetTimelineReloader: {})
        store._cancelPlanUtilizationHistoryLoadForTesting()
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: AccountInfo(email: nil, plan: nil),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: .system)
        defer { controller.releaseStatusItemsForTesting() }
        try await body(controller)
    }

    private static func snapshot() -> UsageSnapshot {
        UsageSnapshot(
            primary: RateWindow(usedPercent: 21, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test(arguments: [UsageProvider.codex, .claude])
    func `usage and error presence change readiness without metric value churn`(provider: UsageProvider) async throws {
        try await self.withFixture(provider: provider) { controller in
            let empty = controller.menuAdjunctReadinessSignature()
            controller.store.snapshots[provider.instanceID] = Self.snapshot()
            let populated = controller.menuAdjunctReadinessSignature()
            #expect(populated != empty)
            controller.store.snapshots[provider.instanceID] = UsageSnapshot(
                primary: RateWindow(usedPercent: 42, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                updatedAt: Date(timeIntervalSince1970: 1_800_000_100))
            #expect(controller.menuAdjunctReadinessSignature() == populated)
            controller.store.errors[provider.instanceID] = "Synthetic failure"
            #expect(controller.menuAdjunctReadinessSignature() != populated)
        }
    }

    @Test
    func `cached codex selected identity changes readiness`() async throws {
        try await self.withFixture(provider: .codex) { controller in
            @MainActor
            func select(_ id: String) {
                controller.settings.cachedCodexAccountMenuProjection = CachedCodexAccountMenuProjection(
                    activeSource: .liveSystem,
                    loadedAt: Date(),
                    projection: CodexVisibleAccountProjection(
                        visibleAccounts: [],
                        activeVisibleAccountID: id,
                        liveVisibleAccountID: id,
                        hasUnreadableAddedAccountStore: false))
            }
            select("first")
            let first = controller.menuAdjunctReadinessSignature()
            select("second")
            #expect(controller.menuAdjunctReadinessSignature() != first)
        }
    }

    @Test
    func `selected token account and native alias change readiness`() async throws {
        try await self.withFixture(provider: .claude) { controller in
            let settings = controller.settings
            settings.addTokenAccount(provider: .claude, label: "First", token: "synthetic-first")
            settings.addTokenAccount(provider: .claude, label: "Second", token: "synthetic-second")
            settings.setActiveTokenAccountIndex(0, for: .claude)
            let first = controller.menuAdjunctReadinessSignature()
            settings.setActiveTokenAccountIndex(1, for: .claude)
            let second = controller.menuAdjunctReadinessSignature()
            #expect(second != first)
            settings.claudeNativeProfileAlias = "synthetic-profile"
            #expect(controller.menuAdjunctReadinessSignature() != second)
        }
    }

    @Test
    func `usage arriving for an open placeholder schedules a metrics rebuild`() async throws {
        try await self.withFixture(provider: .codex) { controller in
            controller.menuRefreshEnabledOverrideForTesting = true
            let menu = controller.makeMenu(for: .codex)
            controller.menuWillOpen(menu)
            defer { controller.menuDidClose(menu) }
            let placeholder = try #require(controller.menuCardModel(for: .codex))
            #expect(placeholder.metrics.isEmpty)
            controller.resyncMenuAdjunctReadinessBaseline()
            var rebuiltModel: UsageMenuCardView.Model?
            controller._test_openMenuRebuildObserver = { _ in
                rebuiltModel = controller.menuCardModel(for: .codex)
            }

            controller.store.snapshots[.codex] = Self.snapshot()
            controller.handleObservedStoreMenuChange()
            let deadline = ContinuousClock.now + .seconds(2)
            while rebuiltModel == nil, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            let rebuilt = try #require(rebuiltModel)
            #expect(!rebuilt.metrics.isEmpty)
            #expect(rebuilt.placeholder == nil)
        }
    }
}
