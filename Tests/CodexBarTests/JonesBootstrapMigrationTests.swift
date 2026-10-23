import Foundation
import Testing
@testable import CodexBarCore

private final class JonesBootstrapMemoryStorage: JonesBootstrapMigration.Storage {
    var inventory = JonesBootstrapMigration.Inventory(
        locations: [
            "old": "/synthetic/old",
            "destination": "/synthetic/new",
            "fallback": "/synthetic/fallback",
            "standard": "/synthetic/preferences",
        ],
        sources: [:], destination: [:])
    var receipt: JonesBootstrapMigration.Receipt?
    var writes: [String] = []
    var unavailable = false
    var interruptAt: Int?
    var boundary = 0
    let configSentinel = Data("config must remain byte identical".utf8)
    let syncSentinel = Data("pending deletions and unknown serialization fields".utf8)

    func checkpoint() throws {
        self.boundary += 1
        if self.boundary == self.interruptAt { throw JonesBootstrapMigration.Failure.incomplete }
    }

    func read() throws -> JonesBootstrapMigration.Inventory {
        if self.unavailable { throw JonesBootstrapMigration.Failure.unavailable }
        return self.inventory
    }

    func write(_ value: Data, key: String) throws {
        try self.checkpoint()
        self.writes.append(key)
        self.inventory.destination[key] = value
        try self.checkpoint()
    }

    func save(_ receipt: JonesBootstrapMigration.Receipt) throws {
        try self.checkpoint()
        self.receipt = receipt
        try self.checkpoint()
    }
}

struct JonesBootstrapMigrationTests {
    private func request(choice: String = "auto") -> JonesBootstrapMigration.Request {
        .init(
            transaction: "12345678-1234-1234-1234-123456789abc", uid: 501,
            target: "/synthetic/Applications/CodexBar Jones.app", oldTree: String(repeating: "a", count: 64),
            candidateTree: String(repeating: "b", count: 64), archive: String(repeating: "c", count: 64),
            revision: String(repeating: "d", count: 40), snapshotSource: choice)
    }

    private func populated() -> JonesBootstrapMemoryStorage {
        let storage = JonesBootstrapMemoryStorage()
        storage.inventory.sources = [
            "debugDisableKeychainAccess": Data("true".utf8),
            "widgetSelectedProvider": Data("\"codex\"".utf8),
            "providerAccentColors": Data("{\"codex\":\"#112233\"}".utf8),
            "oldSnapshot": Data("synthetic snapshot".utf8),
        ]
        return storage
    }

