import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct JonesCompactAccountPresentationTests {
    private func accounts(
        count: Int = 5,
        activeIndex: Int = 0,
        provider: UsageProvider = .codex,
        usedPercent: Double? = nil,
        error: String? = nil,
        hasSnapshot: Bool = true) -> [ProviderAccountUsageSnapshot]
    {
        (0..<count).map { index in
            ProviderAccountUsageSnapshot(
                id: ProviderAccountIdentity(source: "codex-account", opaqueID: "synthetic-\(index)"),
                provider: provider,
                displayLabel: "account\(index)@example.com",
                isActive: index == activeIndex,
                canActivate: index != activeIndex,
                snapshot: hasSnapshot ? UsageSnapshot(
                    primary: RateWindow(
                        usedPercent: usedPercent ?? Double(min(index * 5, 45)),
                        windowMinutes: nil,
                        resetsAt: nil,
                        resetDescription: nil),
                    secondary: nil,
                    updatedAt: Date(timeIntervalSince1970: 1_782_000_000)) : nil,
                error: error,
                sourceLabel: "synthetic")
        }
    }

    private func accountIDs(in plan: AccountMenuLayoutPlanner.Plan) -> [ProviderAccountIdentity] {
        plan.rows.compactMap { row in
            switch row {
            case let .card(id): id
            case let .compact(compact): compact.accountID
            case .collapsedHealthy: nil
            }
        }
    }

    @Test(arguments: [0, 1, 2, 3, 4, 5, 6, 8, 12])
    func `Codex initially shows up to five total accounts and folds even one overflow account`(count: Int) {
        let accounts = self.accounts(count: count)
        let codex = JonesCompactAccountPresentation.plan(for: .codex, accounts: accounts)
        #expect(codex.usesCompactLayout == (count > 0))
        #expect(self.accountIDs(in: codex).count == min(count, 5))
        if count == 0 {
            #expect(codex.rows.isEmpty)
            return
        }
        #expect(codex.rows.first == .card(accounts[0].id))
        #expect(codex.rows.count { if case .card = $0 { true } else { false } } == 1)
        if count > 5 {
            #expect(codex.rows.last == .collapsedHealthy(count: count - 5))
        } else {
            #expect(codex.rows.count == count)
        }
    }

    @Test(arguments: [1, 2, 3, 4, 5, 6, 8, 12])
    func `other providers retain default planning at every account count`(count: Int) {
        let accounts = self.accounts(count: count, provider: .copilot)
        for tailExpanded in [false, true] {
            let unchanged = JonesCompactAccountPresentation.plan(
                for: .copilot,
                accounts: accounts,
                expandedAccountIDs: [accounts[count - 1].id],
                collapsedAccountIDs: [accounts[0].id],
                healthyTailExpanded: tailExpanded)
            #expect(unchanged == AccountMenuLayoutPlanner.plan(
                accounts: accounts,
                expandedAccountIDs: [accounts[count - 1].id],
                healthyTailExpanded: tailExpanded,
                collapsedAccountIDs: [accounts[0].id]))
        }
    }

    @Test(arguments: [1, 2, 3, 4, 5, 6, 8, 12])
    func `every visible account toggles compact and full without changing account order`(count: Int) {
        let accounts = self.accounts(count: count)
        var expandedIDs: Set<ProviderAccountIdentity> = []
        var collapsedIDs: Set<ProviderAccountIdentity> = []
        let initial = JonesCompactAccountPresentation.plan(for: .codex, accounts: accounts)
        for accountID in self.accountIDs(in: initial) {
            for expanded in [false, true, false, true] {
                JonesCompactAccountPresentation.setExpanded(
                    expanded,
                    accountID: accountID,
                    expandedAccountIDs: &expandedIDs,
                    collapsedAccountIDs: &collapsedIDs)
                let plan = JonesCompactAccountPresentation.plan(
                    for: .codex,
                    accounts: accounts,
                    expandedAccountIDs: expandedIDs,
                    collapsedAccountIDs: collapsedIDs)
                #expect(self.accountIDs(in: plan) == self.accountIDs(in: initial))
                #expect(plan.rows.contains(.card(accountID)) == expanded)
                #expect(plan.rows.contains { row in
                    if case let .compact(compact) = row { return compact.accountID == accountID }
                    return false
                } == !expanded)
                #expect(expandedIDs.isDisjoint(with: collapsedIDs))
            }
        }
    }

    @Test
    func `collapse stays with account identity when active selection changes`() {
        let original = self.accounts()
        var expandedIDs: Set<ProviderAccountIdentity> = []
        var collapsedIDs: Set<ProviderAccountIdentity> = []
        JonesCompactAccountPresentation.setExpanded(
            false,
            accountID: original[0].id,
            expandedAccountIDs: &expandedIDs,
            collapsedAccountIDs: &collapsedIDs)
        let switched = self.accounts(activeIndex: 2)
        let plan = JonesCompactAccountPresentation.plan(
            for: .codex,
            accounts: switched,
            expandedAccountIDs: expandedIDs,
            collapsedAccountIDs: collapsedIDs)
        #expect(plan.rows.first == .card(switched[2].id))
        #expect(!plan.rows.contains(.card(original[0].id)))
        #expect(Set(self.accountIDs(in: plan)) == Set(switched.map(\.id)))

        let removed = Array(switched.dropFirst())
        let afterRemoval = JonesCompactAccountPresentation.plan(
            for: .codex,
            accounts: removed,
            expandedAccountIDs: expandedIDs,
            collapsedAccountIDs: collapsedIDs)
        #expect(!self.accountIDs(in: afterRemoval).contains(original[0].id))
        #expect(afterRemoval.rows.first == .card(switched[2].id))
    }

    @Test(arguments: [6, 8, 12])
    func `Codex overflow reveals remaining accounts in the same order`(count: Int) {
        let accounts = self.accounts(count: count)
        let initial = JonesCompactAccountPresentation.plan(for: .codex, accounts: accounts)
        #expect(self.accountIDs(in: initial).count == 5)
        #expect(initial.rows.last == .collapsedHealthy(count: count - 5))
        let revealed = JonesCompactAccountPresentation.plan(
            for: .codex, accounts: accounts, healthyTailExpanded: true)
        #expect(Set(self.accountIDs(in: revealed)) == Set(accounts.map(\.id)))
        #expect(revealed.rows.count == count)
        let visibleIDs = Set(self.accountIDs(in: initial))
        #expect(self.accountIDs(in: revealed).filter { visibleIDs.contains($0) } == self.accountIDs(in: initial))
        var expandedIDs: Set<ProviderAccountIdentity> = []
        var collapsedIDs: Set<ProviderAccountIdentity> = []
        for account in accounts {
            for expanded in [true, false] {
                JonesCompactAccountPresentation.setExpanded(
                    expanded,
                    accountID: account.id,
                    expandedAccountIDs: &expandedIDs,
                    collapsedAccountIDs: &collapsedIDs)
                let toggled = JonesCompactAccountPresentation.plan(
                    for: .codex,
                    accounts: accounts,
                    expandedAccountIDs: expandedIDs,
                    collapsedAccountIDs: collapsedIDs,
                    healthyTailExpanded: true)
                #expect(self.accountIDs(in: toggled) == self.accountIDs(in: revealed))
                #expect(toggled.rows.contains(.card(account.id)) == expanded)
            }
        }
    }

    @Test(arguments: [1, 2, 3, 4, 5, 6, 8, 12])
    func `last menu close resets overrides and requests a rebuild before reopening`(count: Int) {
        let accounts = self.accounts(count: count)
        let expandedID = accounts[count - 1].id
        var expandedIDs: Set<ProviderAccountIdentity> = count > 1 ? [expandedID] : []
        var collapsedIDs: Set<ProviderAccountIdentity> = [accounts[0].id]
        var expandedProviders: Set<ProviderInstanceID> = [.codex]
        #expect(!JonesCompactAccountPresentation.resetIfIdle(
            hasOpenMenus: true,
            expandedAccountIDs: &expandedIDs,
            collapsedAccountIDs: &collapsedIDs,
            expandedHealthyTailProviders: &expandedProviders))
        #expect(expandedIDs == (count > 1 ? [expandedID] : []))
        #expect(collapsedIDs == [accounts[0].id])
        #expect(expandedProviders == [.codex])

        #expect(JonesCompactAccountPresentation.resetIfIdle(
            hasOpenMenus: false,
            expandedAccountIDs: &expandedIDs,
            collapsedAccountIDs: &collapsedIDs,
            expandedHealthyTailProviders: &expandedProviders))
        #expect(expandedIDs.isEmpty && collapsedIDs.isEmpty && expandedProviders.isEmpty)
        let reopened = JonesCompactAccountPresentation.plan(
            for: .codex,
            accounts: accounts,
            expandedAccountIDs: expandedIDs,
            collapsedAccountIDs: collapsedIDs,
            healthyTailExpanded: expandedProviders.contains(.codex))
        #expect(reopened == JonesCompactAccountPresentation.plan(for: .codex, accounts: accounts))
        #expect(reopened.rows.first == .card(accounts[0].id))
        #expect(self.accountIDs(in: reopened).count == min(count, 5))
        #expect(!JonesCompactAccountPresentation.resetIfIdle(
            hasOpenMenus: false,
            expandedAccountIDs: &expandedIDs,
            collapsedAccountIDs: &collapsedIDs,
            expandedHealthyTailProviders: &expandedProviders))
    }

    @Test
    func `five account target never hides constrained error or unknown usage rows`() {
        let fixtures = [
            self.accounts(count: 8, usedPercent: 60),
            self.accounts(count: 8, usedPercent: 95),
            self.accounts(count: 8, error: "Synthetic unavailable account"),
            self.accounts(count: 8, hasSnapshot: false),
        ]
        for accounts in fixtures {
            let plan = JonesCompactAccountPresentation.plan(for: .codex, accounts: accounts)
            #expect(Set(self.accountIDs(in: plan)) == Set(accounts.map(\.id)))
            #expect(plan.rows.count == accounts.count)
        }
    }
}
