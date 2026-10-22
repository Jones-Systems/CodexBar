import Dispatch
import Foundation

@MainActor
protocol JonesUpdateDriver: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticallyDownloadsUpdates: Bool { get set }
    var canCheckForUpdates: Bool { get }
    var stateDidChange: (@MainActor () -> Void)? { get set }
    func start() throws
    func checkForUpdates(_ sender: Any?)
    func checkForUpdatesInBackground()
}

/// Destruction invalidates the resource even when its owner never reaches a terminal callback.
final class JonesUpdateCancellation {
    private let cancel: () -> Void

    init(_ cancel: @escaping () -> Void) {
        self.cancel = cancel
    }

    deinit {
        self.cancel()
    }
}

@MainActor
final class JonesUpdateController: NSObject, UpdaterProviding {
    typealias IdleSafetyProvider = @MainActor () -> JonesUpdateIdleSafetyInputs
    typealias CapacityProvider = @MainActor () -> JonesUpdateAdmission.Capacity
    typealias IdleScheduler = @MainActor (@escaping @MainActor () -> Void) -> JonesUpdateCancellation

    private struct PreparedInstallation {
        let update: JonesPreparedUpdate
        let install: @MainActor () -> Void
    }

    let policy: JonesUpdateTrustPolicy
    let updateStatus = UpdateStatus()
    let detail: JonesUpdateDetail
    // Existing consumers can retain the protocol; Jones UI localizes detail.state instead.
    let unavailableReason: String? = nil
    private(set) var lifecycle: JonesUpdateLifecycle
    private var driver: (any JonesUpdateDriver)?
    private var started = false
    private var preparedInstallation: PreparedInstallation?
    private var idleTimer: JonesUpdateCancellation?
    private var idleSafetyProvider: IdleSafetyProvider
    private let capacityProvider: CapacityProvider
    private let clock: @MainActor () -> TimeInterval
    private let launchTime: TimeInterval
    private let scheduleIdle: IdleScheduler
    private let describeFailure: @MainActor (JonesUpdateFailure) -> String?

    /// The default safety/capacity inputs deny automation until integration supplies known values.
    convenience init(
        policy: JonesUpdateTrustPolicy,
        savedAutoUpdate: Bool,
        idleSafetyProvider: @escaping IdleSafetyProvider = { .unknown },
        capacityProvider: @escaping CapacityProvider = { .unknown },
        describeFailure: @escaping @MainActor (JonesUpdateFailure) -> String? = { _ in nil }) throws
    {
        try policy.validateHostBundle(.main)
        self.init(
            policy: policy,
            driver: nil,
            idleSafetyProvider: idleSafetyProvider,
            capacityProvider: capacityProvider,
            describeFailure: describeFailure)
        guard policy.isEnabled else { return }
        #if canImport(Sparkle) && ENABLE_SPARKLE
        self.connect(JonesSparkleUpdateDriver(delegate: self), savedAutoUpdate: savedAutoUpdate)
        #else
        self.finish(.disabled(.sparkleUnavailable))
        #endif
    }

    /// Model tests inject a driver and scheduler; this initializer never reads app defaults or launches Sparkle.
    init(
        policy: JonesUpdateTrustPolicy,
        driver: (any JonesUpdateDriver)?,
        savedAutoUpdate: Bool = false,
        idleSafetyProvider: @escaping IdleSafetyProvider = { .unknown },
        capacityProvider: @escaping CapacityProvider = { .unknown },
        clock: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        scheduleIdle: @escaping IdleScheduler = JonesUpdateController.scheduleIdleTimer,
        describeFailure: @escaping @MainActor (JonesUpdateFailure) -> String? = { _ in nil })
    {
        self.policy = policy
        let initial: JonesUpdateState = policy.isEnabled ? .idle : .disabled(.channelDisabled)
        self.lifecycle = JonesUpdateLifecycle(disabledReason: policy.isEnabled ? nil : .channelDisabled)
        self.detail = JonesUpdateDetail(state: initial)
        self.idleSafetyProvider = idleSafetyProvider
        self.capacityProvider = capacityProvider
        self.clock = clock
        self.launchTime = clock()
        self.scheduleIdle = scheduleIdle
        self.describeFailure = describeFailure
        super.init()
        if policy.isEnabled, let driver {
            self.connect(driver, savedAutoUpdate: savedAutoUpdate)
        }
    }

