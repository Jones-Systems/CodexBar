import AppKit
import CodexBarCore
import Observation

@MainActor
protocol NetdataScheduledWake: AnyObject {
    func cancel()
}

@MainActor
protocol NetdataWakeScheduling {
    func schedule(at date: Date, action: @escaping @MainActor @Sendable () -> Void) -> any NetdataScheduledWake
}

@MainActor
struct NetdataTimerScheduler: NetdataWakeScheduling {
    private final class Wake: NetdataScheduledWake {
        let timer: Timer

        init(timer: Timer) {
            self.timer = timer
        }

        func cancel() {
            self.timer.invalidate()
        }
    }

    func schedule(at date: Date, action: @escaping @MainActor @Sendable () -> Void) -> any NetdataScheduledWake {
        let timer = Timer(fire: date, interval: 0, repeats: false) { _ in
            MainActor.assumeIsolated { action() }
        }
        // Continue aging the menu's sample while AppKit is tracking it.
        RunLoop.main.add(timer, forMode: .common)
        return Wake(timer: timer)
    }
}

/// One app lifetime, one physical fetch slot, and one scheduled wake shared by both consumers.
@MainActor
@Observable
final class NetdataObservabilityCoordinator {
    typealias FetcherFactory = (NetdataConfiguration.Host) throws -> any NetdataObservationFetching

    let bridge: NetdataObservabilityBridge
    private(set) var presentationNow: Date
    private(set) var isRunning = false
    private(set) var isSleeping = false
    private(set) var menuVisible = false
    private(set) var systemsVisible = false
    private(set) var isFetching = false
    private let settings: SettingsStore
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private let scheduler: any NetdataWakeScheduling
    @ObservationIgnored private let makeFetcher: FetcherFactory
    @ObservationIgnored private let workspaceNotifications: NotificationCenter
    @ObservationIgnored private var systemsTabVisible = false
    @ObservationIgnored private var settingsWindowVisible = true
    @ObservationIgnored private var settingsToken: NSObjectProtocol?
    @ObservationIgnored private var notificationTokens: [NSObjectProtocol] = []
    @ObservationIgnored private var lifecycleID = UUID()
    @ObservationIgnored private var binding: NetdataConfiguration.TransportIdentity?
    @ObservationIgnored private(set) var fetchTask: Task<Void, Never>?
    @ObservationIgnored private var fetchID: UUID?
    @ObservationIgnored private var scheduledWake: (any NetdataScheduledWake)?
    @ObservationIgnored private var wakeID: UUID?

    init(
        settings: SettingsStore,
        bridge: NetdataObservabilityBridge = NetdataObservabilityBridge(),
        clock: @escaping @Sendable () -> Date = { Date() },
        scheduler: any NetdataWakeScheduling = NetdataTimerScheduler(),
        workspaceNotifications: NotificationCenter = NSWorkspace.shared.notificationCenter,
        makeFetcher: @escaping FetcherFactory = { host in
            try NetdataLoopbackClient(
                origin: host.origin,
                expectedMachineGUID: host.expectedMachineGUID,
                environmentID: host.environmentID)
        })
    {
        self.settings = settings
        self.bridge = bridge
        self.clock = clock
        self.scheduler = scheduler
        self.workspaceNotifications = workspaceNotifications
        self.makeFetcher = makeFetcher
        self.presentationNow = clock()
    }

    var configuration: NetdataConfiguration {
        self.settings.netdataConfiguration
    }

    var visible: Bool {
        self.menuVisible || self.systemsVisible
    }

    func start() {
        guard !self.isRunning else { return }
        self.lifecycleID = UUID()
        self.isRunning = true
        self.isSleeping = false
        self.bridge.wake(now: self.clock())
        self.observeSettings(lifecycleID: self.lifecycleID)
        self.observeWorkspace(lifecycleID: self.lifecycleID)
        self.reconcile()
    }

    func stop() {
        guard self.isRunning else { return }
        self.isRunning = false
        self.lifecycleID = UUID()
        self.cancelWake()
        for token in self.notificationTokens {
            self.workspaceNotifications.removeObserver(token)
        }
        self.notificationTokens.removeAll()
        if let settingsToken { self.settings.netdataConfigurationNotifications.removeObserver(settingsToken) }
        self.settingsToken = nil
        self.bridge.suspend()
        self.invalidateBinding()
    }

    func sleep() {
        guard self.isRunning, !self.isSleeping else { return }
        self.isSleeping = true
        self.bridge.suspend()
        self.cancelWake()
        self.invalidateBinding()
    }

