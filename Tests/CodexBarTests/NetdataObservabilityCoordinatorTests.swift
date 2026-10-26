import AppKit
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct NetdataObservabilityCoordinatorTests {
    @Test
    func `disabled and rejected persisted configurations never bind schedule or construct a fetcher`() throws {
        var unsupported = netdataTestConfiguration()
        unsupported.version = 99
        var invalid = netdataTestConfiguration()
        invalid.host?.environmentID = "local"
        var disabled = netdataTestConfiguration()
        disabled.enabled = false
        let records: [Data?] = [
            nil, Data("corrupt".utf8), try JSONEncoder().encode(unsupported),
            try JSONEncoder().encode(invalid), try JSONEncoder().encode(disabled),
        ]
        for record in records {
            let defaults = InMemoryUserDefaults()
            defaults.set(record, forKey: SettingsStore.netdataConfigurationKey)
            let fixture = try NetdataAppTestFixture(defaults: defaults)
            defer { fixture.close() }
            let harness = NetdataCoordinatorHarness(settings: fixture.settings)
            harness.coordinator.start()
            harness.coordinator.start()
            harness.coordinator.refresh()
            #expect(harness.constructedHosts.isEmpty)
            #expect(harness.scheduler.active.isEmpty)
            #expect(harness.coordinator.bridge.refreshState(environmentID: "vps-a") == nil)
            harness.coordinator.stop()
        }
    }

    @Test
    func `initial cadence visible cadence backoff and manual coalescing use bridge deadlines`() async throws {
        let fixture = try NetdataAppTestFixture()
        defer { fixture.close() }
        try fixture.settings.applyNetdataConfiguration(netdataTestConfiguration())
        let harness = NetdataCoordinatorHarness(settings: fixture.settings)
        let coordinator = harness.coordinator
        coordinator.start()
        coordinator.start()
        await harness.fetches.waitForCalls(1)
        coordinator.refresh()
        coordinator.refresh()
        await harness.finish(observation: try netdataTestObservation(now: harness.clock.now()))
        #expect(await harness.fetches.callCount == 1)
        var due = try #require(coordinator.bridge.refreshState(environmentID: "vps-a")?.nextRefreshAt)
        #expect(due == harness.clock.now().addingTimeInterval(10))
        coordinator.setMenuVisible(true)
        coordinator.setSystemsVisible(true)
        coordinator.setMenuVisible(false)
        #expect(coordinator.visible)
        #expect(coordinator.bridge.refreshState(environmentID: "vps-a")?.nextRefreshAt == due)
        harness.advance(to: due)
        await harness.fetches.waitForCalls(2)
        await harness.finish(observation: try netdataTestObservation(now: harness.clock.now()))
        due = try #require(coordinator.bridge.refreshState(environmentID: "vps-a")?.nextRefreshAt)
        #expect(due == harness.clock.now().addingTimeInterval(5))

        for (index, interval) in [5.0, 10, 20, 40, 60, 60].enumerated() {
            harness.advance(to: due)
            await harness.fetches.waitForCalls(3 + index)
            await harness.finish(observation: nil)
            due = try #require(coordinator.bridge.refreshState(environmentID: "vps-a")?.nextRefreshAt)
            #expect(due == harness.clock.now().addingTimeInterval(interval))
            coordinator.setSystemsVisible(false)
            coordinator.setMenuVisible(true)
            #expect(coordinator.bridge.refreshState(environmentID: "vps-a")?.nextRefreshAt == due)
        }
        #expect(harness.scheduler.active.count == 1)
        #expect(harness.scheduler.maximumActive == 1)
        coordinator.refresh()
        await harness.fetches.waitForCalls(9)
        coordinator.refresh()
        await harness.finish(observation: try netdataTestObservation(now: harness.clock.now()))
        #expect(await harness.fetches.callCount == 9)
        coordinator.stop()
        #expect(harness.scheduler.active.isEmpty)
    }

    @Test
    func `cancel ignores cooperation and serializes changed IDs same IDs ABA and disable`() async throws {
        for transition in ["changed-id", "same-id", "aba", "disabled"] {
            let fixture = try NetdataAppTestFixture()
            defer { fixture.close() }
            let original = netdataTestConfiguration()
            try fixture.settings.applyNetdataConfiguration(original)
            let harness = NetdataCoordinatorHarness(settings: fixture.settings)
            let coordinator = harness.coordinator
            coordinator.start()
            await harness.fetches.waitForCalls(1)
            let oldTask = coordinator.fetchTask
            var replacement = netdataTestConfiguration(environmentID: "vps-b")
            if transition == "same-id" {
                replacement = original
                replacement.host?.origin = "http://localhost:19998"
            } else if transition == "disabled" {
                replacement = original
                replacement.enabled = false
            }
            try fixture.settings.applyNetdataConfiguration(replacement)
            if transition == "aba" {
                replacement = original
                try fixture.settings.applyNetdataConfiguration(replacement)
            }
            #expect(oldTask?.isCancelled == true)
            #expect(coordinator.isFetching)
            #expect(coordinator.bridge.refreshState(environmentID: "vps-a") == nil)
            #expect(coordinator.bridge.refreshState(environmentID: "vps-b") == nil)
            coordinator.refresh()
            #expect(harness.constructedHosts.count == 1)
            #expect(await harness.fetches.maximumActive == 1)
            await harness.fetches.finishNext(observation: try netdataTestObservation(now: harness.clock.now()))
            await oldTask?.value
            if transition == "disabled" {
                #expect(!coordinator.isFetching)
                #expect(harness.scheduler.active.isEmpty)
                #expect(await harness.fetches.callCount == 1)
            } else {
                await harness.fetches.waitForCalls(2)
                let id = try #require(replacement.host?.environmentID)
                #expect(coordinator.bridge.refreshState(environmentID: id)?.observation == nil)
                #expect(harness.constructedHosts.last == replacement.host)
                #expect(await harness.fetches.maximumActive == 1)
                coordinator.stop()
                await harness.finish(observation: nil)
            }
            coordinator.stop()
        }
    }

    @Test
    func `sleep wake stop and restart reject stale callbacks without releasing occupied slot`() async throws {
        let fixture = try NetdataAppTestFixture()
        defer { fixture.close() }
        try fixture.settings.applyNetdataConfiguration(netdataTestConfiguration())
        let harness = NetdataCoordinatorHarness(settings: fixture.settings)
        let coordinator = harness.coordinator
        coordinator.start()
        await harness.fetches.waitForCalls(1)
        let staleWake = try #require(harness.scheduler.active.first)
        harness.notifications.post(name: NSWorkspace.willSleepNotification, object: nil)
        coordinator.sleep()
        #expect(coordinator.bridge.isSuspended)
        #expect(coordinator.fetchTask?.isCancelled == true)
        #expect(harness.scheduler.active.isEmpty)
        staleWake.action()
        harness.notifications.post(name: NSWorkspace.didWakeNotification, object: nil)
        coordinator.wake()
        #expect(!coordinator.bridge.isSuspended)
        #expect(harness.constructedHosts.count == 1)
        await harness.finish(observation: nil)
        await harness.fetches.waitForCalls(2)
        #expect(harness.constructedHosts.count == 2)
        let draining = coordinator.fetchTask
        coordinator.stop()
        coordinator.stop()
        try fixture.settings.applyNetdataConfiguration(netdataTestConfiguration(environmentID: "vps-b"))
        staleWake.action()
        harness.notifications.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(harness.scheduler.active.isEmpty)
        #expect(!coordinator.isRunning)
        coordinator.start()
        #expect(harness.constructedHosts.count == 2)
        await harness.fetches.finishNext(observation: nil)
        await draining?.value
        await harness.fetches.waitForCalls(3)
        #expect(harness.constructedHosts.last?.environmentID == "vps-b")
        #expect(await harness.fetches.maximumActive == 1)
        staleWake.action()
        #expect(harness.scheduler.active.count == 1)
        coordinator.stop()
        await harness.finish(observation: nil)
        #expect(!coordinator.isFetching)
        #expect(harness.scheduler.active.isEmpty)
    }

    @Test
    func `presentation edits preserve requests while the shared clock ages stalled samples`() async throws {
        let fixture = try NetdataAppTestFixture()
        defer { fixture.close() }
        var configuration = netdataTestConfiguration()
        try fixture.settings.applyNetdataConfiguration(configuration)
        let harness = NetdataCoordinatorHarness(settings: fixture.settings)
        let coordinator = harness.coordinator
        coordinator.start()
        await harness.fetches.waitForCalls(1)
        await harness.finish(observation: try netdataTestObservation(now: harness.clock.now()))
        let sampledAt = harness.clock.now()
        harness.advance(to: sampledAt.addingTimeInterval(10))
        await harness.fetches.waitForCalls(2)
        configuration.host?.label = "Renamed"
        configuration.dashboardURL = "https://dashboard.example.invalid"
        try fixture.settings.applyNetdataConfiguration(configuration)
        coordinator.setSystemsVisible(true)
        coordinator.setMenuVisible(true)
        coordinator.setSettingsWindowVisible(false)
        #expect(coordinator.visible)
        coordinator.setMenuVisible(false)
        #expect(!coordinator.visible)
        #expect(coordinator.isRunning)
        #expect(coordinator.fetchTask?.isCancelled == false)
        #expect(harness.constructedHosts.count == 1)
        harness.advance(to: sampledAt.addingTimeInterval(31))
        let stale = coordinator.bridge.systemsState(environmentID: "vps-a", now: coordinator.presentationNow)
        #expect(stale.availability == .stale)
        #expect(stale.compactLabel(hostLabel: "Renamed") == "Renamed Stale")
        harness.advance(to: sampledAt.addingTimeInterval(301))
        let unavailable = coordinator.bridge.systemsState(environmentID: "vps-a", now: coordinator.presentationNow)
        #expect(unavailable.availability == .unavailable)
        #expect(unavailable.observedAt == sampledAt)
        #expect(unavailable.cpuPercent == 0)
        #expect(await harness.fetches.callCount == 2)
        coordinator.stop()
        await harness.finish(observation: nil)
    }
}

