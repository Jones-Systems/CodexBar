import Foundation
@testable import CodexBarCore

let repositorySyncTestDate = Date(timeIntervalSince1970: 2000000000)
let repositorySyncBefore = String(repeating: "1", count: 40)
let repositorySyncAfter = String(repeating: "2", count: 40)

func repositorySyncTarget(
    environment: String = "fixture-environment",
    revision: String = "configuration-v1",
    repository: String = "fixture-repository",
    root: String = "/fixture/repos",
    path: String = "team/project",
    remote: String = "https://example.invalid/team/project.git",
    branch: String = "main") throws -> RepositorySyncTarget
{
    try RepositorySyncTarget(
        environmentID: environment,
        configurationRevision: revision,
        repositoryID: repository,
        rootPath: root,
        relativePath: path,
        canonicalRemote: remote,
        branch: branch)
}

func repositorySyncSnapshot(
    target: RepositorySyncTarget,
    head: String = repositorySyncBefore,
    canonical: String = repositorySyncAfter,
    ahead: Int = 0,
    behind: Int = 1,
    ancestor: Bool = true,
    hazards: Set<RepositorySyncHazard> = [],
    observedAt: Date = repositorySyncTestDate,
    actualBranch: String? = "main",
    actualPath: String? = nil,
    actualRemote: String? = nil,
    identity: String = "fixture-inode-1") -> RepositorySyncSnapshot
{
    RepositorySyncSnapshot(
        target: target,
        repositoryIdentity: identity,
        revision: "fixture-state-v1",
        observedAt: observedAt,
        resolvedPath: actualPath ?? target.path,
        actualRemote: actualRemote ?? target.canonicalRemote,
        actualBranch: actualBranch,
        headOID: head,
        canonicalOID: canonical,
        ahead: ahead,
        behind: behind,
        headIsAncestor: ancestor,
        hazards: hazards)
}

func repositorySyncDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("codexbar-sync-test-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
    return directory
}

actor RepositorySyncFixtureHost: RepositorySyncHost {
    enum Behavior: Sendable {
        case applied
        case notApplied
        case cancelled
        case lostResponse
        case wrongHead
        case missingBackup
        case wrongOperation
    }

    private(set) var executions: [RepositorySyncPlan] = []
    private(set) var lookups: [RepositorySyncPlan] = []
    private(set) var cancellations: [RepositorySyncPlan] = []
    private var behavior: Behavior = .applied
    private var lookupBehavior: Behavior?
    private var pause = false
    private var release: CheckedContinuation<Void, Never>?
    private var entered: [CheckedContinuation<Void, Never>] = []
    private var corruptionURL: URL?

    func configure(
        behavior: Behavior = .applied,
        lookup: Behavior? = nil,
        pause: Bool = false,
        corruptionURL: URL? = nil)
    {
        self.behavior = behavior
        self.lookupBehavior = lookup
        self.pause = pause
        self.corruptionURL = corruptionURL
    }

    func execute(_ plan: RepositorySyncPlan) async throws -> RepositorySyncReceipt {
        self.executions.append(plan)
        for waiter in self.entered { waiter.resume() }
        self.entered.removeAll()
        if self.pause { await withCheckedContinuation { self.release = $0 } }
        if let url = self.corruptionURL { try Data("corrupt".utf8).write(to: url) }
        return try self.receipt(plan, behavior: self.behavior)
    }

    func waitForExecution() async {
        if !self.executions.isEmpty { return }
        await withCheckedContinuation { self.entered.append($0) }
    }

    func resumeExecution() {
        self.release?.resume()
        self.release = nil
    }

    func status(of plan: RepositorySyncPlan) async throws -> RepositorySyncLookup {
        self.lookups.append(plan)
        guard let behavior = self.lookupBehavior else { return .unresolved }
        return try .terminal(self.receipt(plan, behavior: behavior))
    }

    func requestCancellation(of plan: RepositorySyncPlan) async throws {
        self.cancellations.append(plan)
        if self.behavior == .lostResponse { throw CancellationError() }
    }

    private func receipt(_ plan: RepositorySyncPlan, behavior: Behavior) throws -> RepositorySyncReceipt {
        switch behavior {
        case .lostResponse:
            throw CancellationError()
        case .notApplied, .cancelled:
            return RepositorySyncReceipt(
                plan: plan,
                state: behavior == .cancelled ? .cancelled : .notApplied,
                observedHeadOID: plan.snapshot.headOID)
        case .applied, .wrongHead, .missingBackup:
            return RepositorySyncReceipt(
                plan: plan,
                state: .applied,
                observedHeadOID: behavior == .wrongHead ? plan.snapshot.headOID : plan.destinationOID,
                preservedBackupRef: behavior == .missingBackup ? nil : plan.backupRef)
        case .wrongOperation:
            let wrong = try RepositorySyncPlan.prepare(snapshot: plan.snapshot, now: plan.createdAt)
            return RepositorySyncReceipt(
                plan: wrong,
                state: .applied,
                observedHeadOID: plan.destinationOID,
                preservedBackupRef: plan.backupRef)
        }
    }
}
