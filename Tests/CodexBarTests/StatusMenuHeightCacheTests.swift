import AppKit
import Foundation
import SwiftUI
import Testing
@testable import CodexBar
@testable import CodexBarCore

extension StatusMenuTests {
    @Test
    func `cached menu height transitions replace unequal rows and retain equal rows`() throws {
        let controller = self.makeHeightCacheController()
        defer { controller.releaseStatusItemsForTesting() }
        let originalHeights: [CGFloat] = [220, 40, 40, 300]
        let incomingHeights: [CGFloat] = [40, 40, 220, 40, 40]
        let original = originalHeights.enumerated().map {
            self.makeHeightTransitionItem(height: $0.element, id: "overview-\($0.offset)")
        }
        let incoming = incomingHeights.enumerated().map {
            self.makeHeightTransitionItem(height: $0.element, id: "codex-\($0.offset)")
        }
        let originalViews = original.map(\.view)
        let menu = NSMenu()
        original.forEach(menu.addItem)
        let notifications = MenuHeightNotifications(menu: menu)
        defer { withExtendedLifetime(notifications) {} }

        let displaced = controller.replaceMenuContentKeepingRowsVisible(menu, fromIndex: 0, with: incoming)

        #expect(menu.items.count == incomingHeights.count)
        #expect(notifications.additions == 4)
        #expect(notifications.removals == 3)
        for (index, contentHeight) in incomingHeights.enumerated() {
            let view = try #require(menu.items[index].view as? MenuRowContainerView)
            #expect(view.frame.size == NSSize(width: 310, height: contentHeight + 7))
            #expect(view.intrinsicContentSize.height == ceil(view.measuredHeight(width: 310) + 7))
            if index == 1 {
                #expect(menu.items[index] === original[index])
                #expect(view === originalViews[index])
            } else {
                #expect(menu.items[index] === incoming[index])
            }
        }
        #expect(displaced.allSatisfy { $0.menu == nil })
        #expect(original.indices.allSatisfy { original[$0].view === originalViews[$0] })

        let returned = controller.replaceMenuContentKeepingRowsVisible(menu, fromIndex: 0, with: displaced)

        #expect(menu.items.count == originalHeights.count)
        #expect(menu.items.map(ObjectIdentifier.init) == original.map(ObjectIdentifier.init))
        #expect(menu.items.compactMap { $0.view?.frame.height } == originalHeights.map { $0 + 7 })
        #expect(returned.count == incomingHeights.count)
        #expect(returned.allSatisfy { $0.menu == nil })
        #expect(incoming.last?.menu == nil)
        #expect(notifications.additions == 7)
        #expect(notifications.removals == 7)
    }

    @Test
    func `menu height refresh notifies native menu after attached row grows and shrinks`() throws {
        let controller = self.makeHeightCacheController()
        defer { controller.releaseStatusItemsForTesting() }
        let item = self.makeHeightTransitionItem(height: 40, id: "resizing")
        let row = try #require(item.view as? MenuRowContainerView)
        let menu = NSMenu()
        menu.addItem(item)
        let notifications = MenuHeightNotifications(menu: menu)
        defer { withExtendedLifetime(notifications) {} }

        for contentHeight: CGFloat in [80, 40] {
            controller.replantMenuCardRowPayload(self.heightTransitionPayload(height: contentHeight), into: row)
            row.applyMeasuredSize(width: 200, height: row.frame.height)
            controller.invalidateMenus()
            notifications.changedHeights.removeAll()

            controller.refreshMenuCardHeights(in: menu)

            #expect(menu.items.first === item)
            #expect(item.view === row)
            #expect(row.frame.height == contentHeight + 7)
            #expect(row.intrinsicContentSize.height == contentHeight + 7)
            #expect(notifications.changedHeights.contains(contentHeight + 7))
        }
    }

