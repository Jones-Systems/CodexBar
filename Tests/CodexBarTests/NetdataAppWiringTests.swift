import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct NetdataAppWiringTests {
    @Test
    func `host button and fixed menu consume the shared bridge without provider refresh`() async throws {
        let fixture = try NetdataAppTestFixture()
        defer { fixture.close() }
        try fixture.settings.applyNetdataConfiguration(netdataTestConfiguration())
        let harness = NetdataCoordinatorHarness(settings: fixture.settings)
        let controller = self.makeController(fixture: fixture)
        defer { controller.prepareForAppShutdown() }
        controller.setNetdataCoordinator(harness.coordinator)
        #expect(controller.store.enabledProvidersForDisplay().isEmpty)
        let item = try #require(controller.netdataStatusItem)
        let menu = try #require(item.menu)
        #expect(menu.delegate === controller)
        #expect(item.autosaveName == "codexbar-netdata")
        #expect(item.button?.accessibilityIdentifier() == "CodexBar.StatusItem.netdata")
        harness.coordinator.start()
        await harness.fetches.waitForCalls(1)
        await harness.finish(observation: try netdataTestObservation(now: harness.clock.now()))
        controller.menuWillOpen(menu)
        #expect(item.button?.title == "VPS 0% · 1.0 GiB avail")
        #expect(harness.coordinator.menuVisible)
        #expect(controller.store.lastMenuOpenAt == nil)
        #expect(controller.menuRefreshTasks.isEmpty)
        #expect(controller.openMenus.isEmpty)
        let cpu = try #require(menu.item(withTag: StatusItemController.NetdataMenuRow.cpu.rawValue))
        let age = try #require(menu.item(withTag: StatusItemController.NetdataMenuRow.age.rawValue))
        let refresh = try #require(menu.item(withTag: StatusItemController.NetdataMenuRow.refresh.rawValue))
        #expect(cpu.title.contains("0%"))
        #expect(age.title.contains(String(format: L("netdata_age_seconds"), 0.0)))
        #expect(refresh.target === controller)
        #expect(refresh.action != nil)
        menu.performActionForItem(at: menu.index(of: refresh))
        await harness.fetches.waitForCalls(2)
        menu.performActionForItem(at: menu.index(of: refresh))
        harness.advance(to: harness.clock.now().addingTimeInterval(31))
        controller.menuNeedsUpdate(menu)
        #expect(item.button?.title == "VPS Stale")
        #expect(menu.item(withTag: StatusItemController.NetdataMenuRow.cpu.rawValue) === cpu)
        #expect(menu.item(withTag: StatusItemController.NetdataMenuRow.age.rawValue) === age)
        #expect(age.title.contains(String(format: L("netdata_age_seconds"), 31.0)))
        #expect(await harness.fetches.callCount == 2)
        let settingsItem = try #require(menu.item(withTag: StatusItemController.NetdataMenuRow.settings.rawValue))
        var openedPane: SettingsPane?
        controller.setSettingsOpenHandler { openedPane = $0 }
        menu.performActionForItem(at: menu.index(of: settingsItem))
        #expect(openedPane == .general)
        controller.menuDidClose(menu)
        #expect(!harness.coordinator.menuVisible)
        #expect(harness.coordinator.isRunning)
        harness.coordinator.stop()
        await harness.finish(observation: nil)
    }

    @Test
    func `host item survives provider layout recovery and is removed on disable and shutdown`() throws {
        let fixture = try NetdataAppTestFixture()
        defer { fixture.close() }
        var configuration = netdataTestConfiguration()
        configuration.dashboardURL = "https://dashboard.example.invalid/netdata"
        try fixture.settings.applyNetdataConfiguration(configuration)
        let harness = NetdataCoordinatorHarness(settings: fixture.settings)
        let controller = self.makeController(fixture: fixture)
        defer { controller.prepareForAppShutdown() }
        controller.setNetdataCoordinator(harness.coordinator)
        let oldItem = try #require(controller.netdataStatusItem)
        let oldMenu = try #require(controller.netdataMenu)
        #expect(controller.expectedVisibleStatusItemAutosaveNames.contains("codexbar-netdata"))
        let dashboard = try #require(oldMenu.item(withTag: StatusItemController.NetdataMenuRow.dashboard.rawValue))
        #expect(!dashboard.isHidden)
        #expect(dashboard.action != nil)
        fixture.settings.mergeIcons = false
        controller.handleProviderConfigChange(reason: "Netdata isolation test")
        #expect(controller.netdataStatusItem === oldItem)
        oldItem.isVisible = false
        controller.refreshExistingStatusItemsForVisibilityRecovery()
        #expect(oldItem.isVisible)
        controller.recreateStatusItemsForVisibilityRecovery()
        #expect(controller.netdataStatusItem !== oldItem)
        #expect(oldItem.menu == nil)
        #expect(oldMenu.delegate == nil)
        #expect(controller.netdataStatusItem?.isVisible == true)
        #expect(controller.expectedVisibleStatusItemAutosaveNames.contains("codexbar-netdata"))
        configuration.enabled = false
        try fixture.settings.applyNetdataConfiguration(configuration)
        controller.updateNetdataStatusItem()
        #expect(controller.netdataStatusItem == nil)
        #expect(!controller.expectedVisibleStatusItemAutosaveNames.contains("codexbar-netdata"))
        configuration.enabled = true
        try fixture.settings.applyNetdataConfiguration(configuration)
        controller.updateNetdataStatusItem()
        let finalItem = try #require(controller.netdataStatusItem)
        let finalMenu = try #require(controller.netdataMenu)
        controller.menuWillOpen(finalMenu)
        controller.prepareForAppShutdown()
        controller.prepareForAppShutdown()
        controller.updateNetdataStatusItem()
        #expect(controller.netdataStatusItem == nil)
        #expect(controller.netdataObservabilityCoordinator == nil)
        #expect(finalItem.menu == nil)
        #expect(finalMenu.delegate == nil)
        #expect(!harness.coordinator.menuVisible)
        #expect(harness.constructedHosts.isEmpty)
    }

    @Test
    func `preferences and provider pane retain the supplied coordinator without fallback collection`() throws {
        let fixture = try NetdataAppTestFixture()
        defer { fixture.close() }
        let harness = NetdataCoordinatorHarness(settings: fixture.settings)
        let controller = self.makeController(fixture: fixture)
        defer { controller.prepareForAppShutdown() }
        let preferences = PreferencesView(
            settings: fixture.settings,
            store: controller.store,
            netdataObservabilityCoordinator: harness.coordinator,
            updater: DisabledUpdaterController(),
            selection: PreferencesSelection())
        let pane = ProvidersPane(
            settings: fixture.settings,
            store: controller.store,
            netdataObservabilityCoordinator: preferences.netdataObservabilityCoordinator)
        #expect(pane.netdataObservabilityBridge === harness.coordinator.bridge)
        #expect(pane.netdataObservabilityCoordinator === harness.coordinator)
        let preview = ProvidersPane(settings: fixture.settings, store: controller.store)
        #expect(preview.netdataObservabilityBridge == nil)
        #expect(preview.netdataObservabilityCoordinator == nil)
        #expect(!harness.coordinator.isRunning)
        #expect(harness.constructedHosts.isEmpty)
    }

    private func makeController(fixture: NetdataAppTestFixture) -> StatusItemController {
        fixture.settings.statusChecksEnabled = false
        fixture.settings.refreshFrequency = .manual
        fixture.settings.mergeIcons = true
        let environment = ["HOME": fixture.root.path, "PATH": "/usr/bin:/bin"]
        let store = UsageStore(
            fetcher: UsageFetcher(environment: environment),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: fixture.settings,
            startupBehavior: .testing,
            environmentBase: environment,
            widgetSnapshotURL: fixture.root.appendingPathComponent("widget.json"),
            widgetTimelineReloader: {})
        return StatusItemController(
            store: store,
            settings: fixture.settings,
            account: AccountInfo(email: nil, plan: nil),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            menuCardRenderingEnabled: false,
            menuRefreshEnabled: false,
            observeProviderConfigNotifications: false)
    }
}
