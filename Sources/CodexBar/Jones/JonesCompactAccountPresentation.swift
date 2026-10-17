import CodexBarCore

enum JonesCompactAccountPresentation {
    static func plan(
        for provider: UsageProvider,
        accounts: [ProviderAccountUsageSnapshot],
        expandedAccountIDs: Set<ProviderAccountIdentity> = [],
        collapsedAccountIDs: Set<ProviderAccountIdentity> = [],
        healthyTailExpanded: Bool = false) -> AccountMenuLayoutPlanner.Plan
    {
        // Provider-specific by design: Codex uses toggles at every count and folds eligible overflow above five total.
        let isCodex = provider == .codex
        return AccountMenuLayoutPlanner.plan(
            accounts: accounts,
            expandedAccountIDs: expandedAccountIDs,
            healthyTailExpanded: healthyTailExpanded,
            collapsedAccountIDs: collapsedAccountIDs,
            minimumVisibleAccountCount: isCodex ? 5 : 0,
            policy: isCodex
                ? .init(compactLayoutMinimumAccountCount: 1, minimumCollapsedHealthyRowCount: 1)
                : .init())
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