    @Test
    func `fresh menu reconciliation notifies native menu when retained item changes height`() throws {
        let controller = self.makeHeightCacheController()
        defer { controller.releaseStatusItemsForTesting() }
        let original = self.makeHeightTransitionItem(height: 220, id: "card")
        let replacement = self.makeHeightTransitionItem(height: 40, id: "card")
        let menu = NSMenu()
        menu.addItem(original)
        let scratch = NSMenu()
        scratch.addItem(replacement)
        let notifications = MenuHeightNotifications(menu: menu)
        defer { withExtendedLifetime(notifications) {} }

        controller.reconcileMenuContent(
            menu,
            fromIndex: 0,
            shapes: controller.menuContentShapes(in: menu, fromIndex: 0),
            with: scratch)

        #expect(menu.items.first === original)
        let view = try #require(original.view)
        #expect(view.frame.size == NSSize(width: 310, height: 47))
        #expect(notifications.changedHeights.contains(47))
        #expect(notifications.additions == 0)
        #expect(notifications.removals == 0)
        #expect(replacement.view == nil)
    }

    private func makeHeightTransitionItem(height: CGFloat, id: String) -> NSMenuItem {
        let row = MenuRowContainerView(payload: self.heightTransitionPayload(height: height), refreshMonitor: nil)
        row.applyMeasuredSize(width: 310, height: ceil(row.measuredHeight(width: 310) + 7))
        let item = MenuCardMenuItem()
        item.title = ""
        item.view = row
        item.representedObject = id
        return item
    }

    private func heightTransitionPayload(height: CGFloat) -> MenuCardRowPayload {
        MenuCardRowPayload(
            content: AnyView(Color.clear.frame(height: height)),
            showsSubmenuIndicator: false,
            submenuIndicatorAlignment: .topTrailing,
            submenuIndicatorTopPadding: 0,
            allowsMenuHighlight: false,
            containsInteractiveControls: false,
            usesGPUSelection: false,
            onClick: nil)
    }

    @Test
    func `menu card sizing uses displayed hosting view`() throws {
        let previousMenuCardRendering = StatusItemController.menuCardRenderingEnabled
        StatusItemController.menuCardRenderingEnabled = true
        defer {
            StatusItemController.menuCardRenderingEnabled = previousMenuCardRendering
        }

        let controller = self.makeHeightCacheController()
        defer { controller.releaseStatusItemsForTesting() }

        let counter = MenuCardRepresentableCounter()
        let item = controller.makeMenuCardItem(
            CountingMenuCardRepresentable(counter: counter),
            id: "countingCard-\(UUID().uuidString)",
            width: 320,
            heightCacheScope: "counting",
            heightCacheFingerprint: "counting-\(UUID().uuidString)")
        let view = try #require(item.view)

        view.layoutSubtreeIfNeeded()

        #expect(counter.makeViewCount == 1)
    }

    @Test
    func `menu card height cache is reused for stable card content`() {
        let previousMenuCardRendering = StatusItemController.menuCardRenderingEnabled
        StatusItemController.menuCardRenderingEnabled = true
        defer {
            StatusItemController.menuCardRenderingEnabled = previousMenuCardRendering
        }

        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        let registry = ProviderRegistry.shared
        for provider in UsageProvider.allCases {
            guard let metadata = registry.metadata[provider] else { continue }
            settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: provider == .codex)
        }

        let store = self.makeCodexStore(settings: settings, dashboardAuthorized: false)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: AccountInfo(email: nil, plan: nil),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.populateMenu(menu, provider: .codex)
        let firstKeys = Set(controller.menuCardHeightCache.keys)

        #expect(!firstKeys.isEmpty)

        controller.populateMenu(menu, provider: .codex)
        #expect(Set(controller.menuCardHeightCache.keys) == firstKeys)

