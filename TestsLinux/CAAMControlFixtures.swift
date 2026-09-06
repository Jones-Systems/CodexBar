import Foundation
@testable import CodexBarCore

enum CAAMControlFixtures {
    static let now = Date(timeIntervalSince1970: 1_700_000_000)
    static let configuration = CAAMEnvironmentConfiguration(id: "fixture", label: "Fixture", connection: .local())
    static let operationID = UUID(uuid: (0, 0, 0, 0, 0, 0, 64, 0, 128, 0, 0, 0, 0, 0, 0, 1))

    static func snapshot(
        revision: String = "1",
        date: Date = Self.now,
        capabilities: [String] = CAAMControlCapability.allCases.map(\.rawValue),
        reachability: CAAMEnvironmentReachability = .reachable,
        active: String = "primary",
        pending: CAAMPendingOperation? = nil,
        warnings: [String] = [],
        provider: String = "codex",
        stableID: String = "fixture-account") -> CAAMEnvironmentSnapshot
    {
        CAAMEnvironmentSnapshot(
            revision: revision, observedAt: date, caamVersion: "fixture-1", capabilities: capabilities,
            reachability: reachability, hostDefaultProfile: active, fallbackProfile: "secondary",
            profiles: ["primary", "secondary"].map { name in
                CAAMEnvironmentProfile(
                    name: name, active: name == active, system: false, eligible: true, health: .healthy,
                    identity: CAAMProfileIdentity(provider: provider, stableID: stableID, displayEmail: "f***@example.invalid"))
            },
            runtime: CAAMRuntimeSnapshot(state: .unknown, reloadRequired: false),
            pendingOperation: pending,
            warnings: warnings)
    }

    static func plan(
        revision: String = "1",
        target: String = "secondary",
        expiresAt: Date = Self.now.addingTimeInterval(30)) -> CAAMSwitchPlan
    {
        CAAMSwitchPlan(
            planDigest: String(repeating: "a", count: 64), expectedRevision: revision,
            currentProfile: "primary", targetProfile: target, affectedProfiles: ["primary", "secondary"],
            reloadRequired: true, expiresAt: expiresAt)
    }

    static func session() -> CAAMControlSession {
        var session = CAAMControlSession(configuration: Self.configuration)
        session.observe(Self.snapshot(), now: Self.now)
        return session
    }

    static func envelope<Value: Codable & Sendable>(
        _ result: Value,
        kind: String,
        environmentID: String = Self.configuration.id,
        version: String = "1.0") throws -> String
    {
        let envelope = CAAMControlEnvelope(
            schema: CAAMEnvironmentContract.schema, kind: kind, environmentID: environmentID,
            protocolVersion: version, result: result, error: nil)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(envelope), as: UTF8.self)
    }

    static func committed(operationID: UUID = Self.operationID) -> CAAMOperationResult {
        CAAMOperationResult(
            operationID: operationID, state: .committed, effect: .knownEffect,
            previousProfile: "primary", currentProfile: "secondary",
            snapshot: Self.snapshot(revision: "2", active: "secondary"))
    }
}

actor CAAMControlFixtureRunner: CAAMEnvironmentCommandRunning {
    enum Step: Sendable {
        case result(SubprocessResult)
        case failure(SubprocessRunnerError)
        case cancelled
    }

    private var steps: [Step]
    private(set) var commands: [CAAMEnvironmentCommand] = []

    init(_ steps: [Step]) { self.steps = steps }

    func run(command: CAAMEnvironmentCommand, environment _: [String: String]) throws -> SubprocessResult {
        self.commands.append(command)
        guard !self.steps.isEmpty else { throw SubprocessRunnerError.launchFailed("fixture exhausted") }
        switch self.steps.removeFirst() {
        case let .result(result): return result
        case let .failure(error): throw error
        case .cancelled: throw CancellationError()
        }
    }
}
