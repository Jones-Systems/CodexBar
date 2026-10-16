import Foundation
import Testing
@testable import CodexBarCore

struct ObservabilityHubLinuxTests {
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
    func `missing host telemetry remains unsupported without synthetic zeros`() {
        let hub = ObservabilityHub.aggregate(
            services: [Self.service()], accounts: [Self.account(), Self.account(profile: "secondary")], providers: [],
            now: Self.now)
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

    @Test
    func `Netdata CPU excludes iowait and available memory keeps its own units`() throws {
        let host = try Self.decodeNetdata()
        #expect(host.environmentID == "fixture")
        #expect(host.cpuPercent == 36)
        #expect(host.memoryAvailableBytes == 1_572_864)
        #expect(host.memoryUsedBytes == nil)
        #expect(host.evidence.availability == .available)
        #expect(host.evidence.observedAt == Self.netdataNow)
    }

    @Test
    func `Netdata missing null empty and stale samples stay explicit`() throws {
        let absent = try NetdataReadOnlyFacade.decode(
            expectedMachineGUID: Self.machineGUID, environmentID: "fixture", now: Self.netdataNow)
        #expect(absent.evidence.availability == .unavailable)
        #expect(absent.cpuPercent == nil)
        let cpuOnly = try NetdataReadOnlyFacade.decode(
            cpuData: Self.netdataData(), expectedMachineGUID: Self.machineGUID,
            environmentID: "fixture", now: Self.netdataNow)
        #expect(cpuOnly.evidence.availability == .partial)
        #expect(cpuOnly.memoryAvailableBytes == nil)
        let null = try Self.decodeNetdata(cpu: Self.netdataData(values: [nil, 2, 3, 4, 5, 6, 7, 8, 9]))
        #expect(null.cpuPercent == nil)
        #expect(null.evidence.availability == .partial)
        let empty = try Self.decodeNetdata(cpu: Self.netdataData(empty: true))
        #expect(empty.cpuPercent == nil)
        #expect(empty.evidence.availability == .partial)
        let stale = try Self.decodeNetdata(cpu: Self.netdataData(timestamp: 1_699_999_699))
        #expect(stale.evidence.availability == .stale)
        #expect(stale.evidence.observedAt == Date(timeIntervalSince1970: 1_699_999_699))
        let future = try Self.decodeNetdata(
            cpu: Self.netdataData(timestamp: 1_700_000_010),
            memory: Self.netdataData(memory: true, timestamp: 1_700_000_010))
        #expect(future.evidence.availability == .stale)
        let oneFuture = try Self.decodeNetdata(cpu: Self.netdataData(timestamp: 1_700_000_010))
        #expect(oneFuture.evidence.availability == .stale)
        let emptyBoth = try NetdataReadOnlyFacade.decode(
            cpuData: Self.netdataData(empty: true),
            availableMemoryData: Self.netdataData(memory: true, empty: true),
            expectedMachineGUID: Self.machineGUID, environmentID: "fixture", now: Self.netdataNow)
        #expect(emptyBoth.evidence.availability == .unavailable)
        #expect(emptyBoth.evidence.observedAt == nil)
        let zero = try Self.decodeNetdata(cpu: Self.netdataData(values: Array(repeating: 0, count: 9)))
        #expect(zero.cpuPercent == 0)
    }

    @Test
    func `Netdata fast metrics become stale after thirty seconds in decoder and hub`() throws {
        let boundary = try Self.decodeNetdata(cpu: Self.netdataData(timestamp: 1_699_999_970))
        #expect(boundary.evidence.availability == .available)
        let expired = try Self.decodeNetdata(cpu: Self.netdataData(timestamp: 1_699_999_969))
        #expect(expired.evidence.availability == .stale)
        let partial = try NetdataReadOnlyFacade.decode(
            cpuData: Self.netdataData(timestamp: 1_699_999_970), expectedMachineGUID: Self.machineGUID,
            environmentID: "fixture", now: Self.netdataNow)
        #expect(partial.evidence.availability == .partial)
        let host = try Self.decodeNetdata()
        let session = Self.service()
        let boundaryHub = ObservabilityHub.aggregate(
            services: [session], providers: [], hostsByEnvironmentID: ["fixture": host],
            now: Self.netdataNow.addingTimeInterval(30))
        #expect(boundaryHub.hosts.first?.evidence.availability == .available)
        let expiredHub = ObservabilityHub.aggregate(
            services: [session], providers: [], hostsByEnvironmentID: ["fixture": host],
            now: Self.netdataNow.addingTimeInterval(31))
        #expect(expiredHub.hosts.first?.evidence.availability == .stale)
        let expiredPartial = ObservabilityHub.aggregate(
            services: [session], providers: [], hostsByEnvironmentID: ["fixture": partial],
            now: Self.netdataNow.addingTimeInterval(1))
        #expect(expiredPartial.hosts.first?.evidence.availability == .stale)
    }

    @Test
    func `Netdata rejects foreign nodes and mismatched response contracts`() throws {
        let mutations: [(inout [String: Any]) -> Void] = [
            { $0["api"] = 2 },
            { $0["summary"] = ["nodes": [], "contexts": [["id": "system.cpu"]]] },
            { $0["summary"] = [
                "nodes": [["mg": Self.machineGUID], ["mg": Self.machineGUID]],
                "contexts": [["id": "system.cpu"]],
            ] },
            { $0["summary"] = [
                "nodes": [["mg": "22222222-2222-4222-8222-222222222222"]],
                "contexts": [["id": "system.cpu"]],
            ] },
            { $0["summary"] = ["nodes": [["mg": Self.machineGUID]], "contexts": [["id": "system.ram"]]] },
            { $0["view"] = ["dimensions": ["ids": ["user"], "units": ["percentage"]]] },
            { $0["view"] = ["dimensions": [
                "ids": Self.cpuDimensions,
                "units": Array(repeating: "percent", count: 9),
            ]] },
            { object in
                var result = object["result"] as? [String: Any] ?? [:]
                result["labels"] = ["time"] + Array(Self.cpuDimensions.reversed())
                object["result"] = result
            },
            { object in
                var result = object["result"] as? [String: Any] ?? [:]
                result["point"] = ["value": 1, "arp": 0, "pa": 2]
                object["result"] = result
            },
            { object in
                var result = object["result"] as? [String: Any] ?? [:]
                let rows = result["data"] as? [[Any]] ?? []
                result["data"] = rows + rows
                object["result"] = result
            },
        ]
        for mutation in mutations {
            let data = try Self.netdataData(mutate: mutation)
            #expect(throws: NetdataReadOnlyFacade.DecodeError.self) { try Self.decodeNetdata(cpu: data) }
        }
    }

    @Test
    func `Netdata rejects malformed oversized and unsafe numeric input`() throws {
        let invalid = try [
            Data("{".utf8), Data(repeating: 32, count: NetdataReadOnlyFacade.maximumPayloadBytes + 1),
            Self.netdataData(timestamp: -1), Self.netdataData(timestamp: 1_700_000_000.5),
            Self.netdataData(timestamp: 253_402_300_800),
            Self.netdataData(values: [-1, 2, 3, 4, 5, 6, 7, 8, 9]),
            Self.netdataData(values: [101, 2, 3, 4, 5, 6, 7, 8, 9]),
            Self.netdataData(values: Array(repeating: 20, count: 9)),
            Self.netdataData(values: [1]),
            Self.netdataData(pointWidth: 2),
        ]
        for data in invalid {
            #expect(throws: NetdataReadOnlyFacade.DecodeError.self) { try Self.decodeNetdata(cpu: data) }
        }
        for value in [-1.0, Double(UInt64.max) / 1_048_576] {
            let data = try Self.netdataData(memory: true, values: [value])
            #expect(throws: NetdataReadOnlyFacade.DecodeError.self) { try Self.decodeNetdata(memory: data) }
        }
        let overflowing = try Self.netdataData(memory: true)
        let overflowJSON = String(decoding: overflowing, as: UTF8.self).replacingOccurrences(of: "1.5", with: "1e400")
        #expect(throws: NetdataReadOnlyFacade.DecodeError.self) {
            try Self.decodeNetdata(memory: Data(overflowJSON.utf8))
        }
        let boolean = try Self.netdataData(mutate: { object in
            var result = object["result"] as? [String: Any] ?? [:]
            let point: [Any] = [true, 0, 0]
            let row: [Any] = [1_700_000_000] + Array(repeating: point, count: 9).map { $0 as Any }
            result["data"] = [row]
            object["result"] = result
        })
        #expect(throws: NetdataReadOnlyFacade.DecodeError.self) { try Self.decodeNetdata(cpu: boolean) }
        #expect(throws: NetdataReadOnlyFacade.DecodeError.invalidIdentity) {
            try NetdataReadOnlyFacade.decode(
                expectedMachineGUID: "invalid", environmentID: "fixture", now: Self.netdataNow)
        }
    }

    @Test
    func `Netdata injection uses only configured matching environments and ages at aggregation`() throws {
        let host = try Self.decodeNetdata()
        let session = Self.service()
        let hub = ObservabilityHub.aggregate(
            services: [session], providers: [], hostsByEnvironmentID: ["fixture": host, "unknown": host],
            now: Self.netdataNow)
        #expect(hub.hosts == [host])
        let stale = ObservabilityHub.aggregate(
            services: [session], providers: [], hostsByEnvironmentID: ["fixture": host],
            now: Self.netdataNow.addingTimeInterval(301))
        #expect(stale.hosts.first?.evidence.availability == .stale)
        let foreign = try NetdataReadOnlyFacade.decode(
            cpuData: Self.netdataData(), expectedMachineGUID: Self.machineGUID,
            environmentID: "foreign", now: Self.netdataNow)
        let mismatch = ObservabilityHub.aggregate(
            services: [session], providers: [], hostsByEnvironmentID: ["fixture": foreign], now: Self.netdataNow)
        #expect(mismatch.hosts.first?.evidence.availability == .unsupported)
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

    private static let machineGUID = "11111111-1111-4111-8111-111111111111"
    private static let netdataNow = Date(timeIntervalSince1970: 1_700_000_000)
    private static let cpuDimensions = [
        "guest_nice", "guest", "steal", "softirq", "irq", "user", "system", "nice", "iowait",
    ]

    private static func decodeNetdata(cpu: Data? = nil, memory: Data? = nil) throws -> HubHostObservation {
        try NetdataReadOnlyFacade.decode(
            cpuData: cpu ?? self.netdataData(),
            availableMemoryData: memory ?? self.netdataData(memory: true),
            expectedMachineGUID: self.machineGUID, environmentID: "fixture", now: self.netdataNow)
    }

    private static func netdataData(
        memory: Bool = false,
        timestamp: Double = 1_700_000_000,
        values: [Double?]? = nil,
        empty: Bool = false,
        pointWidth: Int = 3,
        mutate: ((inout [String: Any]) -> Void)? = nil) throws -> Data
    {
        let dimensions = memory ? ["avail"] : Self.cpuDimensions
        let values = values ?? (memory ? [1.5] : [1, 2, 3, 4, 5, 6, 7, 8, 9])
        let points: [[Any]] = values.map { value in
            [value.map { $0 as Any } ?? NSNull()] + Array(repeating: 0, count: pointWidth - 1).map { $0 as Any }
        }
        let row: [Any] = [timestamp] + points.map { $0 as Any }
        var object: [String: Any] = [
            "api": 3,
            "summary": [
                "nodes": [["mg": Self.machineGUID]],
                "contexts": [["id": memory ? "mem.available" : "system.cpu"]],
            ],
            "view": ["dimensions": [
                "ids": dimensions,
                "units": Array(repeating: memory ? "MiB" : "percentage", count: dimensions.count),
            ]],
            "result": [
                "labels": ["time"] + dimensions,
                "point": ["value": 0, "arp": 1, "pa": 2],
                "data": empty ? [] : [row],
            ],
        ]
        mutate?(&object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
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
