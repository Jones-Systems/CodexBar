import CodexBarCore
import Foundation
import Observation

@MainActor
@Observable
final class CAAMEnvironmentCoordinator {
    private static var applicationInstance: CAAMEnvironmentCoordinator?
    @ObservationIgnored private let client: CAAMEnvironmentClient
    @ObservationIgnored private let receiptStore: any CAAMOperationReceiptStoring
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let qualifiedConfigurations: [CAAMEnvironmentConfiguration]
    @ObservationIgnored private var configurationGeneration = 0
    @ObservationIgnored private var receipts: [String: CAAMOperationReceipt] = [:]
    @ObservationIgnored private var receiptsLoaded = false
    private(set) var sessionsByID: [String: CAAMControlSession] = [:]
    private(set) var isRefreshing = false
    private(set) var isOperating = false
    private(set) var notice: String?
    private(set) var receiptStorageAvailable = true

    init(
        client: CAAMEnvironmentClient = CAAMEnvironmentClient(),
        receiptStore: any CAAMOperationReceiptStoring = CAAMMemoryReceiptStore(),
        qualifiedConfigurations: [CAAMEnvironmentConfiguration] = [],
        now: @escaping @Sendable () -> Date = { Date() })
    {
        self.client = client
        self.receiptStore = receiptStore
        self.qualifiedConfigurations = qualifiedConfigurations
        self.now = now
    }

    static func applicationCoordinator() -> CAAMEnvironmentCoordinator {
        if SettingsStore.isRunningTests {
            return CAAMEnvironmentCoordinator(client: CAAMEnvironmentClient(
                runner: CAAMTestProcessNoLaunchRunner(), environment: [:], resolveLocalGateway: { _ in nil }))
        }
        if let instance = self.applicationInstance { return instance }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let url = directory.appendingPathComponent("CodexBar/caam-operation-receipts.json")
        // No environment is qualified merely because it advertises capability strings.
        let instance = CAAMEnvironmentCoordinator(receiptStore: CAAMFileReceiptStore(url: url))
        self.applicationInstance = instance
        return instance
    }

    func session(for configuration: CAAMEnvironmentConfiguration) -> CAAMControlSession {
        let receipt = self.receipts[configuration.id]
        if let session = self.sessionsByID[configuration.id], session.configuration == configuration {
            if let receipt, receipt.configuration == configuration, session.pendingOperationID == nil {
                var restored = CAAMControlSession(configuration: configuration, pendingOperationID: receipt.operationID)
                if let snapshot = session.snapshot, let receivedAt = session.receivedAt {
                    restored.observe(snapshot, now: receivedAt)
                }
                return restored
            }
            return session
        }
        return CAAMControlSession(
            configuration: configuration,
            pendingOperationID: receipt?.configuration == configuration ? receipt?.operationID : nil)
    }

    func state(configurations: [CAAMEnvironmentConfiguration], at date: Date? = nil) -> CodexEnvironmentsSectionState {
        let displayOrder = configurations.filter { $0.connection.kind == .local } +
            configurations.filter { $0.connection.kind == .ssh }
        return CodexEnvironmentsSectionState(
            configurations: configurations,
            rows: displayOrder.map { self.session(for: $0).row(now: date ?? self.now()) },
            isRefreshing: self.isRefreshing,
            notice: self.notice)
    }

    func canChangeConfigurations(
        from old: [CAAMEnvironmentConfiguration],
        to new: [CAAMEnvironmentConfiguration]) -> Bool
    {
        guard !self.isRefreshing, !self.isOperating else { return false }
        return old.allSatisfy { configuration in
            if new.contains(configuration) { return true }
            return self.receiptsLoaded && self.receiptStorageAvailable && self.session(for: configuration).canForget &&
                self.receipts[configuration.id] == nil
        }
    }

    func retainedConfigurations(
        outside configurations: [CAAMEnvironmentConfiguration]) -> [CAAMEnvironmentConfiguration]
    {
        self.receipts.values.map(\.configuration)
            .filter { !configurations.contains($0) }
            .sorted { $0.id < $1.id }
    }

