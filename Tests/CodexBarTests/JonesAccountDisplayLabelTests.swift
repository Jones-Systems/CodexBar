import AppKit
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct JonesAccountDisplayLabelTests {
    @Test
    func `local override wins and verified aliases supply short labels`() {
        #expect(JonesAccountDisplayLabel.resolve(
            provider: .codex,
            profileIdentity: "profile:one",
            verifiedAlias: "north",
            override: "  Primary  ") == "Primary")
        #expect(JonesAccountDisplayLabel.resolve(
            provider: .codex, profileIdentity: "profile:one", verifiedAlias: "north", override: "  ") == "North")
        #expect(JonesAccountDisplayLabel.resolve(
            provider: .codex, profileIdentity: "profile:umich", verifiedAlias: "umich") == "UMICH")
        #expect(JonesAccountDisplayLabel.resolve(
            provider: .codex, profileIdentity: "profile:umich", verifiedAlias: "umich", override: "Campus") == "Campus")
        #expect(JonesAccountDisplayLabel.resolve(
            provider: .claude, profileIdentity: "native:default", verifiedAlias: "default") == "default")
        #expect(JonesAccountDisplayLabel.resolve(
            provider: .claude,
            profileIdentity: "native:default",
            verifiedAlias: "default",
            override: "Primary synthetic") == "Primary synthetic")
        let unknown = JonesAccountDisplayLabel.resolve(provider: .codex, profileIdentity: "profile:one")
        #expect(unknown.hasPrefix("Account · "))
        #expect(unknown == JonesAccountDisplayLabel.resolve(provider: .codex, profileIdentity: "profile:one"))
        #expect(unknown != JonesAccountDisplayLabel.resolve(provider: .codex, profileIdentity: "profile:two"))
        #expect(unknown != JonesAccountDisplayLabel.resolve(provider: .claude, profileIdentity: "profile:one"))
    }

    @Test
    func `profile keys distinguish homes and providers without using email`() {
        let first = self.account(path: "/fixture/north")
        let second = self.account(path: "/fixture/south")
        let firstIdentity = JonesAccountDisplayLabel.codexProfileIdentity(for: first)
        let secondIdentity = JonesAccountDisplayLabel.codexProfileIdentity(for: second)
        #expect(first.email == second.email)
        #expect(firstIdentity != secondIdentity)
        #expect(!firstIdentity.contains(first.email))
        #expect(JonesAccountDisplayLabel.overrideKey(provider: .codex, profileIdentity: firstIdentity)
            != JonesAccountDisplayLabel.overrideKey(provider: .claude, profileIdentity: firstIdentity))
        let defaultIdentity = JonesAccountDisplayLabel.claudeProfileIdentity(
            alias: "default", home: "/fixture", configDirectory: nil)
        let namedIdentity = JonesAccountDisplayLabel.claudeProfileIdentity(
            alias: "north", home: "/fixture", configDirectory: "/fixture/.claude-t3/north")
        #expect(defaultIdentity != namedIdentity)
        #expect(defaultIdentity == "native-profile:default:/fixture/.claude")
    }

    @Test
    func `local overrides are provider scoped and reading labels never writes preferences`() {
        let defaults = InMemoryUserDefaults()
        let settings = self.settings(defaults: defaults)
        let identity = "profile:/fixture/north"
        #expect(settings.accountDisplayLabel(
            provider: .codex, profileIdentity: identity, verifiedAlias: "north") == "North")
        #expect(defaults.object(forKey: SettingsStore.accountDisplayLabelOverridesKey) == nil)
        settings.setAccountDisplayLabel("Primary", provider: .codex, profileIdentity: identity)
        #expect(settings.accountDisplayLabel(
            provider: .codex, profileIdentity: identity, verifiedAlias: "north") == "Primary")
        #expect(settings.accountDisplayLabel(
            provider: .claude, profileIdentity: identity, verifiedAlias: "north") == "North")
        let key = JonesAccountDisplayLabel.overrideKey(provider: .codex, profileIdentity: identity)
        #expect((defaults.dictionary(forKey: SettingsStore.accountDisplayLabelOverridesKey) as? [String: String])?[key]
            == "Primary")
        #expect(!key.contains("/fixture"))
        settings.setAccountDisplayLabel(nil, provider: .codex, profileIdentity: identity)
        #expect(settings.accountDisplayLabel(
            provider: .codex, profileIdentity: identity, verifiedAlias: "north") == "North")
    }

    @Test
    func `only enrolled profile homes gain alias metadata and identity stays unchanged`() throws {
        let north = ObservedSystemCodexAccount(
            email: "shared@example.test", codexHomePath: "/fixture/.codex-t3/north", observedAt: .distantPast)
        let south = ObservedSystemCodexAccount(
            email: "shared@example.test", codexHomePath: "/fixture/unknown/south", observedAt: .distantPast)
        func projection(fleetHomes: [String]) -> CodexVisibleAccountProjection {
            CodexVisibleAccountProjection.make(from: CodexAccountReconciliationSnapshot(
                storedAccounts: [],
                activeStoredAccount: nil,
                liveSystemAccount: nil,
                profileHomeAccounts: [north, south],
                fleetProfileHomePaths: fleetHomes,
                matchingStoredAccountForLiveSystemAccount: nil,
                activeSource: .profileHome(path: north.codexHomePath),
                hasUnreadableAddedAccountStore: false))
        }
        let before = projection(fleetHomes: [])
        let enrolled = projection(fleetHomes: [north.codexHomePath])
        let account = try #require(enrolled.visibleAccounts.first {
            $0.selectionSource == .profileHome(path: north.codexHomePath)
        })
        #expect(account.fleetProfileAlias == "north")
        let unknown = enrolled.visibleAccounts.first { $0.selectionSource == .profileHome(path: south.codexHomePath) }
        #expect(unknown?.fleetProfileAlias == nil)
        #expect(before.visibleAccounts.map(\.id) == enrolled.visibleAccounts.map(\.id))
        #expect(before.visibleAccounts.map(\.email) == enrolled.visibleAccounts.map(\.email))
        #expect(before.visibleAccounts.map(\.displayDiscriminator)
            == enrolled.visibleAccounts.map(\.displayDiscriminator))
        #expect(before.activeVisibleAccountID == enrolled.activeVisibleAccountID)
    }

    @Test
    func `switcher labels and tooltips use overrides while selecting original identities`() {
        let accounts = [
            self.account(path: "/fixture/north", alias: "north"),
            self.account(path: "/fixture/south", alias: "south"),
        ]
        let settings = self.settings(defaults: InMemoryUserDefaults())
        settings.setAccountDisplayLabel(
            "Primary",
            provider: .codex,
            profileIdentity: JonesAccountDisplayLabel.codexProfileIdentity(for: accounts[0]))
        let labels = settings.codexAccountDisplayLabels(for: accounts)
        var selected: CodexVisibleAccount?
        let view = CodexAccountSwitcherView(
            accounts: accounts,
            selectedAccountID: accounts[0].id,
            width: 320,
            displayLabels: labels,
            onSelect: { selected = $0 })
        #expect(view._test_buttonTitles() == ["Primary", "South"])
        #expect(view._test_buttonToolTips() == ["Primary", "South"])
        view._test_selectAccount(id: accounts[1].id)
        #expect(selected == accounts[1])
        let hidden = CodexAccountSwitcherView(
            accounts: accounts,
            selectedAccountID: accounts[0].id,
            width: 320,
            displayLabels: labels,
            hidePersonalInfo: true,
            onSelect: { _ in })
        #expect(hidden._test_buttonTitles() == ["", ""])
        #expect(hidden._test_buttonToolTips() == ["", ""])
    }

    @Test
    func `compact projection uses labels without changing row identity or snapshot ownership`() {
        let account = self.account(path: "/fixture/north", alias: "north")
        let snapshot = self.snapshot(email: account.email, provider: .codex)
        let display = CodexAccountMenuDisplay(
            accounts: [account],
            snapshots: [CodexAccountUsageSnapshot(
                account: account, snapshot: snapshot, error: nil, sourceLabel: "fixture")],
            activeVisibleAccountID: account.id,
            layout: .stacked)
        let rows = StatusItemController.projectedCodexAccounts(display: display, displayLabels: [account.id: "Primary"])
        #expect(rows.first?.displayLabel == "Primary")
        #expect(rows.first?.id.opaqueID == account.id)
        #expect(rows.first?.snapshot?.accountEmail(for: .codex) == account.email)
        #expect(rows.first?.isActive == true)
    }

    @Test(arguments: [UsageProvider.codex, .claude])
    func `header display labels preserve identity fingerprints and redaction`(provider: UsageProvider) throws {
        let original = try self.model(provider: provider, label: nil)
        let renamed = try self.model(provider: provider, label: "Primary")
        let hidden = try self.model(provider: provider, label: "Primary", hidePersonalInfo: true)
        let different = try self.model(provider: provider, label: "Primary", email: "different@example.test")
        #expect(original.email == "owner@example.test")
        #expect(renamed.email == "Primary")
        #expect(hidden.email.isEmpty)
        #expect(original.accountIdentityFingerprint == renamed.accountIdentityFingerprint)
        #expect(renamed.accountIdentityFingerprint == hidden.accountIdentityFingerprint)
        #expect(renamed.accountIdentityFingerprint != different.accountIdentityFingerprint)
    }

    @Test
    func `selected Codex header uses the source label instead of fetched email`() throws {
        let settings = self.settings(defaults: InMemoryUserDefaults())
        settings.codexActiveSource = .liveSystem
        settings.setAccountDisplayLabel("Primary", provider: .codex, profileIdentity: "system")
        let fetcher = UsageFetcher(environment: [:])
        let store = UsageStore(
            fetcher: fetcher,
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
        store._setSnapshotForTesting(self.snapshot(email: "owner@example.test", provider: .codex), provider: .codex)
        try withStatusItemControllerForTesting(
            store: store,
            settings: settings,
            fetcher: fetcher,
            account: AccountInfo(email: nil, plan: nil))
        { controller in
            let model = try #require(controller.menuCardModel(for: .codex))
            #expect(model.email == "Primary")
            #expect(store.snapshot(for: .codex)?.accountEmail(for: .codex) == "owner@example.test")
        }
    }

    @Test(arguments: [false, true])
    func `unresolved Codex source never synthesizes a default header label`(blankOverride: Bool) throws {
        let settings = self.settings(defaults: InMemoryUserDefaults())
        settings.codexActiveSource = .liveSystem
        if blankOverride {
            settings.setAccountDisplayLabel("  ", provider: .codex, profileIdentity: "system")
        }
        let fetcher = UsageFetcher(environment: [:])
        let store = UsageStore(
            fetcher: fetcher,
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
        store._setSnapshotForTesting(self.snapshot(email: "owner@example.test", provider: .codex), provider: .codex)
        try withStatusItemControllerForTesting(
            store: store,
            settings: settings,
            fetcher: fetcher,
            account: AccountInfo(email: nil, plan: nil))
        { controller in
            #expect(controller.selectedCodexAccountDisplayLabel() == nil)
            let model = try #require(controller.menuCardModel(for: .codex))
            #expect(model.email == "owner@example.test")
            #expect(model.email != "default")
            #expect(settings.codexActiveSource == .liveSystem)
        }
    }

    private func settings(defaults: InMemoryUserDefaults) -> SettingsStore {
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: "JonesAccountDisplayLabelTests-\(UUID().uuidString)"),
            codexCookieStore: InMemoryCookieHeaderStore(),
            claudeCookieStore: InMemoryCookieHeaderStore(),
            tokenAccountStore: InMemoryTokenAccountStore(),
            keychainAccessPolicy: SettingsStoreKeychainAccessPolicy(
                setDisabled: { _ in }, isExplicitlyDisabled: { true }),
            performInitialProviderDetection: false)
        settings.configFileWatcher?.stop()
        settings.hidePersonalInfo = false
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        return settings
    }

    private func account(path: String, alias: String? = nil) -> CodexVisibleAccount {
        CodexVisibleAccount(
            id: path,
            email: "owner@example.test",
            storedAccountID: nil,
            selectionSource: .profileHome(path: path),
            isActive: false,
            isLive: false,
            canReauthenticate: false,
            canRemove: false,
            fleetProfileAlias: alias)
    }

    private func snapshot(email: String, provider: UsageProvider) -> UsageSnapshot {
        UsageSnapshot(
            primary: RateWindow(usedPercent: 20, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date(timeIntervalSince1970: 1_782_000_000),
            identity: ProviderIdentitySnapshot(
                providerID: provider.instanceID, accountEmail: email, accountOrganization: nil, loginMethod: "fixture"))
    }

    private func model(
        provider: UsageProvider,
        label: String?,
        hidePersonalInfo: Bool = false,
        email: String = "owner@example.test") throws -> UsageMenuCardView.Model
    {
        try UsageMenuCardView.Model.make(.init(
            provider: provider,
            metadata: #require(ProviderDefaults.metadata[provider]),
            snapshot: self.snapshot(email: email, provider: provider),
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: email, plan: nil),
            accountDisplayLabel: label,
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: false,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: false,
            hidePersonalInfo: hidePersonalInfo,
            now: Date(timeIntervalSince1970: 1_782_000_000)))
    }
}
