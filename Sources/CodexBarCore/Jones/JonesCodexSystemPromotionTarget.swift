import Foundation

/// Promotion provenance is independent of the source selected for usage observation.
public enum JonesCodexSystemPromotionTarget: Equatable, Sendable {
    case managedAccount(UUID)
    case fleetProfile(JonesCodexFleetPromotionTarget)

    public var managedAccountID: UUID? {
        guard case let .managedAccount(id) = self else { return nil }
        return id
    }
}

public struct JonesCodexFleetPromotionTarget: Equatable, Sendable {
    public let canonicalHomePath: String
    public let expectedEmail: String
    public let expectedWorkspaceAccountID: String
    public let expectedAuthFingerprint: String

    public init?(profile: ObservedSystemCodexAccount, fleetHomePaths: [String]) {
        guard let path = CodexHomeScope.normalizedHomePath(profile.codexHomePath),
              fleetHomePaths.contains(path),
              let email = CodexIdentityResolver.normalizeEmail(profile.email),
              let workspace = ManagedCodexAccount.normalizeWorkspaceAccountID(profile.workspaceAccountID),
              let fingerprint = profile.authFingerprint
        else { return nil }
        self.canonicalHomePath = path
        self.expectedEmail = email
        self.expectedWorkspaceAccountID = workspace
        self.expectedAuthFingerprint = fingerprint
    }
}