    func configurationsDidChange(_ configurations: [CAAMEnvironmentConfiguration]) {
        self.configurationGeneration &+= 1
        self.sessionsByID = self.sessionsByID.filter { _, session in
            configurations.contains(session.configuration) || !session.canForget
        }
        self.notice = nil
    }

    func mutationsQualified(for configuration: CAAMEnvironmentConfiguration) -> Bool {
        self.qualifiedConfigurations.contains(configuration) && self.receiptStorageAvailable && self.receiptsLoaded &&
            (self.receipts[configuration.id] == nil || self.receipts[configuration.id]?.configuration == configuration)
    }

    func refresh(configurations: [CAAMEnvironmentConfiguration], force: Bool = true) async {
        guard !self.isRefreshing, !self.isOperating else { return }
        guard (try? CAAMEnvironmentContract.validateConfigurations(configurations)) != nil else {
            self.notice = L("The CAAM configuration is invalid.")
            return
        }
        self.isRefreshing = true
        self.notice = nil
        defer { self.isRefreshing = false }
        let generation = self.configurationGeneration
        await self.loadReceipts()
        self.sessionsByID = self.sessionsByID.filter { _, session in
            configurations.contains(session.configuration) || !session.canForget
        }
        for configuration in configurations {
            guard generation == self.configurationGeneration, !Task.isCancelled else { return }
            guard self.sessionsByID[configuration.id] != nil ||
                self.sessionsByID.count < CAAMEnvironmentContract.maximumEnvironmentCount
            else {
                self.notice = L("Resolve retained operations before adding more environment observations.")
                continue
            }
            var session = self.session(for: configuration)
            if !force, session.row(now: self.now()).availability == .ready { continue }
            do {
                let snapshot = try await self.client.fetchSnapshot(for: configuration)
                session.observe(snapshot, now: self.now())
            } catch {
                session.failRefresh(CAAMEnvironmentClient.failure(for: error, possibleEffect: .knownNoEffect))
            }
            guard generation == self.configurationGeneration else { return }
            // Publish each completed environment without waiting for slower hosts; old rows remain visible meanwhile.
            self.sessionsByID[configuration.id] = session
            if let operationID = session.pendingOperationID, self.receipts[configuration.id] == nil {
                self.receipts[configuration.id] = CAAMOperationReceipt(
                    configuration: configuration, operationID: operationID)
                await self.saveReceipts()
            }
        }
        if !self.receiptStorageAvailable, self.receiptsLoaded { await self.saveReceipts() }
        if self.receipts.values.contains(where: { !configurations.contains($0.configuration) }) {
            self.notice = L(
                "An unresolved operation belongs to a changed environment. Restore its original configuration.")
        }
    }

    func plan(configuration: CAAMEnvironmentConfiguration, target: String, fallback: Bool = false) async {
        guard self.canStart(configuration) else { return }
        self.isOperating = true
        defer { self.isOperating = false }
        let generation = self.configurationGeneration
        var session = self.session(for: configuration)
        do {
            let revision = try session.beginPlan(target: target, fallback: fallback, now: self.now())
            self.sessionsByID[configuration.id] = session
            let plan = try await self.client.fetchPlan(for: configuration, profile: target, expectedRevision: revision)
            guard generation == self.configurationGeneration else {
                throw CAAMControlFailure(reason: .stale)
            }
            try session.acceptPlan(plan, now: self.now())
        } catch {
            session.failPlan((error as? CAAMControlFailure) ??
                CAAMEnvironmentClient.failure(for: error, possibleEffect: .knownNoEffect))
        }
        self.sessionsByID[configuration.id] = session
    }

    func prepareRecovery(configuration: CAAMEnvironmentConfiguration) {
        guard self.canStart(configuration) else { return }
        var session = self.session(for: configuration)
        do {
            try session.prepareRecovery(now: self.now())
        } catch {
            self.notice = CAAMControlFailure(reason: .stale).localizedDescription
        }
        self.sessionsByID[configuration.id] = session
    }

    func cancelConfirmation(configuration: CAAMEnvironmentConfiguration) {
        self.sessionsByID[configuration.id]?.cancelConfirmation()
    }

