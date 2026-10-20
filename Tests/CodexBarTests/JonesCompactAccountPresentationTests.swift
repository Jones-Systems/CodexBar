import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct JonesCompactAccountPresentationTests {
    private static let detailNow = Date(timeIntervalSince1970: 1_781_726_400)

    private static func detailAccount(
        weekly: RateWindow?,
        credits: [CodexRateLimitResetCredit] = [],
        error: String? = nil,
        hasSnapshot: Bool = true) -> ProviderAccountUsageSnapshot
    {
        ProviderAccountUsageSnapshot(
            id: ProviderAccountIdentity(source: "codex-account", opaqueID: "synthetic-details"),
            provider: .codex,
            displayLabel: "Friendly account",
            isActive: false,
            snapshot: hasSnapshot ? UsageSnapshot(
                primary: RateWindow(usedPercent: 10, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
                secondary: weekly,
                codexResetCredits: CodexRateLimitResetCreditsSnapshot(
                    credits: credits, availableCount: 99, updatedAt: self.detailNow),
                updatedAt: self.detailNow) : nil,
            error: error,
            sourceLabel: "synthetic")
    }

    private static func resetCredit(
        id: String,
        expiresIn: TimeInterval?,
        status: CodexRateLimitResetCreditStatus = .available) -> CodexRateLimitResetCredit
    {
        CodexRateLimitResetCredit(
            id: id,
            resetType: "weekly",
            status: status,
            grantedAt: self.detailNow.addingTimeInterval(-86400),
            expiresAt: expiresIn.map { Self.detailNow.addingTimeInterval($0) },
            redeemStartedAt: nil,
            redeemedAt: nil,
            title: nil,
            description: nil)
    }

    @Test(arguments: [10.0, 95.0])
    func `healthy and constrained Codex rows retain weekly remaining and reset`(usedPercent: Double) throws {
        let weekly = RateWindow(
            usedPercent: usedPercent,
            windowMinutes: 10080,
            resetsAt: Self.detailNow.addingTimeInterval(399_600),
            resetDescription: nil)
        let account = Self.detailAccount(weekly: weekly)
        let detail = JonesCompactAccountPresentation.codexRowDetail(
            account: account, resetStyle: .countdown, now: Self.detailNow)
        let reset = try #require(UsageFormatter.resetLine(for: weekly, style: .countdown, now: Self.detailNow))

        #expect(detail.text == "Weekly \(Int(100 - usedPercent))% left · \(reset)")
        #expect(detail.text?.contains("4d 15h") == true)
        #expect(detail.trailingDetail == nil)
    }

    @Test
    func `weekly absolute style leaves banked expiry as a countdown`() throws {
        let weekly = RateWindow(
            usedPercent: 25,
            windowMinutes: 10080,
            resetsAt: Self.detailNow.addingTimeInterval(399_600),
            resetDescription: nil)
        let account = Self.detailAccount(
            weekly: weekly,
            credits: [Self.resetCredit(id: "banked", expiresIn: 172_800)])
        let detail = JonesCompactAccountPresentation.codexRowDetail(
            account: account, resetStyle: .absolute, now: Self.detailNow)
        let reset = try #require(UsageFormatter.resetLine(for: weekly, style: .absolute, now: Self.detailNow))

        #expect(detail.text == "Weekly 75% left · \(reset)")
        #expect(detail.trailingDetail?.text == "2d")
        #expect(detail.trailingDetail?.count == 1)
    }

    @Test
    func `banked expiry selects nearest available date and counts available inventory`() {
        let account = Self.detailAccount(
            weekly: nil,
            credits: [
                Self.resetCredit(id: "undated", expiresIn: nil),
                Self.resetCredit(id: "later", expiresIn: 259_200),
                Self.resetCredit(id: "redeemed", expiresIn: 60, status: .redeemed),
                Self.resetCredit(id: "expired", expiresIn: -1),
                Self.resetCredit(id: "at-now", expiresIn: 0),
                Self.resetCredit(id: "nearest", expiresIn: 86400),
            ])
        let detail = JonesCompactAccountPresentation.codexRowDetail(
            account: account, resetStyle: .countdown, now: Self.detailNow)

        #expect(detail.text == nil)
        #expect(detail.trailingDetail?.text == "1d")
        #expect(detail.trailingDetail?.count == 3)
        #expect(detail.trailingDetail?.accessibilityLabel == "Limit Reset Credits, 3 available, Expires in 1d")
    }

    @Test
    func `expired and undated inventory never invent a banked expiry`() {
        for credits in [
            [Self.resetCredit(id: "expired", expiresIn: -1)],
            [Self.resetCredit(id: "at-now", expiresIn: 0)],
            [Self.resetCredit(id: "undated", expiresIn: nil)],
            [],
        ] {
            let detail = JonesCompactAccountPresentation.codexRowDetail(
                account: Self.detailAccount(weekly: nil, credits: credits),
                resetStyle: .countdown,
                now: Self.detailNow)
            #expect(detail.trailingDetail == nil)
        }
    }

    @Test
    func `weekly missing date omits reset and missing usage or errors add no detail`() {
        let weekly = RateWindow(
            usedPercent: 20,
            windowMinutes: 10080,
            resetsAt: nil,
            resetDescription: "in 4d")
        let undated = JonesCompactAccountPresentation.codexRowDetail(
            account: Self.detailAccount(weekly: weekly), resetStyle: .countdown, now: Self.detailNow)
        #expect(undated.text == "Weekly 80% left")
        for account in [
            Self.detailAccount(weekly: nil),
            Self.detailAccount(weekly: weekly, error: "Needs re-auth"),
            Self.detailAccount(weekly: weekly, hasSnapshot: false),
        ] {
            let detail = JonesCompactAccountPresentation.codexRowDetail(
                account: account, resetStyle: .countdown, now: Self.detailNow)
            #expect(detail.text == nil)
            #expect(detail.trailingDetail == nil)
        }
    }

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

    private func activeCompactIDs(in plan: AccountMenuLayoutPlanner.Plan) -> [ProviderAccountIdentity] {
        plan.rows.compactMap { row in
            if case let .compact(compact) = row, compact.isActive { return compact.accountID }
            return nil
        }
    }

    @Test(arguments: [0, 1, 2, 3, 4, 5, 6, 8, 9, 12])
    func `Codex initially shows every account collapsed without a healthy tail fold`(count: Int) {
        let accounts = self.accounts(count: count)
        let codex = JonesCompactAccountPresentation.plan(for: .codex, accounts: accounts)
        #expect(codex.usesCompactLayout == (count > 0))
        #expect(self.accountIDs(in: codex).count == count)
        if count == 0 {
            #expect(codex.rows.isEmpty)
            return
        }
        #expect(!codex.rows.contains { if case .card = $0 { true } else { false } })
        #expect(self.activeCompactIDs(in: codex) == [accounts[0].id])
        #expect(codex.rows.count == count)
        #expect(!codex.rows.contains { if case .collapsedHealthy = $0 { true } else { false } })
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
        #expect(!plan.rows.contains { if case .card = $0 { true } else { false } })
        #expect(self.activeCompactIDs(in: plan) == [switched[2].id])
        #expect(self.accountIDs(in: plan) == switched.map(\.id))

        let removed = Array(switched.dropFirst())
        let afterRemoval = JonesCompactAccountPresentation.plan(
            for: .codex,
            accounts: removed,
            expandedAccountIDs: expandedIDs,
            collapsedAccountIDs: collapsedIDs)
        #expect(!self.accountIDs(in: afterRemoval).contains(original[0].id))
        #expect(self.accountIDs(in: afterRemoval) == removed.map(\.id))
        #expect(self.activeCompactIDs(in: afterRemoval) == [switched[2].id])
    }

    @Test(arguments: [6, 8, 9, 12])
    func `Codex healthy tail expansion does not change the complete account list`(count: Int) {
        let accounts = self.accounts(count: count)
        let initial = JonesCompactAccountPresentation.plan(for: .codex, accounts: accounts)
        #expect(self.accountIDs(in: initial).count == count)
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
        #expect(!reopened.rows.contains { if case .card = $0 { true } else { false } })
        #expect(self.accountIDs(in: reopened) == accounts.map(\.id))
        #expect(!JonesCompactAccountPresentation.resetIfIdle(
            hasOpenMenus: false,
            expandedAccountIDs: &expandedIDs,
            collapsedAccountIDs: &collapsedIDs,
            expandedHealthyTailProviders: &expandedProviders))
    }

    @Test(arguments: [0, 2, 4])
    func `Codex keeps the caller's account order regardless of active account or headroom`(activeIndex: Int) {
        // Synthetic usage rises with index, so headroom sorting would reverse this order.
        let accounts = self.accounts(count: 5, activeIndex: activeIndex)
        let plan = JonesCompactAccountPresentation.plan(for: .codex, accounts: accounts)
        #expect(self.accountIDs(in: plan) == accounts.map(\.id))
        #expect(self.activeCompactIDs(in: plan) == [accounts[activeIndex].id])

        let expanded = JonesCompactAccountPresentation.plan(
            for: .codex,
            accounts: accounts,
            expandedAccountIDs: [accounts[activeIndex].id])
        #expect(self.accountIDs(in: expanded) == accounts.map(\.id))
        #expect(expanded.rows[activeIndex] == .card(accounts[activeIndex].id))
    }

    @Test
    func `Overview keeps Codex order and leaves the active account to the provider summary row`() {
        let accounts = self.accounts(count: 5, activeIndex: 2)
        let plan = AccountMenuLayoutPlanner.plan(
            accounts: accounts,
            healthyTailExpanded: true,
            policy: JonesCompactAccountPresentation.overviewPolicy(for: .codex))
        #expect(self.accountIDs(in: plan) == accounts.map(\.id))
        #expect(plan.rows[2] == .card(accounts[2].id))
        #expect(JonesCompactAccountPresentation.overviewPolicy(for: .claude) ==
            .init(compactLayoutMinimumAccountCount: 1))
    }

    @Test
    func `Codex never hides constrained error or unknown usage rows`() {
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