    var isAvailable: Bool { self.policy.isEnabled && self.started }

    var automaticallyChecksForUpdates: Bool {
        get { self.driver?.automaticallyChecksForUpdates ?? false }
        set {
            self.driver?.automaticallyChecksForUpdates = newValue
            self.refreshDriverState()
        }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { self.driver?.automaticallyDownloadsUpdates ?? false }
        set {
            self.driver?.automaticallyDownloadsUpdates = newValue
            self.refreshDriverState()
        }
    }

    func checkForUpdates(_ sender: Any?) {
        guard self.isAvailable, self.driver?.canCheckForUpdates == true else { return }
        self.driver?.checkForUpdates(sender)
    }

    func checkForUpdatesInBackground() {
        guard self.isAvailable, self.driver?.canCheckForUpdates == true else { return }
        self.driver?.checkForUpdatesInBackground()
    }

    func installUpdate() {
        self.installPreparedUpdate()
    }

    func setIdleSafetyProvider(_ provider: @escaping IdleSafetyProvider) {
        self.idleSafetyProvider = provider
    }

    /// Parent integration can explicitly deny idle apply without discarding a prepared normal-quit update.
    func disableIdleApplication() {
        self.idleSafetyProvider = { .unknown }
        self.detail.idleDecision = .deferred(.unknown(.hidIdleTime))
    }

    @discardableResult
    func evaluateIdleApplication() -> JonesUpdateApplyPolicy.Decision {
        guard let prepared = self.lifecycle.state.preparedUpdate else {
            self.detail.idleDecision = .deferred(.notPrepared)
            return self.detail.idleDecision
        }
        let now = self.clock()
        let decision = JonesUpdateApplyPolicy.evaluate(.init(
            preparedAge: now - prepared.preparedAt,
            launchAge: now - self.launchTime,
            automaticUpdatesEnabled: self.automaticallyChecksForUpdates && self.automaticallyDownloadsUpdates,
            safety: self.idleSafetyProvider()))
        self.detail.idleDecision = decision
        if decision == .eligible { self.installPreparedUpdate() }
        return decision
    }

    func beginCheck() {
        self.clearPreparedInstallation()
        self.lifecycle.beginCheck()
        self.publishLifecycle()
    }

    func admitDownload(_ candidate: JonesUpdateAdmission.Candidate) throws {
        do {
            try self.policy.validateArchiveURL(candidate.archiveURL)
            // 2.9.3 skips the veto hook on delta-to-full fallback; willDownloadUpdate cannot veto it.
            guard !candidate.isDelta else { throw JonesUpdateAdmission.Rejection.unsupportedDelta }
            guard candidate.installationType == "application" else {
                throw JonesUpdateAdmission.Rejection.unsupportedInstallationType
            }
            _ = try JonesUpdateAdmission.validate(
                archiveLength: candidate.archiveLength, capacity: self.capacityProvider())
        } catch let reason as JonesUpdateTrustPolicy.Rejection {
            throw self.rejecting(.trust(reason))
        } catch let reason as JonesUpdateAdmission.Rejection {
            throw self.rejecting(.admission(reason))
        }
    }

    func found(version: String) {
        self.lifecycle.found(version: version, generation: self.lifecycle.generation)
        self.publishLifecycle()
    }

    func preparing(version: String) {
        self.lifecycle.preparing(version: version, generation: self.lifecycle.generation)
        self.publishLifecycle()
    }

