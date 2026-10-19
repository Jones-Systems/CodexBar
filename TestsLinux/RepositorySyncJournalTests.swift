import Foundation
import Testing
@testable import CodexBarCore

struct RepositorySyncJournalTests {
    @Test
    func `new state is private and creating it twice never overwrites evidence`() async throws {
        let directory = try repositorySyncDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try RepositorySyncJournal(directory: directory, createNew: true)
        let plan = try self.plan()
        #expect(try await journal.reserve(plan))
        #expect(throws: RepositorySyncError.journalUnavailable) {
            try RepositorySyncJournal(directory: directory, createNew: true)
        }
        let reopened = try RepositorySyncJournal(directory: directory)
        #expect(try await reopened.record(plan.operationID)?.state == .pending)
        for name in ["operations.json", "operations.lock"] {
            let path = directory.appendingPathComponent(name).path
            let permissions = try FileManager.default.attributesOfItem(atPath: path)
            #expect((permissions[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
    }

    @Test
    func `missing journal is never treated as empty on restart or an existing instance`() async throws {
        let directory = try repositorySyncDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try RepositorySyncJournal(directory: directory, createNew: true)
        try FileManager.default.removeItem(at: directory.appendingPathComponent("operations.json"))
        #expect(throws: RepositorySyncError.journalUnavailable) { try RepositorySyncJournal(directory: directory) }
        await #expect(throws: RepositorySyncError.journalUnavailable) { try await journal.record(UUID()) }
        #expect(throws: RepositorySyncError.journalUnavailable) {
            try RepositorySyncJournal(directory: directory, createNew: true)
        }
    }

    @Test(arguments: ["corrupt", "[]", "{}", "{\"version\":2,\"records\":[]}"])
    func `malformed or unsupported journal content blocks all dispatch`(_ payload: String) async throws {
        let directory = try repositorySyncDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try RepositorySyncJournal(directory: directory, createNew: true)
        try Data(payload.utf8).write(to: directory.appendingPathComponent("operations.json"))
        let plan = try self.plan()
        let host = RepositorySyncFixtureHost()
        let coordinator = RepositorySyncCoordinator(
            host: host,
            journal: journal,
            qualifiedTargets: [plan.snapshot.target])
        await #expect(throws: RepositorySyncError.journalUnavailable) {
            try await coordinator.execute(plan, now: repositorySyncTestDate)
        }
        #expect(await host.executions.isEmpty)
    }

    @Test
    func `oversize journal is refused before decoding`() async throws {
        let directory = try repositorySyncDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try RepositorySyncJournal(directory: directory, createNew: true)
        try Data(repeating: 32, count: 1048577).write(to: directory.appendingPathComponent("operations.json"))
        await #expect(throws: RepositorySyncError.journalUnavailable) { try await journal.record(UUID()) }
    }

    @Test
    func `symlink journal does not read or replace its target`() async throws {
        let directory = try repositorySyncDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try RepositorySyncJournal(directory: directory, createNew: true)
        let dataURL = directory.appendingPathComponent("operations.json")
        let outside = directory.appendingPathComponent("unrelated.txt")
        try Data("untouched".utf8).write(to: outside)
        try FileManager.default.removeItem(at: dataURL)
        try FileManager.default.createSymbolicLink(at: dataURL, withDestinationURL: outside)
        await #expect(throws: RepositorySyncError.journalUnavailable) { try await journal.reserve(self.plan()) }
        #expect(try String(contentsOf: outside, encoding: .utf8) == "untouched")
    }

    @Test
    func `symlink directory and public directory are rejected`() throws {
        let directory = try repositorySyncDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let alias = directory.appendingPathComponent("alias")
        let real = directory.appendingPathComponent("real")
        try FileManager.default.createDirectory(
            at: real,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real)
        #expect(throws: RepositorySyncError.journalUnavailable) {
            try RepositorySyncJournal(directory: alias, createNew: true)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: real.path)
        #expect(throws: RepositorySyncError.journalUnavailable) {
            try RepositorySyncJournal(directory: real, createNew: true)
        }
    }

    @Test
    func `permission drift is checked on every transaction`() async throws {
        let directory = try repositorySyncDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try RepositorySyncJournal(directory: directory, createNew: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        await #expect(throws: RepositorySyncError.journalUnavailable) { try await journal.record(UUID()) }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: directory.appendingPathComponent("operations.json").path)
        await #expect(throws: RepositorySyncError.journalUnavailable) { try await journal.record(UUID()) }
    }

    @Test
    func `unknown records and tombstones are retained at capacity`() async throws {
        let directory = try repositorySyncDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try RepositorySyncJournal(directory: directory, createNew: true)
        var original: RepositorySyncPlan?
        for index in 0..<256 {
            let plan = try self.plan(environment: "fixture-\(index)")
            #expect(try await journal.reserve(plan))
            if index == 0 {
                original = plan
                _ = try await journal.setState(.unknown, for: plan.operationID)
            } else {
                _ = try await journal.setState(.notApplied, for: plan.operationID)
            }
        }
        await #expect(throws: RepositorySyncError.journalCapacity) {
            try await journal.reserve(self.plan(environment: "overflow"))
        }
        let retained = try #require(original)
        #expect(try await journal.record(retained.operationID)?.state == .unknown)
        #expect(try await !journal.reserve(retained))
    }

    @Test
    func `decoded targets are revalidated and duplicate operation IDs are refused`() async throws {
        let directory = try repositorySyncDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try RepositorySyncJournal(directory: directory, createNew: true)
        #expect(try await journal.reserve(self.plan()))
        let url = directory.appendingPathComponent("operations.json")
        let valid = try Data(contentsOf: url)
        let altered = try #require(String(data: valid, encoding: .utf8)).replacingOccurrences(
            of: "fixture-repository",
            with: "invalid/token")
        try Data(altered.utf8).write(to: url)
        await #expect(throws: RepositorySyncError.journalUnavailable) { try await journal.record(UUID()) }
        var envelope = try #require(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        let records = try #require(envelope["records"] as? [[String: Any]])
        envelope["records"] = records + records
        try JSONSerialization.data(withJSONObject: envelope).write(to: url)
        await #expect(throws: RepositorySyncError.journalUnavailable) { try await journal.record(UUID()) }
    }

    @Test
    func `orphan temporary writes cannot replace the last atomic journal`() async throws {
        let directory = try repositorySyncDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try RepositorySyncJournal(directory: directory, createNew: true)
        let plan = try self.plan()
        #expect(try await journal.reserve(plan))
        try Data("partial".utf8).write(to: directory.appendingPathComponent("intent-interrupted.tmp"))
        let reopened = try RepositorySyncJournal(directory: directory)
        #expect(try await reopened.record(plan.operationID)?.state == .pending)
    }

    @Test
    func `terminal results never regress when an older lookup is unresolved`() async throws {
        let directory = try repositorySyncDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try RepositorySyncJournal(directory: directory, createNew: true)
        let plan = try self.plan()
        #expect(try await journal.reserve(plan))
        _ = try await journal.setState(.applied, for: plan.operationID)
        #expect(try await journal.setState(.unknown, for: plan.operationID).state == .applied)
        #expect(try await journal.setState(.cancelled, for: plan.operationID).state == .conflicted)
        #expect(try await journal.setState(.applied, for: plan.operationID).state == .conflicted)
        await #expect(throws: RepositorySyncError.resourceBusy) { try await journal.reserve(self.plan()) }
    }

    private func plan(environment: String = "fixture-environment") throws -> RepositorySyncPlan {
        try RepositorySyncPlan.prepare(
            snapshot: repositorySyncSnapshot(target: repositorySyncTarget(environment: environment)),
            now: repositorySyncTestDate)
    }
}
