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
                    #expect(model.constraintDetail?.hasPrefix("Resets ") == true)
                    #expect(model.constraintDetail?.contains("left") == false)
                    #expect(model.trailingDetail?.text == "2d")
                    #expect(model.trailingDetail?.count == 1)
                    #expect(!model.hasError)
                }
            }
        }
    }

    @Test
    func `Codex missing weekly reserves blank detail and retains loading status text`() throws {
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
            #expect(controller.compactAccountRowModel(for: compact, rendering: rendering).constraintDetail == nil)
            #expect(controller.overviewFleetAccountRows(for: .codex, now: now).first?.model.constraintDetail == nil)
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
            let source = try #require(controller.overviewFleetSource(for: .codex))
            for account in source.accounts where !account.isActive {
                let card = try #require(source.cardModel(account))
                #expect(card.metrics.isEmpty)
                #expect(card.creditsRemaining == nil)
                #expect(card.codexResetCredits == nil)
                #expect(!card.emailIsActiveAccount)
            }
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
    func `overview runtime account click retains overview`() throws {
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
            #expect(controller.compactAccountExpandedIDs.isEmpty)
            #expect(controller.compactAccountCollapsedIDs.contains(accountID))
            #expect(controller.settings.mergedMenuLastSelectedWasOverview)
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
            #expect(controller.overviewExpansionState.expandedAccountIDs.contains(id))
            #expect(controller.compactAccountExpandedIDs.isEmpty)
            #expect(controller.settings.mergedMenuLastSelectedWasOverview)
            #expect(controller.settings.claudeNativeProfileAlias == "default")
            #expect(controller.store.claudeNativeProfileAccountsForDisplay()
                .first { $0.isActive }?.id.opaqueID == "default")
            #expect(controller.settings.effectiveSelectedTokenAccount(for: .claude) == nil)
        }
    }

    @Test
    func `expanded account models retain their own quota credits and reset details`() throws {
        try self.withFixture { controller in
            self.seedClaude(2, controller: controller)
            let accounts = try self.seedCodex(3, controller: controller)
            let now = Date()
            controller.store.codexAccountSnapshots = accounts.enumerated().map { index, account in
                CodexAccountUsageSnapshot(
                    account: account,
                    snapshot: UsageSnapshot(
                        primary: RateWindow(
                            usedPercent: Double(10 + index),
                            windowMinutes: 300,
                            resetsAt: now.addingTimeInterval(3600),
                            resetDescription: nil),
                        secondary: nil,
                        codexResetCredits: CodexRateLimitResetCreditsSnapshot(
                            credits: [CodexRateLimitResetCredit(
                                id: "credit-\(index)",
                                resetType: "weekly",
                                status: .available,
                                grantedAt: now,
                                expiresAt: now.addingTimeInterval(172_800),
                                redeemStartedAt: nil,
                                redeemedAt: nil,
                                title: nil,
                                description: nil)],
                            availableCount: 1,
                            updatedAt: now),
                        updatedAt: now),
                    error: nil,
                    sourceLabel: "Synthetic",
                    credits: CreditsSnapshot(remaining: Double(100 + index), events: [], updatedAt: now))
            }
            controller.settings.showOptionalCreditsAndExtraUsage = true
            controller.settings.usageBarsShowUsed = true
            let source = try #require(controller.overviewFleetSource(for: .codex))
            for (index, account) in source.accounts.enumerated() {
                let card = try #require(source.cardModel(account))
                #expect(card.metrics.first?.percent == Double(10 + index))
                #expect(card.metrics.first?.resetText != nil)
                #expect(card.creditsRemaining == Double(100 + index))
                #expect(card.codexResetCredits?.items.count == 1)
                #expect(card.emailIsActiveAccount == account.isActive)
            }
            let claudeID = ProviderAccountIdentity(source: "claude-native-profile", opaqueID: "secondary")
            controller.store.claudeNativeProfileAccountSnapshots[1] = ProviderAccountUsageSnapshot(
                id: claudeID,
                provider: .claude,
                displayLabel: "Secondary native",
                isActive: false,
                snapshot: UsageSnapshot(
                    primary: RateWindow(
                        usedPercent: 68,
                        windowMinutes: 300,
                        resetsAt: now.addingTimeInterval(7200),
                        resetDescription: nil),
                    secondary: nil,
                    updatedAt: now),
                error: nil,
                sourceLabel: "Synthetic")
            let claudeSource = try #require(controller.overviewFleetSource(for: .claude))
            let secondary = try #require(claudeSource.accounts.first { $0.id == claudeID })
            let card = try #require(claudeSource.cardModel(secondary))
            #expect(card.metrics.first?.percent == 68)
            #expect(card.metrics.first?.resetText != nil)
            #expect(card.creditsRemaining == nil)
            #expect(card.email != "selected@example.com")
        }
    }

    @Test
    func `single Codex summary collapses in place without an account list`() throws {
        try self.withFixture(renderCards: true) { controller in
            self.seedClaude(1, controller: controller)
            try self.seedCodex(1, controller: controller)
            let menu = controller.makeMenu()
            controller.populateMenu(menu, provider: .codex)
            #expect(controller.overviewFleetAccountRows(for: .codex).isEmpty)
            let summary = try #require(menu.items.first { $0.representedObject as? String == "overviewRow-codex" })
            #expect(try #require(summary.view as? MenuRowContainerView)._test_simulateRuntimeClick())
            #expect(controller.overviewExpansionState.collapsedSummaryProviders == [.codex])
            #expect(controller.settings.mergedMenuLastSelectedWasOverview)
            controller.populateMenu(menu, provider: .codex)
            let collapsed = try #require(menu.items.first { $0.representedObject as? String == "overviewRow-codex" })
            #expect(try #require(collapsed.view as? MenuRowContainerView)._test_simulateRuntimeClick())
            #expect(controller.overviewExpansionState.collapsedSummaryProviders.isEmpty)
        }
    }

    @Test
    func `both providers expand and collapse runtime rows without navigation or selection`() throws {
        try self.withFixture(renderCards: true) { controller in
            self.seedClaude(2, controller: controller)
            try self.seedCodex(3, controller: controller)
            let selectedProvider = controller.selectedMenuProvider
            let source = controller.settings.codexActiveSource
            let menu = controller.makeMenu()
            controller.populateMenu(menu, provider: .codex)
            let switcherSelection = controller.lastMergedSwitcherSelection
            let active = controller.settings.codexVisibleAccountProjectionForMenuDisplay?.activeVisibleAccountID
            for provider in [UsageProvider.codex, .claude] {
                controller.populateMenu(menu, provider: .codex)
                let summaryID = "overviewRow-\(provider.rawValue)"
                let summary = try #require(menu.items.first { $0.representedObject as? String == summaryID })
                #expect(try #require(summary.view as? MenuRowContainerView)._test_simulateRuntimeClick())
                #expect(controller.overviewExpansionState.collapsedSummaryProviders == [provider])
                controller.populateMenu(menu, provider: .codex)
                let collapsed = try #require(menu.items.first { $0.representedObject as? String == summaryID })
                #expect(try #require(collapsed.view as? MenuRowContainerView)._test_simulateRuntimeClick())
                #expect(controller.overviewExpansionState.collapsedSummaryProviders.isEmpty)
                controller.populateMenu(menu, provider: .codex)
                let keyboardRow = try #require(menu.items.first { $0.representedObject as? String == summaryID })
                #expect(keyboardRow.action != nil)
                #expect(keyboardRow.target is StatusItemController)
                controller.selectOverviewProvider(keyboardRow)
                #expect(controller.overviewExpansionState.collapsedSummaryProviders == [provider])
                #expect(controller.settings.mergedMenuLastSelectedWasOverview)
                #expect(controller.selectedMenuProvider == selectedProvider)
                #expect(controller.lastMergedSwitcherSelection == switcherSelection)
                controller.selectOverviewProvider(keyboardRow)
                #expect(controller.overviewExpansionState.collapsedSummaryProviders.isEmpty)
                controller.populateMenu(menu, provider: .codex)
                let compact = try #require(menu.items.first {
                    ($0.representedObject as? String)?.hasPrefix("overviewAccount-\(provider.rawValue)-") == true
                })
                let compactID = try #require(compact.representedObject as? String)
                let cardID = compactID.replacingOccurrences(of: "overviewAccount-", with: "overviewAccountCard-")
                #expect(try #require(compact.view as? MenuRowContainerView)._test_simulateRuntimeClick())
                controller.populateMenu(menu, provider: .codex)
                let card = try #require(menu.items.first { $0.representedObject as? String == cardID })
                #expect(card.submenu == nil)
                #expect(try #require(card.view as? MenuRowContainerView)._test_simulateRuntimeClick())
                controller.populateMenu(menu, provider: .codex)
                #expect(menu.items.contains { $0.representedObject as? String == compactID })
                #expect(!menu.items.contains { $0.representedObject as? String == cardID })
                #expect(controller.overviewExpansionState.expandedAccountIDs.isEmpty)
                #expect(controller.compactAccountExpandedIDs.isEmpty)
                #expect(controller.compactAccountCollapsedIDs.isEmpty)
                #expect(controller.selectedMenuProvider == selectedProvider)
                #expect(controller.lastMergedSwitcherSelection == switcherSelection)
                #expect(controller.settings.mergedMenuLastSelectedWasOverview)
                #expect(controller.settings.codexActiveSource == source)
                #expect(controller.settings.codexVisibleAccountProjectionForMenuDisplay?
                    .activeVisibleAccountID == active)
                #expect(controller.settings.claudeNativeProfileAlias == "default")
                #expect(controller.settings.effectiveSelectedTokenAccount(for: .claude) == nil)
            }
        }
    }

    @Test(arguments: [false, true])
    func `collapsed provider summaries match compact account row heights`(hasResetDates: Bool) throws {
        try self.withFixture(renderCards: true) { controller in
            self.seedClaude(2, controller: controller)
            let accounts = try self.seedCodex(3, controller: controller)
            if hasResetDates {
                let now = Date()
                let snapshot = UsageSnapshot(
                    primary: RateWindow(
                        usedPercent: 50,
                        windowMinutes: 300,
                        resetsAt: now.addingTimeInterval(3600),
                        resetDescription: nil),
                    secondary: RateWindow(
                        usedPercent: 20,
                        windowMinutes: 10080,
                        resetsAt: now.addingTimeInterval(86400),
                        resetDescription: nil),
                    updatedAt: now)
                controller.store.snapshots[.codex] = snapshot
                controller.store.snapshots[.claude] = snapshot
                controller.store.codexAccountSnapshots = accounts.map {
                    CodexAccountUsageSnapshot(account: $0, snapshot: snapshot, error: nil, sourceLabel: "Synthetic")
                }
                controller.store.claudeNativeProfileAccountSnapshots = controller.store
                    .claudeNativeProfileAccountSnapshots.map {
                        ProviderAccountUsageSnapshot(
                            id: $0.id,
                            provider: .claude,
                            displayLabel: $0.displayLabel,
                            isActive: $0.isActive,
                            snapshot: snapshot,
                            error: nil,
                            sourceLabel: "Synthetic")
                    }
                let claudeRows = controller.overviewFleetAccountRows(for: .claude, now: now)
                let expected = [snapshot.primary, snapshot.secondary].compactMap { window in
                    window.flatMap { UsageFormatter.resetLine(for: $0, style: .countdown, now: now) }
                }.joined(separator: " · ")
                #expect(claudeRows.first?.model.constraintDetail == expected)
                #expect(claudeRows.first?.model.trailingDetail == nil)
                let projected = controller.overviewFleetAccounts(for: .claude)
                let plan = controller.compactAccountPlan(for: .claude, accounts: projected)
                let rendering = StatusItemController.CompactAccountMenuRendering(
                    plan: plan,
                    accounts: projected,
                    idPrefix: "claudeNativeProfile",
                    cardModel: { _ in nil },
                    codexRowDetails: StatusItemController.compactAccountRowDetails(
                        accounts: projected, resetStyle: .countdown, now: now))
                for row in plan.rows {
                    if case let .compact(compact) = row {
                        #expect(controller.compactAccountRowModel(for: compact, rendering: rendering).constraintDetail
                            == expected)
                    }
                }
            }
            let menu = controller.makeMenu()
            controller.populateMenu(menu, provider: .codex)
            for provider in [UsageProvider.codex, .claude] {
                let summaryID = "overviewRow-\(provider.rawValue)"
                let summary = try #require(menu.items.first { $0.representedObject as? String == summaryID })
                #expect(try #require(summary.view as? MenuRowContainerView)._test_simulateRuntimeClick())
                controller.populateMenu(menu, provider: .codex)
                let collapsed = try #require(menu.items.first { $0.representedObject as? String == summaryID })
                let account = try #require(menu.items.first {
                    ($0.representedObject as? String)?.hasPrefix("overviewAccount-\(provider.rawValue)-") == true
                })
                let summaryView = try #require(collapsed.view as? MenuRowContainerView)
                let accountView = try #require(account.view as? MenuRowContainerView)
                #expect(summaryView.frame.height == accountView.frame.height)
                #expect(summaryView.intrinsicContentSize.height == accountView.intrinsicContentSize.height)
                #expect(controller.settings.mergedMenuLastSelectedWasOverview)
            }
        }
    }

    @Test
    func `overview state survives sibling close and resets after last menu closes`() throws {
        try self.withFixture { controller in
            self.seedClaude(2, controller: controller)
            try self.seedCodex(2, controller: controller)
            let first = NSMenu()
            let second = NSMenu()
            controller.openMenus[ObjectIdentifier(first)] = first
            controller.openMenus[ObjectIdentifier(second)] = second
            controller.activateOverviewRow(.codex, menu: first)
            controller.activateOverviewRow(.claude, menu: first)
            let account = try #require(controller.overviewFleetAccounts(for: .claude).last)
            controller.selectOverviewFleetAccount(account.id, provider: .claude, menu: first)
            controller.menuDidClose(first)
            #expect(controller.overviewExpansionState.collapsedSummaryProviders == [.codex, .claude])
            #expect(controller.overviewExpansionState.expandedAccountIDs == [account.id])
            controller.menuDidClose(second)
            #expect(controller.overviewExpansionState.collapsedSummaryProviders.isEmpty)
            #expect(controller.overviewExpansionState.expandedAccountIDs.isEmpty)
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
            let source = try #require(controller.overviewFleetSource(for: .claude))
            let account = try #require(source.accounts.first { $0.id == id })
            let card = try #require(source.cardModel(account))
            #expect(card.metrics.isEmpty)
            #expect(card.email == "Secondary")
            #expect(card.creditsRemaining == nil)
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
            let source = try #require(controller.overviewFleetSource(for: .codex))
            let projected = try #require(source.accounts.first { $0.id == id })
            let card = try #require(source.cardModel(projected))
            #expect(card.email == PersonalInfoRedactor.redactEmail("private@example.com", isEnabled: true))
            #expect(!card.emailIsActiveAccount)
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

extension OverviewFleetAccountsTests {
    private func seedSelectedCodexFleet(
        controller: StatusItemController,
        liveAlias: String? = "malcolm",
        missingQuota: Bool = false) throws
    {
        let home = try URL(fileURLWithPath: #require(controller.store.environmentBase["HOME"]))
        let observed = JonesAccountAggregate.codexAliases.enumerated().map { index, alias in
            ObservedSystemCodexAccount(
                email: "\(alias)@example.test",
                workspaceAccountID: "workspace-\(index)",
                authFingerprint: "fingerprint-\(index)",
                codexHomePath: home.appendingPathComponent(alias).path,
                observedAt: Date(timeIntervalSince1970: 1_800_000_000),
                identity: .providerAccount(id: "workspace-\(index)"))
        }
        let live = observed.first { URL(fileURLWithPath: $0.codexHomePath).lastPathComponent == liveAlias }
            ?? ObservedSystemCodexAccount(
                email: "unmatched@example.test",
                workspaceAccountID: "distinct-default-workspace",
                authFingerprint: "distinct-default-fingerprint",
                codexHomePath: home.appendingPathComponent("system").path,
                observedAt: Date(timeIntervalSince1970: 1_800_000_000),
                identity: .providerAccount(id: "distinct-default-workspace"))
        let extras = ["default", "extra", "unregistered"].map { alias in
            ObservedSystemCodexAccount(
                email: "\(alias)@example.test",
                workspaceAccountID: "workspace-\(alias)",
                authFingerprint: "fingerprint-\(alias)",
                codexHomePath: home.appendingPathComponent(alias).path,
                observedAt: Date(timeIntervalSince1970: 1_800_000_000),
                identity: .providerAccount(id: "workspace-\(alias)"))
        }
        let managed = ManagedCodexAccount(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            email: "managed@example.test",
            managedHomePath: home.appendingPathComponent("managed").path,
            createdAt: 1,
            updatedAt: 1,
            lastAuthenticatedAt: 1)
        controller.settings._test_codexAccountSnapshotLoader = { source in
            CodexAccountReconciliationSnapshot(
                storedAccounts: [managed],
                activeStoredAccount: source == .managedAccount(id: managed.id) ? managed : nil,
                liveSystemAccount: live,
                profileHomeAccounts: observed + extras,
                fleetProfileHomePaths: (observed + Array(extras.prefix(2))).map(\.codexHomePath),
                matchingStoredAccountForLiveSystemAccount: nil,
                activeSource: source,
                hasUnreadableAddedAccountStore: false)
        }
        let accounts = controller.settings.codexVisibleAccountProjection.visibleAccounts
        controller.store.codexAccountSnapshots = accounts.map {
            CodexAccountUsageSnapshot(
                account: $0,
                snapshot: missingQuota && $0.fleetProfileAlias == "steven"
                    ? nil : Self.snapshot(provider: .codex, accountEmail: $0.email),
                error: missingQuota && $0.fleetProfileAlias == "wallace" ? "Unavailable" : nil,
                sourceLabel: "Synthetic")
        }
        controller.store.snapshots[.codex] = Self.snapshot(provider: .codex, accountEmail: "malcolm@example.test")
    }

    @Test(arguments: [false, true])
    func `Codex overview summary survives an absent or empty cached account projection`(cachedEmpty: Bool) throws {
        try self.withFixture(providers: [.codex]) { controller in
            controller.store.snapshots[.codex] = Self.snapshot(provider: .codex)
            let empty = CodexVisibleAccountProjection(
                visibleAccounts: [],
                activeVisibleAccountID: nil,
                liveVisibleAccountID: nil,
                hasUnreadableAddedAccountStore: false)
            controller.settings.cachedCodexAccountMenuProjection = cachedEmpty
                ? CachedCodexAccountMenuProjection(
                    activeSource: controller.settings.codexActiveSource, loadedAt: Date(), projection: empty)
                : nil
            #expect(controller.settings.codexVisibleAccountProjectionForMenuDisplay == (cachedEmpty ? empty : nil))
            let context = StatusItemController.MenuCardContext(
                currentProvider: .codex,
                selectedProvider: .codex,
                menuWidth: 320,
                codexAccountDisplay: nil,
                tokenAccountDisplay: nil,
                openAIContext: .init(
                    hasUsageBreakdown: false,
                    hasCreditsHistory: false,
                    hasCostHistory: false,
                    canShowBuyCredits: false,
                    hasOpenAIWebMenuItems: false))
            let menu = NSMenu()
            controller.addPrimaryMenuContent(to: menu, context: context, switcherSelection: .overview)
            #expect(self.identifiers(in: menu).contains("overviewRow-codex"))
            #expect(controller.settings.codexVisibleAccountProjectionForMenuDisplay?.visibleAccounts.isEmpty == true)
        }
    }

    @Test(arguments: [false, true], [false, true])
    func `named Codex fleet excludes unrelated accounts in stacked segmented and overview presentation`(
        reversed: Bool,
        managedActive: Bool) throws
    {
        try self.withFixture(providers: [.codex, .gemini]) { controller in
            controller.store.snapshots[.gemini] = Self.snapshot(provider: .gemini)
            let activeSource: CodexActiveSource = managedActive
                ? .managedAccount(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!) : .liveSystem
            controller.settings.codexActiveSource = activeSource
            try self.seedSelectedCodexFleet(controller: controller, liveAlias: nil, missingQuota: true)
            let raw = try #require(controller.settings.codexVisibleAccountProjectionForMenuDisplay)
            #expect(raw.visibleAccounts.count == 10)
            #expect(raw.visibleAccounts.first { $0.id == raw.activeVisibleAccountID }?.selectionSource == activeSource)
            let expected = raw.visibleAccounts.filter {
                JonesAccountAggregate.codexAliases.contains($0.fleetProfileAlias ?? "")
            }
            #expect(expected.count == 5)
            let ordered = reversed ? Array(raw.visibleAccounts.reversed()) : raw.visibleAccounts
            controller.settings.updateProviderConfig(provider: .codex, affectsBackgroundWork: false) {
                $0.codexAccountOrder = ordered.map(CodexAccountOrder.key)
            }
            controller.settings.cachedCodexAccountMenuProjection = CachedCodexAccountMenuProjection(
                activeSource: activeSource, loadedAt: Date(), projection: raw)
            for layout in [MultiAccountMenuLayout.stacked, .segmented] {
                controller.settings.multiAccountMenuLayout = layout
                let display = try #require(controller.codexAccountMenuDisplay(for: .codex))
                #expect(Set(display.accounts.map(\.id)) == Set(expected.map(\.id)))
                #expect(display.accounts.allSatisfy { expected.contains($0) })
                #expect(display.workspaceSections.map(\.title) == ["Personal"])
                #expect(display.workspaceSections.flatMap(\.accounts) == display.accounts)
                #expect(display.showsWorkspaceGroups)
                #expect(display.activeVisibleAccountID == nil)
                #expect(controller.overviewFleetAccounts(for: .codex).count == 5)
                #expect(controller.overviewFleetAccountRows(for: .codex).count == 5)
                let context = StatusItemController.MenuCardContext(
                    currentProvider: .codex,
                    selectedProvider: .codex,
                    menuWidth: 320,
                    codexAccountDisplay: display,
                    tokenAccountDisplay: nil,
                    openAIContext: .init(
                        hasUsageBreakdown: false,
                        hasCreditsHistory: false,
                        hasCostHistory: false,
                        canShowBuyCredits: false,
                        hasOpenAIWebMenuItems: false))
                let menu = NSMenu()
                controller.addPrimaryMenuContent(to: menu, context: context, switcherSelection: .overview)
                #expect(self.identifiers(in: menu).contains("overviewRow-gemini"))
                #expect(!self.identifiers(in: menu).contains("overviewRow-codex"))
                #expect(self.identifiers(in: menu).count { $0.hasPrefix("overviewAccount-codex-") } == 5)
            }
            #expect(controller.settings.codexVisibleAccountProjectionForMenuDisplay == raw)
            #expect(controller.settings.codexActiveSource == activeSource)
        }
    }

    @Test
    func `full Codex menu and segmented picker present only named accounts without workspace labels`() throws {
        try self.withFixture(providers: [.codex]) { controller in
            try self.seedSelectedCodexFleet(controller: controller, liveAlias: "jace")
            controller.settings.mergeIcons = false
            let compactMenu = controller.makeMenu(for: .codex)
            controller.refreshMenuForOpenIfNeeded(compactMenu, provider: .codex)
            #expect(self.identifiers(in: compactMenu).count { $0.hasPrefix("codexAccountCompact-") } == 5)
            #expect(compactMenu.items.filter { ($0.representedObject as? String)?.hasPrefix("codexWorkspace-") == true }
                .map(\.title) == ["Personal"])
            controller.settings.multiAccountMenuLayout = .segmented
            let pickerMenu = controller.makeMenu(for: .codex)
            controller.refreshMenuForOpenIfNeeded(pickerMenu, provider: .codex)
            let picker = try #require(pickerMenu.items.compactMap { $0.view as? CodexAccountSwitcherView }.first)
            func buttons(in view: NSView) -> [NSButton] {
                view.subviews.flatMap { child in
                    if let button = child as? NSButton { return [button] }
                    return buttons(in: child)
                }
            }
            let items = buttons(in: picker)
            #expect(items.count == 5)
            #expect(Set(items.compactMap(\.toolTip)) == Set(["Malcolm", "Jace", "Umich", "Steven", "Wallace"]))
            #expect(items.allSatisfy { !$0.title.contains("Workspace") && $0.title != "default" })
        }
    }

    @Test
    func `verified live Codex alias appears once and names the minimized summary`() throws {
        try self.withFixture(providers: [.codex]) { controller in
            try self.seedSelectedCodexFleet(controller: controller, liveAlias: "jace")
            let raw = try #require(controller.settings.codexVisibleAccountProjectionForMenuDisplay)
            let jace = try #require(raw.visibleAccounts.first { $0.fleetProfileAlias == "jace" })
            let display = try #require(controller.codexAccountMenuDisplay(for: .codex))
            #expect(display.accounts.count == 5)
            #expect(display.activeVisibleAccountID == jace.id)
            let projected = controller.overviewFleetAccounts(for: .codex)
            #expect(projected.filter(\.isActive).map(\.id.opaqueID) == [jace.id])
            #expect(controller.overviewFleetAccountRows(for: .codex).count == 4)
            #expect(!controller.overviewFleetAccountRows(for: .codex).contains { $0.accountID.opaqueID == jace.id })
            let card = try #require(controller.menuCardModel(for: .codex))
            #expect(controller.overviewSummaryCompactModel(for: .codex, model: card).label == "Jace")
            controller.settings.setAccountDisplayLabel(
                "private@example.test",
                provider: .codex,
                profileIdentity: JonesAccountDisplayLabel.codexProfileIdentity(for: jace))
            controller.settings.hidePersonalInfo = true
            #expect(controller.overviewSummaryCompactModel(for: .codex, model: card).label
                == PersonalInfoRedactor.redactEmail("private@example.test", isEnabled: true))
            #expect(controller.settings.codexVisibleAccountProjectionForMenuDisplay == raw)
            #expect(controller.settings.codexActiveSource == .liveSystem)
        }
    }

    @Test
    func `selected fleet aggregate follows accounts before storage and plan usage and refreshes with totals`() throws {
        try self.withFixture(providers: [.codex, .claude]) { controller in
            // Claude selection changes invalidate cached Codex projections, so seed configuration first.
            self.seedClaude(2, controller: controller)
            try self.seedSelectedCodexFleet(controller: controller)
            controller.settings.providerStorageFootprintsEnabled = true
            for provider in [UsageProvider.codex, .claude] {
                controller.store.providerStorageFootprints[provider.instanceID] = ProviderStorageFootprint(
                    provider: provider,
                    totalBytes: 1024,
                    paths: [],
                    missingPaths: [],
                    unreadablePaths: [],
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
                let menu = NSMenu()
                let display = controller.codexAccountMenuDisplay(for: provider)
                let context = StatusItemController.MenuCardContext(
                    currentProvider: provider,
                    selectedProvider: provider,
                    menuWidth: 320,
                    codexAccountDisplay: display,
                    tokenAccountDisplay: nil,
                    openAIContext: .init(
                        hasUsageBreakdown: false,
                        hasCreditsHistory: false,
                        hasCostHistory: false,
                        canShowBuyCredits: false,
                        hasOpenAIWebMenuItems: false))
                let aggregateID: String
                if provider == .codex {
                    #expect(try controller.addCompactCodexAccountMenuIfPlanned(
                        display: #require(display), to: menu, captureMenu: menu, context: context))
                    aggregateID = "codexAccountAggregate"
                } else {
                    controller.addClaudeNativeProfileMenuCards(to: menu, captureMenu: menu, context: context)
                    aggregateID = "claudeNativeProfileAggregate"
                }
                #expect(controller.addUsageHistoryMenuItemIfNeeded(to: menu, provider: provider, width: 320))
                let ids = self.identifiers(in: menu)
                let totalIndex = try #require(ids.firstIndex(of: aggregateID))
                let storageIndex = try #require(ids.firstIndex(of: "menuCardStorage"))
                let historyIndex = try #require(ids.firstIndex(of: "usageHistorySubmenu"))
                #expect(totalIndex > 0)
                #expect(totalIndex < storageIndex)
                #expect(storageIndex < historyIndex)
                let rowPrefix = provider == .codex ? "codexAccountCompact-" : "claudeNativeProfile"
                #expect(ids.prefix(totalIndex).contains { $0.hasPrefix(rowPrefix) })
                #expect(!ids.suffix(from: totalIndex + 1).contains { $0.hasPrefix(rowPrefix) })
                let overview = NSMenu()
                controller.addOverviewFleetAccountRows(for: provider, to: overview, captureMenu: overview, width: 320)
                let overviewIDs = self.identifiers(in: overview)
                #expect(overviewIDs.last == "overviewAccountAggregate-\(provider.rawValue)")
                #expect(overviewIDs.dropLast().contains { $0.hasPrefix("overviewAccount-\(provider.rawValue)-") })
            }
            let before = controller.menuAdjunctReadinessSignature()
            let index = try #require(controller.store.codexAccountSnapshots.firstIndex {
                $0.account.fleetProfileAlias == "malcolm"
            })
            let old = controller.store.codexAccountSnapshots[index]
            controller.store.codexAccountSnapshots[index] = CodexAccountUsageSnapshot(
                account: old.account, snapshot: old.snapshot, error: "Unavailable", sourceLabel: old.sourceLabel)
            let total = try #require(controller.overviewFleetSource(for: .codex)?.aggregate)
            #expect(total.reportingCount == 4)
            #expect(total.maximumPercent == 500)
            #expect(controller.menuAdjunctReadinessSignature() != before)
        }
    }

    @Test
    func `aggregate runtime clicks toggle separate provider and overview state then reset on idle`() throws {
        try self.withFixture(providers: [.codex, .claude], renderCards: true) { controller in
            self.seedClaude(2, controller: controller)
            try self.seedSelectedCodexFleet(controller: controller)
            for provider in [UsageProvider.codex, .claude] {
                let menu = NSMenu()
                let display = controller.codexAccountMenuDisplay(for: provider)
                let context = StatusItemController.MenuCardContext(
                    currentProvider: provider, selectedProvider: provider, menuWidth: 310,
                    codexAccountDisplay: display, tokenAccountDisplay: nil,
                    openAIContext: .init(
                        hasUsageBreakdown: false, hasCreditsHistory: false, hasCostHistory: false,
                        canShowBuyCredits: false, hasOpenAIWebMenuItems: false))
                let scope = provider == .codex ? "codexAccount" : "claudeNativeProfile"
                if provider == .codex {
                    #expect(try controller.addCompactCodexAccountMenuIfPlanned(
                        display: #require(display), to: menu, captureMenu: menu, context: context))
                } else {
                    controller.addClaudeNativeProfileMenuCards(to: menu, captureMenu: menu, context: context)
                }
                let item = try #require(menu.items.first { ($0.representedObject as? String) == "\(scope)Aggregate" })
                #expect(item.isEnabled)
                let view = try #require(item.view as? MenuRowContainerView)
                #expect(view._test_simulateRuntimeClick())
                #expect(controller.compactAccountExpandedAggregateScopes.contains(scope))
                #expect(controller.overviewExpansionState.expandedAggregateProviders.isEmpty)
                #expect(view._test_simulateRuntimeClick())
                #expect(!controller.compactAccountExpandedAggregateScopes.contains(scope))
                #expect(view._test_simulateRuntimeClick())

                let overview = NSMenu()
                controller.addOverviewFleetAccountRows(for: provider, to: overview, captureMenu: overview, width: 310)
                let overviewItem = try #require(overview.items.first {
                    ($0.representedObject as? String) == "overviewAccountAggregate-\(provider.rawValue)"
                })
                #expect(overviewItem.isEnabled)
                let overviewView = try #require(overviewItem.view as? MenuRowContainerView)
                #expect(overviewView._test_simulateRuntimeClick())
                #expect(controller.overviewExpansionState.expandedAggregateProviders.contains(provider))
                #expect(controller.compactAccountExpandedAggregateScopes.contains(scope))
                #expect(overviewView._test_simulateRuntimeClick())
                #expect(!controller.overviewExpansionState.expandedAggregateProviders.contains(provider))
                #expect(overviewView._test_simulateRuntimeClick())
                #expect(controller.compactAccountExpandedIDs.isEmpty)
                #expect(controller.overviewExpansionState.expandedAccountIDs.isEmpty)
                controller.openMenus[ObjectIdentifier(menu)] = menu
                controller.resetCompactAccountMenuExpansionStateIfIdle()
                #expect(controller.compactAccountExpandedAggregateScopes.contains(scope))
                #expect(controller.overviewExpansionState.expandedAggregateProviders.contains(provider))
                controller.openMenus.removeValue(forKey: ObjectIdentifier(menu))
                controller.resetCompactAccountMenuExpansionStateIfIdle()
                #expect(controller.compactAccountExpandedAggregateScopes.isEmpty)
                #expect(controller.overviewExpansionState.expandedAggregateProviders.isEmpty)
            }
        }
    }
}
