import Foundation
import Testing
@testable import CodexBar

@MainActor
private final class JonesUpdateFixtureDriver: JonesUpdateDriver {
    var automaticallyChecksForUpdates = false
    var automaticallyDownloadsUpdates = false
    var canCheckForUpdates = true
    var stateDidChange: (@MainActor () -> Void)?
    var starts = 0
    var checks = 0
    var backgroundChecks = 0
    var startError: Error?

    func start() throws {
        self.starts += 1
        if let startError { throw startError }
    }

    func checkForUpdates(_ sender: Any?) {
        self.checks += 1
    }

    func checkForUpdatesInBackground() {
        self.backgroundChecks += 1
    }
}

@MainActor
private final class JonesUpdateFixtureTimer {
    var starts = 0
    var cancellations = 0
    var tick: (@MainActor () -> Void)?

    func schedule(_ tick: @escaping @MainActor () -> Void) -> JonesUpdateCancellation {
        self.starts += 1
        self.tick = tick
        return JonesUpdateCancellation { [weak self] in
            self?.cancellations += 1
            self?.tick = nil
        }
    }
}

@MainActor
struct JonesUpdateControllerTests {
    @Test
    func `disabled channel starts no driver and manual actions have no effects`() throws {
        let driver = JonesUpdateFixtureDriver()
        let controller = try JonesUpdateController(
            policy: JonesUpdateTestFixtures.policy(channel: "none"), driver: driver)
        #expect(driver.starts == 0)
        #expect(!controller.isAvailable)
        #expect(!controller.detail.canCheckForUpdates)
        #expect(controller.detail.state == .disabled(.channelDisabled))
        controller.checkForUpdates(nil)
        controller.checkForUpdatesInBackground()
        controller.installUpdate()
        #expect(driver.checks == 0)
        #expect(driver.backgroundChecks == 0)
        #expect(!controller.updateStatus.isUpdateReady)
    }

    @Test
    func `check availability and automatic preferences follow the injected driver`() throws {
        let driver = JonesUpdateFixtureDriver()
        let controller = try JonesUpdateController(
            policy: JonesUpdateTestFixtures.policy(), driver: driver, savedAutoUpdate: true)
        let updater: any UpdaterProviding = controller
        #expect(updater.isAvailable)
        #expect(driver.starts == 1)
        #expect(driver.automaticallyChecksForUpdates)
        #expect(driver.automaticallyDownloadsUpdates)
        driver.canCheckForUpdates = false
        driver.stateDidChange?()
        #expect(!controller.detail.canCheckForUpdates)
        updater.checkForUpdates(nil)
        controller.checkForUpdatesInBackground()
        #expect(driver.checks == 0)
        #expect(driver.backgroundChecks == 0)
        driver.canCheckForUpdates = true
        driver.stateDidChange?()
        #expect(controller.detail.canCheckForUpdates)
        updater.checkForUpdates(nil)
        controller.checkForUpdatesInBackground()
        #expect(driver.checks == 1)
        #expect(driver.backgroundChecks == 1)
        updater.automaticallyChecksForUpdates = false
        #expect(!driver.automaticallyChecksForUpdates)
        #expect(!controller.detail.automaticUpdatesEnabled)
    }

    @Test
    func `preparation is synchronous and manual apply consumes the handler before reentrancy`() throws {
        let timer = JonesUpdateFixtureTimer()
        let controller = try JonesUpdateController(
            policy: JonesUpdateTestFixtures.policy(),
            driver: JonesUpdateFixtureDriver(),
            scheduleIdle: timer.schedule)
        var installations = 0
        controller.beginCheck()
        controller.found(version: "135.2")
        controller.preparing(version: "135.2")
        #expect(!controller.updateStatus.isUpdateReady)
        #expect(timer.starts == 0)
        let accepted = controller.prepared(
            version: "135.2", generation: controller.lifecycle.generation)
        { [weak controller] in
            installations += 1
            controller?.installUpdate()
        }
        #expect(accepted)
        #expect(controller.updateStatus.isUpdateReady)
        #expect(timer.starts == 1)
        #expect(controller.detail.installsPreparedUpdateAtQuit)
        controller.installUpdate()
        controller.installUpdate()
        #expect(installations == 1)
        #expect(!controller.updateStatus.isUpdateReady)
        #expect(controller.detail.state == .installing(version: "135.2"))
        #expect(timer.cancellations == 1)
    }

