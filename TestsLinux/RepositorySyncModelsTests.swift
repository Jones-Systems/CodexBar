import Foundation
import Testing
@testable import CodexBarCore

struct RepositorySyncModelsTests {
    @Test
    func `path mapping preserves spaces without shell expansion`() throws {
        let target = try repositorySyncTarget(root: "/fixture/My Repos", path: "team/My Project")
        #expect(target.path == "/fixture/My Repos/team/My Project")
        #expect(try JSONDecoder().decode(RepositorySyncTarget.self, from: JSONEncoder().encode(target)) == target)
    }

    @Test(arguments: ["../x", "x/../y", "/absolute", "./x", "x//y", "x/.git", "x\\y", "~/x", "x/\n", "x/.", "x."])
    func `unsafe relative paths are rejected`(_ path: String) {
        #expect(throws: RepositorySyncError.invalidTarget) { try repositorySyncTarget(path: path) }
    }

    @Test(arguments: ["/", "/tmp/", "relative", "/tmp/../x", "/tmp//x"])
    func `ambiguous roots are rejected`(_ root: String) {
        #expect(throws: RepositorySyncError.invalidTarget) { try repositorySyncTarget(root: root) }
    }

    @Test(arguments: [
        "http://example.invalid/a/b", "https://user:secret@example.invalid/a/b",
        "https://example.invalid/a/b?token=value", "https://example.invalid/a/b#fragment",
        "https://example.invalid/a/%2e%2e/b", "file:///fixture/repo", "ssh://example.invalid/a/b",
    ])
    func `only credential free canonical HTTPS remotes are accepted`(_ remote: String) {
        #expect(throws: RepositorySyncError.invalidTarget) { try repositorySyncTarget(remote: remote) }
    }

    @Test(arguments: ["-main", "a..b", ".main", "a.lock", "a/.b", "a@{b}", "HEAD:main", "a b", "a/", "@", "HEAD"])
    func `unsafe branch names are rejected`(_ branch: String) {
        #expect(throws: RepositorySyncError.invalidTarget) { try repositorySyncTarget(branch: branch) }
    }

    @Test
    func `overlap ignores configuration revision and catches case and nested aliases`() throws {
        let target = try repositorySyncTarget()
        #expect(try target.overlaps(repositorySyncTarget(revision: "configuration-v2")))
        #expect(try target.overlaps(repositorySyncTarget(repository: "other", path: "TEAM/PROJECT")))
        #expect(try target.overlaps(repositorySyncTarget(repository: "other", path: "team/project/child")))
        #expect(try !target.overlaps(repositorySyncTarget(repository: "other", path: "team/project-other")))
        #expect(try !target.overlaps(repositorySyncTarget(environment: "other-environment")))
    }

    @Test
    func `safe behind state prepares only a fast forward`() throws {
        let target = try repositorySyncTarget()
        let plan = try RepositorySyncPlan.prepare(
            snapshot: repositorySyncSnapshot(target: target),
            now: repositorySyncTestDate)
        #expect(plan.action == .fastForward)
        #expect(plan.destinationOID == repositorySyncAfter)
        #expect(plan.backupRef == "refs/codexbar-sync/" + plan.operationID.uuidString.lowercased())
    }

    @Test(arguments: RepositorySyncHazard.allCases)
    func `every unsafe or unknown Git state blocks planning`(_ hazard: RepositorySyncHazard) throws {
        let snapshot = repositorySyncSnapshot(target: try repositorySyncTarget(), hazards: [hazard])
        #expect(throws: RepositorySyncError.unsafeState) {
            try RepositorySyncPlan.prepare(snapshot: snapshot, now: repositorySyncTestDate)
        }
    }

    @Test
    func `ahead diverged and contradictory ancestry are not silently merged or pushed`() throws {
        let target = try repositorySyncTarget()
        let snapshots = [
            repositorySyncSnapshot(target: target, ahead: 1, behind: 0),
            repositorySyncSnapshot(target: target, ahead: 1, behind: 1),
            repositorySyncSnapshot(target: target, ancestor: false),
            repositorySyncSnapshot(target: target, behind: 0),
            repositorySyncSnapshot(target: target, head: repositorySyncAfter),
            repositorySyncSnapshot(target: target, ahead: -1),
        ]
        for snapshot in snapshots {
            #expect(throws: RepositorySyncError.unsafeState) {
                try RepositorySyncPlan.prepare(snapshot: snapshot, now: repositorySyncTestDate)
            }
        }
    }

    @Test
    func `detached HEAD wrong remote wrong physical path and malformed OIDs block`() throws {
        let target = try repositorySyncTarget()
        let snapshots = [
            repositorySyncSnapshot(target: target, actualBranch: nil),
            repositorySyncSnapshot(target: target, actualBranch: "other"),
            repositorySyncSnapshot(target: target, actualPath: "/fixture/escape"),
            repositorySyncSnapshot(target: target, actualRemote: "https://example.invalid/other/repo"),
            repositorySyncSnapshot(target: target, head: "abc123"),
            repositorySyncSnapshot(target: target, head: String(repeating: "0", count: 40)),
            repositorySyncSnapshot(target: target, head: String(repeating: "A", count: 40)),
        ]
        for snapshot in snapshots {
            #expect(throws: RepositorySyncError.unsafeState) {
                try RepositorySyncPlan.prepare(snapshot: snapshot, now: repositorySyncTestDate)
            }
        }
    }

    @Test(arguments: [-61.0, 1.0])
    func `stale and future dated snapshots fail closed`(_ offset: Double) throws {
        let snapshot = repositorySyncSnapshot(
            target: try repositorySyncTarget(),
            observedAt: repositorySyncTestDate.addingTimeInterval(offset))
        #expect(throws: RepositorySyncError.stalePlan) {
            try RepositorySyncPlan.prepare(snapshot: snapshot, now: repositorySyncTestDate)
        }
    }

    @Test
    func `SHA256 repositories retain exact object format`() throws {
        let snapshot = repositorySyncSnapshot(
            target: try repositorySyncTarget(),
            head: String(repeating: "1", count: 64),
            canonical: String(repeating: "2", count: 64))
        let plan = try RepositorySyncPlan.prepare(snapshot: snapshot, now: repositorySyncTestDate)
        #expect(plan.destinationOID.count == 64)
    }
}