    func wake() {
        guard self.isRunning, self.isSleeping else { return }
        self.isSleeping = false
        self.bridge.wake(now: self.clock())
        self.reconcile()
    }

    func setMenuVisible(_ visible: Bool) {
        self.menuVisible = visible
    }

    func setSystemsVisible(_ visible: Bool) {
        self.systemsTabVisible = visible
        self.systemsVisible = visible && self.settingsWindowVisible
    }

    func setSettingsWindowVisible(_ visible: Bool) {
        self.settingsWindowVisible = visible
        self.systemsVisible = visible && self.systemsTabVisible
    }

    func refresh() {
        // An occupied request satisfies all manual refreshes; do not queue a forced follow-up.
        self.reconcile(force: self.fetchTask == nil)
    }

    private func observeSettings(lifecycleID: UUID) {
        // SettingsStore posts synchronously after Apply on the main actor. Invalidate every transport
        // transition immediately, even A -> B -> A before an asynchronous observation callback could run.
        self.settingsToken = self.settings.netdataConfigurationNotifications.addObserver(
            forName: SettingsStore.netdataConfigurationDidChange, object: nil, queue: nil)
        { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isRunning, self.lifecycleID == lifecycleID else { return }
                self.reconcile()
            }
        }
    }

    private func observeWorkspace(lifecycleID: UUID) {
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification] {
            let token = self.workspaceNotifications.addObserver(
                forName: name, object: nil, queue: .main)
            { [weak self] notification in
                let sleeping = notification.name == NSWorkspace.willSleepNotification
                MainActor.assumeIsolated {
                    guard let self, self.isRunning, self.lifecycleID == lifecycleID else { return }
                    if sleeping { self.sleep() } else { self.wake() }
                }
            }
            self.notificationTokens.append(token)
        }
    }

    private func invalidateBinding() {
        if let binding { self.bridge.removeBinding(environmentID: binding.environmentID) }
        self.binding = nil
        // Cancellation is cooperative. Keep the physical slot occupied until the task actually returns,
        // including a changed environment ID or A -> B -> A configuration while the old fetch ignores cancel.
        self.fetchTask?.cancel()
    }

    private func reconcile(force: Bool = false) {
        self.cancelWake()
        guard self.isRunning else { return }
        self.presentationNow = self.clock()
        let host = self.configuration.activeHost
        if self.binding != host?.transportIdentity {
            self.invalidateBinding()
        }
        guard !self.isSleeping, let host else { return }
        if self.fetchTask == nil {
            if self.binding == nil {
                guard let fetcher = try? self.makeFetcher(host),
                      self.bridge.bind(environmentID: host.environmentID, fetcher: fetcher)
                else { return }
                self.binding = host.transportIdentity
            }
            let due = self.bridge.refreshState(environmentID: host.environmentID)?.nextRefreshAt
            if force || due.map({ $0 <= self.presentationNow }) != false {
                self.beginFetch(host: host, force: force)
            }
        }
        self.scheduleWake()
    }

    private func beginFetch(host: NetdataConfiguration.Host, force: Bool) {
        guard self.fetchTask == nil else { return }
        let id = UUID()
        self.fetchID = id
        self.isFetching = true
        let bridge = self.bridge
        let clock = self.clock
        let visible = self.visible
        self.fetchTask = Task { @MainActor [weak self] in
            _ = try? await bridge.refresh(
                environmentID: host.environmentID, visible: visible, force: force, clock: clock)
            guard let self, self.fetchID == id else { return }
            self.fetchTask = nil
            self.fetchID = nil
            self.isFetching = false
            // Only the draining task releases its slot. Reconcile the latest configuration and lifecycle,
            // never the captured host; stopped/sleeping collectors cannot restart from this completion.
            self.reconcile()
        }
    }

    private func cancelWake() {
        self.scheduledWake?.cancel()
        self.scheduledWake = nil
        self.wakeID = nil
    }

    private func scheduleWake() {
        guard self.isRunning, !self.isSleeping, self.configuration.activeHost != nil else { return }
        var next = self.presentationNow.addingTimeInterval(1)
        if self.fetchTask == nil, let binding,
           let due = self.bridge.refreshState(environmentID: binding.environmentID)?.nextRefreshAt
        {
            next = min(next, due)
        }
        let id = UUID()
        let lifecycleID = self.lifecycleID
        self.wakeID = id
        self.scheduledWake = self.scheduler.schedule(at: next) { [weak self] in
            guard let self, self.wakeID == id, self.lifecycleID == lifecycleID, self.isRunning else { return }
            self.scheduledWake = nil
            self.wakeID = nil
            self.reconcile()
        }
    }
}
