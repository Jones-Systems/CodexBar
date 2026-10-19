import AppKit
import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
@Suite(.serialized)
struct OverviewFleetAccountsTests {
    private func withFixture(
        providers: [UsageProvider] = [.codex, .claude],
        renderCards: Bool = false,
        _ body: (StatusItemController) throws -> Void) throws
    {
        let root = TestFixtureScratch.root
            .appendingPathComponent("OverviewFleetAccountsTests-" + UUID().uuidString, isDirectory: true)
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

    private static func snapshot(provider: UsageProvider) -> UsageSnapshot {
        UsageSnapshot(
            primary: RateWindow(usedPercent: 21, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            identity: ProviderIdentitySnapshot(
                providerID: provider.instanceID,
                accountEmail: "selected@example.com",
                accountOrganization: nil,
                loginMethod: "Pro"))
    }

    private func seedCodex(_ count: Int, controller: StatusItemController) {
        let accounts = (0..<count).map { index in
            CodexVisibleAccount(
                id: "codex-\(index)",
                email: "account\(index)@example.com",
                storedAccountID: nil,
                selectionSource: .liveSystem,
                isActive: index == 0,
                isLive: index == 0,
                canReauthenticate: false,
                canRemove: false)
        }
        controller.settings.cachedCodexAccountMenuProjection = CachedCodexAccountMenuProjection(
            activeSource: .liveSystem,
            loadedAt: Date(),
            projection: CodexVisibleAccountProjection(
                visibleAccounts: accounts,
                activeVisibleAccountID: accounts.first?.id,
                liveVisibleAccountID: accounts.first?.id,
                hasUnreadableAddedAccountStore: false))
        controller.store.codexAccountSnapshots = accounts.map {
            CodexAccountUsageSnapshot(
                account: $0, snapshot: Self.snapshot(provider: .codex), error: nil, sourceLabel: "Synthetic")
        }
        controller.store.snapshots[.codex] = Self.snapshot(provider: .codex)
    }

    private func seedClaude(_ count: Int, controller: StatusItemController) {
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
                snapshot: Self.snapshot(provider: .claude),
                error: nil,
                sourceLabel: "Synthetic")
        }
        controller.store.snapshots[.claude] = Self.snapshot(provider: .claude)
    }

    private func identifiers(in menu: NSMenu) -> [String] {
        menu.items.compactMap { $0.representedObject as? String }
    }

    @Test
    func `overview renders six codex and two claude accounts without folding`() throws {
        try self.withFixture(providers: [.codex, .claude]) { controller in
            self.seedCodex(6, controller: controller)
            self.seedClaude(2, controller: controller)
            let menu = controller.makeMenu()
            controller.refreshMenuForOpenIfNeeded(menu, provider: nil)
            let ids = self.identifiers(in: menu)
            let codexIndex = try #require(ids.firstIndex(of: "overviewRow-codex"))
            let accountIDs = ids.filter { $0.hasPrefix("overviewAccount-codex-") }
            #expect(accountIDs.count == 5)
            #expect(!accountIDs.contains("overviewAccount-codex-codex-0"))
            #expect(Array(ids[(codexIndex + 1)...].prefix(5)) == accountIDs)
            let claudeIndex = try #require(ids.firstIndex(of: "overviewRow-claude"))
            #expect(ids.dropFirst(claudeIndex + 1).first == "overviewAccount-claude-secondary")
            #expect(ids.count(where: { $0.hasPrefix("overviewAccount-claude-") }) == 1)
            #expect(!ids.contains { $0.contains("Collapsed") })
        }
    }