    @Test
    func `all conflicts and inaccessible stores refuse before any writes or journal`() throws {
        for key in JonesBootstrapMigration.preferences + [JonesBootstrapMigration.snapshot] {
            let storage = self.populated()
            storage.inventory.destination[key] = Data("conflicting existing value".utf8)
            #expect(throws: (any Error).self) {
                try JonesBootstrapMigration.prepare(self.request(), storage: storage)
            }
            #expect(storage.writes.isEmpty)
            #expect(storage.receipt == nil)
        }
        let storage = self.populated()
        storage.unavailable = true
        #expect(throws: (any Error).self) {
            try JonesBootstrapMigration.prepare(self.request(), storage: storage)
        }
        #expect(storage.receipt == nil)
        #expect(storage.writes.isEmpty)
    }

    @Test
    func `different snapshots require explicit choice and neither source is modified`() throws {
        let storage = self.populated()
        storage.inventory.sources["fallbackSnapshot"] = Data("different snapshot".utf8)
        let sources = storage.inventory.sources
        #expect(throws: (any Error).self) {
            try JonesBootstrapMigration.prepare(self.request(), storage: storage)
        }
        #expect(storage.writes.isEmpty)
        let prepared = try JonesBootstrapMigration.prepare(self.request(choice: "fallback"), storage: storage)
        #expect(storage.inventory.destination[JonesBootstrapMigration.snapshot] == sources["fallbackSnapshot"])
        #expect(storage.inventory.sources == sources)
        #expect(prepared.phase == "prepared")
    }

    @Test
    func `shared only disable is copied and local false retains precedence without changing local preferences`() throws {
        for local in [nil, Data("false".utf8), Data("true".utf8)] {
            let storage = self.populated()
            storage.inventory.sources["localPolicy"] = local
            let before = storage.inventory.sources
            let prepared = try JonesBootstrapMigration.prepare(self.request(), storage: storage)
            let verified = try JonesBootstrapMigration.verify(prepared, storage: storage)
            #expect(verified.phase == "data-verified")
            #expect(storage.inventory.destination["debugDisableKeychainAccess"] == Data("true".utf8))
            #expect(storage.inventory.sources == before)
            #expect(storage.configSentinel == Data("config must remain byte identical".utf8))
            #expect(storage.syncSentinel == Data("pending deletions and unknown serialization fields".utf8))
        }
    }

    @Test
    func `absence is recorded and equal destination is idempotent`() throws {
        let storage = self.populated()
        let prepared = try JonesBootstrapMigration.prepare(self.request(), storage: storage)
        #expect(prepared.plan.sources["fallbackSnapshot"]?.status == "absent")
        let writes = storage.writes
        _ = try JonesBootstrapMigration.prepare(self.request(), storage: storage, resume: prepared)
        #expect(storage.writes == writes)
        let empty = JonesBootstrapMemoryStorage()
        let absent = try JonesBootstrapMigration.prepare(self.request(), storage: empty)
        #expect(absent.plan.items.allSatisfy { $0.after.status == "absent" })
        #expect(empty.writes.isEmpty)
    }

    @Test
    func `every journal and write interruption resumes only the recorded plan`() throws {
        for boundary in 1...12 {
            let storage = self.populated()
            storage.interruptAt = boundary
            #expect(throws: (any Error).self) {
                try JonesBootstrapMigration.prepare(self.request(), storage: storage)
            }
            storage.interruptAt = nil
            let prepared = try JonesBootstrapMigration.prepare(
                self.request(),
                storage: storage,
                resume: storage.receipt)
            _ = try JonesBootstrapMigration.verify(prepared, storage: storage)
            #expect(storage.writes.count == 4)
            #expect(storage.inventory.sources["debugDisableKeychainAccess"] == Data("true".utf8))
        }
    }

    @Test
    func `changed sources destinations and request bindings refuse resume or verification`() throws {
        let storage = self.populated()
        let prepared = try JonesBootstrapMigration.prepare(self.request(), storage: storage)
        var changed = self.request()
        changed.uid = 502
        #expect(throws: (any Error).self) {
            try JonesBootstrapMigration.prepare(changed, storage: storage, resume: prepared)
        }
        storage.inventory.sources["localPolicy"] = Data("true".utf8)
        #expect(throws: (any Error).self) { try JonesBootstrapMigration.verify(prepared, storage: storage) }
        storage.inventory.sources.removeValue(forKey: "localPolicy")
        storage.inventory.destination["widgetSelectedProvider"] = Data("\"changed\"".utf8)
        #expect(throws: (any Error).self) { try JonesBootstrapMigration.verify(prepared, storage: storage) }
        #expect(storage.writes.count == 4)
    }

    @Test
    func `receipt schema tampering and consumed phase refuse`() throws {
        let storage = self.populated()
        var receipt = try JonesBootstrapMigration.prepare(self.request(), storage: storage)
        receipt.schema = "unknown"
        #expect(throws: (any Error).self) { try receipt.validate() }
        receipt.schema = "jones-bootstrap-receipt/v1"
        receipt.phase = "installed"
        #expect(throws: (any Error).self) { try JonesBootstrapMigration.verify(receipt, storage: storage) }
        #expect(throws: (any Error).self) {
            try JonesBootstrapMigration.prepare(self.request(), storage: storage, resume: receipt)
        }
    }
}
