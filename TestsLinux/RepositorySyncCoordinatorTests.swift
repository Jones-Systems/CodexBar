import Foundation
import Testing
@testable import CodexBarCore

struct RepositorySyncCoordinatorTests {
    @Test
    func `production execution is disabled by default`() async throws {
        let directory = try repositorySyncDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try RepositorySyncJournal(directory: directory, createNew: true)
        let host = RepositorySyncFixtureHost()
        let coordinator = RepositorySyncCoordinator(host: host, journal: journal)
        let plan = try self.plan()
        await #expect(throws: RepositorySyncError.unqualifiedTarget) {
            try await coordinator.execute(plan, now: repositorySyncTestDate)
        }
        #expect(await host.executions.isEmpty)
        #expect(try await journal.record(plan.operationID) == nil)
    }

    @Test
    func `one confirmation dispatches once and restart never replays`() async throws {
        let directory = try repositorySyncDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try RepositorySyncJournal(directory: directory, createNew: true)
        let host = RepositorySyncFixtureHost()
        let plan = try self.plan()
        let coordinator = self.coordinator(host, journal, plan)
        #expect(try await coordinator.execute(plan, now: repositorySyncTestDate).state == .applied)
        for _ in 0..<10 {
            #expect(try await coordinator.execute(plan, now: repositorySyncTestDate).state == .applied)
        }
        let reopened = try RepositorySyncJournal(directory: directory)
        let successor = RepositorySyncCoordinator(host: host, journal: reopened)
        let afterRestart = try await successor.execute(plan, now: repositorySyncTestDate.addingTimeInterval(600))
        #expect(afterRestart.state == .applied)
        #expect(await host.executions.count == 1)
    }

    @Test
    func `unchanged state is recorded without a host effect`() async throws {
        let directory = try repositorySyncDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try RepositorySyncJournal(directory: directory, createNew: true)
        let host = RepositorySyncFixtureHost()
        let snapshot = repositorySyncSnapshot(target: try repositorySyncTarget(), head: repositorySyncAfter, behind: 0)
        let plan = try RepositorySyncPlan.prepare(snapshot: snapshot, now: repositorySyncTestDate)
        let result = try await self.coordinator(host, journal, plan).execute(plan, now: repositorySyncTestDate)
        #expect(result.state == .notApplied)
        #expect(await host.executions.isEmpty)
    }

    @Test(arguments: [-1.0, 60.0, 61.0])
    func `expired and future plans cannot reserve or dispatch`(_ offset: Double) async throws {
        let directory = try repositorySyncDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try RepositorySyncJournal(directory: directory, createNew: true)
        let host = RepositorySyncFixtureHost()
        let plan = try self.plan()
        await #expect(throws: RepositorySyncError.stalePlan) {
            try await self.coordinator(host, journal, plan).execute(
                plan,
                now: repositorySyncTestDate.addingTimeInterval(offset))
        }
        #expect(try await journal.record(plan.operationID) == nil)
        #expect(await host.executions.isEmpty)
    }

    @Test
    func `qualification is bound to complete configuration not just environment id`() async throws {
        let directory = try repositorySyncDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try RepositorySyncJournal(directory: directory, createNew: true)
        let host = RepositorySyncFixtureHost()
        let plan = try self.plan(target: repositorySyncTarget(revision: "configuration-v2"))
        let coordinator = RepositorySyncCoordinator(
            host: host,
            journal: journal,
            qualifiedTargets: [try repositorySyncTarget()])
        await #expect(throws: RepositorySyncError.unqualifiedTarget) {
            try await coordinator.execute(plan, now: repositorySyncTestDate)
        }
    }

    @Test
    func `reuse of UUID for a different intent is rejected`() async throws {
        let directory = try repositorySyncDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try RepositorySyncJournal(directory: directory, createNew: true)
        let host = RepositorySyncFixtureHost()
        let first = try self.plan()
        let coordinator = self.coordinator(host, journal, first)
        _ = try await coordinator.execute(first, now: repositorySyncTestDate)
        let changed = try self.plan(target: repositorySyncTarget(revision: "new-revision"), id: first.operationID)
        await #expect(throws: RepositorySyncError.operationConflict) {
            try await coordinator.execute(changed, now: repositorySyncTestDate)
        }
        #expect(await host.executions.count == 1)
    }

    @Test
    func `lost response requires same operation readback never execute retry`() async throws {
        let directory = try repositorySyncDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try RepositorySyncJournal(directory: directory, createNew: true)
        let host = RepositorySyncFixtureHost()
        await host.configure(behavior: .lostResponse)
        let plan = try self.plan()
        let coordinator = self.coordinator(host, journal, plan)
        #expect(try await coordinator.execute(plan, now: repositorySyncTestDate).state == .unknown)
        #expect(try await coordinator.execute(plan, now: repositorySyncTestDate).state == .unknown)
        #expect(try await coordinator.reconcile(plan.operationID).state == .unknown)
        await host.configure(lookup: .applied)
        let reopened = try RepositorySyncJournal(directory: directory)
        let successor = RepositorySyncCoordinator(host: host, journal: reopened)
        #expect(try await successor.reconcile(plan.operationID).state == .applied)
        #expect(await host.executions.count == 1)
        #expect(await host.lookups.allSatisfy { $0 == plan })
    }

    @Test
    func `unknown outcome blocks overlapping paths but independent targets can proceed`() async throws {
        let directory = try repositorySyncDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try RepositorySyncJournal(directory: directory, createNew: true)
        let host = RepositorySyncFixtureHost()
        await host.configure(behavior: .lostResponse)
        let original = try self.plan()
        let nested = try self.plan(target: repositorySyncTarget(repository: "nested", path: "team/project/child"))
        let independent = try self.plan(target: repositorySyncTarget(environment: "other-environment"))
        let coordinator = RepositorySyncCoordinator(
            host: host,
            journal: journal,
            qualifiedTargets: [original.snapshot.target, nested.snapshot.target, independent.snapshot.target])
        _ = try await coordinator.execute(original, now: repositorySyncTestDate)
        await #expect(throws: RepositorySyncError.resourceBusy) {
            try await coordinator.execute(nested, now: repositorySyncTestDate)
        }
        await host.configure()
        #expect(try await coordinator.execute(independent, now: repositorySyncTestDate).state == .applied)
        #expect(await host.executions.count == 2)
    }

    @Test
    func `already cancelled task records known no effect before dispatch`() async throws {
        let directory = try repositorySyncDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try RepositorySyncJournal(directory: directory, createNew: true)
        let host = RepositorySyncFixtureHost()
        let plan = try self.plan()
        let coordinator = self.coordinator(host, journal, plan)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await coordinator.execute(plan, now: repositorySyncTestDate)
        }
        #expect(try await task.value.state == .cancelled)
        #expect(await host.executions.isEmpty)
    }

    @Test
    func `applied completion wins cancellation race and preserves request evidence`() async throws {
        let directory = try repositorySyncDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try RepositorySyncJournal(directory: directory, createNew: true)
        let host = RepositorySyncFixtureHost()
        await host.configure(pause: true)
        let plan = try self.plan()
        let coordinator = self.coordinator(host, journal, plan)
        let task = Task { try await coordinator.execute(plan, now: repositorySyncTestDate) }
        await host.waitForExecution()
        let interrupted = try await coordinator.cancel(plan.operationID)
        #expect(interrupted.cancellationRequested)
        #expect(interrupted.state == .unknown)
        await host.resumeExecution()
        let completed = try await task.value
        #expect(completed.state == .applied)
        #expect(completed.cancellationRequested)
        #expect(await host.cancellations == [plan])
        #expect(try await coordinator.cancel(plan.operationID).state == .applied)
        #expect(await host.cancellations.count == 1)
    }

    @Test
    func `lost cancellation acknowledgement is not reported as cancelled`() async throws {
        let directory = try repositorySyncDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try RepositorySyncJournal(directory: directory, createNew: true)
        let host = RepositorySyncFixtureHost()
        await host.configure(behavior: .lostResponse)
        let plan = try self.plan()
        let coordinator = self.coordinator(host, journal, plan)
        _ = try await coordinator.execute(plan, now: repositorySyncTestDate)
        #expect(try await coordinator.cancel(plan.operationID).state == .unknown)
        await host.configure(lookup: .cancelled)
        #expect(try await coordinator.reconcile(plan.operationID).state == .cancelled)
        #expect(await host.executions.count == 1)
    }

    @Test(arguments: [
        RepositorySyncFixtureHost.Behavior.wrongHead, .missingBackup, .wrongOperation,
    ])
    func `misbound or incomplete receipts fence instead of inventing success`(
        _ behavior: RepositorySyncFixtureHost.Behavior) async throws
    {
        let directory = try repositorySyncDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try RepositorySyncJournal(directory: directory, createNew: true)
        let host = RepositorySyncFixtureHost()
        await host.configure(behavior: behavior, lookup: behavior)
        let plan = try self.plan()
        let coordinator = self.coordinator(host, journal, plan)
        #expect(try await coordinator.execute(plan, now: repositorySyncTestDate).state == .unknown)
        #expect(try await coordinator.reconcile(plan.operationID).state == .unknown)
        #expect(await host.executions.count == 1)
    }

    @Test
    func `competing coordinators allow at most one dispatch despite nonblocking lock contention`() async throws {
        let directory = try repositorySyncDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try RepositorySyncJournal(directory: directory, createNew: true)
        let second = try RepositorySyncJournal(directory: directory)
        let host = RepositorySyncFixtureHost()
        let plan = try self.plan()
        let firstCoordinator = self.coordinator(host, journal, plan)
        let secondCoordinator = self.coordinator(host, second, plan)
        try await withThrowingTaskGroup(of: RepositorySyncRecord?.self) { group in
            for index in 0..<20 {
                let coordinator = index.isMultiple(of: 2) ? firstCoordinator : secondCoordinator
                group.addTask {
                    do {
                        return try await coordinator.execute(plan, now: repositorySyncTestDate)
                    } catch RepositorySyncError.journalUnavailable {
                        // Nonblocking process locks can report contention, never permission to replay.
                        return nil
                    }
                }
            }
            for try await _ in group {}
        }
        let count = await host.executions.count
        #expect(count <= 1)
        await host.configure(lookup: count == 1 ? .applied : nil)
        let resolved = try await firstCoordinator.reconcile(plan.operationID)
        #expect(resolved.state == (count == 1 ? .applied : .unknown))
        _ = try await firstCoordinator.execute(plan, now: repositorySyncTestDate)
        #expect(await host.executions.count == count)
    }

    @Test
    func `rollback requires stored applied original and exact current state`() async throws {
        let directory = try repositorySyncDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try RepositorySyncJournal(directory: directory, createNew: true)
        let host = RepositorySyncFixtureHost()
        let plan = try self.plan()
        let coordinator = self.coordinator(host, journal, plan)
        let original = try await coordinator.execute(plan, now: repositorySyncTestDate)
        let current = repositorySyncSnapshot(target: plan.snapshot.target, head: repositorySyncAfter, behind: 0)
        let rollback = try RepositorySyncPlan.rollback(
            original: original,
            snapshot: current,
            now: repositorySyncTestDate)
        #expect(rollback.destinationOID == repositorySyncBefore)
        #expect(rollback.backupRef == plan.backupRef)
        #expect(try await coordinator.execute(rollback, now: repositorySyncTestDate).state == .applied)
        #expect(try await coordinator.execute(rollback, now: repositorySyncTestDate).state == .applied)
        #expect(await host.executions.count == 2)
        let moved = repositorySyncSnapshot(target: plan.snapshot.target, head: String(repeating: "3", count: 40))
        #expect(throws: RepositorySyncError.rollbackUnavailable) {
            try RepositorySyncPlan.rollback(original: original, snapshot: moved, now: repositorySyncTestDate)
        }
    }

    @Test
    func `an unrecorded applied original cannot authorize rollback`() async throws {
        let directory = try repositorySyncDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try RepositorySyncJournal(directory: directory, createNew: true)
        let host = RepositorySyncFixtureHost()
        let plan = try self.plan()
        var forged = RepositorySyncRecord(plan: plan)
        forged.state = .applied
        let rollback = try RepositorySyncPlan.rollback(
            original: forged,
            snapshot: repositorySyncSnapshot(target: plan.snapshot.target, head: repositorySyncAfter, behind: 0),
            now: repositorySyncTestDate)
        await #expect(throws: RepositorySyncError.rollbackUnavailable) {
            try await self.coordinator(host, journal, plan).execute(rollback, now: repositorySyncTestDate)
        }
        #expect(await host.executions.isEmpty)
    }

    @Test
    func `persistence failure after dispatch prevents retry even when no result can be saved`() async throws {
        let directory = try repositorySyncDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try RepositorySyncJournal(directory: directory, createNew: true)
        let host = RepositorySyncFixtureHost()
        await host.configure(corruptionURL: directory.appendingPathComponent("operations.json"))
        let plan = try self.plan()
        let coordinator = self.coordinator(host, journal, plan)
        await #expect(throws: RepositorySyncError.journalUnavailable) {
            try await coordinator.execute(plan, now: repositorySyncTestDate)
        }
        await #expect(throws: RepositorySyncError.journalUnavailable) {
            try await coordinator.execute(plan, now: repositorySyncTestDate)
        }
        #expect(await host.executions.count == 1)
    }

    private func plan(target: RepositorySyncTarget? = nil, id: UUID = UUID()) throws -> RepositorySyncPlan {
        try RepositorySyncPlan.prepare(
            snapshot: repositorySyncSnapshot(target: try target ?? repositorySyncTarget()),
            operationID: id,
            now: repositorySyncTestDate)
    }

    private func coordinator(
        _ host: RepositorySyncFixtureHost,
        _ journal: RepositorySyncJournal,
        _ plan: RepositorySyncPlan) -> RepositorySyncCoordinator
    {
        RepositorySyncCoordinator(host: host, journal: journal, qualifiedTargets: [plan.snapshot.target])
    }
}