    @Test
    func `segmented overview uses cached quota only for matching account id and owner`() throws {
        try self.withFixture(providers: [.codex]) { controller in
            self.seedCodex(3, controller: controller)
            controller.settings.multiAccountMenuLayout = .segmented
            let display = try #require(controller.codexAccountMenuDisplay(for: .codex))
            #expect(display.snapshots.isEmpty)
            let initialRows = controller.overviewFleetAccountRows(for: .codex)
            #expect(initialRows.count == 2)
            #expect(initialRows.allSatisfy { $0.model.headroomPercent == 79 })

            let first = try #require(display.accounts.first { $0.id == "codex-1" })
            let second = try #require(display.accounts.first { $0.id == "codex-2" })
            let wrongOwner = CodexVisibleAccount(
                id: first.id,
                email: "different-owner@example.com",
                storedAccountID: nil,
                selectionSource: first.selectionSource,
                isActive: false,
                isLive: false,
                canReauthenticate: false,
                canRemove: false)
            let wrongID = CodexVisibleAccount(
                id: "different-id",
                email: second.email,
                storedAccountID: nil,
                selectionSource: second.selectionSource,
                isActive: false,
                isLive: false,
                canReauthenticate: false,
                canRemove: false)
            controller.store.codexAccountSnapshots = [wrongOwner, wrongID].map {
                CodexAccountUsageSnapshot(
                    account: $0, snapshot: Self.snapshot(provider: .codex), error: nil, sourceLabel: "Synthetic")
            }
            let rejectedRows = controller.overviewFleetAccountRows(for: .codex)
            #expect(rejectedRows.count == 2)
            #expect(rejectedRows.allSatisfy { $0.model.headroomPercent == nil })
            #expect(controller.settings.multiAccountMenuLayout == .segmented)
            #expect(controller.settings.codexVisibleAccountProjectionForMenuDisplay?
                .activeVisibleAccountID == "codex-0")
        }
    }

    @Test
    func `single codex account and other providers add no overview account rows`() throws {
        try self.withFixture(providers: [.codex, .gemini]) { controller in
            self.seedCodex(1, controller: controller)
            controller.store.snapshots[.gemini] = Self.snapshot(provider: .gemini)
            let overviewMenu = controller.makeMenu()
            controller.refreshMenuForOpenIfNeeded(overviewMenu, provider: nil)
            let ids = self.identifiers(in: overviewMenu)
            #expect(ids.contains("overviewRow-codex"))
            #expect(ids.contains("overviewRow-gemini"))
            #expect(!ids.contains { $0.hasPrefix("overviewAccount-") })
            let menu = NSMenu()
            let existing = NSMenuItem(title: "Existing", action: nil, keyEquivalent: "")
            menu.addItem(existing)
            controller.addOverviewFleetAccountRows(for: .gemini, to: menu, captureMenu: menu, width: 320)
            #expect(menu.items.count == 1)
            #expect(menu.items.first === existing)
        }
    }

    @Test
    func `overview account click expands and navigates without changing active account`() throws {
        try self.withFixture(providers: [.codex, .claude], renderCards: true) { controller in
            self.seedCodex(6, controller: controller)
            let menu = NSMenu()
            let accountID = ProviderAccountIdentity(source: "codex-account", opaqueID: "codex-1")
            controller.compactAccountCollapsedIDs.insert(accountID)
            let originalSource = controller.settings.codexActiveSource
            let originalSelectedID = controller.settings.codexVisibleAccountProjectionForMenuDisplay?
                .activeVisibleAccountID
            controller.addOverviewFleetAccountRows(for: .codex, to: menu, captureMenu: menu, width: 320)
            let item = try #require(menu.items.first {
                ($0.representedObject as? String) == "overviewAccount-codex-codex-1"
            })
            let view = try #require(item.view as? MenuRowContainerView)
            #expect(view._test_simulateRuntimeClick())
            #expect(controller.compactAccountExpandedIDs.contains(accountID))
            #expect(!controller.compactAccountCollapsedIDs.contains(accountID))
            #expect(controller.selectedMenuProvider == .codex)
            #expect(!controller.settings.mergedMenuLastSelectedWasOverview)
            #expect(controller.settings.codexActiveSource == originalSource)
            #expect(controller.settings.codexVisibleAccountProjectionForMenuDisplay?.activeVisibleAccountID
                == originalSelectedID)
        }
    }

    @Test
    func `claude overview click expands its profile without selecting it`() throws {
        try self.withFixture { controller in
            self.seedClaude(2, controller: controller)
            let id = ProviderAccountIdentity(source: "claude-native-profile", opaqueID: "secondary")
            let menu = NSMenu()
            controller.selectOverviewFleetAccount(id, provider: .claude, menu: menu)
            #expect(controller.compactAccountExpandedIDs.contains(id))
            #expect(controller.selectedMenuProvider == .claude)
            #expect(controller.settings.claudeNativeProfileAlias == "default")
            #expect(controller.store.claudeNativeProfileAccountsForDisplay()
                .first { $0.isActive }?.id.opaqueID == "default")
            #expect(controller.settings.effectiveSelectedTokenAccount(for: .claude) == nil)
        }
    }

    @Test
    func `single claude profile adds no row and loading profile retains its indicator`() throws {
        try self.withFixture { controller in
            self.seedClaude(1, controller: controller)
            #expect(controller.overviewFleetAccountRows(for: .claude).isEmpty)
            self.seedClaude(2, controller: controller)
            let id = ProviderAccountIdentity(source: "claude-native-profile", opaqueID: "secondary")
            controller.store.claudeNativeProfileAccountSnapshots[1] = ProviderAccountUsageSnapshot(
                id: id,
                provider: .claude,
                displayLabel: "secondary",
                isActive: false,
                snapshot: nil,
                error: nil,
                sourceLabel: nil)
            controller.store.claudeNativeProfileRefreshingAliases.insert("secondary")
            let row = try #require(controller.overviewFleetAccountRows(for: .claude).first)
            #expect(row.accountID == id)
            #expect(row.model.isRefreshing)
            #expect(row.model.headroomPercent == nil)
        }
    }

    @Test
    func `overview rows redact labels and ignore prior expansion`() throws {
        try self.withFixture(providers: [.codex]) { controller in
            self.seedCodex(9, controller: controller)
            let accounts = try #require(controller.codexAccountMenuDisplay(for: .codex)).accounts
            let account = try #require(accounts.first { !$0.isActive })
            controller.settings.setAccountDisplayLabel(
                "private@example.com",
                provider: .codex,
                profileIdentity: JonesAccountDisplayLabel.codexProfileIdentity(for: account))
            let id = ProviderAccountIdentity(source: "codex-account", opaqueID: account.id)
            controller.compactAccountExpandedIDs.insert(id)
            controller.settings.hidePersonalInfo = true
            let rows = controller.overviewFleetAccountRows(for: .codex)
            #expect(rows.count == 8)
            let row = try #require(rows.first { $0.accountID == id })
            #expect(row.model.label == PersonalInfoRedactor.redactEmail("private@example.com", isEnabled: true))
            #expect(row.model.label != "private@example.com")
        }
    }

    @Test
    func `overview account rows respect selected provider scopes and provider limit`() throws {
        let providers: [UsageProvider] = [.codex, .claude, .gemini, .cursor, .copilot, .zai, .augment]
        try self.withFixture(providers: providers) { controller in
            self.seedCodex(6, controller: controller)
            for provider in providers where provider != .codex {
                controller.store.snapshots[provider.instanceID] = Self.snapshot(provider: provider)
            }
            #expect(controller.overviewProviderScopes(enabledProviders: providers).visible.count == 6)
            _ = controller.settings.setMergedOverviewProviderSelection(
                provider: .codex, isSelected: false, activeProviders: providers)
            let menu = controller.makeMenu()
            controller.refreshMenuForOpenIfNeeded(menu, provider: nil)
            let ids = self.identifiers(in: menu)
            #expect(!ids.contains("overviewRow-codex"))
            #expect(!ids.contains { $0.hasPrefix("overviewAccount-codex-") })
            #expect(ids.count(where: { $0.hasPrefix("overviewRow-") }) <= 6)
        }
    }
}
