import AppKit
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite(.serialized)
@MainActor
struct StatusMenuCodexSwitcherPresentationTests {
    @Test
    func `compact Codex detail map preserves account identity and excludes other providers`() throws {
        let now = Date(timeIntervalSince1970: 1_781_726_400)
        let accounts = [UsageProvider.codex, .claude, .copilot].map { provider in
            ProviderAccountUsageSnapshot(
                id: ProviderAccountIdentity(source: "synthetic", opaqueID: provider.rawValue),
                provider: provider,
                displayLabel: "Friendly \(provider.rawValue)",
                isActive: false,
                snapshot: UsageSnapshot(
                    primary: RateWindow(
                        usedPercent: 10, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
                    secondary: RateWindow(
                        usedPercent: 20,
                        windowMinutes: 10080,
                        resetsAt: now.addingTimeInterval(399_600),
                        resetDescription: nil),
                    updatedAt: now),
                error: nil,
                sourceLabel: "Synthetic")
        }
        let details = StatusItemController.compactCodexRowDetails(
            accounts: accounts, resetStyle: .countdown, now: now)
        let codex = try #require(accounts.first)
        #expect(Set(details.keys) == [codex.id])
        #expect(details[codex.id] == JonesCompactAccountPresentation.codexRowDetail(
            account: codex, resetStyle: .countdown, now: now))
        #expect(details[codex.id]?.text == "Weekly 80% left · Resets in 4d 15h")
    }

    private func disableMenuCardsForTesting() {
        StatusItemController.menuCardRenderingEnabled = false
        StatusItemController.setMenuRefreshEnabledForTesting(false)
    }

    private func makeSettings() -> SettingsStore {
        let suite = "StatusMenuCodexSwitcherPresentationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
    }

    private func makeManagedAccountStoreURL(accounts: [ManagedCodexAccount]) throws -> URL {
        let storeURL = TestFixtureScratch.root.appendingPathComponent(UUID().uuidString)
        let store = FileManagedCodexAccountStore(fileURL: storeURL)
        try store.storeAccounts(ManagedCodexAccountSet(
            version: FileManagedCodexAccountStore.currentVersion,
            accounts: accounts))
        return storeURL
    }

    private func enableOnlyCodex(_ settings: SettingsStore) {
        let registry = ProviderRegistry.shared
        for provider in UsageProvider.allCases {
            guard let metadata = registry.metadata[provider] else { continue }
            settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: provider == .codex)
        }
    }

    private func representedIDs(in menu: NSMenu) -> [String] {
        menu.items.compactMap { $0.representedObject as? String }
    }

    private func snapshot(email: String, percent: Double = 12) -> UsageSnapshot {
        UsageSnapshot(
            primary: RateWindow(
                usedPercent: percent,
                windowMinutes: 300,
                resetsAt: Date().addingTimeInterval(300),
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: percent,
                windowMinutes: 10080,
                resetsAt: Date().addingTimeInterval(86400),
                resetDescription: nil),
            updatedAt: Date(),
            identity: ProviderIdentitySnapshot(
                providerID: .codex,
                accountEmail: email,
                accountOrganization: nil,
                loginMethod: "Plus"))
    }

    private func removeAccountIdentity(fromSnapshotStoreAt fileURL: URL) throws {
        var payload = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any])
        var records = try #require(payload["records"] as? [[String: Any]])
        records[0].removeValue(forKey: "accountIdentity")
        payload["records"] = records
        try JSONSerialization.data(withJSONObject: payload).write(to: fileURL)
    }

    @Test
    func `codex account ordering keeps workspace groups contiguous`() {
        let teamActive = CodexVisibleAccount(
            id: "team-a-active",
            email: "active@example.com",
            workspaceLabel: "Team A",
            workspaceAccountID: "team-a",
            storedAccountID: UUID(),
            selectionSource: .managedAccount(id: UUID()),
            isActive: true,
            isLive: false,
            canReauthenticate: true,
            canRemove: true)
        let teamHighQuota = CodexVisibleAccount(
            id: "team-b-high-quota",
            email: "high@example.com",
            workspaceLabel: "Team B",
            workspaceAccountID: "team-b",
            storedAccountID: UUID(),
            selectionSource: .managedAccount(id: UUID()),
            isActive: false,
            isLive: false,
            canReauthenticate: true,
            canRemove: true)
        let teamSibling = CodexVisibleAccount(
            id: "team-a-sibling",
            email: "sibling@example.com",
            workspaceLabel: "Team A",
            workspaceAccountID: "team-a",
            storedAccountID: UUID(),
            selectionSource: .managedAccount(id: UUID()),
            isActive: false,
            isLive: false,
            canReauthenticate: true,
            canRemove: true)
        let accounts = [teamActive, teamHighQuota, teamSibling]
        let snapshots = [
            CodexAccountUsageSnapshot(
                account: teamActive,
                snapshot: self.snapshot(email: teamActive.email, percent: 95),
                error: nil,
                sourceLabel: "test"),
            CodexAccountUsageSnapshot(
                account: teamHighQuota,
                snapshot: self.snapshot(email: teamHighQuota.email, percent: 10),
                error: nil,
                sourceLabel: "test"),
            CodexAccountUsageSnapshot(
                account: teamSibling,
                snapshot: self.snapshot(email: teamSibling.email, percent: 20),
                error: nil,
                sourceLabel: "test"),
        ]

        let ordered = CodexAccountPresentationOrdering.orderedAccounts(
            accounts,
            snapshots: snapshots,
            activeVisibleAccountID: teamActive.id)

        #expect(ordered.map(\.id) == ["team-a-active", "team-a-sibling", "team-b-high-quota"])
        #expect(ordered.codexWorkspaceSections().map(\.title) == ["Team A", "Team B"])
        #expect(ordered.codexWorkspaceSections().first?.accounts.map(\.id) == ["team-a-active", "team-a-sibling"])
    }

    @Test
    func `codex stacked menu orders by quota and groups workspaces`() throws {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        settings.multiAccountMenuLayout = .stacked
        self.enableOnlyCodex(settings)

        let lowID = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-111111111111"))
        let highID = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-222222222222"))
        let low = ManagedCodexAccount(
            id: lowID,
            email: "low@example.com",
            workspaceLabel: "Team Low",
            workspaceAccountID: "team-low",
            managedHomePath: "/tmp/low-home",
            createdAt: 1,
            updatedAt: 2,
            lastAuthenticatedAt: 2)
        let high = ManagedCodexAccount(
            id: highID,
            email: "high@example.com",
            workspaceLabel: "Team High",
            workspaceAccountID: "team-high",
            managedHomePath: "/tmp/high-home",
            createdAt: 1,
            updatedAt: 2,
            lastAuthenticatedAt: 2)
        let storeURL = try self.makeManagedAccountStoreURL(accounts: [low, high])
        defer {
            settings._test_managedCodexAccountStoreURL = nil
            settings._test_liveSystemCodexAccount = nil
            try? FileManager.default.removeItem(at: storeURL)
        }

        settings._test_managedCodexAccountStoreURL = storeURL
        settings._test_liveSystemCodexAccount = ObservedSystemCodexAccount(
            email: "active@example.com",
            workspaceLabel: "Personal",
            codexHomePath: "/Users/test/.codex",
            observedAt: Date())
        settings.codexActiveSource = .liveSystem

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        store.codexAccountSnapshots = settings.codexVisibleAccountProjection.visibleAccounts.map { account in
            let usedPercent = switch account.email {
            case "high@example.com":
                10.0
            case "low@example.com":
                80.0
            default:
                95.0
            }
            return CodexAccountUsageSnapshot(
                account: account,
                snapshot: self.snapshot(email: account.email, percent: usedPercent),
                error: nil,
                sourceLabel: "test")
        }
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: .system)
        defer { controller.releaseStatusItemsForTesting() }

        let display = try #require(controller.codexAccountMenuDisplay(for: .codex))
        #expect(display.accounts.map(\.email) == ["active@example.com", "high@example.com", "low@example.com"])
        #expect(display.workspaceSections.map(\.title) == ["Personal", "Team High", "Team Low"])

        let menu = controller.makeMenu(for: .codex)
        controller.menuWillOpen(menu)
        #expect(self.representedIDs(in: menu).count(where: { $0.hasPrefix("codexWorkspace-") }) == 3)
    }

    @Test(arguments: [6, 9])
    func `Codex stacked menu shows every account without tabs or folds`(count: Int) throws {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        settings.multiAccountMenuLayout = .stacked
        self.enableOnlyCodex(settings)
        let managed = (1..<count).map { index in
            ManagedCodexAccount(
                id: UUID(),
                email: "account\(index)@example.com",
                managedHomePath: TestFixtureScratch.root.appendingPathComponent("unused-home-\(index)").path,
                createdAt: 1,
                updatedAt: 2,
                lastAuthenticatedAt: 2)
        }
        let storeURL = try self.makeManagedAccountStoreURL(accounts: managed)
        defer {
            settings._test_managedCodexAccountStoreURL = nil
            settings._test_liveSystemCodexAccount = nil
            try? FileManager.default.removeItem(at: storeURL)
        }
        settings._test_managedCodexAccountStoreURL = storeURL
        settings._test_liveSystemCodexAccount = ObservedSystemCodexAccount(
            email: "active@example.com",
            codexHomePath: TestFixtureScratch.root.appendingPathComponent("unused-live-home").path,
            observedAt: Date())
        settings.codexActiveSource = .liveSystem
        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        store.codexAccountSnapshots = settings.codexVisibleAccountProjection.visibleAccounts.map { account in
            CodexAccountUsageSnapshot(
                account: account,
                snapshot: self.snapshot(email: account.email),
                error: nil,
                sourceLabel: "synthetic")
        }
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: testStatusBar())
        defer { controller.releaseStatusItemsForTesting() }
        let display = try #require(controller.codexAccountMenuDisplay(for: .codex))
        #expect(display.accounts.count == count)
        #expect(!display.showSwitcher)
        #expect(store.limitedCodexVisibleAccounts(
            display.accounts, activeVisibleAccountID: display.activeVisibleAccountID).count == count)
        let menu = controller.makeMenu(for: .codex)
        controller.menuWillOpen(menu)
        let ids = self.representedIDs(in: menu)
        #expect(ids.count { $0.hasPrefix("codexAccountCard-") } == 0)
        #expect(ids.count { $0.hasPrefix("codexAccountCompact-") } == count)
        #expect(!ids.contains("codexAccountCollapsed"))
        #expect(!menu.items.contains { $0.view is CodexAccountSwitcherView })

        let activeID = try #require(display.activeVisibleAccountID)
        controller.compactAccountCollapsedIDs.insert(
            ProviderAccountIdentity(source: "codex-account", opaqueID: activeID))
        let collapsed = controller.compactAccountPlan(
            for: .codex, accounts: StatusItemController.projectedCodexAccounts(display: display))
        let activeIdentity = ProviderAccountIdentity(source: "codex-account", opaqueID: activeID)
        #expect(!collapsed.rows.contains(.card(activeIdentity)))
        #expect(collapsed.rows.count { if case .compact = $0 { true } else { false } } == count)
    }

    @Test
    func `codex stacked menu surfaces account health labels`() throws {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        settings.multiAccountMenuLayout = .stacked
        self.enableOnlyCodex(settings)

        let managedAccountID = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-111111111111"))
        let managedAccount = ManagedCodexAccount(
            id: managedAccountID,
            email: "managed@example.com",
            managedHomePath: "/tmp/managed-home",
            createdAt: 1,
            updatedAt: 2,
            lastAuthenticatedAt: 2)
        let storeURL = try self.makeManagedAccountStoreURL(accounts: [managedAccount])
        defer {
            settings._test_managedCodexAccountStoreURL = nil
            settings._test_liveSystemCodexAccount = nil
            try? FileManager.default.removeItem(at: storeURL)
        }

        settings._test_managedCodexAccountStoreURL = storeURL
        settings._test_liveSystemCodexAccount = ObservedSystemCodexAccount(
            email: "live@example.com",
            codexHomePath: "/Users/test/.codex",
            observedAt: Date())
        settings.codexActiveSource = .liveSystem

        let visibleAccount = try #require(settings.codexVisibleAccountProjection.visibleAccounts
            .first { $0.email == "managed@example.com" })

        #expect(CodexAccountHealth.status(for: visibleAccount, error: "401 Unauthorized")
            .label == "Needs re-auth")
    }

    @Test
    func `codex account snapshot store hydrates current visible accounts`() {
        let fileURL = TestFixtureScratch.root.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let account = CodexVisibleAccount(
            id: "active@example.com",
            email: "active@example.com",
            workspaceAccountID: "acct-active",
            storedAccountID: nil,
            selectionSource: .liveSystem,
            isActive: true,
            isLive: true,
            canReauthenticate: true,
            canRemove: false)
        let store = FileCodexAccountUsageSnapshotStore(fileURL: fileURL)
        store.store([
            CodexAccountUsageSnapshot(
                account: account,
                snapshot: self.snapshot(email: account.email, percent: 17),
                error: nil,
                sourceLabel: "test"),
        ])

        let hydrated = store.load(for: [account])

        #expect(hydrated.map(\.id) == [account.id])
        #expect(hydrated.first?.snapshot?.primary?.usedPercent == 17)
        #expect(hydrated.first?.account.email == account.email)
    }

    @Test
    func `codex account snapshot store roundtrips monthly credit limits`() {
        let fileURL = TestFixtureScratch.root.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let credits = CreditsSnapshot(
            remaining: 0,
            events: [],
            updatedAt: now,
            codexCreditLimit: CodexCreditLimitSnapshot(
                used: 27,
                limit: 1000,
                remainingPercent: 73,
                resetsAt: nil,
                updatedAt: now))

        let account = CodexVisibleAccount(
            id: "biz@example.com",
            email: "biz@example.com",
            workspaceAccountID: "acct-biz",
            storedAccountID: nil,
            selectionSource: .liveSystem,
            isActive: true,
            isLive: true,
            canReauthenticate: true,
            canRemove: false)
        let store = FileCodexAccountUsageSnapshotStore(fileURL: fileURL)
        store.store([
            CodexAccountUsageSnapshot(
                account: account,
                snapshot: self.snapshot(email: account.email, percent: 0),
                error: nil,
                sourceLabel: "oauth",
                credits: credits),
        ])

        let hydrated = store.load(for: [account])

        #expect(hydrated.first?.credits?.codexCreditLimit?.used == 27)
        #expect(hydrated.first?.credits?.codexCreditLimit?.limit == 1000)
        #expect(hydrated.first?.credits?.codexCreditLimit?.remainingPercent == 73)
    }

    @Test
    func `codex account snapshot store rejects mismatched workspace records`() {
        let fileURL = TestFixtureScratch.root.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let oldAccountID = UUID()
        let newAccountID = UUID()
        let oldAccount = CodexVisibleAccount(
            id: "workspace@example.com",
            email: "workspace@example.com",
            workspaceLabel: "Old Team",
            workspaceAccountID: "acct-old",
            storedAccountID: oldAccountID,
            selectionSource: .managedAccount(id: oldAccountID),
            isActive: false,
            isLive: false,
            canReauthenticate: true,
            canRemove: true)
        let newAccount = CodexVisibleAccount(
            id: "workspace@example.com",
            email: "workspace@example.com",
            workspaceLabel: "New Team",
            workspaceAccountID: "acct-new",
            storedAccountID: newAccountID,
            selectionSource: .managedAccount(id: newAccountID),
            isActive: true,
            isLive: false,
            canReauthenticate: true,
            canRemove: true)
        let store = FileCodexAccountUsageSnapshotStore(fileURL: fileURL)
        store.store([
            CodexAccountUsageSnapshot(
                account: oldAccount,
                snapshot: self.snapshot(email: oldAccount.email, percent: 71),
                error: nil,
                sourceLabel: "test"),
        ])

        let hydrated = store.load(for: [newAccount])

        #expect(hydrated.isEmpty)
    }

    @Test
    func `codex account snapshot store keeps same composite owner after auth fingerprint changes`() {
        let fileURL = TestFixtureScratch.root.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let accountID = UUID()
        let oldAccount = CodexVisibleAccount(
            id: "reauth@example.com",
            email: "reauth@example.com",
            workspaceAccountID: "acct-reauth",
            authFingerprint: "old-auth-fingerprint",
            storedAccountID: accountID,
            selectionSource: .managedAccount(id: accountID),
            isActive: false,
            isLive: false,
            canReauthenticate: true,
            canRemove: true)
        let newAccount = CodexVisibleAccount(
            id: "reauth@example.com",
            email: "reauth@example.com",
            workspaceAccountID: "acct-reauth",
            authFingerprint: "new-auth-fingerprint",
            storedAccountID: accountID,
            selectionSource: .managedAccount(id: accountID),
            isActive: true,
            isLive: false,
            canReauthenticate: true,
            canRemove: true)
        let store = FileCodexAccountUsageSnapshotStore(fileURL: fileURL)
        store.store([
            CodexAccountUsageSnapshot(
                account: oldAccount,
                snapshot: self.snapshot(email: oldAccount.email, percent: 71),
                error: nil,
                sourceLabel: "test"),
        ])

        let hydrated = store.load(for: [newAccount])

        #expect(hydrated.map(\.id) == [newAccount.id])
        #expect(hydrated.first?.snapshot?.primary?.usedPercent == 71)
    }

    @Test
    func `codex account snapshot store rejects legacy workspace records without identity`() throws {
        let fileURL = TestFixtureScratch.root.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let payload = """
        {
          "records" : [
            {
              "error" : "cached",
              "id" : "legacy@example.com",
              "snapshot" : null,
              "sourceLabel" : "legacy"
            }
          ],
          "version" : 1
        }
        """
        try Data(payload.utf8).write(to: fileURL)

        let accountID = UUID()
        let workspaceAccount = CodexVisibleAccount(
            id: "legacy@example.com",
            email: "legacy@example.com",
            workspaceLabel: "New Team",
            workspaceAccountID: "acct-new",
            storedAccountID: accountID,
            selectionSource: .managedAccount(id: accountID),
            isActive: true,
            isLive: false,
            canReauthenticate: true,
            canRemove: true)
        let store = FileCodexAccountUsageSnapshotStore(fileURL: fileURL)

        let hydrated = store.load(for: [workspaceAccount])

        #expect(hydrated.isEmpty)
    }

    @Test
    func `codex account snapshot store rejects normalized legacy email ids without composite owner`() throws {
        let fileURL = TestFixtureScratch.root.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let payload = """
        {
          "records" : [
            {
              "error" : "cached",
              "id" : "Legacy@Example.com",
              "snapshot" : null,
              "sourceLabel" : "legacy"
            }
          ],
          "version" : 1
        }
        """
        try Data(payload.utf8).write(to: fileURL)

        let account = CodexVisibleAccount(
            id: "Legacy@Example.com",
            email: "legacy@example.com",
            storedAccountID: nil,
            selectionSource: .liveSystem,
            isActive: true,
            isLive: true,
            canReauthenticate: true,
            canRemove: false)
        let store = FileCodexAccountUsageSnapshotStore(fileURL: fileURL)

        #expect(store.load(for: [account]).isEmpty)
    }

    @Test
    func `codex account snapshot store rejects legacy stable ids crossing workspace members`() throws {
        let fileURL = TestFixtureScratch.root.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let managedAccountID = UUID()
        let visibleID = "managed:\(managedAccountID.uuidString.lowercased())"
        let priorAccount = CodexVisibleAccount(
            id: visibleID,
            email: "first-member@example.com",
            workspaceAccountID: "shared-workspace",
            storedAccountID: managedAccountID,
            selectionSource: .managedAccount(id: managedAccountID),
            isActive: false,
            isLive: false,
            canReauthenticate: true,
            canRemove: true)
        let otherMember = CodexVisibleAccount(
            id: priorAccount.id,
            email: "second-member@example.com",
            workspaceAccountID: priorAccount.workspaceAccountID,
            storedAccountID: managedAccountID,
            selectionSource: .managedAccount(id: managedAccountID),
            isActive: true,
            isLive: false,
            canReauthenticate: true,
            canRemove: true)
        let store = FileCodexAccountUsageSnapshotStore(fileURL: fileURL)
        store.store([
            CodexAccountUsageSnapshot(
                account: priorAccount,
                snapshot: self.snapshot(email: priorAccount.email, percent: 71),
                error: nil,
                sourceLabel: "legacy"),
        ])

        try self.removeAccountIdentity(fromSnapshotStoreAt: fileURL)

        #expect(store.load(for: [otherMember]).isEmpty)
    }
}
