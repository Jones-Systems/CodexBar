import CodexBarCore
import Foundation

enum JonesCompactAccountPresentation {
    struct OverviewExpansionState {
        var expandedAggregateProviders: Set<UsageProvider> = []
        var collapsedSummaryProviders: Set<UsageProvider> = []
        var expandedAccountIDs: Set<ProviderAccountIdentity> = []

        mutating func toggleAggregate(_ provider: UsageProvider) {
            if self.expandedAggregateProviders.remove(provider) == nil {
                self.expandedAggregateProviders.insert(provider)
            }
        }

        mutating func toggleSummary(_ provider: UsageProvider) {
            if self.collapsedSummaryProviders.remove(provider) == nil {
                self.collapsedSummaryProviders.insert(provider)
            }
        }

        mutating func toggleAccount(_ accountID: ProviderAccountIdentity) {
            if self.expandedAccountIDs.remove(accountID) == nil {
                self.expandedAccountIDs.insert(accountID)
            }
        }

        mutating func resetIfIdle(hasOpenMenus: Bool) -> Bool {
            guard !hasOpenMenus else { return false }
            let changed = !self.collapsedSummaryProviders.isEmpty || !self.expandedAccountIDs.isEmpty ||
                !self.expandedAggregateProviders.isEmpty
            self = Self()
            return changed
        }
    }

    struct CodexRowDetail: Equatable {
        let text: String?
        let trailingDetail: MenuCardCompactAccountRowView.TrailingDetail?
    }

    static func codexRowDetail(
        account: ProviderAccountUsageSnapshot,
        resetStyle: ResetTimeDisplayStyle,
        now: Date) -> CodexRowDetail
    {
        // Provider-specific by design: Codex rows pair weekly reset timing with the nearest limit-reset credit expiry.
        guard account.provider == .codex, account.error == nil, let snapshot = account.snapshot else {
            return CodexRowDetail(text: nil, trailingDetail: nil)
        }
        let text = snapshot.secondary.flatMap { weekly in
            weekly.resetsAt == nil ? nil : UsageFormatter.resetLine(for: weekly, style: resetStyle, now: now)
        }
        var trailingDetail: MenuCardCompactAccountRowView.TrailingDetail?
        if let credits = snapshot.codexResetCredits,
           credits.availableInventory(at: now).nextExpiringCredit != nil,
           let presentation = CodexResetCreditsPresentation.make(snapshot: credits, resetStyle: .countdown, now: now),
           let nearest = presentation.items.first
        {
            trailingDetail = .init(
                text: nearest.compactExpiryText,
                count: presentation.items.count,
                accessibilityLabel: [L("Limit Reset Credits"), presentation.text, nearest.expiryText]
                    .joined(separator: ", "))
        }
        return CodexRowDetail(text: text, trailingDetail: trailingDetail)
    }

    static func claudeRowDetail(
        account: ProviderAccountUsageSnapshot,
        resetStyle: ResetTimeDisplayStyle,
        now: Date) -> CodexRowDetail
    {
        // Provider-specific by design: Claude exposes session and weekly reset dates, but no banked reset inventory.
        guard account.provider == .claude, account.error == nil, let snapshot = account.snapshot else {
            return CodexRowDetail(text: nil, trailingDetail: nil)
        }
        let lines = [snapshot.primary, snapshot.secondary].compactMap { window -> String? in
            guard let window, !window.isSyntheticPlaceholder, window.resetsAt != nil else { return nil }
            return UsageFormatter.resetLine(for: window, style: resetStyle, now: now)
        }
        return CodexRowDetail(text: lines.isEmpty ? nil : lines.joined(separator: " · "), trailingDetail: nil)
    }

    static func rowDetail(
        account: ProviderAccountUsageSnapshot,
        resetStyle: ResetTimeDisplayStyle,
        now: Date) -> CodexRowDetail?
    {
        // Provider-specific by design: only Codex and Claude replace compact quota text with reset timing.
        switch account.provider {
        case .codex: self.codexRowDetail(account: account, resetStyle: resetStyle, now: now)
        case .claude: self.claudeRowDetail(account: account, resetStyle: resetStyle, now: now)
        default: nil
        }
    }

    struct OverviewSummaryInput {
        let provider: UsageProvider
        let label: String
        let snapshot: UsageSnapshot?
        let hasError: Bool
        let isRefreshing: Bool
    }

