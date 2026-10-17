import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct JonesCompactAccountPresentationTests {
    private func accounts(count: Int = 5, activeIndex: Int = 0) -> [ProviderAccountUsageSnapshot] {
        (0..<count).map { index in
            ProviderAccountUsageSnapshot(
                id: ProviderAccountIdentity(source: "codex-account", opaqueID: "synthetic-\(index)"),
                provider: .codex,
                displayLabel: "account\(index)@example.com",
                isActive: index == activeIndex,
                canActivate: index != activeIndex,
                snapshot: UsageSnapshot(
                    primary: RateWindow(
                        usedPercent: Double(index * 5),
                        windowMinutes: nil,
                        resetsAt: nil,
                        resetDescription: nil),
                    secondary: nil,
                    updatedAt: Date(timeIntervalSince1970: 1_782_000_000)),
                error: nil,
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

    @Test
    func `Codex wiring shows five including active while other providers keep default planning`() {
        let accounts = self.accounts()
        let codex = JonesCompactAccountPresentation.plan(for: .codex, accounts: accounts)
        #expect(codex.rows.first == .card(accounts[0].id))
        #expect(self.accountIDs(in: codex).count == 5)
        #expect(codex == AccountMenuLayoutPlanner.plan(accounts: accounts, minimumVisibleAccountCount: 5))
        let unchanged = JonesCompactAccountPresentation.plan(for: .copilot, accounts: accounts)
        #expect(unchanged == AccountMenuLayoutPlanner.plan(accounts: accounts))
        #expect(unchanged.rows.last == .collapsedHealthy(count: 3))
    }

    @Test
    func `every visible account toggles compact and full without changing account order`() {
        let accounts = self.accounts()
        var expandedIDs: Set<ProviderAccountIdentity> = []
        var collapsedIDs: Set<ProviderAccountIdentity> = []
        let initial = JonesCompactAccountPresentation.plan(for: .codex, accounts: accounts)
        for account in accounts {
            for expanded in [false, true, false, true] {
                JonesCompactAccountPresentation.setExpanded(
                    expanded, accountID: account.id,
                    expandedAccountIDs: &expandedIDs, collapsedAccountIDs: &collapsedIDs)
                let plan = JonesCompactAccountPresentation.plan(
                    for: .codex, accounts: accounts,
                    expandedAccountIDs: expandedIDs, collapsedAccountIDs: collapsedIDs)
                #expect(self.accountIDs(in: plan) == self.accountIDs(in: initial))
                #expect(plan.rows.contains(.card(account.id)) == expanded)
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
            false, accountID: original[0].id,
            expandedAccountIDs: &expandedIDs, collapsedAccountIDs: &collapsedIDs)
        let switched = self.accounts(activeIndex: 2)
        let plan = JonesCompactAccountPresentation.plan(
            for: .codex, accounts: switched,
            expandedAccountIDs: expandedIDs, collapsedAccountIDs: collapsedIDs)
        #expect(plan.rows.first == .card(switched[2].id))
        #expect(!plan.rows.contains(.card(original[0].id)))
        #expect(Set(self.accountIDs(in: plan)) == Set(switched.map(\.id)))

        let removed = Array(switched.dropFirst())
        let afterRemoval = JonesCompactAccountPresentation.plan(
            for: .codex, accounts: removed,
            expandedAccountIDs: expandedIDs, collapsedAccountIDs: collapsedIDs)
        #expect(!self.accountIDs(in: afterRemoval).contains(original[0].id))
        #expect(afterRemoval.rows.first == .card(switched[2].id))
    }

    @Test
    func `Codex overflow reveals remaining accounts in the same order`() {
        let accounts = self.accounts(count: 8)
        let initial = JonesCompactAccountPresentation.plan(for: .codex, accounts: accounts)
        #expect(self.accountIDs(in: initial).count == 5)
        #expect(initial.rows.last == .collapsedHealthy(count: 3))
        let revealed = JonesCompactAccountPresentation.plan(
            for: .codex, accounts: accounts, healthyTailExpanded: true)
        #expect(self.accountIDs(in: revealed) == [accounts[0].id] + accounts.dropFirst().reversed().map(\.id))
    }

    @Test
    func `last menu close resets overrides and requests a rebuild before reopening`() {
        let accounts = self.accounts(count: 8)
        var expandedIDs: Set<ProviderAccountIdentity> = [accounts[1].id]
        var collapsedIDs: Set<ProviderAccountIdentity> = [accounts[0].id]
        var expandedProviders: Set<ProviderInstanceID> = [.codex]
        #expect(!JonesCompactAccountPresentation.resetIfIdle(
            hasOpenMenus: true,
            expandedAccountIDs: &expandedIDs, collapsedAccountIDs: &collapsedIDs,
            expandedHealthyTailProviders: &expandedProviders))
        #expect(expandedIDs == [accounts[1].id])
        #expect(collapsedIDs == [accounts[0].id])
        #expect(expandedProviders == [.codex])

        #expect(JonesCompactAccountPresentation.resetIfIdle(
            hasOpenMenus: false,
            expandedAccountIDs: &expandedIDs, collapsedAccountIDs: &collapsedIDs,
            expandedHealthyTailProviders: &expandedProviders))
        #expect(expandedIDs.isEmpty && collapsedIDs.isEmpty && expandedProviders.isEmpty)
        let reopened = JonesCompactAccountPresentation.plan(
            for: .codex, accounts: accounts,
            expandedAccountIDs: expandedIDs, collapsedAccountIDs: collapsedIDs,
            healthyTailExpanded: expandedProviders.contains(.codex))
        #expect(reopened == JonesCompactAccountPresentation.plan(for: .codex, accounts: accounts))
        #expect(reopened.rows.first == .card(accounts[0].id))
        #expect(self.accountIDs(in: reopened).count == 5)
        #expect(!JonesCompactAccountPresentation.resetIfIdle(
            hasOpenMenus: false,
            expandedAccountIDs: &expandedIDs, collapsedAccountIDs: &collapsedIDs,
            expandedHealthyTailProviders: &expandedProviders))
    }
}
