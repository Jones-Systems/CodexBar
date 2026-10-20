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

    private static func snapshot(
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
    private func seedCodex(_ count: Int, controller: StatusItemController) throws -> [CodexVisibleAccount] {
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
        controller.settings._test_codexAccountSnapshotLoader = { source in
            CodexAccountReconciliationSnapshot(
                storedAccounts: [],
                activeStoredAccount: nil,
                liveSystemAccount: observed.first,
                profileHomeAccounts: Array(observed.dropFirst()),
                matchingStoredAccountForLiveSystemAccount: nil,
                activeSource: source,
                hasUnreadableAddedAccountStore: false)
        }
        // Descriptor construction reloads reconciliation; seed its source as well as the menu projection.
        let accounts = controller.settings.codexVisibleAccountProjection.visibleAccounts
        controller.store.codexAccountSnapshots = accounts.map {
            CodexAccountUsageSnapshot(
                account: $0,
                snapshot: Self.snapshot(provider: .codex, accountEmail: $0.email),
                error: nil,
                sourceLabel: "Synthetic")
        }
        let activeAccount = try #require(accounts.first { $0.isActive })
        controller.store.snapshots[.codex] = Self.snapshot(provider: .codex, accountEmail: activeAccount.email)
        return accounts
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
    func `Codex overview and compact menu share weekly and banked expiry details`() throws {
        try self.withFixture(providers: [.codex]) { controller in
            let now = Date(timeIntervalSince1970: 1_781_726_400)
            let accounts = try self.seedCodex(3, controller: controller)
            let credits = CodexRateLimitResetCreditsSnapshot(
                credits: [
                    CodexRateLimitResetCredit(
                        id: "synthetic-banked",
                        resetType: "weekly",
                        status: .available,
                        grantedAt: now,
                        expiresAt: now.addingTimeInterval(172_800),
                        redeemStartedAt: nil,
                        redeemedAt: nil,
                        title: nil,
                        description: nil),
                ],
                availableCount: 1,
                updatedAt: now)
            controller.store.codexAccountSnapshots = accounts.map {
                CodexAccountUsageSnapshot(
                    account: $0,
                    snapshot: UsageSnapshot(
                        primary: RateWindow(
                            usedPercent: 10, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
                        secondary: RateWindow(
                            usedPercent: 20,
                            windowMinutes: 10080,
                            resetsAt: now.addingTimeInterval(399_600),
                            resetDescription: nil),
                        codexResetCredits: credits,
                        updatedAt: now),
                    error: nil,
                    sourceLabel: "Synthetic")
            }
            for style in [ResetTimeDisplayStyle.countdown, .absolute] {
                controller.settings.resetTimesShowAbsolute = style == .absolute
                let display = try #require(controller.codexAccountMenuDisplay(for: .codex))
                let projected = StatusItemController.projectedCodexAccounts(
                    display: display,
                    displayLabels: controller.settings.codexAccountDisplayLabels(for: display.accounts))
                let plan = controller.compactAccountPlan(for: .codex, accounts: projected)
                let details = StatusItemController.compactCodexRowDetails(
                    accounts: projected, resetStyle: style, now: now)
                let rendering = StatusItemController.CompactAccountMenuRendering(
                    plan: plan,
                    accounts: projected,
                    idPrefix: "codexAccount",
                    cardModel: { _ in nil },
                    codexRowDetails: details)
                let overviewRows = controller.overviewFleetAccountRows(for: .codex, now: now)
                #expect(overviewRows.count == 2)
                #expect(plan.rows.count { if case let .compact(compact) = $0 { compact.isActive } else { false } } == 1)
                for row in plan.rows {
                    // The active account is in the Codex list but stays the Overview provider summary row.
                    guard case let .compact(compact) = row, !compact.isActive else { continue }
                    let model = controller.compactAccountRowModel(for: compact, rendering: rendering)
                    let overview = try #require(overviewRows.first { $0.accountID == compact.accountID })
                    #expect(model == overview.model)
                    #expect(model.constraintDetail?.hasPrefix("Weekly 80% left · Resets ") == true)
                    #expect(model.trailingDetail?.text == "2d")
                    #expect(model.trailingDetail?.count == 1)
                    #expect(!model.hasError)
                }
            }
        }
    }

    @Test
    func `Codex missing weekly keeps constraint fallback and loading status text`() throws {
        try self.withFixture(providers: [.codex]) { controller in
            let now = Date(timeIntervalSince1970: 1_781_726_400)
            let accounts = try self.seedCodex(2, controller: controller)
            controller.store.codexAccountSnapshots = accounts.map {
                CodexAccountUsageSnapshot(
                    account: $0,
                    snapshot: UsageSnapshot(
                        primary: RateWindow(
                            usedPercent: 95, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
                        secondary: nil,
                        updatedAt: now),
                    error: nil,
                    sourceLabel: "Synthetic")
            }
            let display = try #require(controller.codexAccountMenuDisplay(for: .codex))
            let projected = StatusItemController.projectedCodexAccounts(display: display)
            let plan = controller.compactAccountPlan(for: .codex, accounts: projected)
            let compact = try #require(plan.rows.compactMap { row -> AccountMenuLayoutPlanner.CompactRow? in
                if case let .compact(compact) = row { return compact }
                return nil
            }.first)
            var rendering = StatusItemController.CompactAccountMenuRendering(
                plan: plan,
                accounts: projected,
                idPrefix: "codexAccount",
                cardModel: { _ in nil },
                codexRowDetails: StatusItemController.compactCodexRowDetails(
                    accounts: projected, resetStyle: .countdown, now: now))
            #expect(compact.constraintDetail != nil)
            #expect(controller.compactAccountRowModel(for: compact, rendering: rendering).constraintDetail
                == compact.constraintDetail)
            #expect(controller.overviewFleetAccountRows(for: .codex, now: now).first?.model.constraintDetail
                == compact.constraintDetail)
            rendering.accountStatusText[compact.accountID] = "Loading synthetic account"
            rendering.refreshingAccountIDs.insert(compact.accountID)
            let loading = controller.compactAccountRowModel(for: compact, rendering: rendering)
            #expect(loading.constraintDetail == "Loading synthetic account")
            #expect(loading.isRefreshing)
        }
    }

    @Test
    func `overview renders six codex and two claude accounts without folding`() throws {
        try self.withFixture(providers: [.codex, .claude]) { controller in
            self.seedClaude(2, controller: controller)
            let accounts = try self.seedCodex(6, controller: controller)
            let projection = try #require(controller.settings.codexVisibleAccountProjectionForMenuDisplay)
            #expect(projection.visibleAccounts.count == 6)
            _ = controller.makeMenuDescriptor(provider: .codex, includeContextualActions: true)
            #expect(controller.settings.codexVisibleAccountProjectionForMenuDisplay == projection)
            let activeID = try #require(accounts.first { $0.isActive }?.id)
            let menu = controller.makeMenu()
            controller.refreshMenuForOpenIfNeeded(menu, provider: nil)
            let ids = self.identifiers(in: menu)
            let codexIndex = try #require(ids.firstIndex(of: "overviewRow-codex"))
            let accountIDs = ids.filter { $0.hasPrefix("overviewAccount-codex-") }
            #expect(accountIDs.count == 5)
            #expect(!accountIDs.contains("overviewAccount-codex-\(activeID)"))
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
            let accounts = try self.seedCodex(3, controller: controller)
            controller.settings.multiAccountMenuLayout = .segmented
            let display = try #require(controller.codexAccountMenuDisplay(for: .codex))
            #expect(display.snapshots.isEmpty)
            let initialRows = controller.overviewFleetAccountRows(for: .codex)
            #expect(initialRows.count == 2)
            #expect(initialRows.allSatisfy { $0.model.headroomPercent == 79 })

            let inactiveAccounts = display.accounts.filter { !$0.isActive }
            let first = try #require(inactiveAccounts.first)
            let second = try #require(inactiveAccounts.last)
            #expect(first.id != second.id)
            let wrongOwner = CodexVisibleAccount(
                id: first.id,
                email: "different-owner@example.com",
                workspaceAccountID: first.workspaceAccountID,
                authFingerprint: first.authFingerprint,
                storedAccountID: first.storedAccountID,
                selectionSource: first.selectionSource,
                isActive: false,
                isLive: false,
                canReauthenticate: false,
                canRemove: false)
            let wrongID = CodexVisibleAccount(
                id: "different-id",
                email: second.email,
                workspaceAccountID: second.workspaceAccountID,
                authFingerprint: second.authFingerprint,
                storedAccountID: second.storedAccountID,
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
                .activeVisibleAccountID == accounts.first { $0.isActive }?.id)
        }
    }

    @Test
    func `single codex account and other providers add no overview account rows`() throws {
        try self.withFixture(providers: [.codex, .gemini]) { controller in
            try self.seedCodex(1, controller: controller)
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
            let accounts = try self.seedCodex(6, controller: controller)
            let inactive = try #require(accounts.first { !$0.isActive })
            let menu = NSMenu()
            let accountID = ProviderAccountIdentity(source: "codex-account", opaqueID: inactive.id)
            controller.compactAccountCollapsedIDs.insert(accountID)
            let originalSource = controller.settings.codexActiveSource
            let originalSelectedID = controller.settings.codexVisibleAccountProjectionForMenuDisplay?
                .activeVisibleAccountID
            controller.addOverviewFleetAccountRows(for: .codex, to: menu, captureMenu: menu, width: 320)
            let item = try #require(menu.items.first {
                ($0.representedObject as? String) == "overviewAccount-codex-\(inactive.id)"
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
            try self.seedCodex(9, controller: controller)
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
            try self.seedCodex(6, controller: controller)
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