    @Test
    func `manual apply before ready neither installs nor starts a new check`() throws {
        let driver = JonesUpdateFixtureDriver()
        let controller = try JonesUpdateController(policy: JonesUpdateTestFixtures.policy(), driver: driver)
        controller.installUpdate()
        controller.beginCheck()
        controller.found(version: "135.2")
        controller.installUpdate()
        #expect(driver.checks == 0)
        #expect(controller.detail.state == .downloading(version: "135.2"))
    }

    @Test
    func `terminal callbacks clear handlers timers and stale preparation`() throws {
        let outcomes: [JonesUpdateOutcome] = [
            .cancelled, .skipped, .upToDate, .failed(.sparkle(domain: "fixture", code: 1)),
        ]
        for outcome in outcomes {
            let timer = JonesUpdateFixtureTimer()
            let controller = try JonesUpdateController(
                policy: JonesUpdateTestFixtures.policy(),
                driver: JonesUpdateFixtureDriver(),
                scheduleIdle: timer.schedule)
            var installations = 0
            controller.beginCheck()
            controller.found(version: "135.2")
            let generation = controller.lifecycle.generation
            #expect(controller.prepared(version: "135.2", generation: generation) { installations += 1 })
            let staleTick = timer.tick
            controller.finish(outcome)
            #expect(!controller.prepared(version: "135.2", generation: generation) { installations += 1 })
            controller.installUpdate()
            staleTick?()
            #expect(installations == 0)
            #expect(timer.cancellations == 1)
            #expect(controller.detail.state == outcome.state)
            #expect(!controller.updateStatus.isUpdateReady)
        }
    }

    @Test
    func `dismissal and successful cycle do not fabricate readiness or installation`() throws {
        let timer = JonesUpdateFixtureTimer()
        let controller = try JonesUpdateController(
            policy: JonesUpdateTestFixtures.policy(),
            driver: JonesUpdateFixtureDriver(),
            scheduleIdle: timer.schedule)
        controller.beginCheck()
        controller.found(version: "135.2")
        controller.preparing(version: "135.2")
        controller.userChose(.dismiss, version: "135.2")
        #expect(!controller.updateStatus.isUpdateReady)
        #expect(controller.detail.state == .idle)
        controller.beginCheck()
        controller.found(version: "135.2")
        #expect(controller.prepared(version: "135.2", generation: controller.lifecycle.generation) {})
        controller.userChose(.dismiss, version: "135.2")
        controller.finishCycle(error: nil)
        #expect(controller.updateStatus.isUpdateReady)
        controller.userChose(.install, version: "135.2")
        #expect(!controller.updateStatus.isUpdateReady)
        #expect(controller.detail.state == .installing(version: "135.2"))
        #expect(timer.cancellations == 1)
        controller.finishCycle(error: nil)
        #expect(controller.detail.state == .installing(version: "135.2"))
    }