    @discardableResult
    func prepared(
        version: String,
        generation: UUID,
        install: @escaping @MainActor () -> Void) -> Bool
    {
        guard let prepared = self.lifecycle.prepared(version: version, generation: generation, at: self.clock()) else {
            return false
        }
        self.preparedInstallation = PreparedInstallation(update: prepared, install: install)
        self.publishLifecycle()
        self.idleTimer = self.scheduleIdle { [weak self] in
            self?.evaluateIdleApplication()
        }
        return true
    }

    func willInstall(version: String) {
        guard self.lifecycle.willInstall(version: version, generation: self.lifecycle.generation) else { return }
        self.clearPreparedInstallation()
        self.publishLifecycle()
    }

    func finish(_ outcome: JonesUpdateOutcome) {
        self.clearPreparedInstallation()
        self.lifecycle.finish(outcome)
        self.publishLifecycle()
    }

    func finishCycle(error: Error?) {
        if let error {
            self.record(error: error)
        } else if self.lifecycle.state == .checking {
            // A successful cycle is not evidence of installation or even of an available update.
            self.finish(.idle)
        } else if case .downloading = self.lifecycle.state {
            self.finish(.idle)
        } else if case .preparing = self.lifecycle.state {
            self.finish(.idle)
        }
    }

    func userChose(_ choice: JonesUpdateUserChoice, version: String, installationStarted: Bool = false) {
        guard self.lifecycle.version == version else { return }
        switch choice {
        case .install:
            self.clearPreparedInstallation()
            if self.lifecycle.state.preparedUpdate != nil || installationStarted {
                self.willInstall(version: version)
            }
            self.publishLifecycle()
        case .skip:
            self.finish(.skipped)
        case .dismiss:
            // A downloaded dismissal does not establish installer readiness.
            if self.lifecycle.state.preparedUpdate == nil { self.finish(.idle) }
        }
    }

    func record(error: Error) {
        // Preserve the specific admission/trust diagnosis when Sparkle subsequently wraps it.
        if case .failed = self.lifecycle.state { return }
        let native = error as NSError
        // Sparkle 2.9.3 SUErrors.h: no-update, authorization cancelled, authorization deferred.
        if native.domain == "SUSparkleErrorDomain", native.code == 1001 {
            self.finish(.upToDate)
        } else if native.domain == "SUSparkleErrorDomain", [4007, 4008].contains(native.code) {
            self.finish(.cancelled)
        } else {
            self.finish(.failed(.sparkle(domain: native.domain, code: native.code)))
        }
    }

    private func connect(_ driver: any JonesUpdateDriver, savedAutoUpdate: Bool) {
        self.driver = driver
        driver.stateDidChange = { [weak self] in self?.refreshDriverState() }
        driver.automaticallyChecksForUpdates = savedAutoUpdate
        driver.automaticallyDownloadsUpdates = savedAutoUpdate
        do {
            try driver.start()
            self.started = true
        } catch {
            self.record(error: error)
        }
        self.refreshDriverState()
    }

    private func refreshDriverState() {
        self.detail.canCheckForUpdates = self.isAvailable && self.driver?.canCheckForUpdates == true
        self.detail.automaticUpdatesEnabled = self.automaticallyChecksForUpdates && self.automaticallyDownloadsUpdates
    }

    private func installPreparedUpdate() {
        guard let prepared = self.preparedInstallation,
              self.lifecycle.requestInstall(prepared.update)
        else { return }
        // Consume before invoking a reentrant Sparkle callback; neither another click nor a timer can reuse it.
        self.clearPreparedInstallation()
        self.publishLifecycle()
        prepared.install()
    }

    private func clearPreparedInstallation() {
        self.idleTimer = nil
        self.preparedInstallation = nil
        self.detail.idleDecision = .deferred(.notPrepared)
    }

    private func publishLifecycle() {
        self.detail.update(state: self.lifecycle.state)
        self.updateStatus.isUpdateReady = self.lifecycle.state.preparedUpdate != nil
        self.refreshDriverState()
    }