    func confirm(configuration: CAAMEnvironmentConfiguration, confirmationID: UUID) async {
        guard self.canStart(configuration) else { return }
        self.isOperating = true
        defer { self.isOperating = false }
        var session = self.session(for: configuration)
        let operation: CAAMGatewayOperation
        do {
            operation = try session.confirm(
                id: confirmationID, mutationsQualified: self.mutationsQualified(for: configuration), now: self.now())
        } catch {
            self.notice = (error as? CAAMControlFailure)?.localizedDescription
            return
        }
        self.sessionsByID[configuration.id] = session
        guard let operationID = operation.operationID else { return }
        self.receipts[configuration.id] = CAAMOperationReceipt(configuration: configuration, operationID: operationID)
        // Persist operation identity before any possible gateway launch, including after app restart.
        await self.saveReceipts()
        guard self.receiptStorageAvailable else {
            session.failOperation(CAAMControlFailure(reason: .unavailable), operation: operation)
            if session.pendingOperationID == nil { self.receipts.removeValue(forKey: configuration.id) }
            // No gateway was launched. A later refresh retries the desired receipt image before qualification
            // can reopen, removing any intent that an atomic write may have installed before reporting failure.
            self.sessionsByID[configuration.id] = session
            return
        }
        await self.run(operation, configuration: configuration)
    }

    func lookup(configuration: CAAMEnvironmentConfiguration) async {
        guard self.canStart(configuration) else { return }
        self.isOperating = true
        defer { self.isOperating = false }
        var session = self.session(for: configuration)
        do {
            let operation = try session.beginLookup()
            self.sessionsByID[configuration.id] = session
            await self.run(operation, configuration: configuration)
        } catch {
            self.notice = CAAMControlFailure(reason: .busy).localizedDescription
        }
    }

    private func canStart(_ configuration: CAAMEnvironmentConfiguration) -> Bool {
        guard !self.isRefreshing, !self.isOperating, !self.session(for: configuration).phase.isBusy,
              self.receipts[configuration.id] == nil || self.receipts[configuration.id]?.configuration == configuration
        else {
            self.notice = CAAMControlFailure(reason: .busy).localizedDescription
            return false
        }
        return true
    }

    private func run(_ operation: CAAMGatewayOperation, configuration: CAAMEnvironmentConfiguration) async {
        guard var session = self.sessionsByID[configuration.id] else { return }
        do {
            let result = try await self.client.perform(operation, for: configuration)
            try session.acceptResult(result, now: self.now())
        } catch {
            let failure = (error as? CAAMControlFailure) ??
                CAAMControlFailure(reason: .invalidResponse, effect: .unknown)
            session.failOperation(failure, operation: operation)
        }
        self.sessionsByID[configuration.id] = session
        if session.pendingOperationID == nil {
            self.receipts.removeValue(forKey: configuration.id)
            await self.saveReceipts()
        }
    }

    private func loadReceipts() async {
        guard !self.receiptsLoaded else { return }
        do {
            let receipts = try await self.receiptStore.load()
            _ = try CAAMEnvironmentContract.validateConfigurations(receipts.map(\.configuration))
            self.receipts = Dictionary(uniqueKeysWithValues: receipts.map { ($0.configuration.id, $0) })
            self.receiptsLoaded = true
            self.receiptStorageAvailable = true
        } catch {
            self.receiptStorageAvailable = false
            self.notice = L("CAAM operation tracking is unavailable. Mutations remain disabled.")
        }
    }

    private func saveReceipts() async {
        guard self.receiptsLoaded else { return }
        do {
            try await self.receiptStore.save(self.receipts.values.sorted { $0.configuration.id < $1.configuration.id })
            self.receiptStorageAvailable = true
        } catch {
            self.receiptStorageAvailable = false
            self.notice = L("CAAM operation tracking is unavailable. Mutations remain disabled.")
        }
    }
}

/// Existing test-process detection must suppress all implicit transport and real receipt-store access.
/// Tests that exercise transport coordination inject their own synthetic client and receipt store instead.
private struct CAAMTestProcessNoLaunchRunner: CAAMEnvironmentCommandRunning {
    func run(command _: CAAMEnvironmentCommand, environment _: [String: String]) async throws -> SubprocessResult {
        throw SubprocessRunnerError.binaryNotFound("CAAM disabled in test process")
    }
}
