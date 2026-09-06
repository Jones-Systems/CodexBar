import Foundation

public enum CAAMEnvironmentContractError: LocalizedError, Sendable, Equatable {
    case invalidConfiguration(String)
    case outputTooLarge
    case invalidEncoding
    case invalidEnvelope(String)
    case remoteError(code: String, message: String, effect: CAAMControlEffect)

    public var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(message): message
        case .outputTooLarge: "The CAAM gateway response exceeded the allowed size."
        case .invalidEncoding: "The CAAM gateway response was not valid UTF-8 JSON."
        case let .invalidEnvelope(message): message
        case let .remoteError(_, message, _): message
        }
    }
}

public enum CAAMEnvironmentContract {
    public static let schema = "caam.codexbar-control/v1"
    public static let maximumOutputBytes = 64 * 1024
    public static let maximumEnvironmentCount = 32
    public static let maximumProfileCount = 64

    public static func validateConfigurations(
        _ configurations: [CAAMEnvironmentConfiguration]) throws -> [CAAMEnvironmentConfiguration]
    {
        guard configurations.count <= self.maximumEnvironmentCount else {
            throw CAAMEnvironmentContractError.invalidConfiguration("Too many CAAM environments are configured.")
        }

        var ids = Set<String>()
        var hasLocal = false
        for configuration in configurations {
            guard self.isSafeIdentifier(configuration.id, maximumLength: 64) else {
                throw CAAMEnvironmentContractError.invalidConfiguration("A CAAM environment ID is invalid.")
            }
            guard ids.insert(configuration.id).inserted else {
                throw CAAMEnvironmentContractError.invalidConfiguration("CAAM environment IDs must be unique.")
            }
            guard self.isSafeDisplayText(configuration.label, maximumLength: 80) else {
                throw CAAMEnvironmentContractError.invalidConfiguration("A CAAM environment label is invalid.")
            }

            switch configuration.connection.kind {
            case .local:
                guard !hasLocal else {
                    throw CAAMEnvironmentContractError.invalidConfiguration(
                        "Only one local CAAM environment can be configured.")
                }
                hasLocal = true
                guard configuration.connection.sshDestination == nil else {
                    throw CAAMEnvironmentContractError.invalidConfiguration(
                        "A local CAAM environment cannot include an SSH destination.")
                }
                if let path = configuration.connection.executablePath {
                    guard path.hasPrefix("/"), self.isSafeDisplayText(path, maximumLength: 1024) else {
                        throw CAAMEnvironmentContractError.invalidConfiguration(
                            "A local CAAM executable override must be an absolute path.")
                    }
                }
            case .ssh:
                guard configuration.connection.executablePath == nil else {
                    throw CAAMEnvironmentContractError.invalidConfiguration(
                        "An SSH CAAM environment cannot include a local executable path.")
                }
                guard let destination = configuration.connection.sshDestination,
                      self.isSafeSSHDestination(destination)
                else {
                    throw CAAMEnvironmentContractError.invalidConfiguration("A CAAM SSH destination is invalid.")
                }
            }
        }
        return configurations
    }

    public static func decodeSnapshot(
        _ data: Data,
        expectedEnvironmentID: String) throws -> CAAMEnvironmentSnapshot
    {
        let snapshot = try self.decodeResponse(
            CAAMEnvironmentSnapshot.self,
            data: data,
            environmentID: expectedEnvironmentID,
            kind: "snapshot")
        try self.validateSnapshot(snapshot)
        return snapshot
    }

