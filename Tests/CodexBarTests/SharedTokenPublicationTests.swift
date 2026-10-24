import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCLI
@testable import CodexBarCore

@MainActor
struct SharedTokenPublicationTests {
    private static let now = Date(timeIntervalSince1970: 1_787_832_000)
    private static var calendar: Calendar { CostUsageBucketTimeZone.calendar(identifier: "UTC") }


    @Test(arguments: [UsageProvider.claude, .codex])
    func `regular unavailable handling preserves failure gating and Codex catchup retention`(
        provider: UsageProvider) async throws
    {
        let store = Self.store(provider: provider)
        // Synthetic snapshots exercise the retained publication and unavailable-history paths.
        store._test_tokenUsageSnapshotLoaderOverride = { _, _, _, _, _ in Self.snapshot(available: true) }
        await store.refreshTokenUsageNow(for: provider, force: true)
        let revision = store.tokenSnapshotPublicationRevision(for: provider)
        store._test_tokenUsageSnapshotLoaderOverride = { _, _, _, _, _ in Self.snapshot(available: false) }
        await store.refreshTokenUsageNow(for: provider, force: true)
        #expect(store.tokenSnapshotPublicationRevision(for: provider) == revision)
        #expect(store.tokenSnapshot(for: provider)?.last30DaysTokens == 198)
        #expect(store.tokenError(for: provider) == nil)
        #expect(store.tokenFailureGates[provider.instanceID]?.streak == (provider == .codex ? 0 : 1))
        await store.codexCostCatchUpTask?.value
        await store.widgetSnapshotPersistTask?.value
        store._test_tokenUsageSnapshotLoaderOverride = nil
    }


    @Test(arguments: [UsageProvider.claude, .codex])
    func `shared overflow repair preserves missing buckets and other providers`(provider: UsageProvider) {
        let rows = zip(["2026-08-25", "2026-08-26", "2026-08-27"], [Int.max - 1, 2, 7]).map { day, count in
            CostUsageDailyReport.Entry(
                date: day,
                inputTokens: count,
                outputTokens: 1,
                totalTokens: count,
                costUSD: nil,
                modelsUsed: nil,
                modelBreakdowns: nil)
        }
        let snapshot = CostUsageFetcher.tokenSnapshot(
            from: .init(data: rows, summary: nil), now: Self.now, calendar: Self.calendar)
        let summary = snapshot.summary(forLastDays: 30, calendar: Self.calendar)
        #expect(summary.tokenMix.inputTokens == nil)
        #expect(summary.tokenMix.outputTokens == 3)
        #expect(summary.tokenMix.cacheReadTokens == nil)
        let payload = CodexBarCLI.makeCostPayload(
            provider: provider, snapshot: snapshot, error: nil, calendar: Self.calendar)
        #expect(payload.totals?.totalInputTokens == nil)
        #expect(payload.totals?.totalOutputTokens == 3)
    }

    private static func snapshot(available: Bool) -> CostUsageTokenSnapshot {
        CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: available ? 198 : nil,
            last30DaysCostUSD: nil,
            historyCoverageIsEstablished: available,
            daily: available ? [.init(
                date: "2026-08-27", inputTokens: 100, outputTokens: 98,
                totalTokens: 198, costUSD: nil, modelsUsed: nil, modelBreakdowns: nil)] : [],
            updatedAt: self.now)
    }

    private static func store(provider: UsageProvider) -> UsageStore {
        let settings = testSettingsStore(suiteName: "SharedTokenPublicationTests-\(UUID())")
        settings.costUsageEnabled = true
        for candidate in UsageProvider.allCases {
            settings.setProviderEnabled(
                provider: candidate,
                metadata: ProviderDescriptorRegistry.descriptor(for: candidate).metadata,
                enabled: candidate == provider)
        }
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
        store._test_widgetSnapshotSaveOverride = { _ in }
        store._test_codexCostCatchUpStatusOverride = { _ in
            .init(pending: false, progressKey: "isolated")
        }
        return store
    }
}
