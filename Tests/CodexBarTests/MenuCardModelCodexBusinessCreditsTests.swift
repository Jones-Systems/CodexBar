import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct MenuCardModelCodexBusinessCreditsTests {
    @Test
    func `codex business override card shows monthly credit instead of limits unavailable`() throws {
        let now = Date()
        let metadata = try #require(ProviderDefaults.metadata[.codex])
        let identity = ProviderIdentitySnapshot(
            providerID: .codex,
            accountEmail: "biz@example.com",
            accountOrganization: "Team",
            loginMethod: "business")
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: nil,
            tertiary: nil,
            updatedAt: now,
            identity: identity)
        let credits = CreditsSnapshot(
            remaining: 0,
            events: [],
            updatedAt: now,
            codexCreditLimit: CodexCreditLimitSnapshot(
                used: 27,
                limit: 1000,
                remainingPercent: 73,
                resetsAt: nil,
                updatedAt: now))
        let projection = CodexConsumerProjection.make(
            surface: .overrideCard,
            context: CodexConsumerProjection.Context(
                snapshot: snapshot,
                rawUsageError: nil,
                liveCredits: credits,
                rawCreditsError: nil,
                liveDashboard: nil,
                rawDashboardError: nil,
                dashboardAttachmentAuthorized: false,
                dashboardRequiresLogin: false,
                now: now))

        let model = UsageMenuCardView.Model.make(.init(
            provider: .codex,
            metadata: metadata,
            snapshot: snapshot,
            codexProjection: projection,
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: "biz@example.com", plan: "business"),
            isRefreshing: false,
            lastError: UsageError.noRateLimitsFound.errorDescription,
            usageBarsShowUsed: true,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            now: now))

        let monthly = try #require(model.metrics.first { $0.id == "monthly" })
        #expect(model.placeholder == nil)
        #expect(monthly.title == "Monthly credit limit")
        #expect(monthly.percent == 27)
        #expect(model.metrics.count == 1)
        #expect(model.subtitleStyle != .error)
        #expect(model.creditsText == nil)
        #expect(projection.credits == nil)
    }

    @Test
    func `codex business override card hides monthly credit when optional credits are off`() throws {
        let now = Date()
        let metadata = try #require(ProviderDefaults.metadata[.codex])
        let identity = ProviderIdentitySnapshot(
            providerID: .codex,
            accountEmail: "biz@example.com",
            accountOrganization: "Team",
            loginMethod: "business")
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: nil,
            tertiary: nil,
            updatedAt: now,
            identity: identity)
        let credits = CreditsSnapshot(
            remaining: 0,
            events: [],
            updatedAt: now,
            codexCreditLimit: CodexCreditLimitSnapshot(
                used: 27,
                limit: 1000,
                remainingPercent: 73,
                resetsAt: nil,
                updatedAt: now))
        let projection = CodexConsumerProjection.make(
            surface: .overrideCard,
            context: CodexConsumerProjection.Context(
                snapshot: snapshot,
                rawUsageError: nil,
                liveCredits: credits,
                rawCreditsError: nil,
                liveDashboard: nil,
                rawDashboardError: nil,
                dashboardAttachmentAuthorized: false,
                dashboardRequiresLogin: false,
                now: now))

        let model = UsageMenuCardView.Model.make(.init(
            provider: .codex,
            metadata: metadata,
            snapshot: snapshot,
            codexProjection: projection,
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: "biz@example.com", plan: "business"),
            isRefreshing: false,
            lastError: UsageError.noRateLimitsFound.errorDescription,
            usageBarsShowUsed: true,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: false,
            hidePersonalInfo: false,
            now: now))

        #expect(model.metrics.contains { $0.id == "monthly" } == false)
        #expect(model.metrics.isEmpty)
        #expect(model.placeholder == "Limits not available")
    }

    @Test(arguments: [true, false], [true, false])
    func `account balance follows optional credits setting without duplicating monthly cap`(
        hasMonthlyLimit: Bool,
        showOptionalCredits: Bool) throws
    {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let metadata = try #require(ProviderDefaults.metadata[.codex])
        let snapshot = UsageSnapshot(
            primary: hasMonthlyLimit ? nil : RateWindow(
                usedPercent: 20,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(3600),
                resetDescription: nil),
            secondary: nil,
            updatedAt: now)
        let credits = CreditsSnapshot(
            remaining: 12345.67,
            events: [],
            updatedAt: now,
            codexCreditLimit: hasMonthlyLimit ? CodexCreditLimitSnapshot(
                used: 27,
                limit: 1000,
                remainingPercent: 73,
                resetsAt: nil,
                updatedAt: now) : nil)
        let projection = CodexConsumerProjection.make(
            surface: .overrideCard,
            context: CodexConsumerProjection.Context(
                snapshot: snapshot,
                rawUsageError: nil,
                liveCredits: credits,
                rawCreditsError: nil,
                liveDashboard: nil,
                rawDashboardError: nil,
                dashboardAttachmentAuthorized: false,
                dashboardRequiresLogin: false,
                now: now,
                showOptionalCreditsAndExtraUsage: showOptionalCredits))
        let model = UsageMenuCardView.Model.make(.init(
            provider: .codex,
            metadata: metadata,
            snapshot: snapshot,
            codexProjection: projection,
            credits: projection.credits?.snapshot,
            creditsError: projection.credits?.userFacingError,
            dashboard: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: "account-a@example.com", plan: hasMonthlyLimit ? "business" : "pro"),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: true,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: showOptionalCredits,
            hidePersonalInfo: false,
            now: now))

        #expect(model.creditsText == (showOptionalCredits ? UsageFormatter.creditsString(from: 12345.67) : nil))
        #expect(model.creditsRemaining == 12345.67)
        #expect(model.creditsProgressPercent == nil)
        #expect(model.creditsScaleText == nil)
        #expect(model.creditsHintText == nil)
        #expect(model.metrics.count(where: { $0.id == "monthly" }) == (hasMonthlyLimit && showOptionalCredits ? 1 : 0))
    }

    @Test(arguments: [0.0, 12345.67])
    func `codex balance presentation uses an inline extra usage row`(balance: Double) throws {
        let presentation = try #require(CodexAccountBalancePresentation.make(
            provider: .codex,
            creditsRemaining: balance,
            progressPercent: nil))

        #expect(presentation.title == "Extra usage")
        #expect(presentation.balanceLine == "Balance: \(UsageFormatter.creditsNumberString(from: balance))")
        #expect(!presentation.balanceLine.contains("tokens"))
        #expect(!presentation.balanceLine.contains("left"))
    }

    @Test
    func `codex balance presentation leaves metered missing and other provider credits unchanged`() {
        #expect(CodexAccountBalancePresentation.make(
            provider: .codex,
            creditsRemaining: 12345.67,
            progressPercent: 73) == nil)
        #expect(CodexAccountBalancePresentation.make(
            provider: .codex,
            creditsRemaining: nil,
            progressPercent: nil) == nil)
        #expect(CodexAccountBalancePresentation.make(
            provider: .claude,
            creditsRemaining: 12345.67,
            progressPercent: nil) == nil)
    }
}