    @Test
    func `default unknown safety denies idle while manual apply bypasses idle gates`() throws {
        let timer = JonesUpdateFixtureTimer()
        var now: TimeInterval = 0
        let controller = try JonesUpdateController(
            policy: JonesUpdateTestFixtures.policy(),
            driver: JonesUpdateFixtureDriver(),
            savedAutoUpdate: true,
            clock: { now },
            scheduleIdle: timer.schedule)
        var installations = 0
        controller.beginCheck()
        controller.found(version: "135.2")
        #expect(controller.prepared(version: "135.2", generation: controller.lifecycle.generation) {
            installations += 1
        })
        now = 1800
        #expect(controller.evaluateIdleApplication() == .deferred(.unknown(.hidIdleTime)))
        #expect(installations == 0)
        controller.automaticallyChecksForUpdates = false
        controller.automaticallyDownloadsUpdates = false
        #expect(controller.updateStatus.isUpdateReady)
        #expect(controller.detail.installsPreparedUpdateAtQuit)
        controller.installUpdate()
        #expect(installations == 1)
    }

    @Test
    func `idle timer uses fresh safety inputs and exact elapsed thresholds`() throws {
        let timer = JonesUpdateFixtureTimer()
        var now: TimeInterval = 0
        var safety = JonesUpdateTestFixtures.idleSafety
        let controller = try JonesUpdateController(
            policy: JonesUpdateTestFixtures.policy(),
            driver: JonesUpdateFixtureDriver(),
            savedAutoUpdate: true,
            idleSafetyProvider: { safety },
            clock: { now },
            scheduleIdle: timer.schedule)
        var installations = 0
        now = 300
        controller.beginCheck()
        controller.found(version: "135.2")
        #expect(controller.prepared(version: "135.2", generation: controller.lifecycle.generation) {
            installations += 1
        })
        now = 899
        timer.tick?()
        #expect(installations == 0)
        now = 900
        safety.hasVisibleMenus = true
        timer.tick?()
        #expect(installations == 0)
        #expect(controller.detail.idleDecision == .deferred(.visibleMenus))
        safety.hasVisibleMenus = false
        timer.tick?()
        #expect(installations == 1)
        #expect(timer.cancellations == 1)
        #expect(timer.tick == nil)
    }

    @Test
    func `explicit no idle hook denies until integration supplies safety again`() throws {
        let timer = JonesUpdateFixtureTimer()
        var now: TimeInterval = 0
        let controller = try JonesUpdateController(
            policy: JonesUpdateTestFixtures.policy(),
            driver: JonesUpdateFixtureDriver(),
            savedAutoUpdate: true,
            idleSafetyProvider: { JonesUpdateTestFixtures.idleSafety },
            clock: { now },
            scheduleIdle: timer.schedule)
        var installations = 0
        controller.beginCheck()
        controller.found(version: "135.2")
        #expect(controller.prepared(version: "135.2", generation: controller.lifecycle.generation) {
            installations += 1
        })
        now = 1800
        controller.disableIdleApplication()
        timer.tick?()
        #expect(installations == 0)
        #expect(controller.updateStatus.isUpdateReady)
        controller.setIdleSafetyProvider { JonesUpdateTestFixtures.idleSafety }
        timer.tick?()
        #expect(installations == 1)
    }

    @Test
    func `termination uncertainty and installation cancellation never silently rearm a handler`() throws {
        let timer = JonesUpdateFixtureTimer()
        let controller = try JonesUpdateController(
            policy: JonesUpdateTestFixtures.policy(),
            driver: JonesUpdateFixtureDriver(),
            scheduleIdle: timer.schedule)
        var installations = 0
        controller.beginCheck()
        controller.found(version: "135.2")
        let generation = controller.lifecycle.generation
        #expect(controller.prepared(version: "135.2", generation: generation) { installations += 1 })
        controller.installUpdate()
        // A still-running process is not proof of cancelled termination; no timeout may rearm it.
        for _ in 0..<3 {
            controller.installUpdate()
            #expect(!controller.prepared(version: "135.2", generation: generation) { installations += 1 })
        }
        #expect(installations == 1)
        controller.record(error: NSError(domain: "SUSparkleErrorDomain", code: 4007))
        #expect(controller.detail.state == .cancelled)
        controller.installUpdate()
        #expect(installations == 1)
        #expect(timer.cancellations == 1)
    }

    @Test
    func `cycle errors clear readiness and preserve an actionable admission reason`() throws {
        let timer = JonesUpdateFixtureTimer()
        let controller = try JonesUpdateController(
            policy: JonesUpdateTestFixtures.policy(),
            driver: JonesUpdateFixtureDriver(),
            scheduleIdle: timer.schedule)
        controller.beginCheck()
        controller.found(version: "135.2")
        #expect(controller.prepared(version: "135.2", generation: controller.lifecycle.generation) {})
        controller.finishCycle(error: NSError(domain: "fixture", code: 23))
        #expect(controller.detail.state == .failed(.sparkle(domain: "fixture", code: 23)))
        #expect(!controller.updateStatus.isUpdateReady)
        #expect(timer.cancellations == 1)
        controller.beginCheck()
        controller.finish(.failed(.admission(.unknownCacheCapacity)))
        controller.finishCycle(error: NSError(domain: "fixture", code: 24))
        #expect(controller.detail.state == .failed(.admission(.unknownCacheCapacity)))
        controller.beginCheck()
        controller.record(error: NSError(domain: "SUSparkleErrorDomain", code: 1001))
        #expect(controller.detail.state == .upToDate)
    }

    @Test
    func `deinitialization releases driver callbacks handler and prepared timer`() throws {
        let timer = JonesUpdateFixtureTimer()
        let driver = JonesUpdateFixtureDriver()
        var controller: JonesUpdateController? = try JonesUpdateController(
            policy: JonesUpdateTestFixtures.policy(), driver: driver, scheduleIdle: timer.schedule)
        weak var weakController = controller
        controller?.beginCheck()
        controller?.found(version: "135.2")
        let generation = try #require(controller?.lifecycle.generation)
        #expect(controller?.prepared(version: "135.2", generation: generation) {} == true)
        controller = nil
        #expect(weakController == nil)
        #expect(timer.cancellations == 1)
        #expect(timer.tick == nil)
        driver.stateDidChange?()
    }

    @Test
    func `startup failure is unavailable and never enables checks`() throws {
        let driver = JonesUpdateFixtureDriver()
        driver.startError = NSError(domain: "fixture", code: 9)
        let controller = try JonesUpdateController(policy: JonesUpdateTestFixtures.policy(), driver: driver)
        #expect(!controller.isAvailable)
        #expect(!controller.detail.canCheckForUpdates)
        #expect(controller.detail.state == .failed(.sparkle(domain: "fixture", code: 9)))
        controller.checkForUpdates(nil)
        #expect(driver.checks == 0)
    }

    @Test
    func `download admission fails closed with a typed reason before any readiness`() throws {
        let candidate = JonesUpdateAdmission.Candidate(
            archiveURL: URL(string: "https://github.com/Jones-Systems/CodexBar/releases/download/v1/app.zip"),
            archiveLength: 1024,
            isDelta: false,
            installationType: "application")
        var capacity = JonesUpdateAdmission.Capacity.unknown
        let controller = try JonesUpdateController(
            policy: JonesUpdateTestFixtures.policy(),
            driver: JonesUpdateFixtureDriver(),
            capacityProvider: { capacity })
        controller.beginCheck()
        #expect(throws: (any Error).self) { try controller.admitDownload(candidate) }
        #expect(controller.detail.state == .failed(.admission(.unknownAppCapacity)))
        #expect(!controller.updateStatus.isUpdateReady)
        capacity = .init(appVolume: .max, cacheVolume: .max)
        controller.beginCheck()
        try controller.admitDownload(candidate)
        #expect(controller.detail.state == .checking)
        #expect(!controller.updateStatus.isUpdateReady)
    }

    @Test
    func `delta and package updates are rejected through the actual admission seam`() throws {
        let controller = try JonesUpdateController(
            policy: JonesUpdateTestFixtures.policy(),
            driver: JonesUpdateFixtureDriver(),
            capacityProvider: { .init(appVolume: .max, cacheVolume: .max) })
        let url = URL(string: "https://github.com/Jones-Systems/CodexBar/releases/download/v1/app.zip")
        controller.beginCheck()
        #expect(throws: (any Error).self) {
            try controller.admitDownload(.init(
                archiveURL: url, archiveLength: 1024, isDelta: true, installationType: "application"))
        }
        #expect(controller.detail.state == .failed(.admission(.unsupportedDelta)))
        controller.beginCheck()
        #expect(throws: (any Error).self) {
            try controller.admitDownload(.init(
                archiveURL: url, archiveLength: 1024, isDelta: false, installationType: "package"))
        }
        #expect(controller.detail.state == .failed(.admission(.unsupportedInstallationType)))
    }
}
