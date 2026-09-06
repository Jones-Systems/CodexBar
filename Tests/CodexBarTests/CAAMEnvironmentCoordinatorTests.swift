import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct CAAMEnvironmentCoordinatorTests {
    @Test
    func `refresh coalesces and never publishes a response into changed configuration`() async {
        let runner = GatedCAAMCoordinatorRunner()
        let coordinator = Self.coordinator(runner: runner)
        let configuration = CAAMCoordinatorFixture.configuration
        let task = Task { await coordinator.refresh(configurations: [configuration]) }
        await runner.waitForStart()
        #expect(coordinator.isRefreshing)
        await coordinator.refresh(configurations: [configuration])
        #expect(await runner.commandCount == 1)
        let changed = CAAMEnvironmentConfiguration(
            id: configuration.id, label: "Changed", connection: .ssh(destination: "changed-fixture"))
        coordinator.configurationsDidChange([changed])
        await runner.release()
        await task.value
        #expect(!coordinator.isRefreshing)
        #expect(coordinator.state(configurations: [changed]).rows.first?.availability == .unavailable)
        #expect(coordinator.sessionsByID.isEmpty)
    }

    @Test
    func `production qualification default rejects execute even with all advertised capabilities`() async throws {
        let runner = CAAMCoordinatorFixtureRunner()
        let coordinator = Self.coordinator(runner: runner)
        let configuration = CAAMCoordinatorFixture.configuration
        await coordinator.refresh(configurations: [configuration])
        await coordinator.plan(configuration: configuration, target: "secondary")
        let confirmation = try #require(coordinator.session(for: configuration).confirmation)
        await coordinator.confirm(configuration: configuration, confirmationID: confirmation.id)
        #expect(await runner.operations == ["snapshot", "plan-switch"])
        #expect(!coordinator.mutationsQualified(for: configuration))
        #expect(coordinator.notice == CAAMControlFailure(reason: .notQualified).localizedDescription)
    }

    @Test
    func `operation identity persists before launch and restart resolves without replay`() async throws {
        let runner = CAAMCoordinatorFixtureRunner()
        let receiptStore = CAAMMemoryReceiptStore()
        let configuration = CAAMCoordinatorFixture.configuration
        let coordinator = Self.coordinator(runner: runner, receiptStore: receiptStore, qualified: [configuration])
        await coordinator.refresh(configurations: [configuration])
        await coordinator.plan(configuration: configuration, target: "secondary")
        let confirmation = try #require(coordinator.session(for: configuration).confirmation)
        await coordinator.confirm(configuration: configuration, confirmationID: confirmation.id)
        let receipt = try #require(try await receiptStore.load().first)
        #expect(coordinator.session(for: configuration).phase == .unknown)
        #expect(!coordinator.canChangeConfigurations(from: [configuration], to: []))
        let restarted = Self.coordinator(runner: runner, receiptStore: receiptStore)
        await restarted.refresh(configurations: [configuration])
        #expect(restarted.session(for: configuration).pendingOperationID == receipt.operationID)
        #expect(restarted.session(for: configuration).phase == .unknown)
        await restarted.lookup(configuration: configuration)
        #expect(restarted.session(for: configuration).phase == .finished)
        #expect(try await receiptStore.load().isEmpty)
        #expect(await runner.operations == [
            "snapshot", "plan-switch", "execute-switch", "snapshot", "operation-status",
        ])
    }

    @Test
    func `failed receipt persistence prevents launch and disables mutation qualification`() async throws {
        let runner = CAAMCoordinatorFixtureRunner()
        let configuration = CAAMCoordinatorFixture.configuration
        let coordinator = Self.coordinator(
            runner: runner, receiptStore: RejectingCAAMReceiptStore(), qualified: [configuration])
        await coordinator.refresh(configurations: [configuration])
        await coordinator.plan(configuration: configuration, target: "secondary")
        let confirmation = try #require(coordinator.session(for: configuration).confirmation)
        await coordinator.confirm(configuration: configuration, confirmationID: confirmation.id)
        #expect(await runner.operations == ["snapshot", "plan-switch"])
        #expect(!coordinator.receiptStorageAvailable)
        #expect(!coordinator.mutationsQualified(for: configuration))
        #expect(!coordinator.canChangeConfigurations(from: [configuration], to: []))
    }

    @Test
    func `qualification binds full configuration and retained operations keep their original target`() async throws {
        let configuration = CAAMCoordinatorFixture.configuration
        let receipt = CAAMOperationReceipt(configuration: configuration, operationID: UUID())
        let store = CAAMMemoryReceiptStore(receipts: [receipt])
        let runner = CAAMCoordinatorFixtureRunner()
        let coordinator = Self.coordinator(runner: runner, receiptStore: store, qualified: [configuration])
        await coordinator.refresh(configurations: [])
        let changed = CAAMEnvironmentConfiguration(
            id: configuration.id, label: "Changed", connection: .ssh(destination: "other-fixture"))
        #expect(!coordinator.mutationsQualified(for: changed))
        #expect(coordinator.retainedConfigurations(outside: [changed]) == [configuration])
        #expect(coordinator.session(for: configuration).pendingOperationID == receipt.operationID)
        #expect(coordinator.session(for: changed).pendingOperationID == nil)
        await coordinator.lookup(configuration: configuration)
        #expect(try await store.load().isEmpty)
        #expect(await runner.operations == ["operation-status"])
    }

    private static func coordinator(
        runner: any CAAMEnvironmentCommandRunning,
        receiptStore: any CAAMOperationReceiptStoring = CAAMMemoryReceiptStore(),
        qualified: [CAAMEnvironmentConfiguration] = []) -> CAAMEnvironmentCoordinator
    {
        CAAMEnvironmentCoordinator(
            client: CAAMEnvironmentClient(
                runner: runner, environment: [:], resolveLocalGateway: { _ in "/fixture/caam-codexbar" }),
            receiptStore: receiptStore,
            qualifiedConfigurations: qualified,
            now: { CAAMCoordinatorFixture.now })
    }
}

