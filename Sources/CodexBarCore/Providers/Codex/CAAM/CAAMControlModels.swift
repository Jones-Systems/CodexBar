import Foundation

public struct CAAMSwitchPlan: Codable, Sendable, Equatable {
    public let planDigest: String
    public let expectedRevision: String
    public let currentProfile: String?
    public let targetProfile: String
    public let affectedProfiles: [String]
    public let reloadRequired: Bool
    public let expiresAt: Date

    public init(
        planDigest: String,
        expectedRevision: String,
        currentProfile: String?,
        targetProfile: String,
        affectedProfiles: [String],
        reloadRequired: Bool,
        expiresAt: Date)
    {
        self.planDigest = planDigest
        self.expectedRevision = expectedRevision
        self.currentProfile = currentProfile
        self.targetProfile = targetProfile
        self.affectedProfiles = affectedProfiles
        self.reloadRequired = reloadRequired
        self.expiresAt = expiresAt
    }

    private enum CodingKeys: String, CodingKey {
        case planDigest = "plan_digest"
        case expectedRevision = "expected_revision"
        case currentProfile = "current_profile"
        case targetProfile = "target_profile"
        case affectedProfiles = "affected_profiles"
        case reloadRequired = "reload_required"
        case expiresAt = "expires_at"
    }
}

public enum CAAMOperationState: String, Codable, Sendable {
    case planned
    case executing
    case committed
    case rejected
    case rolledBack = "rolled_back"
    case recoveryRequired = "recovery_required"
    case manualRequired = "manual_required"

    public var isTerminal: Bool {
        switch self {
        case .committed, .rejected, .rolledBack: true
        case .planned, .executing, .recoveryRequired, .manualRequired: false
        }
    }
}

public struct CAAMOperationResult: Codable, Sendable, Equatable {
    public let operationID: UUID
    public let state: CAAMOperationState
    public let effect: CAAMControlEffect
    public let previousProfile: String?
    public let currentProfile: String?
    public let recoveryRequired: Bool
    public let manualRequired: Bool
    public let snapshot: CAAMEnvironmentSnapshot?

    public init(
        operationID: UUID,
        state: CAAMOperationState,
        effect: CAAMControlEffect,
        previousProfile: String? = nil,
        currentProfile: String? = nil,
        recoveryRequired: Bool = false,
        manualRequired: Bool = false,
        snapshot: CAAMEnvironmentSnapshot? = nil)
    {
        self.operationID = operationID
        self.state = state
        self.effect = effect
        self.previousProfile = previousProfile
        self.currentProfile = currentProfile
        self.recoveryRequired = recoveryRequired
        self.manualRequired = manualRequired
        self.snapshot = snapshot
    }

    private enum CodingKeys: String, CodingKey {
        case operationID = "operation_id"
        case state
        case effect
        case previousProfile = "previous_profile"
        case currentProfile = "current_profile"
        case recoveryRequired = "recovery_required"
        case manualRequired = "manual_required"
        case snapshot
    }
}

/// Closed presentation details only. Raw process output never enters control state or UI.
public struct CAAMControlFailure: Error, LocalizedError, Sendable, Equatable {
    public enum Reason: String, Sendable {
        case unavailable
        case timeout
        case cancelled
        case oversized
        case incompatible
        case invalidResponse
        case rejected
        case transport
        case stale
        case notQualified
        case busy
    }

    public let reason: Reason
    public let effect: CAAMControlEffect
    public let code: String?

    public init(reason: Reason, effect: CAAMControlEffect = .knownNoEffect, code: String? = nil) {
        self.reason = reason
        self.effect = effect
        self.code = code
    }

    public var errorDescription: String? {
        let summary = switch self.reason {
        case .unavailable: "CAAM is unavailable."
        case .timeout: "The CAAM request timed out."
        case .cancelled: "The CAAM request was interrupted."
        case .oversized: "The CAAM response exceeded its size limit."
        case .incompatible: "The CAAM protocol is unsupported."
        case .invalidResponse: "The CAAM response could not be verified."
        case .rejected: "CAAM rejected the request."
        case .transport: "The CAAM transport failed."
        case .stale: "Refresh this environment and request a new plan."
        case .notQualified: "Environment mutations require independently qualified CAAM conformance."
        case .busy: "Resolve the current CAAM operation first."
        }
        return self.effect == .unknown
            ? summary + " The effect is unknown; look up the existing operation, do not execute again."
            : summary
    }
}

struct CAAMControlEnvelope<Value: Codable & Sendable>: Codable, Sendable {
    let schema: String
    let kind: String
    let environmentID: String
    let protocolVersion: String
    let result: Value?
    let error: CAAMControlErrorPayload?

    private enum CodingKeys: String, CodingKey {
        case schema
        case kind
        case environmentID = "environment_id"
        case protocolVersion = "protocol_version"
        case result
        case error
    }
}

extension CAAMGatewayOperation {
    public var kind: String {
        switch self {
        case .snapshot: "snapshot"
        case .planSwitch: "plan-switch"
        case .executeSwitch: "execute-switch"
        case .operationStatus: "operation-status"
        case .recoverSwitch: "recover-switch"
        case .restoreFallback: "restore-fallback"
        }
    }

    public var operationID: UUID? {
        switch self {
        case let .executeSwitch(_, _, id, _), let .operationStatus(_, id),
             let .recoverSwitch(_, id, _), let .restoreFallback(_, _, _, id, _): id
        case .snapshot, .planSwitch: nil
        }
    }
}
