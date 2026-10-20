import CodexBarCore
import Foundation

enum JonesCompactAccountPresentation {
    struct CodexRowDetail: Equatable {
        let text: String?
        let trailingDetail: MenuCardCompactAccountRowView.TrailingDetail?
    }

    static func codexRowDetail(
        account: ProviderAccountUsageSnapshot,
        resetStyle: ResetTimeDisplayStyle,
        now: Date) -> CodexRowDetail
    {
        // Provider-specific by design: Codex rows pair weekly allowance with the nearest limit-reset credit expiry.
        guard account.provider == .codex, account.error == nil, let snapshot = account.snapshot else {
            return CodexRowDetail(text: nil, trailingDetail: nil)
        }
        let text = snapshot.secondary.map { weekly in
            let remaining = String(format: L("%@ left"), "\(Int(weekly.remainingPercent.rounded()))%")
            var parts = ["\(L("Weekly")) \(remaining)"]
            if weekly.resetsAt != nil,
               let reset = UsageFormatter.resetLine(for: weekly, style: resetStyle, now: now)
            {
                parts.append(reset)
            }
            return parts.joined(separator: " · ")
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

    static func plan(
        for provider: UsageProvider,
        accounts: [ProviderAccountUsageSnapshot],
        expandedAccountIDs: Set<ProviderAccountIdentity> = [],
        collapsedAccountIDs: Set<ProviderAccountIdentity> = [],
        healthyTailExpanded: Bool = false) -> AccountMenuLayoutPlanner.Plan
    {
        // Provider-specific by design: native fleet rows use toggles at every count and never fold away accounts.
        let keepsAllAccountsVisible = provider == .codex || (provider == .claude && !accounts.isEmpty &&
            accounts.allSatisfy { $0.id.source == "claude-native-profile" })
        return AccountMenuLayoutPlanner.plan(
            accounts: accounts,
            expandedAccountIDs: expandedAccountIDs,
            healthyTailExpanded: healthyTailExpanded,
            collapsedAccountIDs: collapsedAccountIDs,
            minimumVisibleAccountCount: keepsAllAccountsVisible ? Int.max : 0,
            policy: keepsAllAccountsVisible
                ? .init(compactLayoutMinimumAccountCount: 1, minimumCollapsedHealthyRowCount: 1)
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
}
