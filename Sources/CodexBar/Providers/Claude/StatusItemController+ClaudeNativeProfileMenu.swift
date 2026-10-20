import AppKit
import CodexBarCore

extension StatusItemController {
    func addClaudeNativeProfileMenuCards(to menu: NSMenu, captureMenu: NSMenu, context: MenuCardContext) {
        let accounts = self.store.claudeNativeProfileAccountsForDisplay()
        self.addCompactAccountMenuRows(
            CompactAccountMenuRendering(
                plan: self.compactAccountPlan(for: .claude, accounts: accounts),
                accounts: accounts,
                idPrefix: "claudeNativeProfile",
                cardModel: { [weak self] account in self?.claudeNativeProfileCardModel(for: account) },
                refreshingAccountIDs: Set(accounts.filter {
                    self.store.claudeNativeProfileRefreshingAliases.contains($0.id.opaqueID)
                }.map(\.id)),
                accountStatusText: Dictionary(uniqueKeysWithValues: accounts.compactMap { account in
                    account.error.map { (account.id, $0) }
                })),
            to: menu,
            captureMenu: captureMenu,
            context: context)
    }

    func claudeNativeProfileCardModel(for account: ProviderAccountUsageSnapshot) -> UsageMenuCardView.Model? {
        self.menuCardModel(
            for: .claude,
            snapshotOverride: account.snapshot,
            errorOverride: account.error,
            forceOverrideCard: true,
            accountOverride: AccountInfo(email: account.accountEmail, plan: nil),
            accountDisplayLabelOverride: account.displayLabel,
            sourceLabelOverride: account.sourceLabel,
            isRefreshingOverride: account.snapshot == nil &&
                (self.store.claudeNativeProfileRefreshingAliases.contains(account.id.opaqueID)
                    || (account.isActive && self.store.shouldShowRefreshingMenuCardIndicator(for: .claude))))
    }
}
