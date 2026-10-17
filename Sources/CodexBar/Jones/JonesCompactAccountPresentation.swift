import CodexBarCore

enum JonesCompactAccountPresentation {
    static func plan(
        for provider: UsageProvider,
        accounts: [ProviderAccountUsageSnapshot],
        expandedAccountIDs: Set<ProviderAccountIdentity> = [],
        collapsedAccountIDs: Set<ProviderAccountIdentity> = [],
        healthyTailExpanded: Bool = false) -> AccountMenuLayoutPlanner.Plan
    {
        AccountMenuLayoutPlanner.plan(
            accounts: accounts,
            expandedAccountIDs: expandedAccountIDs,
            healthyTailExpanded: healthyTailExpanded,
            collapsedAccountIDs: collapsedAccountIDs,
            minimumVisibleAccountCount: provider == .codex ? 5 : 0)
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