    public static func rowState(
        configuration: CAAMEnvironmentConfiguration,
        snapshot: CAAMEnvironmentSnapshot,
        now: Date = Date(),
        refreshFailed: Bool = false) -> CAAMEnvironmentRowState
    {
        let current = self.isCurrent(snapshot, now: now) && !refreshFailed
        let capabilities = snapshot.supportedCapabilities
        let hasAllSwitchCapabilities = capabilities.isSuperset(of: [
            .snapshot,
            .planSwitch,
            .executeSwitch,
            .operationStatus,
            .recoverSwitch,
        ])
        let hasPending = snapshot.pendingOperation != nil
        let currentProfile = snapshot.profiles.first(where: { $0.name == snapshot.hostDefaultProfile })
        let accountLabel = currentProfile?.identity.flatMap { identity in
            identity.provider == "codex" ? Self.accountLabel(identity) : nil
        }
        let availability: CAAMEnvironmentAvailability = if !capabilities.contains(.snapshot) {
            .incompatible
        } else if !current {
            .stale
        } else if snapshot.pendingOperation?.state == .manualRequired ||
            snapshot.pendingOperation?.state == .recoveryRequired
        {
            .recoveryRequired
        } else if snapshot.reachability == .degraded || !snapshot.warnings.isEmpty {
            .degraded
        } else {
            .ready
        }
        let canMutate = current && availability == .ready && hasAllSwitchCapabilities && !hasPending
        let eligibleTargets = snapshot.profiles.filter { $0.eligible && $0.name != snapshot.hostDefaultProfile }

        return CAAMEnvironmentRowState(
            id: configuration.id,
            label: configuration.label,
            connectionKind: configuration.connection.kind,
            availability: availability,
            currentProfile: snapshot.hostDefaultProfile,
            currentAccountLabel: accountLabel,
            fallbackProfile: snapshot.fallbackProfile,
            runtimeState: snapshot.runtime.state,
            reloadRequired: snapshot.runtime.reloadRequired,
            caamVersion: snapshot.caamVersion,
            observedAt: snapshot.observedAt,
            message: current ? snapshot.warnings.first : "Cached state is stale; refresh before changing environments.",
            canSwitch: canMutate && !eligibleTargets.isEmpty,
            canRecover: current && snapshot.reachability == .reachable &&
                capabilities.isSuperset(of: [.snapshot, .recoverSwitch, .operationStatus]) &&
                snapshot.pendingOperation?.state == .recoveryRequired,
            canRestoreFallback: canMutate && capabilities.contains(.restoreFallback) &&
                eligibleTargets.contains { $0.name == snapshot.fallbackProfile })
    }

    public static func unavailableRow(
        configuration: CAAMEnvironmentConfiguration,
        message: String) -> CAAMEnvironmentRowState
    {
        CAAMEnvironmentRowState(
            id: configuration.id,
            label: configuration.label,
            connectionKind: configuration.connection.kind,
            availability: .unavailable,
            message: message)
    }

