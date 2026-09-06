import Foundation

public enum CAAMControlPhase: String, Sendable {
    case idle
    case planning
    case awaitingConfirmation
    case executing
    case resolving
    case unknown
    case recoveryRequired
    case manualRequired
    case finished

    public var isBusy: Bool {
        self == .planning || self == .executing || self == .resolving
    }
}

public struct CAAMControlConfirmation: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable {
        case switchProfile
        case restoreFallback
        case recoverSwitch
    }

    public let id: UUID
    public let kind: Kind
    public let revision: String
    public let plan: CAAMSwitchPlan?
    public let operationID: UUID?
}

/// Pure execute-once state machine. Configuration identity, not just its ID, owns cached evidence.
public struct CAAMControlSession: Sendable, Equatable {
    public let configuration: CAAMEnvironmentConfiguration
    public private(set) var snapshot: CAAMEnvironmentSnapshot?
    public private(set) var receivedAt: Date?
    public private(set) var refreshFailed = false
    public private(set) var phase: CAAMControlPhase = .idle
    public private(set) var confirmation: CAAMControlConfirmation?
    public private(set) var pendingOperationID: UUID?
    public private(set) var lastResult: CAAMOperationResult?
    public private(set) var failure: CAAMControlFailure?
    private var requestedTarget: String?
    private var requestedFallback = false
    private var expectedCommittedProfile: String?

    public init(configuration: CAAMEnvironmentConfiguration, pendingOperationID: UUID? = nil) {
        self.configuration = configuration
        self.pendingOperationID = pendingOperationID
        if pendingOperationID != nil { self.phase = .unknown }
    }

    public var canForget: Bool {
        self.pendingOperationID == nil && !self.phase.isBusy
    }

    public func cachedSnapshot(now: Date) -> CAAMEnvironmentSnapshot? {
        guard let snapshot, let receivedAt,
              now.timeIntervalSince(receivedAt) >= 0,
              now.timeIntervalSince(receivedAt) <= CAAMEnvironmentContract.maximumCacheAge,
              now.timeIntervalSince(snapshot.observedAt) >= -CAAMEnvironmentContract.clockSkewAllowance,
              now.timeIntervalSince(snapshot.observedAt) <= CAAMEnvironmentContract.maximumCacheAge
        else { return nil }
        return snapshot
    }

    public func row(now: Date) -> CAAMEnvironmentRowState {
        guard let snapshot = self.cachedSnapshot(now: now) else {
            if self.failure?.reason == .incompatible {
                return CAAMEnvironmentRowState(
                    id: self.configuration.id,
                    label: self.configuration.label,
                    connectionKind: self.configuration.connection.kind,
                    availability: .incompatible,
                    message: self.failure?.localizedDescription)
            }
            return CAAMEnvironmentContract.unavailableRow(
                configuration: self.configuration,
                message: self.failure?.localizedDescription ?? "Not checked yet.")
        }
        return CAAMEnvironmentContract.rowState(
            configuration: self.configuration,
            snapshot: snapshot,
            now: now,
            refreshFailed: self.refreshFailed || self.phase == .unknown || self.phase.isBusy)
    }

    public mutating func observe(_ snapshot: CAAMEnvironmentSnapshot, now: Date) {
        self.snapshot = snapshot
        self.receivedAt = now
        self.refreshFailed = false
        self.confirmation = nil
        self.failure = nil
        // A snapshot alone cannot settle a locally ambiguous operation, even if its journal is empty.
        if self.pendingOperationID == nil {
            self.pendingOperationID = snapshot.pendingOperation?.operationID
        }
        if let pendingOperationID = self.pendingOperationID {
            if let pending = snapshot.pendingOperation, pending.operationID == pendingOperationID {
                self.phase = switch pending.state {
                case .recoveryRequired: .recoveryRequired
                case .manualRequired: .manualRequired
                case .planned, .executing: .unknown
                }
            } else {
                self.phase = .unknown
            }
        } else {
            self.phase = .idle
        }
    }

    public mutating func failRefresh(_ failure: CAAMControlFailure) {
        self.refreshFailed = true
        self.failure = failure
        self.confirmation = nil
        if self.phase == .awaitingConfirmation { self.phase = self.pendingOperationID == nil ? .idle : .unknown }
    }

    public mutating func beginPlan(target: String, fallback: Bool, now: Date) throws -> String {
        guard self.canForget else { throw CAAMControlFailure(reason: .busy) }
        let row = self.row(now: now)
        guard let snapshot, (fallback ? row.canRestoreFallback : row.canSwitch),
              !fallback || target == snapshot.fallbackProfile,
              snapshot.profiles.contains(where: { $0.name == target && $0.eligible && !$0.active })
        else { throw CAAMControlFailure(reason: .stale) }
        self.requestedTarget = target
        self.requestedFallback = fallback
        self.confirmation = nil
        self.failure = nil
        self.phase = .planning
        return snapshot.revision
    }

    public mutating func acceptPlan(_ plan: CAAMSwitchPlan, now: Date) throws {
        guard self.phase == .planning, let snapshot, let target = self.requestedTarget else {
            throw CAAMControlFailure(reason: .stale)
        }
        try CAAMEnvironmentContract.validatePlan(plan, snapshot: snapshot, target: target, now: now)
        self.confirmation = CAAMControlConfirmation(
            id: UUID(),
            kind: self.requestedFallback ? .restoreFallback : .switchProfile,
            revision: snapshot.revision,
            plan: plan,
            operationID: nil)
        self.phase = .awaitingConfirmation
    }