private enum CAAMCoordinatorFixture {
    static let now = Date(timeIntervalSince1970: 1_700_000_000)
    static let configuration = CAAMEnvironmentConfiguration(id: "fixture", label: "Fixture", connection: .local())

    static func snapshot(active: String = "primary") -> CAAMEnvironmentSnapshot {
        CAAMEnvironmentSnapshot(
            revision: "1", observedAt: Self.now, caamVersion: "fixture",
            capabilities: CAAMControlCapability.allCases.map(\.rawValue), reachability: .reachable,
            hostDefaultProfile: active, fallbackProfile: "secondary",
            profiles: ["primary", "secondary"].map { name in
                CAAMEnvironmentProfile(
                    name: name, active: name == active, system: false, eligible: true, health: .healthy)
            },
            runtime: CAAMRuntimeSnapshot(state: .unknown, reloadRequired: false))
    }

    static func response<Value: Codable & Sendable>(_ value: Value, kind: String) throws -> SubprocessResult {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(CAAMControlEnvelope(
            schema: CAAMEnvironmentContract.schema, kind: kind, environmentID: Self.configuration.id,
            protocolVersion: "1.0", result: value, error: nil))
        return SubprocessResult(stdout: String(decoding: data, as: UTF8.self), stderr: "")
    }
}

private actor CAAMCoordinatorFixtureRunner: CAAMEnvironmentCommandRunning {
    private(set) var operations: [String] = []

    func run(command: CAAMEnvironmentCommand, environment _: [String: String]) throws -> SubprocessResult {
        let kind = command.arguments.first ?? ""
        self.operations.append(kind)
        switch kind {
        case "snapshot":
            return try CAAMCoordinatorFixture.response(CAAMCoordinatorFixture.snapshot(), kind: kind)
        case "plan-switch":
            return try CAAMCoordinatorFixture.response(CAAMSwitchPlan(
                planDigest: String(repeating: "a", count: 64), expectedRevision: "1", currentProfile: "primary",
                targetProfile: "secondary", affectedProfiles: ["primary", "secondary"], reloadRequired: false,
                expiresAt: CAAMCoordinatorFixture.now.addingTimeInterval(30)), kind: kind)
        case "execute-switch":
            throw SubprocessRunnerError.timedOut("fixture interruption")
        case "operation-status":
            guard let operationID = UUID(uuidString: command.arguments.last ?? "") else {
                throw SubprocessRunnerError.launchFailed("fixture invalid operation ID")
            }
            return try CAAMCoordinatorFixture.response(CAAMOperationResult(
                operationID: operationID, state: .committed, effect: .knownEffect,
                previousProfile: "primary", currentProfile: "secondary",
                snapshot: CAAMCoordinatorFixture.snapshot(active: "secondary")), kind: kind)
        default:
            throw SubprocessRunnerError.launchFailed("fixture unexpected operation")
        }
    }
}

private actor GatedCAAMCoordinatorRunner: CAAMEnvironmentCommandRunning {
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private(set) var commandCount = 0

    func waitForStart() async {
        if self.commandCount > 0 { return }
        await withCheckedContinuation { self.startWaiter = $0 }
    }

    func release() {
        self.releaseWaiter?.resume()
        self.releaseWaiter = nil
    }

    func run(command _: CAAMEnvironmentCommand, environment _: [String: String]) async throws -> SubprocessResult {
        self.commandCount += 1
        self.startWaiter?.resume()
        self.startWaiter = nil
        await withCheckedContinuation { self.releaseWaiter = $0 }
        return try CAAMCoordinatorFixture.response(CAAMCoordinatorFixture.snapshot(), kind: "snapshot")
    }
}

private actor RejectingCAAMReceiptStore: CAAMOperationReceiptStoring {
    func load() -> [CAAMOperationReceipt] { [] }

    func save(_: [CAAMOperationReceipt]) throws { throw CAAMControlFailure(reason: .unavailable) }
}
