#if os(macOS)
import CryptoKit
import Foundation

/// Explicit bootstrap only. Adapters must prove absence and throw on unavailable or unreadable stores.
public enum JonesBootstrapMigration {
    public static let bundle = "com.jonessystems.codexbar"
    public static let oldGroup = "JONESLOCAL.com.jonessystems.codexbar"
    public static let newGroup = "2CUPSQS986.com.jonessystems.codexbar"
    public static let preferences = ["debugDisableKeychainAccess", "widgetSelectedProvider", "providerAccentColors"]
    public static let snapshot = "widget-snapshot.json"

    public enum Failure: Error { case invalid, conflict, drift, unavailable, incomplete }

    public struct Request: Codable, Equatable, Sendable {
        public var schema = "jones-bootstrap-request/v1"
        public var transaction: String
        public var uid: UInt32
        public var target: String
        public var oldTree: String
        public var candidateTree: String
        public var archive: String
        public var revision: String
        public var snapshotSource: String

        public init(
            transaction: String,
            uid: UInt32,
            target: String,
            oldTree: String,
            candidateTree: String,
            archive: String,
            revision: String,
            snapshotSource: String)
        {
            self.transaction = transaction
            self.uid = uid
            self.target = target
            self.oldTree = oldTree
            self.candidateTree = candidateTree
            self.archive = archive
            self.revision = revision
            self.snapshotSource = snapshotSource
        }

        public func validate() throws {
            guard self.schema == "jones-bootstrap-request/v1", UUID(uuidString: self.transaction) != nil,
                  self.target.hasPrefix("/"), self.target.hasSuffix("/CodexBar Jones.app"),
                  [self.oldTree, self.candidateTree, self.archive].allSatisfy({ Self.hex($0, count: 64) }),
                  Self.hex(self.revision, count: 40),
                  ["auto", "old-group", "fallback"].contains(self.snapshotSource)
            else { throw Failure.invalid }
        }

        private static func hex(_ text: String, count: Int) -> Bool {
            text.count == count && text.allSatisfy { "0123456789abcdef".contains($0) }
        }
    }

    public struct Fingerprint: Codable, Equatable, Sendable {
        public let status: String
        public let sha256: String?

        public init(_ data: Data?) {
            self.status = data == nil ? "absent" : "present"
            self.sha256 = data.map(JonesBootstrapMigration.digest)
        }
    }

    public struct Item: Codable, Equatable, Sendable {
        public let key: String
        public let source: String
        public let before: Fingerprint
        public let after: Fingerprint
    }

    public struct Plan: Codable, Equatable, Sendable {
        public let request: Request
        public let oldGroup: String
        public let newGroup: String
        public let locations: [String: String]
        public let sources: [String: Fingerprint]
        public let items: [Item]
    }

    public struct Receipt: Codable, Equatable, Sendable {
        public var schema = "jones-bootstrap-receipt/v1"
        public let plan: Plan
        public let planSHA256: String
        public var phase: String

        public func validate() throws {
            try self.plan.request.validate()
            let keys = JonesBootstrapMigration.preferences + [JonesBootstrapMigration.snapshot]
            guard self.schema == "jones-bootstrap-receipt/v1",
                  self.plan.oldGroup == JonesBootstrapMigration.oldGroup,
                  self.plan.newGroup == JonesBootstrapMigration.newGroup,
                  self.plan.items.map(\.key) == keys,
                  Array(self.plan.items.prefix(3)).allSatisfy({ $0.key == $0.source }),
                  ["oldSnapshot", "fallbackSnapshot"].contains(self.plan.items.last?.source ?? ""),
                  Set(self.plan.sources.keys) == Set(JonesBootstrapMigration.preferences
                      + ["localPolicy", "oldSnapshot", "fallbackSnapshot"]),
                  try self.planSHA256 == (JonesBootstrapMigration.digest(JonesBootstrapMigration.encode(self.plan))),
                  ["incomplete", "prepared", "data-verified", "installed", "launch-attempted"]
                      .contains(self.phase)
            else { throw Failure.invalid }
            for item in self.plan.items {
                guard let source = self.plan.sources[item.source],
                      item.after == (source.status == "absent" ? item.before : source),
                      item.before.status == "absent" || source.status == "absent" || item.before == source
                else { throw Failure.invalid }
            }
        }
    }

    public struct Inventory {
        public var locations: [String: String]
        public var sources: [String: Data]
        public var destination: [String: Data]

        public init(locations: [String: String], sources: [String: Data], destination: [String: Data]) {
            self.locations = locations
            self.sources = sources
            self.destination = destination
        }
    }

    public protocol Storage {
        func read() throws -> Inventory
        func write(_ value: Data, key: String) throws
        func save(_ receipt: Receipt) throws
    }

