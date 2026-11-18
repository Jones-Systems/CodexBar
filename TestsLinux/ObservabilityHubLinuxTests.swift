import Foundation
import Testing
@testable import CodexBarCore

struct ObservabilityHubLinuxTests {

    @Test
    func `service and account observations aggregate without provider input`() {
        let hub = ObservabilityHub.aggregate(
            services: [Self.service()], accounts: [Self.account(), Self.account(profile: "secondary")], providers: [],
            now: Self.now)
        #expect(hub.services.count == 1)
        #expect(hub.accounts.count == 2)
        #expect(hub.providers.isEmpty)
        #expect(hub.work.isEmpty)
    }

    @Test
    func `local row identities stay distinct without claiming account correlation`() {
        let rows = ["profile-a", "profile-b"].map { id in
            HubAccountObservation(
                environmentID: "local", environmentLabel: "Local", profile: "Same display name",
                provider: "codex", stableID: nil, displayLabel: nil, hostDefault: false,
                health: .unknown,
                evidence: HubEvidence(source: "Synthetic projection", observedAt: nil, availability: .partial),
                id: id)
        }
        let hub = ObservabilityHub.aggregate(accounts: rows, providers: [], now: Self.now)
        #expect(Set(hub.accounts.map(\.id)).count == 2)
        #expect(!hub.accounts[0].isSameAccount(as: hub.accounts[1]))
    }

    @Test
    func `cost provenance currency window and metered component remain distinct`() throws {
        let cost = Self.cost(provenance: .mixed)
        let usage = UsageSnapshot(
            primary: RateWindow(usedPercent: 25, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil, updatedAt: Self.now)
        let input = HubProviderInput(id: "fixture", label: "Fixture", source: "Fixture API", usage: usage, cost: cost)
        let hub = ObservabilityHub.aggregate(providers: [input], now: Self.now)
        let provider = try #require(hub.providers.first)
        #expect(provider.primaryUsedPercent == 25)
        #expect(provider.windowMinutes == 300)
        #expect(provider.cost?.amount == 12)
        #expect(provider.cost?.meteredAmount == 3)
        #expect(provider.cost?.currency == "USD")
        #expect(provider.cost?.historyDays == 30)
        #expect(provider.cost?.provenance == .mixed)
        #expect(provider.cost?.evidence.observedAt == Self.now)
    }

    @Test
    func `placeholder usage and invalid numeric costs remain unavailable`() {
        let usage = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 0, windowMinutes: 300, resetsAt: nil, resetDescription: nil,
                isSyntheticPlaceholder: true),
            secondary: nil, updatedAt: Self.now)
        let cost = CostUsageTokenSnapshot(
            sessionTokens: nil, sessionCostUSD: nil, last30DaysTokens: nil,
            last30DaysCostUSD: .infinity, costProvenance: .unknown, daily: [], updatedAt: Self.now)
        let input = HubProviderInput(id: "fixture", label: "Fixture", source: "Fixture", usage: usage, cost: cost)
        let hub = ObservabilityHub.aggregate(providers: [input], now: Self.now)
        #expect(hub.providers.first?.primaryUsedPercent == nil)
        #expect(hub.providers.first?.evidence.availability == .partial)
        #expect(hub.providers.first?.cost?.amount == nil)
    }

    @Test
    func `work records are lazy bounded historical and never identify live jobs`() {
        let sessions = (0..<120).map { index in
            CostUsageSessionBreakdown(
                sessionID: "private-fixture-\(index)", lastActivity: Self.now,
                inputTokens: nil, cachedInputTokens: nil, outputTokens: nil,
                totalTokens: 10, requestCount: nil, costUSD: 0.1, modelBreakdowns: [])
        }
        let input = HubProviderInput(
            id: "fixture", label: "Fixture", source: "Fixture local records", usage: nil,
            cost: Self.cost(sessions: sessions))
        let overview = ObservabilityHub.aggregate(providers: [input], now: Self.now)
        #expect(overview.work.isEmpty)
        let work = ObservabilityHub.aggregate(
            providers: [input], includeWork: true, now: Self.now)
        #expect(work.work.count == 100)
        #expect(work.workIsPartial)
        #expect(!work.work.contains { $0.id.contains("private-fixture") })
        #expect(work.work.first?.evidence.availability == .partial)
        let stale = ObservabilityHub.aggregate(
            providers: [input], includeWork: true,
            now: Self.now.addingTimeInterval(301))
        #expect(stale.work.first?.evidence.availability == .stale)
    }

    @Test
    func `account correlation requires matching provider and stable ID not profile name or email`() throws {
        let account = Self.account()
        let other = Self.account(environmentID: "other", provider: "other-provider")
        let hub = ObservabilityHub.aggregate(accounts: [account, other], providers: [], now: Self.now)
        let firstAccount = try #require(hub.accounts.first)
        let otherAccount = try #require(hub.accounts.first { $0.environmentID == "other" })
        #expect(firstAccount.profile == otherAccount.profile)
        #expect(firstAccount.displayLabel == otherAccount.displayLabel)
        #expect(!firstAccount.isSameAccount(as: otherAccount))
        let matched = Self.account(environmentID: "other")
        #expect(firstAccount.isSameAccount(as: matched))
        #expect(!firstAccount.isSameAccount(as: Self.account(stableID: nil)))
    }

    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    private static func service() -> HubServiceObservation {
        HubServiceObservation(
            id: "fixture", label: "Fixture", currentProfile: "primary",
            evidence: HubEvidence(
                source: "Synthetic service observation",
                observedAt: self.now,
                availability: .available))
    }

    private static func account(
        environmentID: String = "fixture", provider: String = "codex", profile: String = "primary",
        stableID: String? = "synthetic-account") -> HubAccountObservation
    {
        HubAccountObservation(
            environmentID: environmentID, environmentLabel: "Fixture", profile: profile,
            provider: provider, stableID: stableID, displayLabel: "synthetic@example.invalid", hostDefault: true,
            health: .unknown,
            evidence: HubEvidence(
                source: "Synthetic account observation",
                observedAt: self.now,
                availability: .available))
    }

    private static func cost(
        provenance: CostProvenance = .listPriceEstimate,
        sessions: [CostUsageSessionBreakdown] = []) -> CostUsageTokenSnapshot
    {
        CostUsageTokenSnapshot(
            sessionTokens: nil, sessionCostUSD: nil, last30DaysTokens: 100,
            last30DaysCostUSD: 12, meteredCostUSD: 3, costProvenance: provenance,
            daily: [], sessions: sessions, updatedAt: self.now)
    }
}