        controller.invalidateMenus()
        #expect(Set(controller.menuCardHeightCache.keys) == firstKeys)
    }

    @Test
    func `standard menu width cache is reused for stable action rows`() {
        let controller = self.makeHeightCacheController()
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.populateMenu(menu, provider: .codex)
        let firstCache = controller.measuredStandardMenuWidthCache

        #expect(!firstCache.isEmpty)
        #expect(firstCache.keys.allSatisfy {
            $0.contains("font=\(StatusItemController.menuCardHeightTextScaleToken())")
        })

        controller.populateMenu(menu, provider: .codex)
        #expect(controller.measuredStandardMenuWidthCache == firstCache)
    }

    @Test
    func `agent session rows use the menu width instead of their natural title width`() {
        let previousMenuCardRendering = StatusItemController.menuCardRenderingEnabled
        StatusItemController.menuCardRenderingEnabled = true
        defer {
            StatusItemController.menuCardRenderingEnabled = previousMenuCardRendering
        }

        let controller = self.makeHeightCacheController()
        defer { controller.releaseStatusItemsForTesting() }

        let now = Date(timeIntervalSince1970: 1000)
        let shortSession = AgentSession(
            id: "session",
            provider: .codex,
            source: .cli,
            state: .active,
            pid: 42,
            cwd: "/tmp/short",
            projectName: "short",
            startedAt: nil,
            lastActivityAt: now,
            transcriptPath: nil,
            host: "local")
        let longSession = AgentSession(
            id: "session",
            provider: .codex,
            source: .cli,
            state: .active,
            pid: 42,
            cwd: "/tmp/long",
            projectName: String(repeating: "very-long-project-name-", count: 24),
            startedAt: nil,
            lastActivityAt: now,
            transcriptPath: nil,
            host: "local")
        let shortSection = MenuDescriptor.agentSessionsSection(
            localSessions: [shortSession],
            remoteHosts: [],
            now: now)
        let longSection = MenuDescriptor.agentSessionsSection(
            localSessions: [longSession],
            remoteHosts: [],
            now: now)
        let baseWidth = StatusItemController.menuCardBaseWidth

        let shortWidth = controller.measuredStandardMenuWidth(for: [shortSection], baseWidth: baseWidth)
        let longWidth = controller.measuredStandardMenuWidth(for: [longSection], baseWidth: baseWidth)

        #expect(longWidth == shortWidth)
        #expect(controller.measuredStandardMenuWidthCache.count == 1)

        let menu = NSMenu()
        controller.addActionableSections([longSection], to: menu, width: longWidth, provider: nil)
        guard menu.items.indices.contains(1),
              case let .action(title, .focusAgentSession) = longSection.entries[1],
              let view = menu.items[1].view
        else {
            Issue.record("Expected a hosted Agent Session action row")
            return
        }
        let row = menu.items[1]

        #expect(row.title.isEmpty)
        #expect(row.toolTip == title)
        #expect(row.representedObject as? String == "agentSession:local:session")
        #expect(row.identifier != nil)
        #expect(view.frame.width == longWidth)
    }

    @Test
    func `fingerprinted menu card height cache survives content version invalidation`() {
        let controller = self.makeHeightCacheController()
        defer { controller.releaseStatusItemsForTesting() }

        var measureCount = 0
        let first = controller.cachedMenuCardHeight(
            for: "menuCard",
            scope: UsageProvider.codex.rawValue,
            width: 320,
            fingerprint: "content:stable")
        {
            measureCount += 1
            return 42
        }

        controller.invalidateMenus()

        let second = controller.cachedMenuCardHeight(
            for: "menuCard",
            scope: UsageProvider.codex.rawValue,
            width: 320,
            fingerprint: "content:stable")
        {
            measureCount += 1
            return 99
        }

        #expect(first == 42)
        #expect(second == 42)
        #expect(measureCount == 1)
    }

    @Test
    func `fingerprinted menu card height cache remeasures when content changes`() {
        let controller = self.makeHeightCacheController()
        defer { controller.releaseStatusItemsForTesting() }

        var measureCount = 0
        let first = controller.cachedMenuCardHeight(
            for: "menuCard",
            scope: UsageProvider.codex.rawValue,
            width: 320,
            fingerprint: "content:a")
        {
            measureCount += 1
            return 42
        }
        let second = controller.cachedMenuCardHeight(
            for: "menuCard",
            scope: UsageProvider.codex.rawValue,
            width: 320,
            fingerprint: "content:b")
        {
            measureCount += 1
            return 99
        }

        #expect(first == 42)
        #expect(second == 99)
        #expect(measureCount == 2)
    }

    @Test
    func `unfingerprinted menu card height cache remains content version scoped`() {
        let controller = self.makeHeightCacheController()
        defer { controller.releaseStatusItemsForTesting() }

        var measureCount = 0
        let first = controller.cachedMenuCardHeight(
            for: "menuCard",
            scope: UsageProvider.codex.rawValue,
            width: 320)
        {
            measureCount += 1
            return 42
        }

        controller.invalidateMenus()

        let second = controller.cachedMenuCardHeight(
            for: "menuCard",
            scope: UsageProvider.codex.rawValue,
            width: 320)
        {
            measureCount += 1
            return 99
        }

        #expect(first == 42)
        #expect(second == 99)
        #expect(measureCount == 2)
    }

    @Test
    func `menu invalidation prunes old version scoped height cache entries`() {
        let controller = self.makeHeightCacheController()
        defer { controller.releaseStatusItemsForTesting() }

        _ = controller.cachedMenuCardHeight(
            for: "versioned",
            scope: UsageProvider.codex.rawValue,
            width: 320)
        {
            42
        }
        _ = controller.cachedMenuCardHeight(
            for: "fingerprinted",
            scope: UsageProvider.codex.rawValue,
            width: 320,
            fingerprint: "content:stable")
        {
            99
        }

        controller.invalidateMenus()

        #expect(controller.menuCardHeightCache.keys.allSatisfy { !$0.fingerprint.hasPrefix("version:") })
        #expect(controller.menuCardHeightCache.keys.contains { $0.fingerprint == "content:stable" })
    }

    @Test
    func `menu card height cache scopes same row ids by provider`() {
        let previousMenuCardRendering = StatusItemController.menuCardRenderingEnabled
        StatusItemController.menuCardRenderingEnabled = true
        defer {
            StatusItemController.menuCardRenderingEnabled = previousMenuCardRendering
        }

        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        let registry = ProviderRegistry.shared
        for provider in UsageProvider.allCases {
            guard let metadata = registry.metadata[provider] else { continue }
            settings.setProviderEnabled(
                provider: provider,
                metadata: metadata,
                enabled: provider == .codex || provider == .claude)
        }

        let store = self.makeCodexStore(settings: settings, dashboardAuthorized: false)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 12,
                    windowMinutes: 300,
                    resetsAt: nil,
                    resetDescription: nil),
                secondary: nil,
                tertiary: nil,
                updatedAt: Date(),
                identity: ProviderIdentitySnapshot(
                    providerID: .claude,
                    accountEmail: "claude@example.com",
                    accountOrganization: nil,
                    loginMethod: "Claude Pro")),
            provider: .claude)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: AccountInfo(email: nil, plan: nil),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.populateMenu(menu, provider: .codex)
        controller.populateMenu(menu, provider: .claude)

        let scopes = Set(controller.menuCardHeightCache.keys.map(\.scope))
        #expect(scopes.contains(UsageProvider.codex.rawValue))
        #expect(scopes.contains(UsageProvider.claude.rawValue))
    }

    private func makeHeightCacheController() -> StatusItemController {
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        let store = self.makeCodexStore(settings: settings, dashboardAuthorized: false)
        return StatusItemController(
            store: store,
            settings: settings,
            account: AccountInfo(email: nil, plan: nil),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
    }
}

