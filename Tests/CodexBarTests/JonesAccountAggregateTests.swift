import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct JonesAccountAggregateTests {
    private func visible(
        _ alias: String,
        email: String? = nil,
        workspace: String? = "workspace") -> CodexVisibleAccount
    {
        CodexVisibleAccount(
            id: alias,
            email: email ?? "\(alias)@example.test",
            workspaceAccountID: workspace,
            storedAccountID: nil,
            selectionSource: .profileHome(path: "/synthetic/\(alias)"),
            isActive: alias == "malcolm",
            isLive: false,
            canReauthenticate: false,
            canRemove: false)
    }

    private func projection(
        _ accounts: [CodexVisibleAccount],
        aliases: [String] = JonesAccountAggregate.codexAliases) -> CodexVisibleAccountProjection
    {
        CodexVisibleAccountProjection(
            visibleAccounts: accounts,
            activeVisibleAccountID: accounts.first?.id,
            liveVisibleAccountID: nil,
            hasUnreadableAddedAccountStore: false,
            fleetProfileHomePaths: aliases.map { "/synthetic/\($0)" })
    }

    private func row(
        _ alias: String,
        remaining: Double? = 50,
        provider: UsageProvider = .codex,
        error: String? = nil,
        email: String? = nil,
        accountID: String? = nil,
        organization: String? = nil,
        tertiaryRemaining: Double? = nil) -> ProviderAccountUsageSnapshot
    {
        ProviderAccountUsageSnapshot(
            id: ProviderAccountIdentity(
                source: provider == .codex ? "codex-account" : "claude-native-profile",
                opaqueID: alias),
            provider: provider,
            displayLabel: "Display label only",
            isActive: false,
            snapshot: remaining.map {
                UsageSnapshot(
                    primary: RateWindow(
                        usedPercent: 100 - $0,
                        windowMinutes: 300,
                        resetsAt: nil,
                        resetDescription: nil),
                    secondary: nil,
                    tertiary: tertiaryRemaining.map {
                        RateWindow(usedPercent: 100 - $0, windowMinutes: nil, resetsAt: nil, resetDescription: nil)
                    },
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                    identity: ProviderIdentitySnapshot(
                        providerID: provider.instanceID,
                        accountEmail: email,
                        accountOrganization: organization,
                        loginMethod: nil,
                        accountID: accountID))
            },
            error: error,
            sourceLabel: "Synthetic")
    }

    @Test
    func `selected Codex sample sums displayed headroom over fixed denominator`() throws {
        let aliases = JonesAccountAggregate.codexAliases
        let projection = self.projection(aliases.map { self.visible($0) })
        let rows = zip(aliases, [98.0, 59, 97, 24, 79]).map { self.row($0, remaining: $1) }
        let total = try #require(JonesAccountAggregate.codex(projection: projection, accounts: rows))
        #expect(total.summedRemainingPercent == 357)
        #expect(total.maximumPercent == 500)
        #expect(total.normalizedPercent == 71.4)
        #expect(total.reportingCount == 5)
        #expect(!total.isPartial)
        #expect(total.detailLabel.contains("357% / 500%"))
    }

    @Test(arguments: [true, false])
    func `missing or failed retained Umesh snapshot remains an unknown selected slot`(retainedError: Bool) throws {
        let aliases = JonesAccountAggregate.codexAliases
        let projection = self.projection(aliases.map { self.visible($0) })
        var rows = zip(aliases, [98.0, 59, 97, 24, 79]).map { self.row($0, remaining: $1) }
        if retainedError {
            rows[2] = self.row("umich", remaining: 97, error: "Unavailable")
        } else {
            rows.remove(at: 2)
        }
        let total = try #require(JonesAccountAggregate.codex(projection: projection, accounts: rows))
        #expect(total.summedRemainingPercent == 260)
        #expect(total.maximumPercent == 500)
        #expect(total.normalizedPercent == 52)
        #expect(total.reportingCount == 4)
        #expect(total.normalizedLabel == "≥52%")
        #expect(total.detailLabel.contains("≥260% / 500%"))
        #expect(total.accessibilityText.contains("At least"))
    }

    @Test
    func `extra enrollment and default duplicate cannot inflate selected capacity`() throws {
        let aliases = JonesAccountAggregate.codexAliases + ["extra", "default"]
        let accounts = aliases.map { self.visible($0) }
        let rows = aliases.map { self.row($0, remaining: 100) }
        let total = try #require(JonesAccountAggregate.codex(
            projection: self.projection(accounts, aliases: aliases), accounts: rows))
        #expect(total.selectedCount == 5)
        #expect(total.reportingCount == 5)
        #expect(total.summedRemainingPercent == 500)
        #expect(JonesAccountAggregate.codex(
            projection: self.projection(accounts, aliases: ["extra", "default"]), accounts: rows) == nil)
    }

    @Test
    func `selected duplicate credentials count once while different email seats remain distinct`() throws {
        let accounts = [
            self.visible("malcolm", email: " SAME@example.test ", workspace: " SHARED "),
            self.visible("jace", email: "same@example.test", workspace: "shared"),
            self.visible("umich", email: "other@example.test", workspace: "shared"),
        ]
        let total = try #require(JonesAccountAggregate.codex(
            projection: self.projection(accounts),
            accounts: accounts.map { self.row($0.id, remaining: 80) }))
        #expect(total.reportingCount == 2)
        #expect(total.summedRemainingPercent == 160)
        #expect(total.maximumPercent == 500)
    }

    @Test
    func `missing identity enrollment row and loading never become confirmed zero`() throws {
        let accounts = [self.visible("malcolm", workspace: nil), self.visible("jace")]
        let total = try #require(JonesAccountAggregate.codex(
            projection: self.projection(accounts),
            accounts: [self.row("malcolm"), self.row("jace", remaining: nil)]))
        #expect(total.reportingCount == 0)
        #expect(total.normalizedPercent == nil)
        #expect(total.normalizedLabel == "Unavailable")
        #expect(!total.detailLabel.contains("0%"))
        #expect(JonesAccountAggregate.codex(projection: self.projection(accounts, aliases: []), accounts: []) == nil)
    }

    @Test
    func `rounding and tertiary constraint match compact account rows`() throws {
        let account = self.visible("malcolm")
        let row = self.row("malcolm", remaining: 98.9, tertiaryRemaining: 24.6)
        let total = try #require(JonesAccountAggregate.codex(
            projection: self.projection([account]), accounts: [row]))
        let headroom = try #require(AccountMenuLayoutPlanner.headroomPercent(for: row))
        #expect(total.summedRemainingPercent == Int(headroom.rounded()))
        #expect(total.summedRemainingPercent == 25)
        #expect(total.normalizedPercent == 5)
    }

    @Test
    func `Claude uses account identity before email fallback with fixed two account denominator`() throws {
        let rows = [
            self.row("default", remaining: 90, provider: .claude, email: "same@example.test", accountID: "one"),
            self.row("jace", remaining: 60, provider: .claude, email: "same@example.test", accountID: "two"),
            self.row("extra", remaining: 100, provider: .claude, accountID: "extra"),
        ]
        let total = try #require(JonesAccountAggregate.claude(
            enrolledAliases: ["default", "jace", "extra"], accounts: rows))
        #expect(total.maximumPercent == 200)
        #expect(total.summedRemainingPercent == 150)
        #expect(total.normalizedPercent == 75)
        #expect(total.reportingCount == 2)
        let loading = try #require(JonesAccountAggregate.claude(
            enrolledAliases: ["default", "jace"], accounts: rows, refreshingAliases: ["jace"]))
        #expect(loading.reportingCount == 1)
        #expect(loading.normalizedPercent == 45)
        #expect(loading.heightFingerprint != total.heightFingerprint)
    }

    @Test
    func `Claude mixed account ID and email fallback for one account count once`() throws {
        let total = try #require(JonesAccountAggregate.claude(
            enrolledAliases: ["default", "jace"],
            accounts: [
                self.row("default", remaining: 90, provider: .claude, email: "SAME@example.test", accountID: "one"),
                self.row("jace", remaining: 60, provider: .claude, email: "same@example.test"),
            ]))
        #expect(total.reportingCount == 1)
        #expect(total.summedRemainingPercent == 90)
        #expect(total.maximumPercent == 200)
    }

    @Test
    func `Claude fallback normalizes email and organization and excludes retained errors`() throws {
        let rows = [
            self.row("default", remaining: 90, provider: .claude, email: " SAME@example.test ", organization: " ORG "),
            self.row("jace", remaining: 60, provider: .claude, email: "same@example.test", organization: "org"),
        ]
        let total = try #require(JonesAccountAggregate.claude(enrolledAliases: ["default", "jace"], accounts: rows))
        #expect(total.reportingCount == 1)
        #expect(total.summedRemainingPercent == 90)
        let unavailable = try #require(JonesAccountAggregate.claude(
            enrolledAliases: ["default", "jace"],
            accounts: [
                self.row("default", provider: .claude),
                self.row("jace", provider: .claude, error: "Unavailable", accountID: "known"),
            ]))
        #expect(unavailable.normalizedPercent == nil)
        #expect(unavailable.maximumPercent == 200)
    }
}
