import Foundation

public enum CAAMEnvironmentConnectionKind: String, Codable, Sendable, CaseIterable {
    case local
    case ssh
}

public struct CAAMEnvironmentConnection: Codable, Sendable, Equatable {
    public var kind: CAAMEnvironmentConnectionKind
    public var executablePath: String?
    public var sshDestination: String?

    public init(
        kind: CAAMEnvironmentConnectionKind,
        executablePath: String? = nil,
        sshDestination: String? = nil)
    {
        self.kind = kind
        self.executablePath = executablePath
        self.sshDestination = sshDestination
    }

    public static func local(executablePath: String? = nil) -> Self {
        Self(kind: .local, executablePath: executablePath)
    }

    public static func ssh(destination: String) -> Self {
        Self(kind: .ssh, sshDestination: destination)
    }
}

public struct CAAMEnvironmentConfiguration: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var label: String
    public var connection: CAAMEnvironmentConnection

    public init(id: String, label: String, connection: CAAMEnvironmentConnection) {
        self.id = id
        self.label = label
        self.connection = connection
    }
}

public enum CAAMControlCapability: String, Codable, Sendable, CaseIterable {
    case snapshot
    case planSwitch = "plan_switch"
    case executeSwitch = "execute_switch"
    case operationStatus = "operation_status"
    case recoverSwitch = "recover_switch"
    case restoreFallback = "restore_fallback"
}

public enum CAAMEnvironmentReachability: String, Codable, Sendable {
    case reachable
    case degraded
}

public enum CAAMProfileHealth: String, Codable, Sendable {
    case healthy
    case warning
    case critical
    case cooldown
    case unknown
}

public struct CAAMProfileIdentity: Codable, Sendable, Equatable {
    public let provider: String
    public let stableID: String?
    public let displayEmail: String?
    public let workspaceID: String?
    public let workspaceLabel: String?
    public let plan: String?

    public init(
        provider: String,
        stableID: String? = nil,
        displayEmail: String? = nil,
        workspaceID: String? = nil,
        workspaceLabel: String? = nil,
        plan: String? = nil)
    {
        self.provider = provider
        self.stableID = stableID
        self.displayEmail = displayEmail
        self.workspaceID = workspaceID
        self.workspaceLabel = workspaceLabel
        self.plan = plan
    }

    private enum CodingKeys: String, CodingKey {
        case provider
        case stableID = "stable_id"
        case displayEmail = "display_email"
        case workspaceID = "workspace_id"
        case workspaceLabel = "workspace_label"
        case plan
    }
}

public struct CAAMEnvironmentProfile: Codable, Sendable, Equatable, Identifiable {
    public var id: String {
        self.name
    }

    public let name: String
    public let active: Bool
    public let system: Bool
    public let eligible: Bool
    public let health: CAAMProfileHealth
    public let identity: CAAMProfileIdentity?

    public init(
        name: String,
        active: Bool,
        system: Bool,
        eligible: Bool,
        health: CAAMProfileHealth,
        identity: CAAMProfileIdentity? = nil)
    {
        self.name = name
        self.active = active
        self.system = system
        self.eligible = eligible
        self.health = health
        self.identity = identity
    }
}

public enum CAAMRuntimeState: String, Codable, Sendable {
    case notRunning = "not_running"
    case matchesDefault = "matches_default"
    case differsFromDefault = "differs_from_default"
    case unknown
}

public struct CAAMRuntimeSnapshot: Codable, Sendable, Equatable {
    public let state: CAAMRuntimeState
    public let effectiveProfile: String?
    public let reloadRequired: Bool

    public init(state: CAAMRuntimeState, effectiveProfile: String? = nil, reloadRequired: Bool) {
        self.state = state
        self.effectiveProfile = effectiveProfile
        self.reloadRequired = reloadRequired
    }

    private enum CodingKeys: String, CodingKey {
        case state
        case effectiveProfile = "effective_profile"
        case reloadRequired = "reload_required"
    }
}

public enum CAAMPendingOperationState: String, Codable, Sendable {
    case planned
    case executing
    case recoveryRequired = "recovery_required"
    case manualRequired = "manual_required"
}

public struct CAAMPendingOperation: Codable, Sendable, Equatable {
    public let operationID: UUID
    public let state: CAAMPendingOperationState
    public let targetProfile: String?

    public init(operationID: UUID, state: CAAMPendingOperationState, targetProfile: String? = nil) {
        self.operationID = operationID
        self.state = state
        self.targetProfile = targetProfile
    }

    private enum CodingKeys: String, CodingKey {
        case operationID = "operation_id"
        case state
        case targetProfile = "target_profile"
    }
}

public struct CAAMEnvironmentSnapshot: Codable, Sendable, Equatable {
    public let revision: String
    public let observedAt: Date
    public let caamVersion: String
    public let capabilities: [String]
    public let reachability: CAAMEnvironmentReachability
    public let hostDefaultProfile: String?
    public let fallbackProfile: String?
    public let profiles: [CAAMEnvironmentProfile]
    public let runtime: CAAMRuntimeSnapshot
    public let pendingOperation: CAAMPendingOperation?
    public let warnings: [String]

