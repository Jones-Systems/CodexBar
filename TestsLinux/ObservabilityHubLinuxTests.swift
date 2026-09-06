import Foundation
import Testing
@testable import CodexBarCore

struct ObservabilityHubLinuxTests {
    @Test
    func `missing host telemetry remains unsupported without synthetic zeros`() {
        let hub = ObservabilityHub.aggregate(
            sessions: [CAAMControlFixtures.session()], providers: [], now: CAAMControlFixtures.now)
        #expect(hub.services.count == 1)
        #expect(hub.accounts.count == 2)
        #expect(hub.providers.isEmpty)
        #expect(hub.hosts.first?.evidence.availability == .unsupported)
        #expect(hub.hosts.first?.evidence.observedAt == nil)
        #expect(hub.hosts.first?.cpuPercent == nil)
        #expect(hub.hosts.first?.memoryUsedBytes == nil)
        #expect(hub.work.isEmpty)
    }

    @Test
    func `cost provenance currency window and metered component remain distinct`() throws {
        let cost = Self.cost(provenance: .mixed)
        let usage = UsageSnapshot(
            primary: RateWindow(usedPercent: 25, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil, updatedAt: CAAMControlFixtures.now)
        let input = HubProviderInput(id: "fixture", label: "Fixture", source: "Fixture API", usage: usage, cost: cost)
        let hub = ObservabilityHub.aggregate(sessions: [], providers: [input], now: CAAMControlFixtures.now)
        let provider = try #require(hub.providers.first)
        #expect(provider.primaryUsedPercent == 25)
        #expect(provider.windowMinutes == 300)
        #expect(provider.cost?.amount == 12)
        #expect(provider.cost?.meteredAmount == 3)
        #expect(provider.cost?.currency == "USD")
        #expect(provider.cost?.historyDays == 30)
        #expect(provider.cost?.provenance == .mixed)
        #expect(provider.cost?.evidence.observedAt == CAAMControlFixtures.now)
    }

    @Test
    func `placeholder usage and invalid numeric costs remain unavailable`() {
        let usage = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 0, windowMinutes: 300, resetsAt: nil, resetDescription: nil,
                isSyntheticPlaceholder: true),
            secondary: nil, updatedAt: CAAMControlFixtures.now)
        let cost = CostUsageTokenSnapshot(
            sessionTokens: nil, sessionCostUSD: nil, last30DaysTokens: nil,
            last30DaysCostUSD: .infinity, costProvenance: .unknown, daily: [], updatedAt: CAAMControlFixtures.now)
        let input = HubProviderInput(id: "fixture", label: "Fixture", source: "Fixture", usage: usage, cost: cost)
        let hub = ObservabilityHub.aggregate(sessions: [], providers: [input], now: CAAMControlFixtures.now)
        #expect(hub.providers.first?.primaryUsedPercent == nil)
        #expect(hub.providers.first?.evidence.availability == .partial)
        #expect(hub.providers.first?.cost?.amount == nil)
    }

    @Test
    func `work records are lazy bounded historical and never identify live jobs`() {
        let sessions = (0..<120).map { index in
            CostUsageSessionBreakdown(
                sessionID: "private-fixture-\(index)", lastActivity: CAAMControlFixtures.now,
                inputTokens: nil, cachedInputTokens: nil, outputTokens: nil,
                totalTokens: 10, requestCount: nil, costUSD: 0.1, modelBreakdowns: [])
        }
        let input = HubProviderInput(
            id: "fixture", label: "Fixture", source: "Fixture local records", usage: nil,
            cost: Self.cost(sessions: sessions))
        let overview = ObservabilityHub.aggregate(sessions: [], providers: [input], now: CAAMControlFixtures.now)
        #expect(overview.work.isEmpty)
        let work = ObservabilityHub.aggregate(
            sessions: [], providers: [input], includeWork: true, now: CAAMControlFixtures.now)
        #expect(work.work.count == 100)
        #expect(work.workIsPartial)
        #expect(!work.work.contains { $0.id.contains("private-fixture") })
        #expect(work.work.first?.evidence.availability == .partial)
        let stale = ObservabilityHub.aggregate(
            sessions: [], providers: [input], includeWork: true,
            now: CAAMControlFixtures.now.addingTimeInterval(301))
        #expect(stale.work.first?.evidence.availability == .stale)
    }

    @Test
    func `account correlation requires matching provider and stable ID not profile name or email`() throws {
        let first = CAAMControlFixtures.session()
        let otherConfiguration = CAAMEnvironmentConfiguration(id: "other", label: "Other", connection: .ssh(destination: "fixture"))
        var other = CAAMControlSession(configuration: otherConfiguration)
        other.observe(CAAMControlFixtures.snapshot(provider: "other-provider"), now: CAAMControlFixtures.now)
        let hub = ObservabilityHub.aggregate(sessions: [first, other], providers: [], now: CAAMControlFixtures.now)
        let account = try #require(hub.accounts.first)
        let otherAccount = try #require(hub.accounts.first { $0.environmentID == "other" })
        #expect(account.profile == otherAccount.profile)
        #expect(account.displayLabel == otherAccount.displayLabel)
        #expect(!account.isSameAccount(as: otherAccount))
        other.observe(CAAMControlFixtures.snapshot(), now: CAAMControlFixtures.now)
        let matched = ObservabilityHub.aggregate(sessions: [other], providers: [], now: CAAMControlFixtures.now)
        #expect(account.isSameAccount(as: try #require(matched.accounts.first)))
    }

    @Test
    func `Netdata navigation validates scheme credentials query and port without collection`() {
        for value in [
            "https://metrics.example.invalid/dashboard", "http://127.0.0.1:19999", "http://localhost:19999",
        ] {
            #expect(NetdataReadOnlyFacade.dashboardURL(value) != nil)
        }
        for value in [
            "http://remote.example.invalid", "file:///tmp/fixture", "javascript:alert(1)",
            "https://user:password@example.invalid", "https://example.invalid?token=fixture",
            "https://example.invalid#fixture", "https://example.invalid:99999", " https://example.invalid",
            "https://example.invalid\n", "https:///dashboard", String(repeating: "x", count: 2049),
        ] {
            #expect(NetdataReadOnlyFacade.dashboardURL(value) == nil)
        }
    }

    private static func cost(
        provenance: CostProvenance = .listPriceEstimate,
        sessions: [CostUsageSessionBreakdown] = []) -> CostUsageTokenSnapshot
    {
        CostUsageTokenSnapshot(
            sessionTokens: nil, sessionCostUSD: nil, last30DaysTokens: 100,
            last30DaysCostUSD: 12, meteredCostUSD: 3, costProvenance: provenance,
            daily: [], sessions: sessions, updatedAt: CAAMControlFixtures.now)
    }
}
