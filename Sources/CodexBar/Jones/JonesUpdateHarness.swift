import AppKit
import Foundation

/// A sealed fixture identity selects this entry point before any application/account initialization.
@MainActor
enum JonesUpdateHarness {
    static func isMarked(_ info: [String: Any]) -> Bool {
        info["JonesUpdateHarness"] != nil || info["JonesUpdateHarnessFixtureID"] != nil ||
            info["CFBundleIdentifier"] as? String == JonesUpdateTrustPolicy.harnessBundleID
    }

    static func validate(_ info: [String: Any]) throws -> JonesUpdateTrustPolicy {
        let policy = try JonesUpdateTrustPolicy.validate(infoDictionary: info)
        guard policy.identity == .harness, policy.isEnabled,
              let fixture = info["JonesUpdateHarnessFixtureID"] as? String, UUID(uuidString: fixture) != nil,
              info["JonesAppGroupID"] == nil, info["JonesICloudID"] == nil,
              info["JonesAppBundleID"] == nil, info["CodexBarTeamID"] == nil,
              info["CFBundleExecutable"] as? String == "CodexBar"
        else { throw JonesUpdateTrustPolicy.Rejection.identity }
        return policy
    }

    static func run() -> Never {
        do {
            let info = Bundle.main.infoDictionary ?? [:]
            let policy = try Self.validate(info)
            let delegate = try JonesUpdateHarnessDelegate(policy: policy, info: info)
            let app = NSApplication.shared
            app.setActivationPolicy(.prohibited)
            app.delegate = delegate
            withExtendedLifetime(delegate) { app.run() }
            exit(delegate.exitStatus)
        } catch {
            // Neither an invalid fixture nor a partially edited production package may fall through.
            FileHandle.standardError.write(Data("Invalid updater harness configuration.\n".utf8))
            exit(78)
        }
    }
}

@MainActor
private final class JonesUpdateHarnessDelegate: NSObject, NSApplicationDelegate {
    private(set) var exitStatus: Int32 = 0

    private struct Command: Decodable {
        enum Action: String, Decodable { case wait, check, install, quit, stop }
        let fixtureID: String
        let requestID: String
        let build: String
        let action: Action
    }

    private let policy: JonesUpdateTrustPolicy
    private let directory: URL
    private let fixtureID: String
    private let build: String
    private var updater: JonesUpdateController?
    private var timer: JonesUpdateCancellation?
    private var lastRequest = ""
    private var lastReport: Data?

    init(policy: JonesUpdateTrustPolicy, info: [String: Any]) throws {
        guard let fixtureID = info["JonesUpdateHarnessFixtureID"] as? String,
              let build = info["CFBundleVersion"] as? String
        else { throw JonesUpdateTrustPolicy.Rejection.identity }
        self.policy = policy
        self.fixtureID = fixtureID
        self.build = build
        self.directory = Bundle.main.bundleURL.deletingLastPathComponent().resolvingSymlinksInPath()
        super.init()
        _ = try self.readCommand()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let appURL = Bundle.main.bundleURL
            let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            self.updater = try JonesUpdateController(
                policy: self.policy,
                savedAutoUpdate: true,
                capacityProvider: {
                    guard let cacheURL else { return .unknown }
                    return .read(appURL: appURL, cacheURL: cacheURL)
                })
            let source = DispatchSource.makeTimerSource(queue: .main)
            source.schedule(deadline: .now(), repeating: .milliseconds(250))
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.tick() }
            }
            source.resume()
            self.timer = JonesUpdateCancellation { source.cancel() }
        } catch {
            self.fail()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        self.timer = nil
        self.updater?.disableIdleApplication()
    }

    private func readCommand() throws -> Command {
        let url = self.directory.appendingPathComponent("harness-command.json")
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 4096
        else { throw JonesUpdateTrustPolicy.Rejection.identity }
        let command = try JSONDecoder().decode(Command.self, from: Data(contentsOf: url))
        guard command.fixtureID == self.fixtureID, UUID(uuidString: command.requestID) != nil else {
            throw JonesUpdateTrustPolicy.Rejection.identity
        }
        return command
    }

    private func tick() {
        do {
            try self.report()
            let command = try self.readCommand()
            guard command.build == self.build, command.requestID != self.lastRequest else { return }
            switch command.action {
            case .check:
                guard self.updater?.detail.canCheckForUpdates == true else { return }
                self.lastRequest = command.requestID
                self.updater?.checkForUpdatesInBackground()
            case .install:
                guard self.updater?.detail.preparedUpdate != nil else { return }
                self.lastRequest = command.requestID
                self.updater?.installUpdate()
            case .quit, .stop:
                self.lastRequest = command.requestID
                NSApplication.shared.terminate(nil)
            case .wait:
                self.lastRequest = command.requestID
            }
        } catch {
            self.fail()
        }
    }

    private func report() throws {
        guard let updater else { return }
        let state: String
        var failure = ""
        switch updater.detail.state {
        case .disabled: state = "disabled"
        case .idle: state = "idle"
        case .checking: state = "checking"
        case .downloading: state = "downloading"
        case .preparing: state = "preparing"
        case .ready: state = "ready"
        case .installing: state = "installing"
        case .upToDate: state = "up-to-date"
        case .cancelled: state = "cancelled"
        case .skipped: state = "skipped"
        case let .failed(reason):
            state = "failed"
            switch reason {
            case .trust: failure = "trust"
            case let .admission(rejection):
                failure = rejection == .archiveTooLarge ? "archive-too-large" : "admission"
            case .sparkle: failure = "sparkle"
            }
        }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let currentURL = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let applications = NSRunningApplication.runningApplications(
            withBundleIdentifier: JonesUpdateTrustPolicy.harnessBundleID)
        let registeredApplication = applications.contains { application in
            application.processIdentifier == currentPID &&
                application.bundleURL?.resolvingSymlinksInPath() == currentURL && !application.isTerminated
        }
        let report: [String: Any] = [
            "schema": "jones-update-harness-report/v1", "fixtureID": self.fixtureID,
            "build": self.build, "sourceRevision": self.policy.sourceRevision,
            "pid": currentPID, "bundlePath": currentURL.path,
            "state": state, "failure": failure, "requestID": self.lastRequest,
            "canCheck": updater.detail.canCheckForUpdates,
            "registeredApplication": registeredApplication,
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        guard data != self.lastReport else { return }
        let url = self.directory.appendingPathComponent("harness-report.json")
        if FileManager.default.fileExists(atPath: url.path) {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                throw JonesUpdateTrustPolicy.Rejection.identity
            }
        }
        try data.write(to: url, options: .atomic)
        self.lastReport = data
    }

    private func fail() {
        self.exitStatus = 1
        FileHandle.standardError.write(Data("Updater harness failed; no normal application fallback.\n".utf8))
        NSApplication.shared.terminate(nil)
    }
}