final class NetdataTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_700_000_000)

    func now() -> Date {
        self.lock.withLock { self.value }
    }

    func set(_ date: Date) {
        self.lock.withLock { self.value = date }
    }
}

@MainActor
final class NetdataTestScheduler: NetdataWakeScheduling {
    final class Wake: NetdataScheduledWake {
        let date: Date
        let action: @MainActor @Sendable () -> Void
        var cancelled = false

        init(date: Date, action: @escaping @MainActor @Sendable () -> Void) {
            self.date = date
            self.action = action
        }

        func cancel() {
            self.cancelled = true
        }
    }

    var wakes: [Wake] = []
    var maximumActive = 0
    var active: [Wake] {
        self.wakes.filter { !$0.cancelled }
    }

    func schedule(at date: Date, action: @escaping @MainActor @Sendable () -> Void) -> any NetdataScheduledWake {
        let wake = Wake(date: date, action: action)
        self.wakes.append(wake)
        self.maximumActive = max(self.maximumActive, self.active.count)
        return wake
    }

    func fire(at date: Date) {
        for wake in self.active where wake.date <= date {
            wake.cancel()
            wake.action()
        }
    }
}

/// Deliberately ignores cancellation until the test releases the physical request.
actor NetdataHeldFetches {
    private var pending: [CheckedContinuation<HubHostObservation, any Error>] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var callCount = 0
    private(set) var maximumActive = 0

    func fetch() async throws -> HubHostObservation {
        try await withCheckedThrowingContinuation { continuation in
            self.pending.append(continuation)
            self.callCount += 1
            self.maximumActive = max(self.maximumActive, self.pending.count)
            let ready = self.waiters.filter { $0.0 <= self.callCount }
            self.waiters.removeAll { $0.0 <= self.callCount }
            for (_, waiter) in ready { waiter.resume() }
        }
    }

    func waitForCalls(_ count: Int) async {
        if self.callCount >= count { return }
        await withCheckedContinuation { self.waiters.append((count, $0)) }
    }

    func finishNext(observation: HubHostObservation?) {
        guard !self.pending.isEmpty else {
            Issue.record("No held Netdata request to release")
            return
        }
        let continuation = self.pending.removeFirst()
        if let observation {
            continuation.resume(returning: observation)
        } else {
            continuation.resume(throwing: URLError(.cannotConnectToHost))
        }
    }
}

