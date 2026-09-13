import Foundation

public enum RepositorySyncError: Error, Equatable, Sendable {
    case invalidTarget
    case unsafeState
    case stalePlan
    case unqualifiedTarget
    case operationConflict
    case resourceBusy
    case unknownOperation
    case invalidReceipt
    case journalUnavailable
    case journalCapacity
    case rollbackUnavailable
}

/// A host-qualified mapping, not a shell command. Use the existing CAAM environment's stable id.
public struct RepositorySyncTarget: Codable, Equatable, Hashable, Sendable {
    public let environmentID: String
    public let configurationRevision: String
    public let repositoryID: String
    public let rootPath: String
    public let relativePath: String
    public let canonicalRemote: String
    public let branch: String

    public init(
        environmentID: String,
        configurationRevision: String,
        repositoryID: String,
        rootPath: String,
        relativePath: String,
        canonicalRemote: String,
        branch: String) throws
    {
        self.environmentID = environmentID
        self.configurationRevision = configurationRevision
        self.repositoryID = repositoryID
        self.rootPath = rootPath
        self.relativePath = relativePath
        self.canonicalRemote = canonicalRemote
        self.branch = branch
        try self.validate()
    }

    public var path: String { self.rootPath + "/" + self.relativePath }

    public func validate() throws {
        guard Self.isToken(self.environmentID), Self.isToken(self.configurationRevision),
              Self.isToken(self.repositoryID), self.rootPath.hasPrefix("/"),
              Self.isPath(String(self.rootPath.dropFirst())), Self.isPath(self.relativePath),
              self.path.utf8.count <= 1024, Self.isBranch(self.branch),
              let url = URLComponents(string: self.canonicalRemote), url.scheme == "https",
              let host = url.host, Self.isToken(host), host == host.lowercased(),
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil, !self.canonicalRemote.contains("%"),
              url.path.hasPrefix("/"), Self.isPath(String(url.path.dropFirst())),
              self.canonicalRemote.utf8.count <= 512
        else { throw RepositorySyncError.invalidTarget }
    }

    /// Conservatively collide case variants and nested mappings, including renamed logical repositories.
    public func overlaps(_ other: Self) -> Bool {
        guard self.environmentID == other.environmentID else { return false }
        let left = self.path.lowercased()
        let right = other.path.lowercased()
        return self.repositoryID == other.repositoryID || left == right ||
            left.hasPrefix(right + "/") || right.hasPrefix(left + "/")
    }

    static func isToken(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128 && value.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) ||
                $0 == 45 || $0 == 46 || $0 == 95
        }
    }

    private static func isPath(_ value: String) -> Bool {
        guard !value.isEmpty, !value.contains("\\"), !value.contains("~"),
              value.utf8.allSatisfy({ (32...126).contains($0) }) else { return false }
        return value.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".." && $0.lowercased() != ".git" &&
                !$0.hasSuffix(" ") && !$0.hasSuffix(".")
        }
    }

    private static func isBranch(_ value: String) -> Bool {
        guard value.utf8.count <= 128, Self.isPath(value), !value.hasPrefix("-"),
              !value.contains(".."), !value.contains("@{"), value != "@", value != "HEAD",
              value.utf8.allSatisfy({
                  (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) ||
                      [45, 46, 47, 95].contains($0)
              }) else { return false }
        return value.split(separator: "/").allSatisfy { !$0.hasPrefix(".") && !$0.hasSuffix(".lock") }
    }
}

public enum RepositorySyncHazard: String, Codable, Sendable, CaseIterable {
    case dirty
    case unknownCleanliness
    case inProgress
    case bare
    case shallow
    case linkedWorktree
    case submodules
    case sparseCheckout
    case untrustedConfiguration
    case unresolvedPath
}

