import AppKit
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct StatusMenuHostedSubmenuReleaseTests {
    @Test
    func `cost view survives hover close and releases after parent closes`() throws {
        try self.withFixture { controller in
            let parent = controller.makeMenu()
            controller.mergedMenu = parent
            controller.menuWillOpen(parent)
            let costItem = try #require(parent.items.first { $0.representedObject as? String == "menuCardCost" })
            let submenu = try #require(costItem.submenu)
            controller.menuWillOpen(submenu)
            weak var hostedView = try #require(submenu.items.first?.view)
            let width = submenu.minimumWidth
            #expect(controller.hostedSubviewRenderSignatures.object(forKey: submenu) != nil)

            controller.menuDidClose(submenu)
            #expect(submenu.items.first?.view === hostedView)
            #expect(hostedView != nil)
            controller.menuWillOpen(submenu)
            #expect(submenu.items.first?.view === hostedView)
            controller.menuDidClose(submenu)
            controller.menuDidClose(parent)

            #expect(costItem.submenu === submenu)
            #expect(submenu.items.count == 1)
            #expect(submenu.items.first?.view == nil)
            #expect(submenu.items.first?.representedObject as? String == StatusItemController.costHistoryChartID)
            #expect(submenu.items.first?.toolTip == UsageProvider.claude.rawValue)
            #expect(submenu.minimumWidth == width)
            #expect(submenu.delegate === controller)
            #expect(controller.hostedSubviewRenderSignatures.object(forKey: submenu) == nil)

            controller.store._setTokenSnapshotForTesting(Self.tokenSnapshot(cost: 4.56), provider: .claude)
            controller.menuWillOpen(parent)
            let reopenedCost = try #require(parent.items.first { $0.representedObject as? String == "menuCardCost" })
            let reopenedSubmenu = try #require(reopenedCost.submenu)
            controller.menuWillOpen(reopenedSubmenu)
            #expect(reopenedSubmenu.items.first?.view != nil)
            #expect(reopenedSubmenu.items.first?.toolTip == UsageProvider.claude.rawValue)
            controller.menuDidClose(reopenedSubmenu)
            controller.menuDidClose(parent)
        }
    }

    @Test
    func `status view releases and rehydrates with its original provider`() throws {
        try self.withFixture { controller in
            controller.settings.statusChecksEnabled = true
            controller.store.statusComponents[.claude] = [
                ProviderStatusComponent(id: "api", name: "API", indicator: .none, status: "operational"),
            ]
            let parent = controller.makeMenu()
            controller.mergedMenu = parent
            controller.menuWillOpen(parent)
            let submenu = controller.makeHostedSubviewPlaceholderMenu(
                chartID: StatusItemController.statusComponentsID,
                provider: .claude,
                width: StatusItemController.menuCardBaseWidth)
            let item = NSMenuItem(title: "Status fixture", action: nil, keyEquivalent: "")
            item.submenu = submenu
            parent.addItem(item)
            controller.menuWillOpen(submenu)
            #expect(submenu.items.first?.view != nil)
            controller.menuDidClose(submenu)
            controller.menuDidClose(parent)
            #expect(submenu.items.count == 1)
            #expect(submenu.items.first?.view == nil)
            #expect(submenu.items.first?.toolTip == UsageProvider.claude.rawValue)
            #expect(controller.hostedSubviewRenderSignatures.object(forKey: submenu) == nil)
            #expect(controller.hydrateHostedSubviewMenuIfNeeded(submenu))
            #expect(submenu.items.first?.view != nil)
            let link = try #require(submenu.items.last)
            #expect(link.identifier?.rawValue == UsageProvider.claude.rawValue)
            #expect(link.action == #selector(StatusItemController.openStatusPageFromMenuItem(_:)))
            #expect(link.target === controller)
        }
    }

    @Test
    func `full close preserves native status links and unavailable rows`() throws {
        try self.withFixture { controller in
            let parent = controller.makeMenu()
            controller.mergedMenu = parent
            controller.menuWillOpen(parent)
            let native = controller.makeHostedSubviewPlaceholderMenu(
                chartID: StatusItemController.statusComponentsID, provider: .claude)
            let unavailable = controller.makeHostedSubviewPlaceholderMenu(
                chartID: StatusItemController.costHistoryChartID, provider: .claude)
            for submenu in [native, unavailable] {
                let item = NSMenuItem(title: "Fixture", action: nil, keyEquivalent: "")
                item.submenu = submenu
                parent.addItem(item)
                controller.menuWillOpen(submenu)
                controller.menuDidClose(submenu)
            }
            let link = try #require(native.items.first)
            let unavailableItem = try #require(unavailable.items.first)
            #expect(link.view == nil)
            #expect(link.identifier?.rawValue == UsageProvider.claude.rawValue)
            #expect(unavailableItem.title == "No data available")
            controller.menuDidClose(parent)
            #expect(native.items.first === link)
            #expect(unavailable.items.first === unavailableItem)
        }
    }

    private static func tokenSnapshot(cost: Double) -> CostUsageTokenSnapshot {
        CostUsageTokenSnapshot(
            sessionTokens: 123,
            sessionCostUSD: cost,
            last30DaysTokens: 123,
            last30DaysCostUSD: cost,
            daily: [CostUsageDailyReport.Entry(
                date: "2025-12-23",
                inputTokens: nil,
                outputTokens: nil,
                totalTokens: 123,
                costUSD: cost,
                modelsUsed: nil,
                modelBreakdowns: nil)],
            updatedAt: Date())
    }

    private func withFixture(
        _ body: (StatusItemController) throws -> Void) throws
    {
        let root = TestFixtureScratch.root
            .appendingPathComponent("StatusMenuHostedSubmenuReleaseTests-" + UUID().uuidString, isDirectory: true)
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
            codexCookieStore: InMemoryCookieHeaderStore(),
            claudeCookieStore: InMemoryCookieHeaderStore(),
            tokenAccountStore: InMemoryTokenAccountStore(fileURL: root.appendingPathComponent("accounts.json")),
            keychainAccessPolicy: SettingsStoreKeychainAccessPolicy(
                setDisabled: { _ in }, isExplicitlyDisabled: { true }),
            performInitialProviderDetection: false)
        defer { settings.configFileWatcher?.stop() }
        settings.setProviderEnabled(
            provider: .claude,
            metadata: ProviderDescriptorRegistry.descriptor(for: .claude).metadata,
            enabled: true)
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        settings.costUsageEnabled = true
        settings.costSummaryDisplayStyle = .both
        settings.selectedMenuProvider = .claude
        settings.mergeIcons = true
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
        let previousRendering = StatusItemController.menuCardRenderingEnabled
        StatusItemController.menuCardRenderingEnabled = true
        defer { StatusItemController.menuCardRenderingEnabled = previousRendering }
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: AccountInfo(email: nil, plan: nil),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: .system)
        defer { controller.releaseStatusItemsForTesting() }
        controller.menuRefreshEnabledOverrideForTesting = true
        store._setSnapshotForTesting(UsageSnapshot(
            primary: RateWindow(usedPercent: 10, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date()), provider: .claude)
        store._setTokenSnapshotForTesting(Self.tokenSnapshot(cost: 1.23), provider: .claude)
        try body(controller)
    }
}
