import Foundation

public struct HubHostObservation: Sendable, Equatable, Identifiable {
    public let environmentID: String
    public let evidence: HubEvidence
    public let cpuPercent: Double?
    public let memoryUsedBytes: UInt64?

    public var id: String { self.environmentID }
}

/// No Netdata API contract is present in this repository. No network collector is activated or guessed.
public enum NetdataReadOnlyFacade {
    public static func unavailable(environmentID: String) -> HubHostObservation {
        HubHostObservation(
            environmentID: environmentID,
            evidence: HubEvidence(source: "Netdata collector not configured", observedAt: nil, availability: .unsupported),
            cpuPercent: nil,
            memoryUsedBytes: nil)
    }

    /// A user-supplied navigation target is not telemetry evidence. Never attach credentials or query parameters.
    public static func dashboardURL(_ value: String) -> URL? {
        guard value.utf8.count <= 2048,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let components = URLComponents(string: value),
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              let host = components.host?.lowercased(), !host.isEmpty,
              components.port == nil || (1...65535).contains(components.port ?? 0)
        else { return nil }
        let loopback = ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host)
        guard components.scheme?.lowercased() == "https" ||
            (components.scheme?.lowercased() == "http" && loopback)
        else { return nil }
        return components.url
    }
}
