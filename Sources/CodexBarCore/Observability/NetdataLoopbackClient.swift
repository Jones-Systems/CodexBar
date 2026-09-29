import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct NetdataLoopbackClient: Sendable {
    public enum ConfigurationError: Error, Equatable {
        case invalidOrigin
    }

    private let origin: URL
    private let expectedMachineGUID: String
    private let environmentID: String
    private let transport: any ProviderHTTPTransport

    /// Injected transports must disable redirects, credentials, cookies, and caching as the default transport does.
    public init(
        origin: String,
        expectedMachineGUID: String,
        environmentID: String,
        transport: (any ProviderHTTPTransport)? = nil) throws
    {
        guard origin.utf8.count <= 2048,
              origin == origin.trimmingCharacters(in: .whitespacesAndNewlines),
              !origin.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let components = URLComponents(string: origin),
              components.scheme?.lowercased() == "http",
              let host = components.percentEncodedHost?.lowercased(),
              ["127.0.0.1", "localhost", "[::1]", "::1"].contains(host),
              components.user == nil, components.password == nil,
              components.path.isEmpty,
              components.query == nil, components.fragment == nil,
              components.port == nil || (1...65535).contains(components.port ?? 0),
              let url = components.url
        else { throw ConfigurationError.invalidOrigin }
        _ = try NetdataReadOnlyFacade.decode(
            expectedMachineGUID: expectedMachineGUID,
            environmentID: environmentID,
            now: Date(timeIntervalSince1970: 0))
        self.origin = url
        self.expectedMachineGUID = expectedMachineGUID
        self.environmentID = environmentID
        self.transport = transport ?? Self.makeTransport()
    }

    /// Failed endpoints contribute no metric; cancellation aborts the observation.
    public func fetch(now: Date = Date()) async throws -> HubHostObservation {
        try Task.checkCancellation()
        _ = try self.decode(now: now)
        let cpu = try await self.read(context: "system.cpu", now: now)
        let memory = try await self.read(context: "mem.available", now: now)
        try Task.checkCancellation()
        return try self.decode(cpu: cpu, memory: memory, now: now)
    }

    private func decode(cpu: Data? = nil, memory: Data? = nil, now: Date) throws -> HubHostObservation {
        try NetdataReadOnlyFacade.decode(
            cpuData: cpu,
            availableMemoryData: memory,
            expectedMachineGUID: self.expectedMachineGUID,
            environmentID: self.environmentID,
            now: now)
    }

    private func read(context: String, now: Date) async throws -> Data? {
        try Task.checkCancellation()
        var components = URLComponents(url: self.origin, resolvingAgainstBaseURL: false)!
        components.path = "/api/v3/data"
        components.queryItems = [
            URLQueryItem(name: "contexts", value: context),
            URLQueryItem(name: "after", value: "-20"),
            URLQueryItem(name: "points", value: "1"),
            URLQueryItem(name: "format", value: "json2"),
        ]
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        do {
            let (data, response) = try await self.transport.data(for: request)
            try Task.checkCancellation()
            // The transport buffers the response; this bounds decoding, not in-flight allocation.
            guard data.count <= NetdataReadOnlyFacade.maximumPayloadBytes,
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  http.url == request.url
            else { return nil }
            if context == "system.cpu" {
                _ = try self.decode(cpu: data, now: now)
            } else {
                _ = try self.decode(memory: data, now: now)
            }
            return data
        } catch {
            try Task.checkCancellation()
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            return nil
        }
    }

    private static func makeTransport() -> ProviderHTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        // This shared guard refuses every redirect originating from HTTP, including same-origin redirects.
        return ProviderHTTPClient(session: ProviderHTTPClient.redirectGuardedSession(configuration: configuration))
    }
}
