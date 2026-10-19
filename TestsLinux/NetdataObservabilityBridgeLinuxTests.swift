import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBarCore

@MainActor
struct NetdataObservabilityBridgeLinuxTests {
    private nonisolated static let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test
    func `empty default and invalid bindings do not collect`() async throws {
        let bridge = NetdataObservabilityBridge()
        let fetcher = SequenceFetcher([.success(Self.observation())])
        let empty = try await bridge.refresh(environmentID: "synthetic", clock: { Self.now })
        let invalid = bridge.bind(environmentID: "bad\nidentity", fetcher: fetcher)
        #expect(!empty)
        #expect(!invalid)
        #expect(await fetcher.calls == 0)
        #expect(bridge.hostsByEnvironmentID(now: Self.now).isEmpty)
        #expect(bridge.systemsState(environmentID: "synthetic", now: Self.now).availability == .unsupported)
    }

    @Test
    func `explicit client with recording transport publishes into independent hub hosts`() async throws {
        let bridge = NetdataObservabilityBridge()
        let transport = RecordingTransport()
        let client = try NetdataLoopbackClient(
            origin: "http://127.0.0.1:19999",
            expectedMachineGUID: RecordingTransport.guid,
            environmentID: "synthetic",
            transport: transport)
        let bound = bridge.bind(environmentID: "synthetic", fetcher: client)
        #expect(bound)
        #expect(await transport.calls == 0)
        let refreshed = try await bridge.refresh(environmentID: "synthetic", clock: { Self.now })
        #expect(refreshed)
        #expect(await transport.calls == 2)
        let state = bridge.systemsState(environmentID: "synthetic", now: Self.now)
        #expect(state.cpuPercent == 8)
        #expect(state.availableRAMGiB == 0.5)
        #expect(state.receivedAt == Self.now)
        #expect(state.compactLabel(hostLabel: "Fixture") == "Fixture 8% · 0.5 GiB avail")
        let unavailableService = CAAMControlSession(configuration: CAAMEnvironmentConfiguration(
            id: "synthetic",
            label: "Fixture",
            connection: .local()))
        let snapshot = ObservabilityHub.aggregate(
            sessions: [unavailableService],
            providers: [],
            hostsByEnvironmentID: bridge.hostsByEnvironmentID(now: Self.now),
            now: Self.now)
        #expect(snapshot.services.first?.evidence.availability == .unavailable)
        #expect(snapshot.hosts.first?.evidence.availability == .available)
        #expect(snapshot.hosts.first?.cpuPercent == 8)
        #expect(snapshot.hosts.first?.memoryUsedBytes == nil)
        #expect(snapshot.accounts.isEmpty)
        #expect(snapshot.providers.isEmpty)
    }

    @Test
    func `partial zero values and age stay consistent across projections`() async throws {
        let bridge = NetdataObservabilityBridge()
        let partial = Self.observation(cpu: 0, memory: nil, availability: .partial)
        bridge.bind(environmentID: "synthetic", fetcher: SequenceFetcher([.success(partial)]))
        let accepted = try await bridge.refresh(environmentID: "synthetic", clock: { Self.now })
        #expect(accepted)
        for (offset, availability) in [(0.0, HubAvailability.partial), (31.0, .stale), (301.0, .unavailable)] {
            let now = Self.now.addingTimeInterval(offset)
            let state = bridge.systemsState(environmentID: "synthetic", now: now)
            let host = try #require(bridge.hostsByEnvironmentID(now: now)["synthetic"])
            #expect(state.availability == availability)
            #expect(host.evidence.availability == availability)
            #expect(host.evidence.observedAt == Self.now)
            #expect(host.cpuPercent == 0)
            #expect(host.memoryAvailableBytes == nil)
            if offset > 0 { #expect(!state.compactLabel(hostLabel: "Fixture").contains("0%")) }
        }
    }

    @Test
    func `failure retains dated cache and recovery follows explicit due decisions`() async throws {
        let bridge = NetdataObservabilityBridge()
        let recoveredAt = Self.now.addingTimeInterval(15)
        let fetcher = SequenceFetcher([
            .success(Self.observation()), .failure(.offline),
            .success(Self.observation(at: recoveredAt, cpu: 12)),
        ])
        bridge.bind(environmentID: "synthetic", fetcher: fetcher)
        let first = try await bridge.refresh(environmentID: "synthetic", visible: true, clock: { Self.now })
        let tooEarly = try await bridge.refresh(environmentID: "synthetic", clock: { Self.now })
        #expect(first)
        #expect(!tooEarly)
        #expect(bridge.refreshState(environmentID: "synthetic")?.nextRefreshAt == Self.now.addingTimeInterval(5))
        let failedAt = Self.now.addingTimeInterval(5)
        await #expect(throws: FixtureError.offline) {
            try await bridge.refresh(environmentID: "synthetic", clock: { failedAt })
        }
        let failed = bridge.systemsState(environmentID: "synthetic", now: failedAt)
        #expect(failed.availability == .stale)
        #expect(failed.observedAt == Self.now)
        #expect(failed.receivedAt == Self.now)
        #expect(bridge.hostsByEnvironmentID(now: failedAt)["synthetic"]?.evidence.availability == .stale)
        let recovery = try await bridge.refresh(environmentID: "synthetic", clock: { recoveredAt })
        #expect(recovery)
        #expect(bridge.systemsState(environmentID: "synthetic", now: recoveredAt).cpuPercent == 12)
        #expect(bridge.refreshState(environmentID: "synthetic")?.nextRefreshAt == recoveredAt.addingTimeInterval(10))
        #expect(await fetcher.calls == 3)
    }