@MainActor
private final class MenuHeightNotifications: NSObject {
    private(set) var additions = 0
    private(set) var removals = 0
    var changedHeights: [CGFloat] = []

    init(menu: NSMenu) {
        super.init()
        for name in [
            NSMenu.didAddItemNotification,
            NSMenu.didRemoveItemNotification,
            NSMenu.didChangeItemNotification,
        ] {
            NotificationCenter.default.addObserver(self, selector: #selector(self.record(_:)), name: name, object: menu)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func record(_ notification: Notification) {
        switch notification.name {
        case NSMenu.didAddItemNotification:
            self.additions += 1
        case NSMenu.didRemoveItemNotification:
            self.removals += 1
        case NSMenu.didChangeItemNotification:
            guard let menu = notification.object as? NSMenu,
                  let index = notification.userInfo?["NSMenuItemIndex"] as? Int,
                  let height = menu.item(at: index)?.view?.frame.height
            else { return }
            self.changedHeights.append(height)
        default:
            break
        }
    }
}

@MainActor
private final class MenuCardRepresentableCounter {
    var makeViewCount = 0
}

private struct CountingMenuCardRepresentable: NSViewRepresentable {
    let counter: MenuCardRepresentableCounter

    func makeNSView(context: Context) -> NSTextField {
        self.counter.makeViewCount += 1
        return NSTextField(labelWithString: "Counted")
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        _ = nsView
        _ = context
    }
}

extension StatusMenuTests {
    @Test
    func `fleet menu cached switches and account collapse preserve current row geometry`() throws {
        try self.withHeightFleetFixture(renderCards: true) { controller in
            self.seedHeightFleetClaude(2, controller: controller)
            try self.seedHeightFleetCodex(6, controller: controller)
            let menu = controller.makeMenu()
            let key = ObjectIdentifier(menu)
            controller.populateMenu(menu, provider: .codex)
            let overviewIDs = menu.items.compactMap { $0.representedObject as? String }
            #expect(overviewIDs.count(where: { $0.hasPrefix("overviewAccount-codex-") }) == 5)
            #expect(overviewIDs.count(where: { $0.hasPrefix("overviewAccount-claude-") }) == 1)
            self.expectHeightFleetGeometry(in: menu)

            controller.warmMergedSwitcherSiblingContent(in: menu)
            let codexCache = try #require(controller.mergedSwitcherContentCaches[key]?[.provider(.codex)])
            #expect(codexCache.menuWidth == 310)
            #expect(codexCache.items.allSatisfy { $0.menu == nil })
            let codexIDs = codexCache.items.compactMap { $0.representedObject as? String }
            controller.preservingMergedSwitcherContentCachesDuringInvalidation {
                controller.settings.mergedMenuLastSelectedWasOverview = false
                controller.selectedMenuProvider = .codex
            }
            controller.populateMenu(menu, provider: .codex)
            let contentStart = controller.providerSwitcherContentStartIndex(in: menu)
            #expect(menu.items.dropFirst(contentStart).compactMap { $0.representedObject as? String } == codexIDs)
            let overviewCache = try #require(controller.mergedSwitcherContentCaches[key]?[.overview])
            #expect(overviewCache.items.allSatisfy { $0.menu == nil })
            self.expectHeightFleetGeometry(in: menu)

            controller.preservingMergedSwitcherContentCachesDuringInvalidation {
                controller.settings.mergedMenuLastSelectedWasOverview = true
            }
            controller.populateMenu(menu, provider: .codex)
            #expect(menu.items.compactMap { $0.representedObject as? String } == overviewIDs)
            self.expectHeightFleetGeometry(in: menu)

            controller.preservingMergedSwitcherContentCachesDuringInvalidation {
                controller.settings.mergedMenuLastSelectedWasOverview = false
            }
            controller.populateMenu(menu, provider: .codex)
            let compactItem = try #require(menu.items.first {
                ($0.representedObject as? String)?.hasPrefix("codexAccountCompact-") == true
            })
            let compactID = try #require(compactItem.representedObject as? String)
            let cardID = compactID.replacingOccurrences(of: "codexAccountCompact-", with: "codexAccountCard-")
            let compactView = try #require(compactItem.view as? MenuRowContainerView)
            let compactHeight = compactView.frame.height
            let collapsedTotal = menu.items.reduce(CGFloat.zero) { $0 + ($1.view?.frame.height ?? 0) }
            let expand = try #require(compactView.rowPayload.onClick)
            expand()
            controller.populateMenu(menu, provider: .codex)
            let expandedItem = try #require(menu.items.first { $0.representedObject as? String == cardID })
            let expandedView = try #require(expandedItem.view as? MenuRowContainerView)
            #expect(expandedView.frame.height > compactHeight)
            self.expectHeightFleetGeometry(in: menu)
            let expandedTotal = menu.items.reduce(CGFloat.zero) { $0 + ($1.view?.frame.height ?? 0) }
            #expect(expandedTotal > collapsedTotal)

            let collapse = try #require(expandedView.rowPayload.onClick)
            collapse()
            controller.populateMenu(menu, provider: .codex)
            let restoredItem = try #require(menu.items.first { $0.representedObject as? String == compactID })
            #expect(restoredItem.view?.frame.height == compactHeight)
            #expect(!menu.items.contains { $0.representedObject as? String == cardID })
            let restoredTotal = menu.items.reduce(CGFloat.zero) { $0 + ($1.view?.frame.height ?? 0) }
            #expect(restoredTotal < expandedTotal)
            #expect(restoredTotal == collapsedTotal)
            self.expectHeightFleetGeometry(in: menu)
        }
    }