    public static func isSafeIdentifier(_ value: String, maximumLength: Int) -> Bool {
        guard !value.isEmpty, value.count <= maximumLength, !value.hasPrefix("-") else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            guard scalar.value < 128 else { return false }
            return switch scalar.value {
            case 45, 46, 48...57, 65...90, 95, 97...122: true
            default: false
            }
        }
    }

    public static func isSafeSSHDestination(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 255, !value.hasPrefix("-") else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            guard scalar.value < 128 else { return false }
            return switch scalar.value {
            case 45, 46, 48...57, 58, 64, 65...90, 95, 97...122: true
            default: false
            }
        }
    }

    static func validateSnapshot(_ snapshot: CAAMEnvironmentSnapshot) throws {
        guard self.isSafeRevision(snapshot.revision),
              self.isSafeVersion(snapshot.caamVersion),
              snapshot.capabilities.count <= CAAMControlCapability.allCases.count + 16,
              snapshot.profiles.count <= self.maximumProfileCount,
              snapshot.warnings.count <= 16
        else {
            throw CAAMEnvironmentContractError.invalidEnvelope("The CAAM environment snapshot exceeded its bounds.")
        }

        let profileNames = snapshot.profiles.map(\.name)
        guard profileNames.allSatisfy({ self.isSafeIdentifier($0, maximumLength: 64) }),
              Set(profileNames).count == profileNames.count,
              snapshot.capabilities.allSatisfy({ self.isSafeIdentifier($0, maximumLength: 64) }),
              snapshot.warnings.allSatisfy({ self.isSafeDisplayText($0, maximumLength: 240) })
        else {
            throw CAAMEnvironmentContractError.invalidEnvelope(
                "The CAAM environment snapshot contained invalid values.")
        }

        let knownProfiles = Set(profileNames)
        for profile in [snapshot.hostDefaultProfile, snapshot.fallbackProfile, snapshot.runtime.effectiveProfile]
            .compactMap(\.self)
        {
            guard knownProfiles.contains(profile) else {
                throw CAAMEnvironmentContractError.invalidEnvelope(
                    "The CAAM environment snapshot referenced an unknown profile.")
            }
        }
        if let pending = snapshot.pendingOperation {
            if let target = pending.targetProfile, !knownProfiles.contains(target) {
                throw CAAMEnvironmentContractError.invalidEnvelope(
                    "The CAAM pending operation referenced an unknown profile.")
            }
        }
        let activeProfiles = snapshot.profiles.filter(\.active)
        guard activeProfiles.count <= 1,
              activeProfiles.first?.name == snapshot.hostDefaultProfile
        else {
            throw CAAMEnvironmentContractError.invalidEnvelope(
                "The CAAM environment snapshot identified inconsistent active profiles.")
        }
        guard snapshot.profiles.allSatisfy({ profile in
            guard let identity = profile.identity else { return true }
            return self.isSafeIdentifier(identity.provider, maximumLength: 64) &&
                self.isSafeOptionalDisplayText(identity.stableID, maximumLength: 160) &&
                self.isSafeOptionalDisplayText(identity.displayEmail, maximumLength: 160) &&
                self.isSafeOptionalDisplayText(identity.workspaceID, maximumLength: 160) &&
                self.isSafeOptionalDisplayText(identity.workspaceLabel, maximumLength: 160) &&
                self.isSafeOptionalDisplayText(identity.plan, maximumLength: 80)
        }) else {
            throw CAAMEnvironmentContractError.invalidEnvelope(
                "The CAAM environment snapshot contained invalid account identity metadata.")
        }
    }

    private static func isSafeRevision(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 64 else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            guard scalar.value < 128 else { return false }
            return switch scalar.value {
            case 45, 46, 48...58, 65...90, 95, 97...122: true
            default: false
            }
        }
    }

    private static func isSafeVersion(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 32 else { return false }
        return self.isASCIIPrintable(value)
    }

    static func isSafeDisplayText(_ value: String, maximumLength: Int) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == value, value.unicodeScalars.count <= maximumLength else { return false }
        return value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }

    private static func isSafeOptionalDisplayText(_ value: String?, maximumLength: Int) -> Bool {
        guard let value else { return true }
        return self.isSafeDisplayText(value, maximumLength: maximumLength)
    }

    private static func isASCIIPrintable(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 32 && scalar.value < 127
        }
    }

    private static func accountLabel(_ identity: CAAMProfileIdentity) -> String? {
        let email = identity.displayEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let workspace = identity.workspaceLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        return switch (email?.isEmpty == false ? email : nil, workspace?.isEmpty == false ? workspace : nil) {
        case let (.some(email), .some(workspace)): "\(email) — \(workspace)"
        case let (.some(email), .none): email
        case let (.none, .some(workspace)): workspace
        case (.none, .none): identity.stableID
        }
    }

    static func containsForbiddenCredentialKey(_ value: Any, depth: Int = 0) -> Bool {
        guard depth <= 32 else { return true }
        let forbiddenKeys = Set([
            "accesstoken",
            "apikey",
            "auth",
            "authorization",
            "authjson",
            "authfiledigest",
            "authfilehash",
            "command",
            "commandtext",
            "shellfragment",
            "authpath",
            "bearer",
            "cookie",
            "cookies",
            "credential",
            "credentials",
            "idtoken",
            "password",
            "privatekey",
            "refreshtoken",
            "secret",
            "token",
            "vaultpath",
        ])
        if let object = value as? [String: Any] {
            return object.contains { key, child in
                let normalizedKey = key.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
                return forbiddenKeys.contains(normalizedKey) || self.containsForbiddenCredentialKey(child, depth: depth + 1)
            }
        }
        if let array = value as? [Any] {
            return array.contains { self.containsForbiddenCredentialKey($0, depth: depth + 1) }
        }
        return false
    }
}