    private static func scheduleIdleTimer(_ tick: @escaping @MainActor () -> Void) -> JonesUpdateCancellation {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 60, repeating: 60, leeway: .seconds(15))
        timer.setEventHandler {
            MainActor.assumeIsolated { tick() }
        }
        timer.resume()
        return JonesUpdateCancellation { timer.cancel() }
    }

    private func rejecting(_ reason: JonesUpdateFailure) -> NSError {
        self.finish(.failed(reason))
        var userInfo: [String: Any] = [:]
        if let description = self.describeFailure(reason) {
            userInfo[NSLocalizedDescriptionKey] = description
        }
        return NSError(domain: "com.jonessystems.codexbar.update", code: 1, userInfo: userInfo)
    }
}

#if canImport(Sparkle) && ENABLE_SPARKLE
import Sparkle

// Sparkle 2.9.3 marks SPUUpdaterDelegate NS_SWIFT_UI_ACTOR. Keep every transition synchronous.
extension JonesUpdateController: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        self.policy.feedURL?.absoluteString
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> { [] }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        self.beginCheck()
    }

    func updater(
        _ updater: SPUUpdater,
        shouldProceedWithUpdate item: SUAppcastItem,
        updateCheck: SPUUpdateCheck) throws
    {
        try self.admitDownload(.init(
            archiveURL: item.fileURL, archiveLength: item.contentLength,
            isDelta: item.isDeltaUpdate, installationType: item.installationType))
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        self.found(version: item.versionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        self.finish(.upToDate)
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        self.found(version: item.versionString)
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        self.preparing(version: item.versionString)
    }

    func updater(_ updater: SPUUpdater, willExtractUpdate item: SUAppcastItem) {
        self.preparing(version: item.versionString)
    }

    func updater(_ updater: SPUUpdater, didExtractUpdate item: SUAppcastItem) {
        self.preparing(version: item.versionString)
    }

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool
    {
        self.prepared(
            version: item.versionString,
            generation: self.lifecycle.generation,
            install: immediateInstallHandler)
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        self.willInstall(version: item.versionString)
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        self.record(error: error)
    }

    func userDidCancelDownload(_ updater: SPUUpdater) {
        self.finish(.cancelled)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        self.record(error: error)
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        self.finishCycle(error: error)
    }

    func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate item: SUAppcastItem,
        state: SPUUserUpdateState)
    {
        switch choice {
        case .install:
            self.userChose(.install, version: item.versionString, installationStarted: state.stage == .installing)
        case .skip:
            self.userChose(.skip, version: item.versionString)
        case .dismiss:
            self.userChose(.dismiss, version: item.versionString)
        @unknown default:
            self.finish(.cancelled)
        }
    }
}

@MainActor
private final class JonesSparkleUpdateDriver: JonesUpdateDriver {
    private let controller: SPUStandardUpdaterController
    private var observations: [NSKeyValueObservation] = []
    var stateDidChange: (@MainActor () -> Void)?

    init(delegate: any SPUUpdaterDelegate) {
        self.controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: delegate, userDriverDelegate: nil)
        let keyPaths: [KeyPath<SPUUpdater, Bool>] = [
            \SPUUpdater.canCheckForUpdates,
            \SPUUpdater.automaticallyChecksForUpdates,
            \SPUUpdater.automaticallyDownloadsUpdates,
        ]
        for keyPath in keyPaths {
            self.observations.append(self.controller.updater.observe(keyPath, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.stateDidChange?() }
            })
        }
    }

    var automaticallyChecksForUpdates: Bool {
        get { self.controller.updater.automaticallyChecksForUpdates }
        set { self.controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { self.controller.updater.automaticallyDownloadsUpdates }
        set { self.controller.updater.automaticallyDownloadsUpdates = newValue }
    }

    var canCheckForUpdates: Bool { self.controller.updater.canCheckForUpdates }

    func start() throws {
        try self.controller.updater.start()
    }

    func checkForUpdates(_ sender: Any?) {
        self.controller.checkForUpdates(sender)
    }

    func checkForUpdatesInBackground() {
        self.controller.updater.checkForUpdatesInBackground()
    }
}
#endif
