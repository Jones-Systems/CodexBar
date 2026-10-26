import Foundation

public enum FleetSnapshotSchema {
    public static let currentVersion = 1
}

public struct DeviceSyncPayload: Codable, Sendable {
    public let schemaVersion: Int
    public let deviceID: String
    public let hostName: String
    public let model: String
    public let appVersion: String
    public let lastSeen: Date

    public init(
        deviceID: String,
        hostName: String,
        model: String,
        appVersion: String,
        lastSeen: Date,
        schemaVersion: Int = FleetSnapshotSchema.currentVersion)
    {
        self.schemaVersion = schemaVersion
        self.deviceID = deviceID
        self.hostName = hostName
        self.model = model
        self.appVersion = appVersion
        self.lastSeen = lastSeen
    }

    public var recordName: String {
        "device-\(self.deviceID)"
    }
}

public struct AccountSnapshotSyncPayload: Codable, Sendable {
    public let schemaVersion: Int
    public let provider: ProviderInstanceID
    public let deviceID: String
    public let accountKey: String
    public let fetchedAt: Date
    public let displayLabel: String
    public let usage: UsageSnapshot

    public init(
        provider: ProviderInstanceID,
        deviceID: String,
        accountIdentity: String?,
        displayLabel: String,
        usage: UsageSnapshot,
        schemaVersion: Int = FleetSnapshotSchema.currentVersion)
    {
        self.schemaVersion = schemaVersion
        self.provider = provider
        self.deviceID = deviceID
        self.accountKey = Self.accountKey(for: accountIdentity)
        self.fetchedAt = usage.updatedAt
        self.displayLabel = displayLabel
        self.usage = usage
    }

    public init(
        provider: ProviderInstanceID,
        deviceID: String,
        accountKey: String,
        fetchedAt: Date,
        displayLabel: String,
        usage: UsageSnapshot,
        schemaVersion: Int = FleetSnapshotSchema.currentVersion)
    {
        self.schemaVersion = schemaVersion
        self.provider = provider
        self.deviceID = deviceID
        self.accountKey = accountKey
        self.fetchedAt = fetchedAt
        self.displayLabel = displayLabel
        self.usage = usage
    }

    public var recordName: String {
        "snap-\(self.provider.rawValue)-\(self.accountKey)-\(self.deviceID)"
    }

    public static func accountKey(for identity: String?) -> String {
        guard let identity = identity?.trimmingCharacters(in: .whitespacesAndNewlines), !identity.isEmpty else {
            return "default"
        }
        return CanonicalSyncJSON.hash(data: Data(identity.lowercased().utf8))
    }
}
