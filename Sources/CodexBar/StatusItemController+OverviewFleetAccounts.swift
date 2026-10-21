import AppKit
import CodexBarCore

extension StatusItemController {
    struct OverviewFleetAccountRow {
        let accountID: ProviderAccountIdentity
        let model: MenuCardCompactAccountRowView.Model
    }

    struct OverviewFleetSource {
        let accounts: [ProviderAccountUsageSnapshot]
        let cardModel: (ProviderAccountUsageSnapshot) -> UsageMenuCardView.Model?
        var aggregate: JonesAccountAggregate?
    }

    func overviewFleetSource(for provider: UsageProvider) -> OverviewFleetSource? {
        let now = Date()
        switch provider {
        case .codex:
            guard let display = self.codexAccountMenuDisplay(for: provider) else {
                return OverviewFleetSource(accounts: [], cardModel: { _ in nil })
            }
            let overviewDisplay = CodexAccountMenuDisplay(
                accounts: display.accounts,
                snapshots: self.codexAccountSnapshots(matching: display.accounts),
                activeVisibleAccountID: display.activeVisibleAccountID,
                layout: display.layout)
            let accounts = Self.projectedCodexAccounts(
                display: overviewDisplay,
                includeOptionalCredits: self.settings.showOptionalCreditsAndExtraUsage,
                displayLabels: self.settings.codexAccountDisplayLabels(for: display.accounts))
            return OverviewFleetSource(
                accounts: accounts,
                cardModel: { [weak self] in self?.codexAccountCardModel(for: $0, display: overviewDisplay) },
                aggregate: JonesAccountAggregate.codex(
                    projection: self.settings.codexVisibleAccountProjectionForMenuDisplay,
                    accounts: accounts,
                    now: now,
                    workDays: self.settings.weeklyProgressWorkDays))
        case .claude:
            let accounts = self.store.claudeNativeProfileAccountsForDisplay()
            return OverviewFleetSource(
                accounts: accounts,
                cardModel: { [weak self] in self?.claudeNativeProfileCardModel(for: $0) },
                aggregate: self.claudeNativeProfileAggregate(accounts: accounts, now: now))
        default:
            return nil
        }
    }

    func overviewFleetAccounts(for provider: UsageProvider) -> [ProviderAccountUsageSnapshot] {
        self.overviewFleetSource(for: provider)?.accounts ?? []
    }

    func overviewFleetAccountRows(
        for provider: UsageProvider,
        now: Date = Date()) -> [OverviewFleetAccountRow]
    {
        let accounts = self.overviewFleetAccounts(for: provider)
        let details = Self.compactAccountRowDetails(
            accounts: accounts,
            resetStyle: self.settings.resetTimeDisplayStyle,
            now: now)
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
                constraintDetail: compact.hasError || details[compact.accountID] == nil
                    ? compact.constraintDetail : details[compact.accountID]?.text,
                hasError: compact.hasError,
                showsBestBadge: compact.isBestCandidate,
                isActiveAccount: compact.isActive,
                trailingDetail: details[compact.accountID]?.trailingDetail)
            if provider == .claude, compact.headroomPercent == nil {
                model.isRefreshing = self.store.claudeNativeProfileRefreshingAliases
                    .contains(compact.accountID.opaqueID)
            }
            return OverviewFleetAccountRow(accountID: compact.accountID, model: model)
        }
    }

    func overviewSummaryCompactModel(
        for provider: UsageProvider,
        model: UsageMenuCardView.Model,
        now: Date = Date()) -> MenuCardCompactAccountRowView.Model
    {
        // Provider-specific by design: Codex and Claude resolve cached selected-account labels before redaction.
        let label: String = switch provider {
        case .codex:
            self.selectedCodexAccountDisplayLabel() ?? model.email
        case .claude:
            self.store.selectedClaudeNativeProfileDisplayLabel()
                ?? self.store.claudeNativeProfileAccountsForDisplay().first(where: \.isActive)?.displayLabel
                ?? model.email
        default:
            model.providerName
        }
        return JonesCompactAccountPresentation.overviewSummaryRow(
            .init(
                provider: provider,
                label: PersonalInfoRedactor.redactEmail(label, isEnabled: self.settings.hidePersonalInfo),
                snapshot: model.metrics.isEmpty ? nil : self.store.presentationSnapshot(for: provider),
                hasError: model.subtitleStyle == .error,
                isRefreshing: model.subtitleStyle == .loading),
            resetStyle: self.settings.resetTimeDisplayStyle,
            now: now)
    }

    func addOverviewFleetAccountRows(
        for provider: UsageProvider,
        to menu: NSMenu,
        captureMenu: NSMenu,
        width: CGFloat)
    {
        guard let source = self.overviewFleetSource(for: provider) else { return }
        var previousRowWasCard = false
        for row in self.overviewFleetAccountRows(for: provider) {
            let click: () -> Void = { [weak self, weak captureMenu] in
                guard let self, let captureMenu else { return }
                self.selectOverviewFleetAccount(row.accountID, provider: provider, menu: captureMenu)
            }
            if self.overviewExpansionState.expandedAccountIDs.contains(row.accountID),
               let account = source.accounts.first(where: { $0.id == row.accountID }),
               let model = source.cardModel(account)
            {
                menu.addItem(.separator())
                let identifier = "overviewAccountCard-\(provider.rawValue)-\(row.accountID.opaqueID)"
                menu.addItem(self.makeMenuCardItem(
                    OverviewMenuCardRowView(model: model, storageText: nil, width: width),
                    id: identifier,
                    width: width,
                    heightCacheScope: identifier,
                    heightCacheFingerprint: model.heightFingerprint(section: "overviewAccount"),
                    onClick: click))
                previousRowWasCard = true
            } else {
                if previousRowWasCard { menu.addItem(.separator()) }
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
                    onClick: click))
                previousRowWasCard = false
            }
        }
        if let aggregate = source.aggregate {
            menu.addItem(.separator())
            self.addAccountAggregateRow(
                aggregate,
                to: menu,
                context: AccountAggregateRowContext(
                    id: "overviewAccountAggregate-\(provider.rawValue)",
                    provider: provider,
                    width: width,
                    isExpanded: self.overviewExpansionState.expandedAggregateProviders.contains(provider),
                    onClick: { [weak self, weak captureMenu] in
                        self?.toggleOverviewAccountAggregate(provider: provider, menu: captureMenu)
                    }))
        }
    }

    func toggleOverviewAccountAggregate(provider: UsageProvider, menu: NSMenu?) {
        self.advanceMenuInteraction(for: menu)
        self.overviewExpansionState.toggleAggregate(provider)
        self.invalidateMenus(refreshOpenMenus: true)
    }

    func selectOverviewFleetAccount(
        _ accountID: ProviderAccountIdentity,
        provider: UsageProvider,
        menu: NSMenu)
    {
        self.advanceMenuInteraction(for: menu)
        self.overviewExpansionState.toggleAccount(accountID)
        self.invalidateMenus(refreshOpenMenus: true)
    }

    func activateOverviewRow(_ provider: UsageProvider, menu: NSMenu) {
        guard self.overviewFleetSource(for: provider) != nil else {
            self.selectOverviewProvider(provider, menu: menu)
            return
        }
        self.advanceMenuInteraction(for: menu)
        self.overviewExpansionState.toggleSummary(provider)
        self.invalidateMenus(refreshOpenMenus: true)
    }
}
