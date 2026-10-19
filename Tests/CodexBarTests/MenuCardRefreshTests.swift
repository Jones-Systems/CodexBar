import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct MenuCardRefreshTests {
    private static func makeModel(
        provider: UsageProvider,
        snapshot: UsageSnapshot?,
        isRefreshing: Bool,
        now: Date) throws -> UsageMenuCardView.Model
    {
        let metadata = try #require(ProviderDefaults.metadata[provider])
        return UsageMenuCardView.Model.make(.init(
            provider: provider,
            metadata: metadata,
            snapshot: snapshot,
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: nil),
            isRefreshing: isRefreshing,
            lastError: nil,
            usageBarsShowUsed: false,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            now: now))
    }

    @MainActor
    @Test
    func `live subtitle requires the hosted layout and account identity`() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var placeholder = try Self.makeModel(provider: .codex, snapshot: nil, isRefreshing: false, now: now)
        placeholder.accountIdentityFingerprint = "selected-account"
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 21, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: now)
        var resolved = try Self.makeModel(provider: .codex, snapshot: snapshot, isRefreshing: false, now: now)
        resolved.accountIdentityFingerprint = "selected-account"
        let monitor = MenuCardRefreshMonitor(resolveModel: { _ in resolved }, isProviderRefreshActive: { _ in false })
        let fallback = MenuCardLiveSubtitle(text: "Hosted subtitle", style: .info)

        #expect(placeholder.metrics.isEmpty)
        #expect(!resolved.metrics.isEmpty)
        #expect(monitor.subtitle(for: .codex, hostedModel: placeholder, fallback: fallback).text == fallback.text)
        #expect(monitor.subtitle(for: .codex, hostedModel: resolved, fallback: fallback).text == resolved.subtitleText)

        var otherAccount = resolved
        otherAccount.accountIdentityFingerprint = "other-account"
        #expect(monitor.subtitle(for: .codex, hostedModel: otherAccount, fallback: fallback).text == fallback.text)

        monitor.beginManualRefresh(frozenModels: [.codex: placeholder], provider: .codex)
        #expect(monitor.subtitle(for: .codex, hostedModel: placeholder, fallback: fallback).text == "Refreshing…")
        monitor.endManualRefresh(for: .codex)
    }

    @Test
    func `background refresh keeps quota timing current`() throws {
        let updatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        for provider in [UsageProvider.claude, .codex] {
            let snapshot = UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 21,
                    windowMinutes: 300,
                    resetsAt: updatedAt.addingTimeInterval(4 * 60 * 60 + 40 * 60),
                    resetDescription: nil),
                secondary: nil,
                updatedAt: updatedAt,
                identity: ProviderIdentitySnapshot(
                    providerID: provider.instanceID,
                    accountEmail: nil,
                    accountOrganization: nil,
                    loginMethod: "Pro"))
            let completedModel = try Self.makeModel(
                provider: provider,
                snapshot: snapshot,
                isRefreshing: false,
                now: updatedAt)
            let refreshingModel = try Self.makeModel(
                provider: provider,
                snapshot: snapshot,
                isRefreshing: true,
                now: updatedAt.addingTimeInterval(10 * 60))

            let completedMetric = try #require(completedModel.metrics.first)
            let refreshingMetric = try #require(refreshingModel.metrics.first)
            #expect(refreshingModel.subtitleText == "Refreshing…")
            #expect(refreshingMetric.percentLabel == completedMetric.percentLabel)
            #expect(completedMetric.resetText == "Resets in 4h 40m")
            #expect(refreshingMetric.resetText == "Resets in 4h 30m")
            #expect(refreshingMetric.detailLeftText != completedMetric.detailLeftText)
            #expect(refreshingMetric.detailRightText != completedMetric.detailRightText)
            #expect(refreshingMetric.pacePercent != completedMetric.pacePercent)
        }
    }
}
