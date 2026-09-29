import Foundation

public struct HubHostObservation: Sendable, Equatable, Identifiable {
    public let environmentID: String
    public let evidence: HubEvidence
    public let cpuPercent: Double?
    public let memoryUsedBytes: UInt64?
    public let memoryAvailableBytes: UInt64?

    public var id: String {
        self.environmentID
    }
}

/// Decodes supplied Netdata v3 json2 data only; no network collector is activated.
public enum NetdataReadOnlyFacade {
    public static func unavailable(environmentID: String) -> HubHostObservation {
        HubHostObservation(
            environmentID: environmentID,
            evidence: HubEvidence(
                source: "Netdata collector not configured", observedAt: nil, availability: .unsupported),
            cpuPercent: nil,
            memoryUsedBytes: nil,
            memoryAvailableBytes: nil)
    }

    public static let maximumPayloadBytes = 65536

    public enum DecodeError: Error, Equatable {
        case invalidIdentity
        case oversizedPayload
        case malformedPayload
        case unexpectedContract
        case wrongNode
        case invalidValue
    }

    /// Inputs are request-bound to system.cpu and mem.available respectively, in json2 format.
    /// Available memory is not used memory. The oldest timestamp governs age; any future sample is stale.
    public static func decode(
        cpuData: Data? = nil,
        availableMemoryData: Data? = nil,
        expectedMachineGUID: String,
        environmentID: String,
        now: Date) throws -> HubHostObservation
    {
        guard let machineGUID = UUID(uuidString: expectedMachineGUID),
              !environmentID.isEmpty, environmentID.utf8.count <= 128,
              !environmentID.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              now.timeIntervalSince1970.isFinite
        else { throw DecodeError.invalidIdentity }
        let cpu = try cpuData.map { try self.sample($0, metric: .cpu, machineGUID: machineGUID) }
        let memory = try availableMemoryData.map { try self.sample($0, metric: .memory, machineGUID: machineGUID) }
        let timestamps = [cpu?.observedAt, memory?.observedAt].compactMap(\.self)
        let observedAt = timestamps.min()
        let futureSample = timestamps.contains { $0.timeIntervalSince(now) > 5 }
        let memoryBytes = memory?.value.map { UInt64($0 * 1_048_576) }
        return HubHostObservation(
            environmentID: environmentID,
            evidence: self.evidence(
                source: "Supplied Netdata v3 json2 data",
                observedAt: observedAt,
                failed: futureSample,
                partial: cpu?.value == nil || memoryBytes == nil,
                now: now),
            cpuPercent: cpu?.value,
            memoryUsedBytes: nil,
            memoryAvailableBytes: memoryBytes)
    }

    static func evidence(
        source: String,
        observedAt: Date?,
        failed: Bool,
        partial: Bool,
        now: Date) -> HubEvidence
    {
        guard let observedAt else {
            return HubEvidence(source: source, observedAt: nil, availability: .unavailable)
        }
        let age = now.timeIntervalSince(observedAt)
        let stale = failed || !age.isFinite || age < -5 || age > 30
        return HubEvidence(
            source: source, observedAt: observedAt, availability: stale ? .stale : partial ? .partial : .available)
    }

    private enum Metric {
        case cpu
        case memory

        var dimensions: [String] {
            switch self {
            case .cpu: ["guest_nice", "guest", "steal", "softirq", "irq", "user", "system", "nice", "iowait"]
            case .memory: ["avail"]
            }
        }

        var unit: String {
            self == .cpu ? "percentage" : "MiB"
        }

        var context: String {
            self == .cpu ? "system.cpu" : "mem.available"
        }
    }

    private struct Sample {
        let observedAt: Date?
        let value: Double?
    }

    private struct Response: Decodable {
        let api: Int
        let summary: Summary
        let view: View
        let result: Result

        struct Summary: Decodable {
            let nodes: [Node]
            let contexts: [Context]

            struct Context: Decodable {
                let id: String
            }

            struct Node: Decodable {
                let mg: String
            }
        }

        struct View: Decodable {
            let dimensions: Dimensions

            struct Dimensions: Decodable {
                let ids: [String]
                let units: [String]
            }
        }

        struct Result: Decodable {
            let labels: [String]
            let data: [[Cell]]
            let point: Point

            struct Point: Decodable {
                let value: Int
                let arp: Int
                let pa: Int
            }
        }
    }

    private enum Cell: Decodable {
        case timestamp(Double)
        case point([Double?])

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let timestamp = try? container.decode(Double.self) {
                self = .timestamp(timestamp)
            } else {
                self = try .point(container.decode([Double?].self))
            }
        }
    }

    private static func sample(_ data: Data, metric: Metric, machineGUID: UUID) throws -> Sample {
        guard data.count <= self.maximumPayloadBytes else { throw DecodeError.oversizedPayload }
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw DecodeError.malformedPayload
        }
        guard response.summary.nodes.count == 1,
              UUID(uuidString: response.summary.nodes[0].mg) == machineGUID
        else { throw DecodeError.wrongNode }
        let dimensions = metric.dimensions
        guard response.api == 3,
              response.summary.contexts.count == 1,
              response.summary.contexts[0].id == metric.context,
              response.result.point.value == 0, response.result.point.arp == 1, response.result.point.pa == 2,
              response.view.dimensions.ids == dimensions,
              response.view.dimensions.units == Array(repeating: metric.unit, count: dimensions.count),
              response.result.labels == ["time"] + dimensions,
              response.result.data.count <= 1
        else { throw DecodeError.unexpectedContract }
        guard let row = response.result.data.first else { return Sample(observedAt: nil, value: nil) }
        guard row.count == dimensions.count + 1 else { throw DecodeError.unexpectedContract }
        guard case let .timestamp(timestamp) = row[0],
              timestamp.isFinite, timestamp > 0, timestamp <= 253_402_300_799,
              timestamp.rounded(.towardZero) == timestamp
        else { throw DecodeError.invalidValue }
        var values: [Double?] = []
        for cell in row.dropFirst() {
            guard case let .point(point) = cell, point.count == 3 else { throw DecodeError.unexpectedContract }
            guard point.compactMap(\.self).allSatisfy(\.isFinite) else { throw DecodeError.invalidValue }
            if let value = point[0] {
                guard value >= 0 else { throw DecodeError.invalidValue }
                if metric == .cpu {
                    guard value <= 100 else { throw DecodeError.invalidValue }
                } else {
                    guard value * 1_048_576 < Double(UInt64.max) else { throw DecodeError.invalidValue }
                }
            }
            values.append(point[0])
        }
        let value: Double?
        if values.contains(where: { $0 == nil }) {
            value = nil
        } else if metric == .cpu {
            let busy = values.dropLast().compactMap(\.self).reduce(0, +)
            guard busy.isFinite, busy <= 100 else { throw DecodeError.invalidValue }
            value = busy
        } else {
            value = values[0]
        }
        return Sample(observedAt: Date(timeIntervalSince1970: timestamp), value: value)
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
