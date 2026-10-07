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
        let otherConfiguration = CAAMEnvironmentConfiguration(
            id: "other", label: "Other", connection: .ssh(destination: "fixture"))
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

    @Test
    func `Netdata CPU excludes iowait and available memory keeps its own units`() throws {
        let host = try Self.decodeNetdata()
        #expect(host.environmentID == "fixture")
        #expect(host.cpuPercent == 36)
        #expect(host.memoryAvailableBytes == 1572864)
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
        let stale = try Self.decodeNetdata(cpu: Self.netdataData(timestamp: 1699999699))
        #expect(stale.evidence.availability == .stale)
        #expect(stale.evidence.observedAt == Date(timeIntervalSince1970: 1699999699))
        let future = try Self.decodeNetdata(
            cpu: Self.netdataData(timestamp: 1700000010),
            memory: Self.netdataData(memory: true, timestamp: 1700000010))
        #expect(future.evidence.availability == .stale)
        let oneFuture = try Self.decodeNetdata(cpu: Self.netdataData(timestamp: 1700000010))
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
        let boundary = try Self.decodeNetdata(cpu: Self.netdataData(timestamp: 1699999970))
        #expect(boundary.evidence.availability == .available)
        let expired = try Self.decodeNetdata(cpu: Self.netdataData(timestamp: 1699999969))
        #expect(expired.evidence.availability == .stale)
        let partial = try NetdataReadOnlyFacade.decode(
            cpuData: Self.netdataData(timestamp: 1699999970), expectedMachineGUID: Self.machineGUID,
            environmentID: "fixture", now: Self.netdataNow)
        #expect(partial.evidence.availability == .partial)
        let host = try Self.decodeNetdata()
        let session = CAAMControlFixtures.session()
        let boundaryHub = ObservabilityHub.aggregate(
            sessions: [session], providers: [], hostsByEnvironmentID: ["fixture": host],
            now: Self.netdataNow.addingTimeInterval(30))
        #expect(boundaryHub.hosts.first?.evidence.availability == .available)
        let expiredHub = ObservabilityHub.aggregate(
            sessions: [session], providers: [], hostsByEnvironmentID: ["fixture": host],
            now: Self.netdataNow.addingTimeInterval(31))
        #expect(expiredHub.hosts.first?.evidence.availability == .stale)
        let expiredPartial = ObservabilityHub.aggregate(
            sessions: [session], providers: [], hostsByEnvironmentID: ["fixture": partial],
            now: Self.netdataNow.addingTimeInterval(1))
        #expect(expiredPartial.hosts.first?.evidence.availability == .stale)
    }

    @Test
    func `Netdata rejects foreign nodes and mismatched response contracts`() throws {
        let mutations: [(inout [String: Any]) -> Void] = [
            { $0["api"] = 2 },
            { $0["summary"] = ["nodes": [], "contexts": [["id": "system.cpu"]]] },
            { $0["summary"] = ["nodes": [["mg": Self.machineGUID], ["mg": Self.machineGUID]],
                                 "contexts": [["id": "system.cpu"]]] },
            { $0["summary"] = ["nodes": [["mg": "22222222-2222-4222-8222-222222222222"]],
                                 "contexts": [["id": "system.cpu"]]] },
            { $0["summary"] = ["nodes": [["mg": Self.machineGUID]], "contexts": [["id": "system.ram"]]] },
            { $0["view"] = ["dimensions": ["ids": ["user"], "units": ["percentage"]]] },
            { $0["view"] = ["dimensions": ["ids": Self.cpuDimensions,
                                             "units": Array(repeating: "percent", count: 9)]] },
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
        let invalid = [
            Data("{".utf8), Data(repeating: 32, count: NetdataReadOnlyFacade.maximumPayloadBytes + 1),
            try Self.netdataData(timestamp: -1), try Self.netdataData(timestamp: 1700000000.5),
            try Self.netdataData(timestamp: 253402300800),
            try Self.netdataData(values: [-1, 2, 3, 4, 5, 6, 7, 8, 9]),
            try Self.netdataData(values: [101, 2, 3, 4, 5, 6, 7, 8, 9]),
            try Self.netdataData(values: Array(repeating: 20, count: 9)),
            try Self.netdataData(values: [1]),
            try Self.netdataData(pointWidth: 2),
        ]
        for data in invalid {
            #expect(throws: NetdataReadOnlyFacade.DecodeError.self) { try Self.decodeNetdata(cpu: data) }
        }
        for value in [-1.0, Double(UInt64.max) / 1048576] {
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
            let row: [Any] = [1700000000] + Array(repeating: point, count: 9).map { $0 as Any }
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
        let session = CAAMControlFixtures.session()
        let hub = ObservabilityHub.aggregate(
            sessions: [session], providers: [], hostsByEnvironmentID: ["fixture": host, "unknown": host],
            now: Self.netdataNow)
        #expect(hub.hosts == [host])
        let stale = ObservabilityHub.aggregate(
            sessions: [session], providers: [], hostsByEnvironmentID: ["fixture": host],
            now: Self.netdataNow.addingTimeInterval(301))
        #expect(stale.hosts.first?.evidence.availability == .stale)
        let foreign = try NetdataReadOnlyFacade.decode(
            cpuData: Self.netdataData(), expectedMachineGUID: Self.machineGUID,
            environmentID: "foreign", now: Self.netdataNow)
        let mismatch = ObservabilityHub.aggregate(
            sessions: [session], providers: [], hostsByEnvironmentID: ["fixture": foreign], now: Self.netdataNow)
        #expect(mismatch.hosts.first?.evidence.availability == .unsupported)
    }

    private static let machineGUID = "11111111-1111-4111-8111-111111111111"
    private static let netdataNow = Date(timeIntervalSince1970: 1700000000)
    private static let cpuDimensions = [
        "guest_nice", "guest", "steal", "softirq", "irq", "user", "system", "nice", "iowait",
    ]

    private static func decodeNetdata(cpu: Data? = nil, memory: Data? = nil) throws -> HubHostObservation {
        try NetdataReadOnlyFacade.decode(
            cpuData: cpu ?? Self.netdataData(),
            availableMemoryData: memory ?? Self.netdataData(memory: true),
            expectedMachineGUID: Self.machineGUID, environmentID: "fixture", now: Self.netdataNow)
    }

    private static func netdataData(
        memory: Bool = false,
        timestamp: Double = 1700000000,
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
            "summary": ["nodes": [["mg": Self.machineGUID]],
                        "contexts": [["id": memory ? "mem.available" : "system.cpu"]]],
            "view": ["dimensions": ["ids": dimensions,
                                    "units": Array(repeating: memory ? "MiB" : "percentage", count: dimensions.count)]],
            "result": ["labels": ["time"] + dimensions, "point": ["value": 0, "arp": 1, "pa": 2],
                       "data": empty ? [] : [row]],
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
            daily: [], sessions: sessions, updatedAt: CAAMControlFixtures.now)
    }
}
