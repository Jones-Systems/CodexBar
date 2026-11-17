import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct SpendDashboardTokenProvenanceTests {
    @Test
    func `direct token scan rejects stale config completion`() async {
        let (settings, store) = Self.makeStore(provider: .claude)
        settings.updateProviderConfig(provider: .claude) { $0.apiKey = "fixture-first" }
        let gate = SpendDashboardProvenanceGate()
        store._test_tokenUsageSnapshotLoaderOverride = { _, _, _, _, _ in
            let call = await gate.enter()
            return Self.tokenSnapshot(cost: call == 1 ? 1 : 2)
        }

        let refresh = Task { @MainActor in
            await store.refreshTokenUsageNow(for: .claude, force: true)
        }
        await gate.waitForCalls(1)
        settings.updateProviderConfig(provider: .claude) { $0.apiKey = "fixture-replacement" }
        await gate.releaseFirst()
        await refresh.value
        await gate.waitForCalls(2)
        await Self.waitUntil {
            store.tokenSnapshotForCurrentProviderConfig(for: .claude)?.snapshot.last30DaysCostUSD == 2
        }

        #expect(store.tokenSnapshotForCurrentProviderConfig(for: .claude)?.snapshot.last30DaysCostUSD == 2)
        #expect(store.tokenSnapshotPublicationRevision(for: .claude) == 1)
    }

    @Test
    func `direct token scan rejects completion across disable and reenable epoch`() async {
        let (settings, store) = Self.makeStore(provider: .claude)
        let gate = SpendDashboardProvenanceGate()
        store._test_tokenUsageSnapshotLoaderOverride = { _, _, _, _, _ in
            let call = await gate.enter()
            return Self.tokenSnapshot(cost: call == 1 ? 1 : 2)
        }

        let refresh = Task { @MainActor in
            await store.refreshTokenUsageNow(for: .claude, force: true)
        }
        await gate.waitForCalls(1)
        settings.costUsageEnabled = false
        settings.costUsageEnabled = true
        await gate.releaseFirst()
        await refresh.value
        await gate.waitForCalls(2)
        await Self.waitUntil {
            store.tokenSnapshotForCurrentProviderConfig(for: .claude)?.snapshot.last30DaysCostUSD == 2
        }

        #expect(store.tokenSnapshotForCurrentProviderConfig(for: .claude)?.snapshot.last30DaysCostUSD == 2)
        #expect(store.tokenSnapshotPublicationRevision(for: .claude) == 1)
    }

    @Test
    func `direct token scan refreshes changed provider config within ttl`() async {
        let (settings, store) = Self.makeStore(provider: .claude)
        settings.updateProviderConfig(provider: .claude) { $0.apiKey = "fixture-first" }
        var loadCount = 0
        store._test_tokenUsageSnapshotLoaderOverride = { _, _, _, _, _ in
            loadCount += 1
            return Self.tokenSnapshot(cost: Double(loadCount))
        }

        await store.refreshTokenUsageNow(for: .claude, force: true)
        #expect(store.tokenSnapshotForCurrentProviderConfig(for: .claude)?.snapshot.last30DaysCostUSD == 1)

        settings.updateProviderConfig(provider: .claude) { $0.apiKey = "fixture-replacement" }
        await store.refreshTokenUsageNow(for: .claude, force: false)

        #expect(loadCount == 2)
        #expect(store.tokenSnapshotForCurrentProviderConfig(for: .claude)?.snapshot.last30DaysCostUSD == 2)
        #expect(store.tokenSnapshotPublicationRevision(for: .claude) == 2)
    }

    @Test(arguments: Self.monthBoundaryDates)
    func `forced successful empty publication removes prior spend without warning`(now: Date) async {
        let (settings, store) = Self.makeStore(provider: .claude)
        var loadCount = 0
        store._test_tokenUsageSnapshotLoaderOverride = { _, _, _, _, _ in
            loadCount += 1
            return loadCount <= 2 ? Self.tokenSnapshot(cost: 4) : Self.emptyTokenSnapshot()
        }
        await store.refreshTokenUsageNow(for: .claude, force: true)
        await store.refreshSpendDashboardTokenUsageNow(for: .claude, force: true)
        let controller = Self.dashboardController(settings: settings, store: store, now: now)
        controller.update(configuration: SpendDashboardSource.configuration(settings: settings, store: store))
        await Self.waitUntil { !controller.isRefreshing }
        #expect(controller.model.groups.first?.totalCost == 4)

        controller.refresh()
        await Self.waitUntil { !controller.isRefreshing }

        #expect(loadCount == 3)
        #expect(controller.model.groups.isEmpty)
        #expect(controller.failedSourceCount == 0)
        #expect(store.tokenSnapshot(for: .claude)?.last30DaysCostUSD == 4)
        let publication = store.spendDashboardTokenSnapshotPublicationForCurrentConfig(for: .claude)
        #expect(publication?.snapshot == nil)
        #expect(publication?.publicationRevision == 2)
    }

    @Test
    func `first open accepts current independent empty publication without redundant refresh`() async {
        let (settings, store) = Self.makeStore(provider: .claude)
        var loadCount = 0
        store._test_tokenUsageSnapshotLoaderOverride = { _, _, _, _, _ in
            loadCount += 1
            return Self.emptyTokenSnapshot()
        }
        await store.refreshTokenUsageNow(for: .claude, force: true)
        await store.refreshSpendDashboardTokenUsageNow(for: .claude, force: true)
        let publicationRevision = store.tokenSnapshotPublicationRevision(for: .claude)
        let controller = Self.dashboardController(settings: settings, store: store, now: Self.fixtureNow)

        controller.update(configuration: SpendDashboardSource.configuration(settings: settings, store: store))
        await Self.waitUntil { !controller.isRefreshing }

        #expect(loadCount == 2)
        #expect(controller.model.groups.isEmpty)
        #expect(controller.failedSourceCount == 0)
        #expect(store.tokenSnapshotPublicationRevision(for: .claude) == publicationRevision)
    }

    @Test
    func `widget does not project raw provider cost without current provenance`() async throws {
        let (_, store) = Self.makeStore(provider: .claude)
        store._setSnapshotForTesting(Self.rawUsage(cost: 8), provider: .claude)
        var savedSnapshots: [WidgetSnapshot] = []
        store._test_widgetSnapshotSaveOverride = { savedSnapshots.append($0) }

        store.persistWidgetSnapshot(reason: "provenance-test")
        await store.widgetSnapshotPersistTask?.value

        let entry = try #require(savedSnapshots.last?.entries.first { $0.provider == .claude })
        #expect(entry.tokenUsage == nil)
        #expect(entry.dailyUsage.isEmpty)
    }

    @Test
    func `token publication counter remains monotonic across clear and identical republish`() {
        let (_, store) = Self.makeStore(provider: .claude)
        let snapshot = Self.tokenSnapshot(cost: 9)
        store._setTokenSnapshotForTesting(snapshot, provider: .claude)
        let firstRevision = store.tokenSnapshotPublicationRevision(for: .claude)

        store._setTokenSnapshotForTesting(nil, provider: .claude)
        store._setTokenSnapshotForTesting(snapshot, provider: .claude)

        #expect(store.tokenSnapshotPublicationRevision(for: .claude) > firstRevision)
        #expect(store.tokenSnapshotForCurrentProviderConfig(for: .claude)?.snapshot == snapshot)
    }

    private static let fixtureNow = Date(timeIntervalSince1970: 1_784_179_200)
    private nonisolated static let monthBoundaryDates = [
        Date(timeIntervalSince1970: 1_785_542_399), // 2026-07-31 23:59:59 UTC
        Date(timeIntervalSince1970: 1_785_542_400), // 2026-08-01 00:00:00 UTC
    ]

    private static func dashboardController(
        settings: SettingsStore,
        store: UsageStore,
        now: Date) -> SpendDashboardController
    {
        SpendDashboardController(
            userDefaults: settings.userDefaults,
            requestBuilder: { mode in
                await SpendDashboardSource.makeRequest(
                    settings: settings,
                    store: store,
                    mode: mode,
                    now: now)
            },
            nowProvider: { now })
    }

    private static func makeStore(provider: UsageProvider) -> (SettingsStore, UsageStore) {
        let settings = testSettingsStore(suiteName: "SpendDashboardTokenProvenanceTests-\(provider.rawValue)")
        settings.costUsageEnabled = true
        for candidate in UsageProvider.allCases {
            guard let metadata = ProviderRegistry.shared.metadata[candidate] else { continue }
            settings.setProviderEnabled(provider: candidate, metadata: metadata, enabled: candidate == provider)
        }
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
        return (settings, store)
    }

    private static func tokenSnapshot(cost: Double) -> CostUsageTokenSnapshot {
        CostUsageTokenSnapshot(
            sessionTokens: 10,
            sessionCostUSD: cost,
            last30DaysTokens: 10,
            last30DaysCostUSD: cost,
            currencyCode: "USD",
            daily: [CostUsageDailyReport.Entry(
                date: "2026-07-16",
                inputTokens: 4,
                outputTokens: 6,
                totalTokens: 10,
                costUSD: cost,
                modelsUsed: nil,
                modelBreakdowns: nil)],
            updatedAt: Date(timeIntervalSince1970: 1_784_203_200))
    }

    private static func emptyTokenSnapshot() -> CostUsageTokenSnapshot {
        CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: 0,
            last30DaysCostUSD: 0,
            daily: [],
            updatedAt: Date(timeIntervalSince1970: 1_784_179_200))
    }

    private static func rawUsage(cost: Double) -> UsageSnapshot {
        UsageSnapshot(
            primary: nil,
            secondary: nil,
            costUsage: self.tokenSnapshot(cost: cost),
            updatedAt: self.fixtureNow)
    }

    private static func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<1000 {
            if condition() {
                return
            }
            await Task.yield()
        }
        Issue.record("Timed out waiting for provenance state")
    }
}

private actor SpendDashboardProvenanceGate {
    private var callCount = 0
    private var firstReleased = false
    private var releaseContinuations: [CheckedContinuation<Void, Never>] = []
    private var callWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func enter() async -> Int {
        self.callCount += 1
        let call = self.callCount
        let ready = self.callWaiters.filter { self.callCount >= $0.count }
        self.callWaiters.removeAll { self.callCount >= $0.count }
        ready.forEach { $0.continuation.resume() }
        if call == 1, !self.firstReleased {
            await withCheckedContinuation { continuation in
                self.releaseContinuations.append(continuation)
            }
        }
        return call
    }

    func waitForCalls(_ count: Int) async {
        if self.callCount >= count {
            return
        }
        await withCheckedContinuation { continuation in
            self.callWaiters.append((count, continuation))
        }
    }

    func releaseFirst() {
        self.firstReleased = true
        let continuations = self.releaseContinuations
        self.releaseContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }
}
