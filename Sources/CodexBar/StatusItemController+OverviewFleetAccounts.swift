import AppKit
import CodexBarCore

extension StatusItemController {
    struct OverviewFleetAccountRow {
        let accountID: ProviderAccountIdentity
        let model: MenuCardCompactAccountRowView.Model
    }

    func overviewFleetAccounts(for provider: UsageProvider) -> [ProviderAccountUsageSnapshot] {
        switch provider {
        case .codex:
            guard let display = self.codexAccountMenuDisplay(for: provider) else { return [] }
            let overviewDisplay = CodexAccountMenuDisplay(
                accounts: display.accounts,
                snapshots: self.codexAccountSnapshots(matching: display.accounts),
                activeVisibleAccountID: display.activeVisibleAccountID,
                layout: display.layout)
            return Self.projectedCodexAccounts(
                display: overviewDisplay,
                includeOptionalCredits: self.settings.showOptionalCreditsAndExtraUsage,
                displayLabels: self.settings.codexAccountDisplayLabels(for: display.accounts))
        case .claude:
            return self.store.claudeNativeProfileAccountsForDisplay()
        default:
            return []
        }
    }

    func overviewFleetAccountRows(
        for provider: UsageProvider,
        now: Date = Date()) -> [OverviewFleetAccountRow]
    {
        let accounts = self.overviewFleetAccounts(for: provider)
        let codexDetails = provider == .codex ? Self.compactCodexRowDetails(
            accounts: accounts,
            resetStyle: self.settings.resetTimeDisplayStyle,
            now: now) : [:]
        let plan = AccountMenuLayoutPlanner.plan(
            accounts: accounts,
            healthyTailExpanded: true,
            policy: JonesCompactAccountPresentation.overviewPolicy(for: provider))
        return plan.rows.compactMap { row in
            guard case let .compact(compact) = row else { return nil }
            var model = MenuCardCompactAccountRowView.Model(
                label: PersonalInfoRedactor.redactEmail(compact.label, isEnabled: self.settings.hidePersonalInfo),
                headroomPercent: compact.headroomPercent,
                severity: compact.severity,
                constraintDetail: codexDetails[compact.accountID]?.text ?? compact.constraintDetail,
                hasError: compact.hasError,
                showsBestBadge: compact.isBestCandidate,
                isActiveAccount: compact.isActive,
                trailingDetail: codexDetails[compact.accountID]?.trailingDetail)
            if provider == .claude, compact.headroomPercent == nil {
                model.isRefreshing = self.store.claudeNativeProfileRefreshingAliases
                    .contains(compact.accountID.opaqueID)
            }
            return OverviewFleetAccountRow(accountID: compact.accountID, model: model)
        }
    }

    func addOverviewFleetAccountRows(
        for provider: UsageProvider,
        to menu: NSMenu,
        captureMenu: NSMenu,
        width: CGFloat)
    {
        for row in self.overviewFleetAccountRows(for: provider) {
            let identifier = "overviewAccount-\(provider.rawValue)-\(row.accountID.opaqueID)"
            menu.addItem(self.makeMenuCardItem(
                MenuCardCompactAccountRowView(
                    model: row.model,
                    progressColor: UsageMenuCardView.Model.progressColor(for: provider),
                    width: width),
                id: identifier,
                width: width,
                heightCacheScope: identifier,
                heightCacheFingerprint: row.model.heightFingerprint,
                onClick: { [weak self, weak captureMenu] in
                    guard let self, let captureMenu else { return }
                    self.selectOverviewFleetAccount(row.accountID, provider: provider, menu: captureMenu)
                }))
        }
    }

    func selectOverviewFleetAccount(
        _ accountID: ProviderAccountIdentity,
        provider: UsageProvider,
        menu: NSMenu)
    {
        JonesCompactAccountPresentation.setExpanded(
            true,
            accountID: accountID,
            expandedAccountIDs: &self.compactAccountExpandedIDs,
            collapsedAccountIDs: &self.compactAccountCollapsedIDs)
        self.selectOverviewProvider(provider, menu: menu)
    }
}