    @Test
    func `one in flight per host does not prevent another host refreshing`() async throws {
        let bridge = NetdataObservabilityBridge()
        let held = HeldFetcher()
        bridge.bind(environmentID: "synthetic", fetcher: held)
        bridge.bind(environmentID: "other", fetcher: SequenceFetcher([.success(Self.observation(id: "other"))]))
        let task = Task { try await bridge.refresh(environmentID: "synthetic", clock: { Self.now }) }
        await held.waitUntilRequested()
        #expect(bridge.systemsState(environmentID: "synthetic", now: Self.now).isRefreshing)
        let duplicate = try await bridge.refresh(environmentID: "synthetic", force: true, clock: { Self.now })
        let other = try await bridge.refresh(environmentID: "other", clock: { Self.now })
        #expect(!duplicate)
        #expect(other)
        #expect(bridge.hostsByEnvironmentID(now: Self.now)["other"]?.evidence.availability == .available)
        await held.release(Self.observation())
        let completed = try await task.value
        #expect(completed)
        #expect(!bridge.systemsState(environmentID: "synthetic", now: Self.now).isRefreshing)
    }

    @Test(arguments: [false, true])
    func `replacement binding rejects old generation even after removal`(removeFirst: Bool) async throws {
        let bridge = NetdataObservabilityBridge()
        let held = HeldFetcher()
        bridge.bind(environmentID: "synthetic", fetcher: held)
        let oldTask = Task { try await bridge.refresh(environmentID: "synthetic", clock: { Self.now }) }
        await held.waitUntilRequested()
        if removeFirst { bridge.removeBinding(environmentID: "synthetic") }
        bridge.bind(environmentID: "synthetic", fetcher: SequenceFetcher([.success(Self.observation(cpu: 2))]))
        let replacement = try await bridge.refresh(environmentID: "synthetic", clock: { Self.now })
        #expect(!replacement)
        await held.release(Self.observation(cpu: 99))
        let oldAccepted = try await oldTask.value
        #expect(!oldAccepted)
        let nextAccepted = try await bridge.refresh(environmentID: "synthetic", clock: { Self.now })
        #expect(nextAccepted)
        #expect(bridge.systemsState(environmentID: "synthetic", now: Self.now).cpuPercent == 2)
    }

    @Test
    func `suspension invalidates replies and new bindings stay suspended until explicit wake`() async throws {
        let bridge = NetdataObservabilityBridge()
        let held = HeldFetcher()
        bridge.bind(environmentID: "synthetic", fetcher: held)
        let task = Task { try await bridge.refresh(environmentID: "synthetic", clock: { Self.now }) }
        await held.waitUntilRequested()
        bridge.suspend()
        let next = SequenceFetcher([.success(Self.observation(id: "other"))])
        bridge.bind(environmentID: "other", fetcher: next)
        let suspended = try await bridge.refresh(environmentID: "other", force: true, clock: { Self.now })
        #expect(!suspended)
        #expect(await next.calls == 0)
        bridge.bind(environmentID: "synthetic", fetcher: SequenceFetcher([.success(Self.observation())]))
        bridge.wake(now: Self.now)
        let stillOccupied = try await bridge.refresh(environmentID: "synthetic", force: true, clock: { Self.now })
        #expect(!stillOccupied)
        await held.release(Self.observation())
        let oldAccepted = try await task.value
        #expect(!oldAccepted)
        #expect(bridge.refreshState(environmentID: "synthetic")?.observation == nil)
        let drained = try await bridge.refresh(environmentID: "synthetic", clock: { Self.now })
        #expect(drained)
        let awake = try await bridge.refresh(environmentID: "other", clock: { Self.now })
        #expect(awake)
        #expect(!bridge.isSuspended)
    }