/// Host observations must cover tracked, untracked, ignored, index, and in-progress Git state.
public struct RepositorySyncSnapshot: Codable, Equatable, Sendable {
    public let target: RepositorySyncTarget
    public let repositoryIdentity: String
    public let revision: String
    public let observedAt: Date
    public let resolvedPath: String
    public let actualRemote: String
    public let actualBranch: String?
    public let headOID: String
    public let canonicalOID: String
    public let ahead: Int
    public let behind: Int
    public let headIsAncestor: Bool
    public let hazards: Set<RepositorySyncHazard>

    public init(
        target: RepositorySyncTarget,
        repositoryIdentity: String,
        revision: String,
        observedAt: Date,
        resolvedPath: String,
        actualRemote: String,
        actualBranch: String?,
        headOID: String,
        canonicalOID: String,
        ahead: Int,
        behind: Int,
        headIsAncestor: Bool,
        hazards: Set<RepositorySyncHazard> = [])
    {
        self.target = target
        self.repositoryIdentity = repositoryIdentity
        self.revision = revision
        self.observedAt = observedAt
        self.resolvedPath = resolvedPath
        self.actualRemote = actualRemote
        self.actualBranch = actualBranch
        self.headOID = headOID
        self.canonicalOID = canonicalOID
        self.ahead = ahead
        self.behind = behind
        self.headIsAncestor = headIsAncestor
        self.hazards = hazards
    }

    func validate(at now: Date) throws {
        try self.target.validate()
        guard RepositorySyncTarget.isToken(self.repositoryIdentity), RepositorySyncTarget.isToken(self.revision),
              self.resolvedPath == self.target.path, self.actualRemote == self.target.canonicalRemote,
              self.actualBranch == self.target.branch, self.hazards.isEmpty,
              Self.isOID(self.headOID), Self.isOID(self.canonicalOID),
              self.headOID.count == self.canonicalOID.count,
              (0...1000000).contains(self.ahead), (0...1000000).contains(self.behind)
        else { throw RepositorySyncError.unsafeState }
        let age = now.timeIntervalSince(self.observedAt)
        guard age.isFinite, age >= 0, age <= 60 else { throw RepositorySyncError.stalePlan }
    }

    static func isOID(_ value: String) -> Bool {
        [40, 64].contains(value.utf8.count) && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        } && value.contains(where: { $0 != "0" })
    }
}

public enum RepositorySyncAction: String, Codable, Sendable {
    case unchanged
    case fastForward
    case rollback
}

/// Immutable exact-state confirmation. Deserialized plans are revalidated at every effect boundary.
public struct RepositorySyncPlan: Codable, Equatable, Sendable {
    public let operationID: UUID
    public let snapshot: RepositorySyncSnapshot
    public let action: RepositorySyncAction
    public let destinationOID: String
    public let originalOperationID: UUID?
    public let createdAt: Date
    public let expiresAt: Date

    public var backupRef: String {
        "refs/codexbar-sync/" + (self.originalOperationID ?? self.operationID).uuidString.lowercased()
    }

    public static func prepare(
        snapshot: RepositorySyncSnapshot,
        operationID: UUID = UUID(),
        now: Date = Date()) throws -> Self
    {
        try snapshot.validate(at: now)
        let unchanged = snapshot.ahead == 0 && snapshot.behind == 0 && snapshot.headOID == snapshot.canonicalOID
        let forward = snapshot.ahead == 0 && snapshot.behind > 0 && snapshot.headIsAncestor &&
            snapshot.headOID != snapshot.canonicalOID
        guard unchanged || forward else { throw RepositorySyncError.unsafeState }
        return Self(
            operationID: operationID,
            snapshot: snapshot,
            action: unchanged ? .unchanged : .fastForward,
            destinationOID: snapshot.canonicalOID,
            originalOperationID: nil,
            createdAt: now,
            expiresAt: now.addingTimeInterval(60))
    }

