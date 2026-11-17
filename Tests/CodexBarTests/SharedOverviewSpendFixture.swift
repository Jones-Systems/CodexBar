import Foundation
@testable import CodexBar
@testable import CodexBarCore

enum SharedOverviewSpendFixture {
    static let now = Date(timeIntervalSince1970: 1_787_011_200)
    static func make(historyDays: Int = 30, established: Bool = true) throws -> (
        model: SpendDashboardModel, summary: OverviewSpendSummary, counts: (total: Int, cost: Int, tokens: Int))
    {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let report = CostUsageDailyReport(data: [.init(
            date: "2026-08-18",
            inputTokens: 600,
            outputTokens: 400,
            totalTokens: 1000,
            costUSD: 12,
            modelsUsed: ["fixture-model"],
            modelBreakdowns: nil)], summary: nil)
        let snapshot = CostUsageFetcher.tokenSnapshot(
            from: report,
            now: self.now,
            historyDays: historyDays,
            calendar: calendar,
            historyCoverageIsEstablished: established,
            costProvenance: .listPriceEstimate)
        let publication = SpendDashboardPublication(
            revision: 1,
            generation: 1,
            configuration: nil,
            loadedAt: self.now,
            isRefreshing: false,
            inputs: [.init(provider: .codex, displayName: "Codex", snapshot: snapshot)],
            sources: [
                .init(id: "codex", provider: .codex, displayName: "Codex", role: .subscription, state: .available),
                .init(id: "claude", provider: .claude, displayName: "Claude", role: .subscription, state: .unavailable),
            ])
        let scope: Set<UsageProvider> = [.codex, .claude]
        let model = publication.model(
            requestedDays: 30, now: self.now, calendar: calendar, preferredCurrencyCode: "USD", providerScope: scope)
        let counts = (
            total: publication.subscriptionCount(providerScope: scope),
            cost: publication.knownCostSubscriptionCount(model: model, providerScope: scope),
            tokens: publication.knownTokenSubscriptionCount(model: model, providerScope: scope))
        let summary = OverviewSpendSummary(
            model: model,
            providerCount: counts.total,
            knownCostProviderCount: counts.cost,
            knownTokenProviderCount: counts.tokens)
        return (model, summary, counts)
    }
}