    public mutating func failPlan(_ failure: CAAMControlFailure) {
        self.phase = .idle
        self.confirmation = nil
        self.failure = failure
        self.refreshFailed = true
    }

    public mutating func prepareRecovery(now: Date) throws {
        guard !self.phase.isBusy, self.row(now: now).canRecover,
              let snapshot, let operationID = self.pendingOperationID,
              snapshot.pendingOperation?.operationID == operationID
        else { throw CAAMControlFailure(reason: .stale) }
        self.confirmation = CAAMControlConfirmation(
            id: UUID(), kind: .recoverSwitch, revision: snapshot.revision, plan: nil, operationID: operationID)
        self.phase = .awaitingConfirmation
    }

    public mutating func cancelConfirmation() {
        self.confirmation = nil
        self.phase = self.pendingOperationID == nil ? .idle : .unknown
    }

    public mutating func confirm(
        id: UUID,
        mutationsQualified: Bool,
        now: Date) throws -> CAAMGatewayOperation
    {
        guard mutationsQualified else { throw CAAMControlFailure(reason: .notQualified) }
        guard let confirmation, confirmation.id == id, self.phase == .awaitingConfirmation,
              let snapshot, snapshot.revision == confirmation.revision,
              CAAMEnvironmentContract.isCurrent(snapshot, now: now), !self.refreshFailed
        else { throw CAAMControlFailure(reason: .stale) }
        let operation: CAAMGatewayOperation
        switch confirmation.kind {
        case .recoverSwitch:
            guard self.row(now: now).canRecover, let operationID = confirmation.operationID,
                  operationID == self.pendingOperationID
            else { throw CAAMControlFailure(reason: .stale) }
            operation = .recoverSwitch(
                environmentID: self.configuration.id, operationID: operationID, expectedRevision: snapshot.revision)
        case .switchProfile, .restoreFallback:
            let row = self.row(now: now)
            guard self.pendingOperationID == nil, let plan = confirmation.plan,
                  (confirmation.kind == .restoreFallback ? row.canRestoreFallback : row.canSwitch)
            else { throw CAAMControlFailure(reason: .stale) }
            try CAAMEnvironmentContract.validatePlan(plan, snapshot: snapshot, target: plan.targetProfile, now: now)
            let operationID = UUID()
            let idempotencyKey = UUID()
            if confirmation.kind == .restoreFallback {
                guard plan.targetProfile == snapshot.fallbackProfile else {
                    throw CAAMControlFailure(reason: .stale)
                }
                operation = .restoreFallback(
                    environmentID: self.configuration.id, expectedRevision: snapshot.revision,
                    planDigest: plan.planDigest, operationID: operationID, idempotencyKey: idempotencyKey)
            } else {
                operation = .executeSwitch(
                    environmentID: self.configuration.id, planDigest: plan.planDigest,
                    operationID: operationID, idempotencyKey: idempotencyKey)
            }
            self.expectedCommittedProfile = plan.targetProfile
        }
        self.pendingOperationID = operation.operationID
        self.confirmation = nil
        self.phase = .executing
        return operation
    }

    public mutating func beginLookup() throws -> CAAMGatewayOperation {
        guard !self.phase.isBusy, let operationID = self.pendingOperationID else {
            throw CAAMControlFailure(reason: .busy)
        }
        self.confirmation = nil
        self.phase = .resolving
        return .operationStatus(environmentID: self.configuration.id, operationID: operationID)
    }

    public mutating func acceptResult(_ result: CAAMOperationResult, now: Date) throws {
        guard let operationID = self.pendingOperationID else {
            throw CAAMControlFailure(reason: .invalidResponse, effect: .unknown)
        }
        try CAAMEnvironmentContract.validateOperationResult(result, operationID: operationID)
        if result.state.isTerminal {
            guard let snapshot = result.snapshot, CAAMEnvironmentContract.isCurrent(snapshot, now: now),
                  result.state != .committed || self.expectedCommittedProfile == nil ||
                  result.currentProfile == self.expectedCommittedProfile
            else { throw CAAMControlFailure(reason: .invalidResponse, effect: .unknown) }
            self.pendingOperationID = nil
            self.expectedCommittedProfile = nil
            self.phase = .finished
        } else {
            self.phase = switch result.state {
            case .recoveryRequired: .recoveryRequired
            case .manualRequired: .manualRequired
            default: .unknown
            }
        }
        if let snapshot = result.snapshot {
            self.snapshot = snapshot
            self.receivedAt = now
            self.refreshFailed = false
        }
        self.lastResult = result
        self.failure = nil
    }

    public mutating func failOperation(_ failure: CAAMControlFailure, operation: CAAMGatewayOperation) {
        self.failure = failure
        self.refreshFailed = true
        // No-effect lookup/recovery failures say nothing about the original switch's effect.
        if failure.effect == .knownNoEffect,
           operation.kind == "execute-switch" || operation.kind == "restore-fallback"
        {
            self.pendingOperationID = nil
            self.expectedCommittedProfile = nil
            self.phase = .idle
        } else {
            self.phase = .unknown
        }
    }
}
