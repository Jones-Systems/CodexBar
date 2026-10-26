import CodexBarCore
import Foundation

/// Device-local, explicit opt-in. Neither this record nor its dashboard belongs to provider sync.
struct NetdataConfiguration: Codable, Equatable, Sendable {
    struct Host: Codable, Equatable, Sendable {
        var environmentID: String
        var label: String
        var origin: String
        var expectedMachineGUID: String

        var transportIdentity: TransportIdentity {
            TransportIdentity(
                environmentID: self.environmentID,
                origin: self.origin,
                expectedMachineGUID: self.expectedMachineGUID)
        }
    }

    struct TransportIdentity: Equatable, Sendable {
        let environmentID: String
        let origin: String
        let expectedMachineGUID: String
    }

    enum ValidationError: Error {
        case unsupportedVersion
        case missingHost
        case invalidHost
        case invalidDashboard
    }

    var version = 1
    var enabled = false
    var host: Host?
    var dashboardURL: String?

    var activeHost: Host? {
        self.enabled ? self.host : nil
    }

    var dashboardDestination: URL? {
        self.dashboardURL.flatMap(NetdataReadOnlyFacade.dashboardURL)
    }

    func validate() throws {
        guard self.version == 1 else { throw ValidationError.unsupportedVersion }
        if self.enabled, self.host == nil { throw ValidationError.missingHost }
        if let host {
            guard host.environmentID != "local",
                  host.environmentID == host.environmentID.trimmingCharacters(in: .whitespacesAndNewlines),
                  !host.label.isEmpty, host.label.count <= 32,
                  host.label == host.label.trimmingCharacters(in: .whitespacesAndNewlines),
                  !host.label.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            else { throw ValidationError.invalidHost }
            // Reuse the transport's exact loopback and identity contract; construction never fetches.
            _ = try NetdataLoopbackClient(
                origin: host.origin,
                expectedMachineGUID: host.expectedMachineGUID,
                environmentID: host.environmentID)
        }
        if self.dashboardURL != nil, self.dashboardDestination == nil { throw ValidationError.invalidDashboard }
    }
}

/// Editing a draft has no effect on the saved configuration or collector.
struct NetdataConfigurationDraft {
    var enabled: Bool
    var environmentID: String
    var label: String
    var origin: String
    var expectedMachineGUID: String
    var dashboardURL: String

    init(configuration: NetdataConfiguration) {
        self.enabled = configuration.enabled
        self.environmentID = configuration.host?.environmentID ?? ""
        self.label = configuration.host?.label ?? ""
        self.origin = configuration.host?.origin ?? ""
        self.expectedMachineGUID = configuration.host?.expectedMachineGUID ?? ""
        self.dashboardURL = configuration.dashboardURL ?? ""
    }

    var configuration: NetdataConfiguration {
        let hasHost = !self.environmentID.isEmpty || !self.label.isEmpty ||
            !self.origin.isEmpty || !self.expectedMachineGUID.isEmpty
        return NetdataConfiguration(
            enabled: self.enabled,
            host: hasHost ? .init(
                environmentID: self.environmentID,
                label: self.label,
                origin: self.origin,
                expectedMachineGUID: self.expectedMachineGUID) : nil,
            dashboardURL: self.dashboardURL.isEmpty ? nil : self.dashboardURL)
    }
}