    public static func rollback(
        original: RepositorySyncRecord,
        snapshot: RepositorySyncSnapshot,
        operationID: UUID = UUID(),
        now: Date = Date()) throws -> Self
    {
        try snapshot.validate(at: now)
        guard original.state == .applied, original.plan.action == .fastForward,
              original.plan.snapshot.target == snapshot.target,
              original.plan.snapshot.repositoryIdentity == snapshot.repositoryIdentity,
              original.plan.destinationOID == snapshot.headOID,
              original.plan.operationID != operationID
        else { throw RepositorySyncError.rollbackUnavailable }
        return Self(
            operationID: operationID,
            snapshot: snapshot,
            action: .rollback,
            destinationOID: original.plan.snapshot.headOID,
            originalOperationID: original.plan.operationID,
            createdAt: now,
            expiresAt: now.addingTimeInterval(60))
    }

    func validate(at now: Date) throws {
        try self.snapshot.validate(at: now)
        let lifetime = self.expiresAt.timeIntervalSince(self.createdAt)
        guard lifetime.isFinite, lifetime > 0, lifetime <= 60,
              now >= self.createdAt, now < self.expiresAt,
              self.createdAt >= self.snapshot.observedAt,
              RepositorySyncSnapshot.isOID(self.destinationOID),
              self.destinationOID.count == self.snapshot.headOID.count
        else { throw RepositorySyncError.stalePlan }
        switch self.action {
        case .unchanged, .fastForward:
            let expected = try Self.prepare(snapshot: self.snapshot, operationID: self.operationID, now: self.createdAt)
            guard self == expected else { throw RepositorySyncError.unsafeState }
        case .rollback:
            guard let original = self.originalOperationID, original != self.operationID,
                  self.destinationOID != self.snapshot.headOID
            else { throw RepositorySyncError.rollbackUnavailable }
        }
    }
}

public enum RepositorySyncState: String, Codable, Sendable {
    case pending
    case unknown
    case conflicted
    case applied
    case notApplied
    case cancelled

    public var isTerminal: Bool { self == .applied || self == .notApplied || self == .cancelled }
}

public struct RepositorySyncRecord: Codable, Equatable, Sendable {
    public let plan: RepositorySyncPlan
    public internal(set) var state: RepositorySyncState = .pending
    public internal(set) var cancellationRequested = false

    public init(plan: RepositorySyncPlan) { self.plan = plan }
}

public struct RepositorySyncReceipt: Sendable {
    public let plan: RepositorySyncPlan
    public let state: RepositorySyncState
    public let observedHeadOID: String
    public let preservedBackupRef: String?

    public init(
        plan: RepositorySyncPlan,
        state: RepositorySyncState,
        observedHeadOID: String,
        preservedBackupRef: String? = nil)
    {
        self.plan = plan
        self.state = state
        self.observedHeadOID = observedHeadOID
        self.preservedBackupRef = preservedBackupRef
    }

    func validate(for plan: RepositorySyncPlan) throws {
        guard self.plan == plan, self.state.isTerminal else { throw RepositorySyncError.invalidReceipt }
        if self.state == .applied {
            guard plan.action != .unchanged, self.observedHeadOID == plan.destinationOID,
                  self.preservedBackupRef == plan.backupRef else { throw RepositorySyncError.invalidReceipt }
        } else {
            guard self.observedHeadOID == plan.snapshot.headOID else { throw RepositorySyncError.invalidReceipt }
        }
    }
}

public enum RepositorySyncLookup: Sendable {
    /// Includes not-found, timeout, malformed data, and in-progress: none proves no effect.
    case unresolved
    case terminal(RepositorySyncReceipt)
}

/// Separate from CAAM account control. A conforming host must lock and revalidate the exact repository,
/// journal intent before Git mutation, suppress hooks/filters, bound all subprocesses, and deduplicate by full plan.
/// No production implementation or live transport is implicitly selected by this protocol.
public protocol RepositorySyncHost: Sendable {
    func execute(_ plan: RepositorySyncPlan) async throws -> RepositorySyncReceipt
    func status(of plan: RepositorySyncPlan) async throws -> RepositorySyncLookup
    func requestCancellation(of plan: RepositorySyncPlan) async throws
}