    public init(
        revision: String,
        observedAt: Date,
        caamVersion: String,
        capabilities: [String],
        reachability: CAAMEnvironmentReachability,
        hostDefaultProfile: String? = nil,
        fallbackProfile: String? = nil,
        profiles: [CAAMEnvironmentProfile],
        runtime: CAAMRuntimeSnapshot,
        pendingOperation: CAAMPendingOperation? = nil,
        warnings: [String] = [])
    {
        self.revision = revision
        self.observedAt = observedAt
        self.caamVersion = caamVersion
        self.capabilities = capabilities
        self.reachability = reachability
        self.hostDefaultProfile = hostDefaultProfile
        self.fallbackProfile = fallbackProfile
        self.profiles = profiles
        self.runtime = runtime
        self.pendingOperation = pendingOperation
        self.warnings = warnings
    }

    public var supportedCapabilities: Set<CAAMControlCapability> {
        Set(self.capabilities.compactMap(CAAMControlCapability.init(rawValue:)))
    }

    public var unknownCapabilities: [String] {
        self.capabilities.filter { CAAMControlCapability(rawValue: $0) == nil }
    }

    private enum CodingKeys: String, CodingKey {
        case revision
        case observedAt = "observed_at"
        case caamVersion = "caam_version"
        case capabilities
        case reachability
        case hostDefaultProfile = "host_default_profile"
        case fallbackProfile = "fallback_profile"
        case profiles
        case runtime
        case pendingOperation = "pending_operation"
        case warnings
    }
}

public enum CAAMControlEffect: String, Codable, Sendable {
    case knownNoEffect = "known_no_effect"
    case knownEffect = "known_effect"
    case unknown
}

public struct CAAMControlErrorPayload: Codable, Sendable, Equatable {
    public let code: String
    public let message: String
    public let effect: CAAMControlEffect

    public init(code: String, message: String, effect: CAAMControlEffect) {
        self.code = code
        self.message = message
        self.effect = effect
    }
}

public struct CAAMSnapshotEnvelope: Codable, Sendable, Equatable {
    public let schema: String
    public let kind: String
    public let environmentID: String
    public let protocolVersion: String
    public let requestID: String?
    public let result: CAAMEnvironmentSnapshot?
    public let error: CAAMControlErrorPayload?

    public init(
        schema: String,
        kind: String,
        environmentID: String,
        protocolVersion: String,
        requestID: String? = nil,
        result: CAAMEnvironmentSnapshot? = nil,
        error: CAAMControlErrorPayload? = nil)
    {
        self.schema = schema
        self.kind = kind
        self.environmentID = environmentID
        self.protocolVersion = protocolVersion
        self.requestID = requestID
        self.result = result
        self.error = error
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case kind
        case environmentID = "environment_id"
        case protocolVersion = "protocol_version"
        case requestID = "request_id"
        case result
        case error
    }
}

public enum CAAMEnvironmentAvailability: Sendable, Equatable {
    case ready
    case degraded
    case incompatible
    case recoveryRequired
    case unavailable
}

public struct CAAMEnvironmentRowState: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let connectionKind: CAAMEnvironmentConnectionKind
    public let availability: CAAMEnvironmentAvailability
    public let currentProfile: String?
    public let currentAccountLabel: String?
    public let fallbackProfile: String?
    public let runtimeState: CAAMRuntimeState?
    public let reloadRequired: Bool
    public let caamVersion: String?
    public let observedAt: Date?
    public let message: String?
    public let canSwitch: Bool
    public let canRecover: Bool
    public let canRestoreFallback: Bool

    public init(
        id: String,
        label: String,
        connectionKind: CAAMEnvironmentConnectionKind,
        availability: CAAMEnvironmentAvailability,
        currentProfile: String? = nil,
        currentAccountLabel: String? = nil,
        fallbackProfile: String? = nil,
        runtimeState: CAAMRuntimeState? = nil,
        reloadRequired: Bool = false,
        caamVersion: String? = nil,
        observedAt: Date? = nil,
        message: String? = nil,
        canSwitch: Bool = false,
        canRecover: Bool = false,
        canRestoreFallback: Bool = false)
    {
        self.id = id
        self.label = label
        self.connectionKind = connectionKind
        self.availability = availability
        self.currentProfile = currentProfile
        self.currentAccountLabel = currentAccountLabel
        self.fallbackProfile = fallbackProfile
        self.runtimeState = runtimeState
        self.reloadRequired = reloadRequired
        self.caamVersion = caamVersion
        self.observedAt = observedAt
        self.message = message
        self.canSwitch = canSwitch
        self.canRecover = canRecover
        self.canRestoreFallback = canRestoreFallback
    }
}