    @Test
    func `caller cancellation clears only its request and never publishes a late sample`() async throws {
        let bridge = NetdataObservabilityBridge()
        let held = HeldFetcher()
        bridge.bind(environmentID: "synthetic", fetcher: held)
        let task = Task { try await bridge.refresh(environmentID: "synthetic", clock: { Self.now }) }
        await held.waitUntilRequested()
        task.cancel()
        await held.release(Self.observation())
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(bridge.refreshState(environmentID: "synthetic")?.inFlight == nil)
        #expect(bridge.refreshState(environmentID: "synthetic")?.observation == nil)
        #expect(bridge.refreshState(environmentID: "synthetic")?.requestFailed == false)
    }

    @Test
    func `mismatched observations never become another hosts metrics`() async throws {
        let bridge = NetdataObservabilityBridge()
        bridge.bind(environmentID: "synthetic", fetcher: SequenceFetcher([.success(Self.observation(id: "other"))]))
        let completed = try await bridge.refresh(environmentID: "synthetic", clock: { Self.now })
        #expect(completed)
        let state = bridge.systemsState(environmentID: "synthetic", now: Self.now)
        #expect(state.availability == .unavailable)
        #expect(state.cpuPercent == nil)
        #expect(bridge.hostsByEnvironmentID(now: Self.now)["other"] == nil)
    }

    @Test
    func `invalid completion clock rejects sample without stranding its in flight request`() async throws {
        let bridge = NetdataObservabilityBridge()
        bridge.bind(environmentID: "synthetic", fetcher: SequenceFetcher([.success(Self.observation())]))
        let clock = SequenceClock([Self.now, Date(timeIntervalSince1970: .nan)])
        let accepted = try await bridge.refresh(environmentID: "synthetic", clock: { clock.next() })
        #expect(!accepted)
        #expect(bridge.refreshState(environmentID: "synthetic")?.inFlight == nil)
        #expect(bridge.refreshState(environmentID: "synthetic")?.observation == nil)
    }

    private final class SequenceClock: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Date]

        init(_ values: [Date]) {
            self.values = values
        }

        func next() -> Date {
            self.lock.lock()
            defer { self.lock.unlock() }
            return self.values.removeFirst()
        }
    }

    private static func observation(
        id: String = "synthetic",
        at: Date = Self.now,
        cpu: Double = 8,
        memory: UInt64? = 536_870_912,
        availability: HubAvailability = .available) -> HubHostObservation
    {
        HubHostObservation(
            environmentID: id,
            evidence: HubEvidence(source: "Synthetic Netdata fixture", observedAt: at, availability: availability),
            cpuPercent: cpu,
            memoryUsedBytes: nil,
            memoryAvailableBytes: memory)
    }

    private enum FixtureError: Error { case offline }

    private actor SequenceFetcher: NetdataObservationFetching {
        private var results: [Result<HubHostObservation, FixtureError>]
        private(set) var calls = 0

        init(_ results: [Result<HubHostObservation, FixtureError>]) {
            self.results = results
        }

        func fetch(now: Date) throws -> HubHostObservation {
            self.calls += 1
            return try self.results.removeFirst().get()
        }
    }

    private actor HeldFetcher: NetdataObservationFetching {
        private var reply: CheckedContinuation<HubHostObservation, Never>?
        private var started: CheckedContinuation<Void, Never>?

        func fetch(now: Date) async -> HubHostObservation {
            await withCheckedContinuation { continuation in
                self.reply = continuation
                self.started?.resume()
                self.started = nil
            }
        }

        func waitUntilRequested() async {
            if self.reply != nil { return }
            await withCheckedContinuation { self.started = $0 }
        }

        func release(_ observation: HubHostObservation) {
            self.reply?.resume(returning: observation)
            self.reply = nil
        }
    }

    private actor RecordingTransport: ProviderHTTPTransport {
        static let guid = "11111111-2222-4333-8444-555555555555"
        private(set) var calls = 0

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            self.calls += 1
            let url = try #require(request.url)
            let context = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "contexts" })?.value ?? ""
            let cpu = context == "system.cpu"
            let dimensions = cpu
                ? ["guest_nice", "guest", "steal", "softirq", "irq", "user", "system", "nice", "iowait"] : ["avail"]
            let body: [String: Any] = [
                "api": 3,
                "summary": ["nodes": [["mg": Self.guid]], "contexts": [["id": context]]],
                "view": ["dimensions": [
                    "ids": dimensions,
                    "units": Array(repeating: cpu ? "percentage" : "MiB", count: dimensions.count),
                ]],
                "result": [
                    "labels": ["time"] + dimensions,
                    "point": ["value": 0, "arp": 1, "pa": 2],
                    "data": [[NetdataObservabilityBridgeLinuxTests.now.timeIntervalSince1970] as [Any]
                        + dimensions.map { _ in [cpu ? 1 : 512, 0, 0] }],
                ],
            ]
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return try (JSONSerialization.data(withJSONObject: body), response)
        }
    }
}
