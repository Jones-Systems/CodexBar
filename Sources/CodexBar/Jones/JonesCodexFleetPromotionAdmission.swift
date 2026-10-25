import CodexBarCore
import Foundation

@MainActor
struct JonesCodexFleetPromotionAdmission {
    let loadFleetHomePaths: @MainActor () -> [String]?
    let defaultHomeURL: URL
    let ambientHomeURL: URL

    static func discoverHomePaths() -> [String]? {
        guard case let .available(paths) = CodexFleetProfileDiscovery.discover() else { return nil }
        return paths
    }

    /// Called after the shared writer is acquired and again after asynchronous preparation.
    func validate(_ target: JonesCodexFleetPromotionTarget) throws -> [URL] {
        try Task.checkCancellation()
        guard let paths = self.loadFleetHomePaths(),
              paths.count(where: { $0 == target.canonicalHomePath }) == 1
        else { throw CodexAccountPromotionError.fleetTargetUnavailable }
        let homes = paths.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let source = URL(fileURLWithPath: target.canonicalHomePath, isDirectory: true)
        guard !Self.overlaps(source, self.defaultHomeURL),
              !homes.contains(where: { Self.overlaps($0, self.defaultHomeURL) }),
              homes.count(where: { Self.overlaps($0, source) }) == 1
        else { throw CodexAccountPromotionError.fleetDestinationAmbiguous }
        // liveSystem consumers use the process's ambient home. Refuse an overridden launch
        // rather than report success for a different home or mutate the launch environment.
        guard Self.sameHome(self.ambientHomeURL, self.defaultHomeURL) else {
            throw CodexAccountPromotionError.fleetLaunchHomeOverride
        }
        return homes
    }

    static func validateIdentity(_ material: PreparedAuthMaterial, target: JonesCodexFleetPromotionTarget) throws {
        guard material.authIdentity.email == target.expectedEmail,
              material.authIdentity.providerAccountID == target.expectedWorkspaceAccountID,
              material.authIdentity.workspaceAccountID == target.expectedWorkspaceAccountID,
              CodexAuthFingerprint.fingerprint(data: material.rawData) == target.expectedAuthFingerprint
        else { throw CodexAccountPromotionError.fleetTargetIdentityChanged }
    }

    static func sameHome(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.resolvingSymlinksInPath() == rhs.standardizedFileURL.resolvingSymlinksInPath()
    }

    static func overlaps(_ lhs: URL, _ rhs: URL) -> Bool {
        let left = lhs.standardizedFileURL.resolvingSymlinksInPath().path
        let right = rhs.standardizedFileURL.resolvingSymlinksInPath().path
        return left == right || left.hasPrefix(right + "/") || right.hasPrefix(left + "/")
            || lhs.appendingPathComponent("auth.json").resolvingSymlinksInPath()
            == rhs.appendingPathComponent("auth.json").resolvingSymlinksInPath()
    }

    static func requireUnprotectedHome(_ home: URL, protectedHomes: [URL]) throws {
        guard !protectedHomes.contains(where: { self.overlaps(home, $0) }) else {
            throw CodexAccountPromotionError.fleetDestinationAmbiguous
        }
    }
}

/// Fleet auth is never represented as a fabricated managed account or enrolled in its store.
enum JonesPreparedPromotionTarget {
    case managed(PreparedStoredManagedAccount)
    case fleet(JonesCodexFleetPromotionTarget, PreparedAuthMaterial)

    var managedAccount: PreparedStoredManagedAccount? {
        guard case let .managed(account) = self else { return nil }
        return account
    }

    var managedAccountID: UUID? {
        self.managedAccount?.persisted.id
    }

    var remoteIdentity: PreparedIdentity {
        switch self {
        case let .managed(account): account.remoteIdentity
        case let .fleet(_, material): material.authIdentity
        }
    }
}