struct NetdataHeldFetcher: NetdataObservationFetching {
    let fetches: NetdataHeldFetches

    func fetch(now: Date) async throws -> HubHostObservation {
        try await self.fetches.fetch()
    }
}

@MainActor
final class NetdataCoordinatorHarness {
    let clock = NetdataTestClock()
    let scheduler = NetdataTestScheduler()
    let notifications = NotificationCenter()
    let fetches = NetdataHeldFetches()
    private(set) var constructedHosts: [NetdataConfiguration.Host] = []
    private let settings: SettingsStore
    private(set) lazy var coordinator: NetdataObservabilityCoordinator = {
        let clock = self.clock
        let fetches = self.fetches
        return NetdataObservabilityCoordinator(
            settings: self.settings,
            clock: { clock.now() },
            scheduler: self.scheduler,
            workspaceNotifications: self.notifications,
            makeFetcher: { [weak self] host in
                self?.constructedHosts.append(host)
                return NetdataHeldFetcher(fetches: fetches)
            })
    }()

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func advance(to date: Date) {
        self.clock.set(date)
        self.scheduler.fire(at: date)
    }

    func finish(observation: HubHostObservation?) async {
        let task = self.coordinator.fetchTask
        await self.fetches.finishNext(observation: observation)
        await task?.value
    }
}

func netdataTestObservation(now: Date, environmentID: String = "vps-a") throws -> HubHostObservation {
    let guid = "11111111-2222-3333-4444-555555555555"
    func payload(context: String, dimensions: [String], unit: String, values: [Double]) throws -> Data {
        var row: [Any] = [now.timeIntervalSince1970]
        row.append(contentsOf: values.map { [$0, 0, 0] })
        return try JSONSerialization.data(withJSONObject: [
            "api": 3,
            "summary": ["nodes": [["mg": guid]], "contexts": [["id": context]]],
            "view": ["dimensions": ["ids": dimensions, "units": Array(repeating: unit, count: dimensions.count)]],
            "result": [
                "labels": ["time"] + dimensions,
                "data": [row],
                "point": ["value": 0, "arp": 1, "pa": 2],
            ],
        ])
    }
    return try NetdataReadOnlyFacade.decode(
        cpuData: payload(
            context: "system.cpu",
            dimensions: ["guest_nice", "guest", "steal", "softirq", "irq", "user", "system", "nice", "iowait"],
            unit: "percentage",
            values: Array(repeating: 0, count: 9)),
        availableMemoryData: payload(context: "mem.available", dimensions: ["avail"], unit: "MiB", values: [1024]),
        expectedMachineGUID: guid,
        environmentID: environmentID,
        now: now)
}
