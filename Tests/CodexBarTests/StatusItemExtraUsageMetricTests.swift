import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

@Suite(.serialized)
@MainActor
struct StatusItemExtraUsageMetricTests {
    @Test
    func `extra usage window keeps combined percent formatting and claude spend preference`() {
        let (store, controller) = self.makeController(
            suiteName: "StatusItemExtraUsageMetricTests-claude-combined-text",
            provider: .claude)
        defer { controller.releaseStatusItemsForTesting() }
        controller.settings.menuBarDisplayMode = .both
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 10, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            providerCost: ProviderCostSnapshot(
                used: 56,
                limit: 100,
                currencyCode: "USD",
                updatedAt: Date()),
            updatedAt: Date())

        store._setSnapshotForTesting(snapshot, provider: .claude)
        store._setErrorForTesting(nil, provider: .claude)

        #expect(controller.settings.menuBarMetricPreference(for: .claude, snapshot: snapshot) == .extraUsage)
        #expect(controller.menuBarDisplayText(for: .claude, snapshot: snapshot) == "$56.00")
        let extraUsageWindow = controller.menuBarMetricWindow(for: .claude, snapshot: snapshot)
        #expect(abs((extraUsageWindow?.usedPercent ?? .nan) - 56) <= 2 * Double(56).ulp)
        let displayText = MenuBarDisplayText.displayText(
            mode: controller.settings.menuBarDisplayMode,
            percentWindow: extraUsageWindow,
            showUsed: controller.settings.usageBarsShowUsed)

        #expect(displayText == "56%")

        controller.settings.setMenuBarMetricPreference(.primary, for: .claude)
        #expect(controller.settings.menuBarMetricPreference(for: .claude, snapshot: snapshot) == .primary)
        #expect(controller.menuBarDisplayText(for: .claude, snapshot: snapshot) == "10%")
    }

    @Test
    func `menu bar extra usage preference preserves claude currency display`() {
        let (store, controller) = self.makeController(
            suiteName: "StatusItemExtraUsageMetricTests-claude-spend-text",
            provider: .claude)
        defer { controller.releaseStatusItemsForTesting() }
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 42, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            providerCost: ProviderCostSnapshot(
                used: 88.8,
                limit: 200,
                currencyCode: "USD",
                period: "Monthly",
                updatedAt: Date()),
            updatedAt: Date())

        store._setSnapshotForTesting(snapshot, provider: .claude)
        store._setErrorForTesting(nil, provider: .claude)

        let displayText = controller.menuBarDisplayText(for: .claude, snapshot: snapshot)

        #expect(displayText == "$88.80")
    }

    @Test
    func `menu bar extra usage preference falls back to existing percent text when provider cost is unavailable`() {
        let (store, controller) = self.makeController(
            suiteName: "StatusItemExtraUsageMetricTests-fallback-percent",
            provider: .claude)
        defer { controller.releaseStatusItemsForTesting() }
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 10, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 72, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            tertiary: nil,
            providerCost: nil,
            updatedAt: Date())

        store._setSnapshotForTesting(snapshot, provider: .claude)
        store._setErrorForTesting(nil, provider: .claude)

        #expect(controller.settings.menuBarMetricPreference(for: .claude) == .extraUsage)
        #expect(controller.settings.menuBarMetricPreference(for: .claude, snapshot: snapshot) == .automatic)
        #expect(controller.menuBarMetricWindow(for: .claude, snapshot: snapshot) == snapshot.primary)
        #expect(controller.menuBarDisplayText(for: .claude, snapshot: snapshot) == "10%")
        let secondaryOnly = UsageSnapshot(
            primary: nil,
            secondary: snapshot.secondary,
            tertiary: nil,
            providerCost: nil,
            updatedAt: snapshot.updatedAt)
        store._setSnapshotForTesting(secondaryOnly, provider: .claude)
        #expect(controller.settings.menuBarMetricPreference(for: .claude, snapshot: secondaryOnly) == .automatic)
        #expect(controller.menuBarMetricWindow(for: .claude, snapshot: secondaryOnly) == snapshot.secondary)
        let displayText = controller.menuBarDisplayText(for: .claude, snapshot: secondaryOnly)

        #expect(displayText == "72%")
    }

    @Test
    func `reset time mode uses extra usage reset instead of spend`() {
        let resetsAt = Date().addingTimeInterval(2 * 24 * 3600)
        let (store, controller) = self.makeController(
            suiteName: "StatusItemExtraUsageMetricTests-reset-time",
            provider: .claude,
            displayMode: .resetTime,
            resetTimesShowAbsolute: true)
        defer { controller.releaseStatusItemsForTesting() }
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 10, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            providerCost: ProviderCostSnapshot(
                used: 12.34,
                limit: 100,
                currencyCode: "USD",
                period: "Monthly",
                resetsAt: resetsAt,
                updatedAt: Date()),
            updatedAt: Date())

        store._setSnapshotForTesting(snapshot, provider: .claude)
        store._setErrorForTesting(nil, provider: .claude)

        let displayText = controller.menuBarDisplayText(for: .claude, snapshot: snapshot)

        #expect(displayText == "↻ \(UsageFormatter.resetDescription(from: resetsAt))")
    }

    private func makeClaudeController(suiteName: String) -> (UsageStore, StatusItemController) {
        self.makeController(suiteName: suiteName, provider: .claude)
    }

    private func makeController(
        suiteName: String,
        provider: UsageProvider,
        displayMode: MenuBarDisplayMode = .percent,
        resetTimesShowAbsolute: Bool = false) -> (UsageStore, StatusItemController)
    {
        let settings = testSettingsStore(suiteName: suiteName)
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.selectedMenuProvider = provider.instanceID
        settings.menuBarDisplayMode = displayMode
        settings.resetTimesShowAbsolute = resetTimesShowAbsolute
        settings.usageBarsShowUsed = true
        settings.setMenuBarMetricPreference(.extraUsage, for: provider)

        let registry = ProviderRegistry.shared
        if let metadata = registry.metadata[provider] {
            settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: true)
        }

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: testStatusBar())
        return (store, controller)
    }
}