    static func overviewSummaryRow(
        _ input: OverviewSummaryInput,
        resetStyle: ResetTimeDisplayStyle,
        now: Date) -> MenuCardCompactAccountRowView.Model
    {
        let account = ProviderAccountUsageSnapshot(
            id: ProviderAccountIdentity(source: "overview-summary", opaqueID: input.provider.rawValue),
            provider: input.provider,
            displayLabel: input.label,
            isActive: false,
            canActivate: false,
            snapshot: input.snapshot,
            error: input.hasError ? L("Account unavailable") : nil,
            sourceLabel: nil)
        let plan = AccountMenuLayoutPlanner.plan(
            accounts: [account],
            policy: .init(
                compactLayoutMinimumAccountCount: 1,
                preservesAccountOrder: true,
                expandsActiveAccount: false))
        let compact = plan.rows.compactMap { row -> AccountMenuLayoutPlanner.CompactRow? in
            if case let .compact(value) = row { return value }
            return nil
        }.first
        let detail = self.rowDetail(account: account, resetStyle: resetStyle, now: now)
        return MenuCardCompactAccountRowView.Model(
            label: input.label,
            headroomPercent: compact?.headroomPercent,
            severity: compact?.severity,
            constraintDetail: input.hasError || detail == nil ? compact?.constraintDetail : detail?.text,
            hasError: input.hasError,
            showsBestBadge: false,
            isRefreshing: input.isRefreshing,
            trailingDetail: detail?.trailingDetail,
            detailIsResetTiming: !input.hasError && detail?.text != nil)
    }

    static func plan(
        for provider: UsageProvider,
        accounts: [ProviderAccountUsageSnapshot],
        expandedAccountIDs: Set<ProviderAccountIdentity> = [],
        collapsedAccountIDs: Set<ProviderAccountIdentity> = [],
        healthyTailExpanded: Bool = false) -> AccountMenuLayoutPlanner.Plan
    {
        // Provider-specific by design: native fleet rows use toggles at every count and never fold away accounts.
        // Codex keeps the Settings menu order and starts fully collapsed; the active account is marked, not moved.
        let keepsAllAccountsVisible = provider == .codex || (provider == .claude && !accounts.isEmpty &&
            accounts.allSatisfy { $0.id.source == "claude-native-profile" })
        return AccountMenuLayoutPlanner.plan(
            accounts: accounts,
            expandedAccountIDs: expandedAccountIDs,
            healthyTailExpanded: healthyTailExpanded,
            collapsedAccountIDs: collapsedAccountIDs,
            minimumVisibleAccountCount: keepsAllAccountsVisible ? Int.max : 0,
            policy: keepsAllAccountsVisible
                ? .init(
                    compactLayoutMinimumAccountCount: 1,
                    minimumCollapsedHealthyRowCount: 1,
                    preservesAccountOrder: provider == .codex,
                    expandsActiveAccount: provider != .codex)
                : .init())
    }

    struct MenuSection: Equatable {
        let workspaceIndex: Int?
        let title: String?
        let rows: [AccountMenuLayoutPlanner.Row]
    }

    static func menuSections(
        plan: AccountMenuLayoutPlanner.Plan,
        workspaceSections: [CodexAccountWorkspaceSection] = []) -> [MenuSection]
    {
        guard !workspaceSections.isEmpty else {
            return [MenuSection(workspaceIndex: nil, title: nil, rows: plan.rows)]
        }
        // Select visible accounts globally, then retain workspace labels even for wholly folded groups.
        // Each summary counts only its workspace; revealing uses the existing provider-wide menu state.
        return workspaceSections.enumerated().map { index, workspace in
            let accountIDs = Set(workspace.accounts.map {
                ProviderAccountIdentity(source: "codex-account", opaqueID: $0.id)
            })
            var rows = plan.rows.filter { row in
                switch row {
                case let .card(id): accountIDs.contains(id)
                case let .compact(compact): accountIDs.contains(compact.accountID)
                case .collapsedHealthy: false
                }
            }
            let hiddenCount = accountIDs.count - rows.count
            if hiddenCount > 0 {
                rows.append(.collapsedHealthy(count: hiddenCount))
            }
            return MenuSection(workspaceIndex: index, title: workspace.title, rows: rows)
        }
    }

    static func setExpanded(
        _ expanded: Bool,
        accountID: ProviderAccountIdentity,
        expandedAccountIDs: inout Set<ProviderAccountIdentity>,
        collapsedAccountIDs: inout Set<ProviderAccountIdentity>)
    {
        if expanded {
            collapsedAccountIDs.remove(accountID)
            expandedAccountIDs.insert(accountID)
        } else {
            expandedAccountIDs.remove(accountID)
            collapsedAccountIDs.insert(accountID)
        }
    }

    static func resetIfIdle(
        hasOpenMenus: Bool,
        expandedAccountIDs: inout Set<ProviderAccountIdentity>,
        collapsedAccountIDs: inout Set<ProviderAccountIdentity>,
        expandedHealthyTailProviders: inout Set<ProviderInstanceID>) -> Bool
    {
        guard !hasOpenMenus else { return false }
        let changed = !expandedAccountIDs.isEmpty || !collapsedAccountIDs.isEmpty ||
            !expandedHealthyTailProviders.isEmpty
        expandedAccountIDs.removeAll()
        collapsedAccountIDs.removeAll()
        expandedHealthyTailProviders.removeAll()
        return changed
    }

    static func overviewPolicy(for provider: UsageProvider) -> AccountMenuLayoutPlanner.Policy {
        // Provider-specific by design: Overview Codex rows keep the Settings menu order below the active summary row.
        .init(compactLayoutMinimumAccountCount: 1, preservesAccountOrder: provider == .codex)
    }
}
