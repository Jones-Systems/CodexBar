import Foundation

/// A presentation projection of supplied observations, never a collector or native acceptance receipt.
public struct NetdataSystemsState: Sendable, Equatable {
    public let environmentID: String
    public let source: String
    public let observedAt: Date?
    public let receivedAt: Date?
    public let sampleAgeSeconds: TimeInterval?
    public let availability: HubAvailability
    public let cpuPercent: Double?
    public let availableRAMGiB: Double?
    public let isRefreshing: Bool

    public init(
        environmentID: String,
        observation: HubHostObservation? = nil,
        receivedAt: Date? = nil,
        now: Date,
        requestFailed: Bool = false,
        isRefreshing: Bool = false)
    {
        self.environmentID = environmentID
        self.isRefreshing = isRefreshing
        guard !environmentID.isEmpty, environmentID.utf8.count <= 128,
              !environmentID.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let observation, observation.environmentID == environmentID
        else {
            self.source = "No supplied host observation"
            self.observedAt = nil
            self.receivedAt = nil
            self.sampleAgeSeconds = nil
            self.availability = .unavailable
            self.cpuPercent = nil
            self.availableRAMGiB = nil
            return
        }
        self.source = observation.evidence.source
        self.observedAt = observation.evidence.observedAt
        self.receivedAt = receivedAt.flatMap { $0.timeIntervalSince1970.isFinite ? $0 : nil }
        let age = observation.evidence.observedAt.map { now.timeIntervalSince($0) }
        self.sampleAgeSeconds = age.flatMap { $0.isFinite ? $0 : nil }
        self.cpuPercent = observation.cpuPercent.flatMap {
            $0.isFinite && (0...100).contains($0) ? $0 : nil
        }
        self.availableRAMGiB = observation.memoryAvailableBytes.map { Double($0) / 1_073_741_824 }
        let supplied = observation.evidence.availability
        if supplied == .unsupported || supplied == .unavailable {
            self.availability = supplied
        } else if self.cpuPercent == nil, self.availableRAMGiB == nil {
            self.availability = .unavailable
        } else if !now.timeIntervalSince1970.isFinite || self.sampleAgeSeconds == nil {
            self.availability = .unavailable
        } else if let age = self.sampleAgeSeconds, age > 300 {
            self.availability = .unavailable
        } else if requestFailed || supplied == .stale ||
            (self.sampleAgeSeconds.map { $0 < -5 || $0 > 30 } ?? true)
        {
            self.availability = .stale
        } else if supplied == .partial || self.cpuPercent == nil || self.availableRAMGiB == nil {
            self.availability = .partial
        } else {
            self.availability = .available
        }
    }

    /// Cached values remain accessible with their original shared sample time; compact text hides stale values.
    public func compactLabel(hostLabel: String) -> String {
        let label = String(String.UnicodeScalarView(
            hostLabel.unicodeScalars.prefix(128).filter { !CharacterSet.controlCharacters.contains($0) }))
        switch self.availability {
        case .available, .partial:
            let cpu = self.cpuPercent.map { Self.number($0, decimals: 0) + "%" } ?? "CPU unavailable"
            let ram = self.availableRAMGiB.map { Self.number($0, decimals: 1) + " GiB avail" } ?? "RAM unavailable"
            return "\(label) \(cpu) · \(ram)"
        case .stale: return "\(label) Stale"
        case .unavailable: return "\(label) Unavailable"
        case .unsupported: return "\(label) Not configured"
        }
    }

    private static func number(_ value: Double, decimals: Int) -> String {
        String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), decimals, value)
    }
}
