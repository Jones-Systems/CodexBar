import Foundation
import Testing
@testable import CodexBarCore

struct NetdataRefreshStateLinuxTests {
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test
    func `one in flight request and visible background schedule remain pure decisions`() throws {
        var state = NetdataRefreshState(environmentID: "fixture")
        let request = try #require(state.beginRefresh(now: Self.now))
        #expect(state.beginRefresh(now: Self.now, force: true) == nil)
        #expect(state.systemsState(now: Self.now).isRefreshing)
        #expect(state.complete(request, observation: Self.host(), now: Self.now))
        #expect(state.nextRefreshAt == Self.now.addingTimeInterval(10))
        #expect(state.beginRefresh(now: Self.now.addingTimeInterval(9)) == nil)
        let visible = try #require(state.beginRefresh(now: Self.now.addingTimeInterval(10)))
        #expect(state.complete(visible, observation: Self.host(), now: Self.now.addingTimeInterval(10), visible: true))
        #expect(state.nextRefreshAt == Self.now.addingTimeInterval(15))
    }

    @Test
    func `configuration changes and repeated completions cannot replace newer observations`() throws {
        var state = NetdataRefreshState(environmentID: "fixture")
        let old = try #require(state.beginRefresh(now: Self.now))
        state.configure(environmentID: "second")
        let current = try #require(state.beginRefresh(now: Self.now))
        #expect(!state.complete(old, observation: Self.host(), now: Self.now))
        #expect(state.inFlight == current)
        #expect(state.complete(current, observation: Self.host(environmentID: "second"), now: Self.now))
        #expect(!state.complete(current, observation: Self.host(cpu: 99), now: Self.now))
        #expect(state.systemsState(now: Self.now).cpuPercent == 28)
        state.configure(environmentID: "fixture")
        #expect(state.observation == nil)
        #expect(state.receivedAt == nil)
        #expect(!state.complete(old, observation: Self.host(), now: Self.now))
    }

    @Test
    func `failed refresh retains dated cache bounded backoff and recovery clears failure`() throws {
        var state = NetdataRefreshState(environmentID: "fixture")
        let initial = try #require(state.beginRefresh(now: Self.now))
        #expect(state.complete(initial, observation: Self.host(), now: Self.now))
        for index in 0..<8 {
            let time = Self.now.addingTimeInterval(Double(index + 1))
            let request = try #require(state.beginRefresh(now: time, force: true))
            #expect(state.complete(request, observation: nil, now: time))
            let row = state.systemsState(now: time)
            #expect(row.availability == .stale)
            #expect(row.receivedAt == Self.now)
            #expect(row.observedAt == Self.now)
            #expect(state.nextRefreshAt?.timeIntervalSince(time) == [10.0, 20, 40, 60, 60, 60, 60, 60][index])
        }
        let time = Self.now.addingTimeInterval(9)
        let request = try #require(state.beginRefresh(now: time, force: true))
        #expect(state.complete(request, observation: Self.host(sampledAt: time), now: time))
        #expect(!state.requestFailed)
        #expect(state.systemsState(now: time).availability == .available)
        #expect(state.receivedAt == time)
        #expect(state.nextRefreshAt == time.addingTimeInterval(10))
    }

    @Test
    func `sleep wake cancellation and wrong environment do not publish late results`() throws {
        var state = NetdataRefreshState(environmentID: "fixture")
        let sleeping = try #require(state.beginRefresh(now: Self.now))
        state.suspend()
        #expect(state.beginRefresh(now: Self.now, force: true) == nil)
        #expect(!state.complete(sleeping, observation: Self.host(), now: Self.now))
        state.wake(now: Self.now)
        let cancelled = try #require(state.beginRefresh(now: Self.now))
        #expect(state.cancel(cancelled, now: Self.now))
        let current = try #require(state.beginRefresh(now: Self.now))
        #expect(!state.complete(cancelled, observation: Self.host(), now: Self.now))
        #expect(state.complete(current, observation: Self.host(environmentID: "other"), now: Self.now))
        #expect(state.observation == nil)
        #expect(state.requestFailed)
        #expect(state.systemsState(now: Self.now).availability == .unavailable)
    }

    @Test
    func `partial samples keep independent absence and cache eventually becomes unavailable`() throws {
        var state = NetdataRefreshState(environmentID: "fixture")
        let request = try #require(state.beginRefresh(now: Self.now))
        #expect(state.complete(request, observation: Self.host(cpu: nil), now: Self.now))
        #expect(state.systemsState(now: Self.now).availability == .partial)
        #expect(state.systemsState(now: Self.now).cpuPercent == nil)
        #expect(state.systemsState(now: Self.now.addingTimeInterval(31)).availability == .stale)
        #expect(state.systemsState(now: Self.now.addingTimeInterval(301)).availability == .unavailable)
    }

    @Test
    func `invalid configuration and invalid clock never start a request`() {
        for id in ["", String(repeating: "x", count: 129), "fixture\n"] {
            var state = NetdataRefreshState(environmentID: id)
            #expect(state.beginRefresh(now: Self.now) == nil)
        }
        var state = NetdataRefreshState(environmentID: "fixture")
        #expect(state.beginRefresh(now: Date(timeIntervalSince1970: .nan)) == nil)
        #expect(state.inFlight == nil)
    }

    private static func host(
        environmentID: String = "fixture", cpu: Double? = 28, sampledAt: Date = Self.now) -> HubHostObservation
    {
        HubHostObservation(
            environmentID: environmentID,
            evidence: HubEvidence(source: "Synthetic fixture", observedAt: sampledAt, availability: .available),
            cpuPercent: cpu, memoryUsedBytes: nil, memoryAvailableBytes: 5_905_580_032)
    }
}