    public static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private static func sources(_ inventory: Inventory) -> [String: Fingerprint] {
        Dictionary(uniqueKeysWithValues: (self.preferences + ["localPolicy", "oldSnapshot", "fallbackSnapshot"])
            .map { ($0, Fingerprint(inventory.sources[$0])) })
    }

    private static func snapshotSource(_ inventory: Inventory, choice: String) throws -> String {
        let old = inventory.sources["oldSnapshot"]
        let fallback = inventory.sources["fallbackSnapshot"]
        if choice == "old-group" {
            guard old != nil else { throw Failure.invalid }
            return "oldSnapshot"
        }
        if choice == "fallback" {
            guard fallback != nil else { throw Failure.invalid }
            return "fallbackSnapshot"
        }
        guard old == nil || fallback == nil || old == fallback else { throw Failure.conflict }
        return old == nil ? "fallbackSnapshot" : "oldSnapshot"
    }

    private static func policy(_ data: Data?) throws -> Bool {
        guard let data else { return false }
        return try JSONDecoder().decode(Bool.self, from: data)
    }

    public static func plan(_ request: Request, inventory: Inventory) throws -> Plan {
        try request.validate()
        let source = try self.snapshotSource(inventory, choice: request.snapshotSource)
        let mappings = self.preferences.map { ($0, $0) } + [(self.snapshot, source)]
        let items = try mappings.map { key, source -> Item in
            let before = inventory.destination[key]
            let value = inventory.sources[source]
            guard value == nil || before == nil || value == before else { throw Failure.conflict }
            return Item(key: key, source: source, before: Fingerprint(before), after: Fingerprint(value ?? before))
        }
        let local = inventory.sources["localPolicy"]
        let oldPolicy = try self.policy(local ?? inventory.sources["debugDisableKeychainAccess"])
        let newPolicy = try self.policy(local ?? inventory.sources["debugDisableKeychainAccess"]
            ?? inventory.destination["debugDisableKeychainAccess"])
        guard oldPolicy == newPolicy else { throw Failure.conflict }
        return Plan(
            request: request,
            oldGroup: self.oldGroup,
            newGroup: self.newGroup,
            locations: inventory.locations,
            sources: self.sources(inventory),
            items: items)
    }

    private static func validateSources(_ plan: Plan, inventory: Inventory) throws {
        guard plan.locations == inventory.locations,
              plan.sources == self.sources(inventory) else { throw Failure.drift }
    }

    /// An interrupted write may already equal its recorded postimage. No other destination change is adopted.
    public static func prepare(_ request: Request, storage: some Storage, resume: Receipt? = nil) throws -> Receipt {
        let inventory = try storage.read()
        var receipt: Receipt
        if let resume {
            try resume.validate()
            guard resume.plan.request == request, ["incomplete", "prepared"].contains(resume.phase) else {
                throw Failure.invalid
            }
            receipt = resume
            try self.validateSources(receipt.plan, inventory: inventory)
        } else {
            let plan = try self.plan(request, inventory: inventory)
            receipt = try Receipt(plan: plan, planSHA256: self.digest(self.encode(plan)), phase: "incomplete")
        }
        for item in receipt.plan.items {
            let actual = Fingerprint(inventory.destination[item.key])
            guard actual == item.before || actual == item.after else { throw Failure.drift }
        }
        try storage.save(receipt)
        for item in receipt.plan.items {
            let fresh = try storage.read()
            try self.validateSources(receipt.plan, inventory: fresh)
            let actual = Fingerprint(fresh.destination[item.key])
            guard actual == item.before || actual == item.after else { throw Failure.drift }
            if actual != item.after {
                guard let value = fresh.sources[item.source], Fingerprint(value) == item.after else {
                    throw Failure.incomplete
                }
                try storage.write(value, key: item.key)
            }
        }
        try self.verifyData(receipt, storage: storage)
        receipt.phase = "prepared"
        try storage.save(receipt)
        return receipt
    }

    public static func verifyData(_ receipt: Receipt, storage: some Storage) throws {
        try receipt.validate()
        let inventory = try storage.read()
        try self.validateSources(receipt.plan, inventory: inventory)
        for item in receipt.plan.items {
            guard Fingerprint(inventory.destination[item.key]) == item.after else { throw Failure.drift }
        }
    }

    /// The native command calls this in a fresh process after prepare and again immediately before the swap.
    public static func verify(_ receipt: Receipt, storage: some Storage) throws -> Receipt {
        guard ["prepared", "data-verified"].contains(receipt.phase) else { throw Failure.invalid }
        try self.verifyData(receipt, storage: storage)
        var verified = receipt
        verified.phase = "data-verified"
        try storage.save(verified)
        return verified
    }
}
#endif
