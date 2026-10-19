import Foundation

extension CAAMEnvironmentContract {
    public static let snapshotFreshness: TimeInterval = 60
    public static let maximumCacheAge: TimeInterval = 15 * 60
    public static let clockSkewAllowance: TimeInterval = 5

    public static func isCurrent(_ snapshot: CAAMEnvironmentSnapshot, now: Date) -> Bool {
        let age = now.timeIntervalSince(snapshot.observedAt)
        return age.isFinite && age >= -self.clockSkewAllowance && age <= self.snapshotFreshness
    }

    static func decodeResponse<Value: Codable & Sendable>(
        _ type: Value.Type,
        data: Data,
        environmentID: String,
        kind: String) throws -> Value
    {
        guard data.count <= self.maximumOutputBytes else {
            throw CAAMEnvironmentContractError.outputTooLarge
        }
        guard String(data: data, encoding: .utf8) != nil else {
            throw CAAMEnvironmentContractError.invalidEncoding
        }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              !self.containsForbiddenCredentialKey(object)
        else {
            throw CAAMEnvironmentContractError.invalidEnvelope("The CAAM response contained invalid fields.")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(CAAMControlEnvelope<Value>.self, from: data) else {
            throw CAAMEnvironmentContractError.invalidEnvelope("The CAAM gateway response was malformed.")
        }
        let version = envelope.protocolVersion.split(separator: ".", omittingEmptySubsequences: false)
        guard envelope.schema == self.schema,
              envelope.protocolVersion.utf8.count <= 32,
              version.first == "1",
              version.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } })
        else {
            throw CAAMControlFailure(reason: .incompatible)
        }
        guard envelope.environmentID == environmentID, envelope.kind == kind,
              (envelope.result == nil) != (envelope.error == nil)
        else {
            throw CAAMEnvironmentContractError.invalidEnvelope("The CAAM response binding was invalid.")
        }
        if let error = envelope.error {
            guard self.isSafeIdentifier(error.code, maximumLength: 64),
                  self.isSafeDisplayText(error.message, maximumLength: 240)
            else {
                throw CAAMEnvironmentContractError.invalidEnvelope("The CAAM gateway error was invalid.")
            }
            throw CAAMEnvironmentContractError.remoteError(
                code: error.code,
                message: "CAAM rejected the request.",
                effect: error.effect)
        }
        guard let result = envelope.result else {
            throw CAAMEnvironmentContractError.invalidEnvelope("The CAAM gateway omitted its result.")
        }
        return result
    }

    public static func validatePlan(
        _ plan: CAAMSwitchPlan,
        snapshot: CAAMEnvironmentSnapshot,
        target: String,
        now: Date) throws
    {
        guard self.isCurrent(snapshot, now: now), plan.expiresAt > now,
              plan.expectedRevision == snapshot.revision,
              plan.currentProfile == snapshot.hostDefaultProfile,
              plan.targetProfile == target,
              snapshot.profiles.contains(where: { $0.name == target && $0.eligible }),
              plan.planDigest.utf8.count == 64,
              plan.planDigest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              plan.affectedProfiles.count <= self.maximumProfileCount,
              Set(plan.affectedProfiles).count == plan.affectedProfiles.count,
              Set(plan.affectedProfiles).isSubset(of: Set(snapshot.profiles.map(\.name))),
              plan.affectedProfiles.contains(target)
        else {
            throw CAAMControlFailure(reason: .stale)
        }
    }

    public static func validateOperationResult(_ result: CAAMOperationResult, operationID: UUID) throws {
        guard result.operationID == operationID,
              [result.previousProfile, result.currentProfile].compactMap(\.self)
                  .allSatisfy({ self.isSafeIdentifier($0, maximumLength: 64) })
        else {
            throw CAAMControlFailure(reason: .invalidResponse, effect: .unknown)
        }
        if let snapshot = result.snapshot {
            try self.validateSnapshot(snapshot)
            guard result.currentProfile == snapshot.hostDefaultProfile,
                  snapshot.pendingOperation == nil || snapshot.pendingOperation?.operationID == operationID
            else {
                throw CAAMControlFailure(reason: .invalidResponse, effect: .unknown)
            }
        }
        guard result.recoveryRequired == (result.state == .recoveryRequired),
              result.manualRequired == (result.state == .manualRequired)
        else {
            throw CAAMControlFailure(reason: .invalidResponse, effect: .unknown)
        }
        if result.state.isTerminal {
            guard let snapshot = result.snapshot, snapshot.pendingOperation == nil, result.effect != .unknown,
                  result.state != .committed || result.effect == .knownEffect,
                  result.state != .rejected || result.effect == .knownNoEffect,
                  result.state != .rolledBack || result.currentProfile == result.previousProfile
            else {
                throw CAAMControlFailure(reason: .invalidResponse, effect: .unknown)
            }
        }
        if result.state == .recoveryRequired || result.state == .manualRequired {
            let expected: CAAMPendingOperationState = result.state == .recoveryRequired
                ? .recoveryRequired : .manualRequired
            guard result.snapshot?.pendingOperation?.state == expected else {
                throw CAAMControlFailure(reason: .invalidResponse, effect: .unknown)
            }
        }
    }
}