    @Test
    func `overview inline toggles restore measured heights and leave provider tab defaults intact`() throws {
        try self.withHeightFleetFixture(renderCards: true) { controller in
            self.seedHeightFleetClaude(2, controller: controller)
            try self.seedHeightFleetCodex(3, controller: controller)
            let menu = controller.makeMenu()
            controller.populateMenu(menu, provider: .codex)
            let originalIDs = menu.items.compactMap { $0.representedObject as? String }
            let total = { menu.items.reduce(CGFloat.zero) { $0 + ($1.view?.frame.height ?? 0) } }
            let originalTotal = total()
            for provider in [UsageProvider.codex, .claude] {
                let summaryID = "overviewRow-\(provider.rawValue)"
                let summary = try #require(menu.items.first { $0.representedObject as? String == summaryID })
                let initialHeight = try #require(summary.view).frame.height
                controller.warmMergedSwitcherSiblingContent(in: menu)
                #expect(try #require(summary.view as? MenuRowContainerView)._test_simulateRuntimeClick())
                #expect(controller.mergedSwitcherContentCaches[ObjectIdentifier(menu)] == nil)
                controller.populateMenu(menu, provider: .codex)
                let collapsed = try #require(menu.items.first { $0.representedObject as? String == summaryID })
                #expect(try #require(collapsed.view).frame.height < initialHeight)
                #expect(total() < originalTotal)
                self.expectHeightFleetGeometry(in: menu)
                #expect(try #require(collapsed.view as? MenuRowContainerView)._test_simulateRuntimeClick())
                controller.populateMenu(menu, provider: .codex)
                #expect(menu.items.first { $0.representedObject as? String == summaryID }?.view?.frame
                    .height == initialHeight)
                #expect(total() == originalTotal)
                let compact = try #require(menu.items.first {
                    ($0.representedObject as? String)?.hasPrefix("overviewAccount-\(provider.rawValue)-") == true
                })
                let compactID = try #require(compact.representedObject as? String)
                let compactHeight = try #require(compact.view).frame.height
                let cardID = compactID.replacingOccurrences(of: "overviewAccount-", with: "overviewAccountCard-")
                #expect(try #require(compact.view as? MenuRowContainerView)._test_simulateRuntimeClick())
                controller.populateMenu(menu, provider: .codex)
                let expanded = try #require(menu.items.first { $0.representedObject as? String == cardID })
                #expect(try #require(expanded.view).frame.height > compactHeight)
                #expect(total() > originalTotal)
                self.expectHeightFleetGeometry(in: menu)
                #expect(try #require(expanded.view as? MenuRowContainerView)._test_simulateRuntimeClick())
                controller.populateMenu(menu, provider: .codex)
                #expect(menu.items.first { $0.representedObject as? String == compactID }?.view?.frame
                    .height == compactHeight)
                #expect(total() == originalTotal)
                #expect(menu.items.compactMap { $0.representedObject as? String } == originalIDs)
                self.expectHeightFleetGeometry(in: menu)
            }
            controller.selectOverviewProvider(.codex, menu: menu)
            controller.populateMenu(menu, provider: .codex)
            let codexIDs = menu.items.compactMap { $0.representedObject as? String }
            #expect(codexIDs.count { $0.hasPrefix("codexAccountCompact-") } == 3)
            #expect(!codexIDs.contains { $0.hasPrefix("codexAccountCard-") })
            controller.selectOverviewProvider(.claude, menu: menu)
            controller.populateMenu(menu, provider: .claude)
            #expect(menu.items.contains { $0.representedObject as? String == "claudeNativeProfileCard-default" })
        }
    }

    private func expectHeightFleetGeometry(in menu: NSMenu) {
        let rows = menu.items.compactMap { $0.view as? MenuRowContainerView }
        #expect(!rows.isEmpty)
        for row in rows {
            let freshHeight = ceil(row.measuredHeight(width: 310) + 7)
            #expect(row.frame.width == 310)
            #expect(row.frame.height == freshHeight)
            #expect(row.intrinsicContentSize.height == freshHeight)
            row.needsLayout = true
            row.layoutSubtreeIfNeeded()
        }
    }

    private func withHeightFleetFixture(
        providers: [UsageProvider] = [.codex, .claude],
        renderCards: Bool = false,
        _ body: (StatusItemController) throws -> Void) throws
    {
        let root = TestFixtureScratch.root
            .appendingPathComponent("MenuHeightFleetFixture-" + UUID().uuidString, isDirectory: true)
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
        for provider in providers {
            settings.setProviderEnabled(
                provider: provider,
                metadata: ProviderDescriptorRegistry.descriptor(for: provider).metadata,
                enabled: true)
        }
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        settings.costUsageEnabled = false
        settings.mergeIcons = true
        settings.mergedMenuLastSelectedWasOverview = true
        settings.multiAccountMenuLayout = .stacked
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
            statusBar: .system,
            menuCardRenderingEnabled: renderCards,
            menuRefreshEnabled: false)
        defer { controller.releaseStatusItemsForTesting() }
        try body(controller)
    }

    private static func heightFleetSnapshot(
        provider: UsageProvider,
        accountEmail: String = "selected@example.com") -> UsageSnapshot
    {
        UsageSnapshot(
            primary: RateWindow(usedPercent: 21, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            identity: ProviderIdentitySnapshot(
                providerID: provider.instanceID,
                accountEmail: accountEmail,
                accountOrganization: nil,
                loginMethod: "Pro"))
    }

    @discardableResult
    private func seedHeightFleetCodex(_ count: Int, controller: StatusItemController) throws -> [CodexVisibleAccount] {
        let home = try URL(fileURLWithPath: #require(controller.store.environmentBase["HOME"]))
        let observed = (0..<count).map { index in
            ObservedSystemCodexAccount(
                email: "account\(index)@example.com",
                workspaceAccountID: "workspace-\(index)",
                authFingerprint: "fingerprint-\(index)",
                codexHomePath: home.appendingPathComponent("codex-\(index)").path,
                observedAt: Date(timeIntervalSince1970: 1_800_000_000),
                identity: .providerAccount(id: "workspace-\(index)"))
        }
        controller.settings.codexActiveSource = .profileHome(path: observed[0].codexHomePath)
        controller.settings._test_codexAccountSnapshotLoader = { source in
            CodexAccountReconciliationSnapshot(
                storedAccounts: [],
                activeStoredAccount: nil,
                liveSystemAccount: nil,
                profileHomeAccounts: observed,
                matchingStoredAccountForLiveSystemAccount: nil,
                activeSource: source,
                hasUnreadableAddedAccountStore: false)
        }
        // Descriptor construction reloads reconciliation; seed its source as well as the menu projection.
        let accounts = controller.settings.codexVisibleAccountProjection.visibleAccounts
        controller.store.codexAccountSnapshots = accounts.map {
            CodexAccountUsageSnapshot(
                account: $0,
                snapshot: Self.heightFleetSnapshot(provider: .codex, accountEmail: $0.email),
                error: nil,
                sourceLabel: "Synthetic")
        }
        let activeAccount = try #require(accounts.first { $0.isActive })
        controller.store.snapshots[.codex] = Self.heightFleetSnapshot(
            provider: .codex, accountEmail: activeAccount.email)
        return accounts
    }

    private func seedHeightFleetClaude(_ count: Int, controller: StatusItemController) {
        let aliases = Array(["default", "secondary"].prefix(count))
        let profiles = aliases.map { alias in
            ClaudeFleetProfileDiscovery.Profile(
                alias: alias,
                home: "/synthetic/home",
                configDirectory: "/synthetic/home/\(alias)",
                nativeCLI: "/synthetic/bin/claude",
                store: "synthetic")
        }
        controller.settings.claudeNativeProfileAlias = "default"
        controller.store.claudeNativeProfileAccountsState = ClaudeNativeProfileAccountsState(
            selectedAlias: "default",
            selectedIdentity: "synthetic-default",
            configRevision: controller.settings.providerConfigRevision(for: .claude),
            profiles: profiles,
            identities: Dictionary(uniqueKeysWithValues: aliases.map { ($0, "synthetic-\($0)") }))
        controller.store.claudeNativeProfileAccountSnapshots = aliases.map { alias in
            ProviderAccountUsageSnapshot(
                id: ProviderAccountIdentity(source: "claude-native-profile", opaqueID: alias),
                provider: .claude,
                displayLabel: alias,
                isActive: alias == "default",
                canActivate: false,
                snapshot: Self.heightFleetSnapshot(provider: .claude),
                error: nil,
                sourceLabel: "Synthetic")
        }
        controller.store.snapshots[.claude] = Self.heightFleetSnapshot(provider: .claude)
    }
}
