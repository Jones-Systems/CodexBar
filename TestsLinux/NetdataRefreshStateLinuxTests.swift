import Foundation
import Testing
@testable import CodexBarCore

struct NetdataRefreshStateLinuxTests {
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test
    func `one in flight request and visible background schedule remain pure decisions`() throws {
        var state = NetdataRefreshState(environmentID: "fixture")
        let started = state.beginRefresh(now: Self.now)
        let request = try #require(started)
        let overlapping = state.beginRefresh(now: Self.now, force: true)
        #expect(overlapping == nil)
        #expect(state.systemsState(now: Self.now).isRefreshing)
        let completed = state.complete(request, observation: Self.host(), now: Self.now)
        #expect(completed)
        #expect(state.nextRefreshAt == Self.now.addingTimeInterval(10))
        let early = state.beginRefresh(now: Self.now.addingTimeInterval(9))
        #expect(early == nil)
        let visibleStarted = state.beginRefresh(now: Self.now.addingTimeInterval(10))
        let visible = try #require(visibleStarted)
        let visibleCompleted = state.complete(
            visible, observation: Self.host(), now: Self.now.addingTimeInterval(10), visible: true)
        #expect(visibleCompleted)
        #expect(state.nextRefreshAt == Self.now.addingTimeInterval(15))
    }

    @Test
    func `configuration changes and repeated completions cannot replace newer observations`() throws {
        var state = NetdataRefreshState(environmentID: "fixture")
        let oldStarted = state.beginRefresh(now: Self.now)
        let old = try #require(oldStarted)
        state.configure(environmentID: "second")
        let currentStarted = state.beginRefresh(now: Self.now)
        let current = try #require(currentStarted)
        let oldCompleted = state.complete(old, observation: Self.host(), now: Self.now)
        #expect(!oldCompleted)
        #expect(state.inFlight == current)
        let currentCompleted = state.complete(current, observation: Self.host(environmentID: "second"), now: Self.now)
        #expect(currentCompleted)
        let repeated = state.complete(current, observation: Self.host(cpu: 99), now: Self.now)
        #expect(!repeated)
        #expect(state.systemsState(now: Self.now).cpuPercent == 28)
        state.configure(environmentID: "fixture")
        #expect(state.observation == nil)
        #expect(state.receivedAt == nil)
        let originalHostCompleted = state.complete(old, observation: Self.host(), now: Self.now)
        #expect(!originalHostCompleted)
    }

    @Test
    func `failed refresh retains dated cache bounded backoff and recovery clears failure`() throws {
        var state = NetdataRefreshState(environmentID: "fixture")
        let initialStarted = state.beginRefresh(now: Self.now)
        let initial = try #require(initialStarted)
        let initialCompleted = state.complete(initial, observation: Self.host(), now: Self.now)
        #expect(initialCompleted)
        for index in 0..<8 {
            let time = Self.now.addingTimeInterval(Double(index + 1))
            let started = state.beginRefresh(now: time, force: true)
            let request = try #require(started)
            let completed = state.complete(request, observation: nil, now: time)
            #expect(completed)
            let row = state.systemsState(now: time)
            #expect(row.availability == .stale)
            #expect(row.receivedAt == Self.now)
            #expect(row.observedAt == Self.now)
            #expect(state.nextRefreshAt?.timeIntervalSince(time) == [10.0, 20, 40, 60, 60, 60, 60, 60][index])
        }
        let time = Self.now.addingTimeInterval(9)
        let started = state.beginRefresh(now: time, force: true)
        let request = try #require(started)
        let completed = state.complete(request, observation: Self.host(sampledAt: time), now: time)
        #expect(completed)
        #expect(!state.requestFailed)
        #expect(state.systemsState(now: time).availability == .available)
        #expect(state.receivedAt == time)
        #expect(state.nextRefreshAt == time.addingTimeInterval(10))
    }

    @Test
    func `sleep wake cancellation and wrong environment do not publish late results`() throws {
        var state = NetdataRefreshState(environmentID: "fixture")
        let sleepingStarted = state.beginRefresh(now: Self.now)
        let sleeping = try #require(sleepingStarted)
        state.suspend()
        let whileSleeping = state.beginRefresh(now: Self.now, force: true)
        #expect(whileSleeping == nil)
        let sleepingCompleted = state.complete(sleeping, observation: Self.host(), now: Self.now)
        #expect(!sleepingCompleted)
        state.wake(now: Self.now)
        let cancelledStarted = state.beginRefresh(now: Self.now)
        let cancelled = try #require(cancelledStarted)
        let didCancel = state.cancel(cancelled, now: Self.now)
        #expect(didCancel)
        let currentStarted = state.beginRefresh(now: Self.now)
        let current = try #require(currentStarted)
        let cancelledCompleted = state.complete(cancelled, observation: Self.host(), now: Self.now)
        #expect(!cancelledCompleted)
        let foreignCompleted = state.complete(current, observation: Self.host(environmentID: "other"), now: Self.now)
        #expect(foreignCompleted)
        #expect(state.observation == nil)
        #expect(state.requestFailed)
        #expect(state.systemsState(now: Self.now).availability == .unavailable)
    }

    @Test
    func `partial samples keep independent absence and cache eventually becomes unavailable`() throws {
        var state = NetdataRefreshState(environmentID: "fixture")
        let started = state.beginRefresh(now: Self.now)
        let request = try #require(started)
        let completed = state.complete(request, observation: Self.host(cpu: nil), now: Self.now)
        #expect(completed)
        #expect(state.systemsState(now: Self.now).availability == .partial)
        #expect(state.systemsState(now: Self.now).cpuPercent == nil)
        #expect(state.systemsState(now: Self.now.addingTimeInterval(31)).availability == .stale)
        #expect(state.systemsState(now: Self.now.addingTimeInterval(301)).availability == .unavailable)
    }

    @Test
    func `invalid configuration and invalid clock never start a request`() {
        for id in ["", String(repeating: "x", count: 129), "fixture\n"] {
            var state = NetdataRefreshState(environmentID: id)
            let started = state.beginRefresh(now: Self.now)
            #expect(started == nil)
        }
        var state = NetdataRefreshState(environmentID: "fixture")
        let started = state.beginRefresh(now: Date(timeIntervalSince1970: .nan))
        #expect(started == nil)
        #expect(state.inFlight == nil)
    }

    private static func host(
        environmentID: String = "fixture", cpu: Double? = 28, sampledAt: Date = Self.now) -> HubHostObservation
    {
        HubHostObservation(
            environmentID: environmentID,
            evidence: HubEvidence(source: "Synthetic fixture", observedAt: sampledAt, availability: .available),
            cpuPercent: cpu,
            memoryUsedBytes: nil,
            memoryAvailableBytes: 5_905_580_032)
    }
}
