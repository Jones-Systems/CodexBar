import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct JonesGroupedCompactAccountPresentationTests {
    private func display(
        count: Int,
        activeIndex: Int = 0,
        usedPercent: Double? = nil,
        errorIndices: Set<Int> = [],
        missingIndices: Set<Int> = [],
        sharedEmail: Bool = false) -> CodexAccountMenuDisplay
    {
        let accounts = (0..<count).map { index in
            CodexVisibleAccount(
                id: "synthetic-\(index)",
                email: sharedEmail ? "shared@example.com" : "account\(index)@example.com",
                workspaceLabel: "Workspace \(index / 2)",
                workspaceAccountID: "workspace-\(index / 2)",
                storedAccountID: nil,
                selectionSource: .liveSystem,
                isActive: index == activeIndex,
                isLive: true,
                canReauthenticate: false,
                canRemove: false)
        }
        let snapshots = accounts.enumerated().map { index, account in
            CodexAccountUsageSnapshot(
                account: account,
                snapshot: missingIndices.contains(index) ? nil : UsageSnapshot(
                    primary: RateWindow(
                        usedPercent: usedPercent ?? Double(min(index * 5, 45)),
                        windowMinutes: nil,
                        resetsAt: nil,
                        resetDescription: nil),
                    secondary: nil,
                    updatedAt: Date(timeIntervalSince1970: 1_782_000_000)),
                error: errorIndices.contains(index) ? "Synthetic unavailable account" : nil,
                sourceLabel: "synthetic")
        }
        return CodexAccountMenuDisplay(
            accounts: accounts, snapshots: snapshots,
            activeVisibleAccountID: accounts.first(where: \.isActive)?.id, layout: .stacked)
    }

    private func sections(
        _ display: CodexAccountMenuDisplay,
        expanded: Set<ProviderAccountIdentity> = [],
        collapsed: Set<ProviderAccountIdentity> = [],
        revealed: Bool = false) -> [JonesCompactAccountPresentation.MenuSection]
    {
        let plan = JonesCompactAccountPresentation.plan(
            for: .codex,
            accounts: StatusItemController.projectedCodexAccounts(display: display),
            expandedAccountIDs: expanded,
            collapsedAccountIDs: collapsed,
            healthyTailExpanded: revealed)
        return JonesCompactAccountPresentation.menuSections(plan: plan, workspaceSections: display.workspaceSections)
    }

    private func ids(in rows: [AccountMenuLayoutPlanner.Row]) -> [ProviderAccountIdentity] {
        rows.compactMap { row in
            switch row {
            case let .card(id): id
            case let .compact(compact): compact.accountID
            case .collapsedHealthy: nil
            }
        }
    }

    private func hiddenCount(in rows: [AccountMenuLayoutPlanner.Row]) -> Int {
        rows.reduce(0) { count, row in
            if case let .collapsedHealthy(hidden) = row { return count + hidden }
            return count
        }
    }

    private func expectWorkspaceIdentity(
        _ sections: [JonesCompactAccountPresentation.MenuSection],
        display: CodexAccountMenuDisplay)
    {
        #expect(sections.map(\.title) == display.workspaceSections.map { Optional($0.title) })
        #expect(sections.map(\.workspaceIndex) == display.workspaceSections.indices.map { Optional($0) })
        for (section, workspace) in zip(sections, display.workspaceSections) {
            let expected = Set(workspace.accounts.map(\.id))
            #expect(Set(self.ids(in: section.rows).map(\.opaqueID)).isSubset(of: expected))
            #expect(self.ids(in: section.rows).count + self.hiddenCount(in: section.rows) == expected.count)
            for row in section.rows {
                if case let .compact(compact) = row {
                    #expect(compact.accountID.source == "codex-account")
                    #expect(compact.label == workspace.accounts.first {
                        $0.id == compact.accountID.opaqueID
                    }?.menuDisplayName)
                }
            }
        }
    }

    @Test(arguments: [1, 2, 3, 4, 5, 6, 8, 12])
    func `workspace headers do not consume the five account budget`(count: Int) {
        let display = self.display(count: count)
        let sections = self.sections(display)
        self.expectWorkspaceIdentity(sections, display: display)
        let rows = sections.flatMap(\.rows)
        #expect(self.ids(in: rows).count == min(count, 5))
        #expect(self.hiddenCount(in: rows) == max(0, count - 5))
        #expect(rows.count { if case .card = $0 { true } else { false } } == 1)
        #expect(sections.first?.rows.first == .card(.init(source: "codex-account", opaqueID: "synthetic-0")))
    }

    @Test(arguments: [6, 8, 12])
    func `overflow retains every workspace including wholly folded groups and reveals in place`(count: Int) {
        let display = self.display(count: count)
        let initial = self.sections(display)
        let revealed = self.sections(display, revealed: true)
        self.expectWorkspaceIdentity(initial, display: display)
        self.expectWorkspaceIdentity(revealed, display: display)
        #expect(self.ids(in: revealed.flatMap(\.rows)).count == count)
        #expect(self.hiddenCount(in: revealed.flatMap(\.rows)) == 0)
        if count >= 8 {
            #expect(initial.contains { self.ids(in: $0.rows).isEmpty && self.hiddenCount(in: $0.rows) > 0 })
        }
        for (before, after) in zip(initial, revealed) {
            let visible = self.ids(in: before.rows)
            #expect(self.ids(in: after.rows).filter { visible.contains($0) } == visible)
        }
    }

    @Test(arguments: [1, 2, 3, 4, 5, 6, 8, 12])
    func `grouped active and inactive accounts collapse and reexpand with labels intact`(count: Int) {
        let display = self.display(count: count, sharedEmail: true)
        var expanded: Set<ProviderAccountIdentity> = []
        var collapsed: Set<ProviderAccountIdentity> = []
        for revealed in [false, true] {
            let initial = self.sections(display, revealed: revealed)
            for id in self.ids(in: initial.flatMap(\.rows)) {
                for isExpanded in [false, true, false, true] {
                    JonesCompactAccountPresentation.setExpanded(
                        isExpanded, accountID: id, expandedAccountIDs: &expanded, collapsedAccountIDs: &collapsed)
                    let toggled = self.sections(display, expanded: expanded, collapsed: collapsed, revealed: revealed)
                    self.expectWorkspaceIdentity(toggled, display: display)
                    #expect(self.ids(in: toggled.flatMap(\.rows)) == self.ids(in: initial.flatMap(\.rows)))
                    #expect(toggled.flatMap(\.rows).contains(.card(id)) == isExpanded)
                    #expect(expanded.isDisjoint(with: collapsed))
                }
            }
        }
    }

    @Test(arguments: [1, 2, 3, 4, 5, 6, 8, 12])
    func `last menu close restores grouped initial visibility and active card`(count: Int) {
        let display = self.display(count: count)
        let accounts = StatusItemController.projectedCodexAccounts(display: display)
        var expanded: Set<ProviderAccountIdentity> = [accounts[count - 1].id]
        var collapsed: Set<ProviderAccountIdentity> = [accounts[0].id]
        var providers: Set<ProviderInstanceID> = [.codex]
        let changed = self.sections(display, expanded: expanded, collapsed: collapsed, revealed: true)
        #expect(!JonesCompactAccountPresentation.resetIfIdle(
            hasOpenMenus: true, expandedAccountIDs: &expanded, collapsedAccountIDs: &collapsed,
            expandedHealthyTailProviders: &providers))
        #expect(self.sections(display, expanded: expanded, collapsed: collapsed, revealed: true) == changed)
        #expect(JonesCompactAccountPresentation.resetIfIdle(
            hasOpenMenus: false, expandedAccountIDs: &expanded, collapsedAccountIDs: &collapsed,
            expandedHealthyTailProviders: &providers))
        let reopened = self.sections(
            display, expanded: expanded, collapsed: collapsed, revealed: providers.contains(.codex))
        #expect(reopened == self.sections(display))
        self.expectWorkspaceIdentity(reopened, display: display)
    }

    @Test
    func `grouping never hides priority errors unknown usage or the best candidate to meet five`() {
        let fixtures = [
            self.display(count: 12, usedPercent: 60),
            self.display(count: 12, usedPercent: 95),
            self.display(count: 12, errorIndices: Set(0..<12)),
            self.display(count: 12, missingIndices: Set(0..<12)),
            self.display(count: 12, errorIndices: [2, 3, 4, 5, 6, 7]),
        ]
        for display in fixtures {
            let accounts = StatusItemController.projectedCodexAccounts(display: display)
            let plan = JonesCompactAccountPresentation.plan(for: .codex, accounts: accounts)
            let sections = self.sections(display)
            self.expectWorkspaceIdentity(sections, display: display)
            let rows = sections.flatMap(\.rows)
            #expect(Set(self.ids(in: rows)) == Set(self.ids(in: plan.rows)))
            #expect(self.ids(in: rows).count > 5)
            for row in plan.rows {
                if case .compact = row { #expect(rows.contains(row)) }
            }
        }
    }

    @Test
    func `selection changes preserve account identity and collapse state across workspaces`() {
        let original = self.display(count: 8, sharedEmail: true)
        let originalAccounts = StatusItemController.projectedCodexAccounts(display: original)
        let selected = self.display(count: 8, activeIndex: 6, sharedEmail: true)
        let sections = self.sections(selected, collapsed: [originalAccounts[0].id], revealed: true)
        self.expectWorkspaceIdentity(sections, display: selected)
        let rows = sections.flatMap(\.rows)
        #expect(!rows.contains(.card(originalAccounts[0].id)))
        #expect(rows.contains(.card(originalAccounts[6].id)))
        #expect(Set(self.ids(in: rows)) == Set(originalAccounts.map(\.id)))
    }

    @Test
    func `ungrouped rendering retains the exact existing rows for every provider`() {
        let accounts = StatusItemController.projectedCodexAccounts(display: self.display(count: 8))
        for provider in [UsageProvider.codex, .copilot] {
            let plan = JonesCompactAccountPresentation.plan(for: provider, accounts: accounts)
            let sections = JonesCompactAccountPresentation.menuSections(plan: plan)
            #expect(sections.count == 1)
            #expect(sections.first?.title == nil)
            #expect(sections.first?.workspaceIndex == nil)
            #expect(sections.first?.rows == plan.rows)
        }
    }
}
