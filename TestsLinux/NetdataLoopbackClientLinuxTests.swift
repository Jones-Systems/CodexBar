import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBarCore

struct NetdataLoopbackClientLinuxTests {
    private static let guid = "11111111-2222-4333-8444-555555555555"
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test
    func `fixed requests decode CPU and available memory without ambient credentials`() async throws {
        let transport = RecordingTransport()
        let client = try self.client(transport)
        let result = try await client.fetch(now: Self.now)
        #expect(result.cpuPercent == 8)
        #expect(result.memoryAvailableBytes == 512 * 1_048_576)
        #expect(result.memoryUsedBytes == nil)
        #expect(result.environmentID == "synthetic")
        #expect(result.evidence.availability == .available)
        let requests = await transport.requests
        #expect(requests.count == 2)
        for (index, request) in requests.enumerated() {
            let url = try #require(request.url)
            let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
            #expect(parts.scheme == "http")
            #expect(parts.host == "127.0.0.1")
            #expect(parts.port == 19999)
            #expect(parts.path == "/api/v3/data")
            #expect(parts.queryItems == [
                URLQueryItem(name: "contexts", value: index == 0 ? "system.cpu" : "mem.available"),
                URLQueryItem(name: "after", value: "-20"),
                URLQueryItem(name: "points", value: "1"),
                URLQueryItem(name: "format", value: "json2"),
            ])
            #expect(request.httpMethod == "GET")
            #expect(request.httpBody == nil)
            #expect(!request.httpShouldHandleCookies)
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            #expect(request.value(forHTTPHeaderField: "Cache-Control") == "no-store")
            #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        }
    }

    @Test(arguments: ["http://localhost", "http://127.0.0.1:19999", "http://[::1]:19999"])
    func `explicit loopback origins are accepted`(origin: String) throws {
        _ = try NetdataLoopbackClient(
            origin: origin, expectedMachineGUID: Self.guid, environmentID: "synthetic",
            transport: RecordingTransport())
    }

    @Test(arguments: [
        "https://localhost", "http://example.com", "http://127.0.0.2", "http://127.1", "http://2130706433",
        "http://user@localhost", "http://user:password@localhost", "http://localhost/",
        "http://localhost/api/v3/data", "http://localhost?x=1", "http://localhost#fragment",
        "http://localhost:0", "http://localhost:65536", " http://localhost", "http://local%68ost",
    ])
    func `invalid origins never issue a request`(origin: String) async {
        let transport = RecordingTransport()
        #expect(throws: NetdataLoopbackClient.ConfigurationError.invalidOrigin) {
            _ = try NetdataLoopbackClient(
                origin: origin, expectedMachineGUID: Self.guid, environmentID: "synthetic", transport: transport)
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test
    func `invalid identities and nonfinite time never issue a request`() async throws {
        let transport = RecordingTransport()
        for (guid, environment) in [("invalid", "synthetic"), (Self.guid, ""), (Self.guid, "bad\nidentity")] {
            #expect(throws: NetdataReadOnlyFacade.DecodeError.invalidIdentity) {
                _ = try NetdataLoopbackClient(
                    origin: "http://localhost", expectedMachineGUID: guid,
                    environmentID: environment, transport: transport)
            }
        }
        let client = try self.client(transport)
        await #expect(throws: NetdataReadOnlyFacade.DecodeError.invalidIdentity) {
            try await client.fetch(now: Date(timeIntervalSince1970: .nan))
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test(arguments: Failure.allCases)
    func `one failed endpoint preserves the valid companion metric`(failure: Failure) async throws {
        for failedContext in ["system.cpu", "mem.available"] {
            let transport = RecordingTransport(failure: failure, failedContext: failedContext)
            let result = try await self.client(transport).fetch(now: Self.now)
            #expect(result.evidence.availability == .partial)
            #expect(result.cpuPercent == (failedContext == "system.cpu" ? nil : 8))
            #expect(result.memoryAvailableBytes == (failedContext == "mem.available" ? nil : 512 * 1_048_576))
            #expect(await transport.requests.count == 2)
        }
    }

    @Test
    func `both failed endpoints are unavailable`() async throws {
        let transport = RecordingTransport(failure: .status, failedContext: nil)
        let result = try await self.client(transport).fetch(now: Self.now)
        #expect(result.evidence.availability == .unavailable)
        #expect(result.cpuPercent == nil)
        #expect(result.memoryAvailableBytes == nil)
    }

    @Test(arguments: [false, true])
    func `transport cancellation stops before the companion request`(urlError: Bool) async throws {
        let transport = RecordingTransport(cancel: true, urlError: urlError)
        let client = try self.client(transport)
        await #expect(throws: CancellationError.self) { try await client.fetch(now: Self.now) }
        #expect(await transport.requests.count == 1)
    }

    @Test
    func `already cancelled task sends no requests`() async throws {
        let transport = RecordingTransport()
        let client = try self.client(transport)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.fetch(now: Self.now)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await transport.requests.isEmpty)
    }

    @Test
    func `production redirect guard rejects same origin and external HTTP redirects`() throws {
        let original = try #require(URL(string: "http://localhost:19999/api/v3/data"))
        for target in ["http://localhost:19999/other", "https://example.com/data", "http://127.0.0.1:19999/data"] {
            let request = URLRequest(url: try #require(URL(string: target)))
            #expect(ProviderHTTPRedirectGuardDelegate.guardedRedirectRequest(
                originalURL: original, redirectRequest: request) == nil)
        }
    }

    private func client(_ transport: RecordingTransport) throws -> NetdataLoopbackClient {
        try NetdataLoopbackClient(
            origin: "http://127.0.0.1:19999", expectedMachineGUID: Self.guid,
            environmentID: "synthetic", transport: transport)
    }

    enum Failure: CaseIterable, Sendable {
        case transport, status, redirect, redirectedResponse, nonHTTP, oversized, malformed, wrongNode, wrongContext
    }

    private actor RecordingTransport: ProviderHTTPTransport {
        var requests: [URLRequest] = []
        let failure: Failure?
        let failedContext: String?
        let cancel: Bool
        let urlError: Bool

        init(
            failure: Failure? = nil,
            failedContext: String? = "system.cpu",
            cancel: Bool = false,
            urlError: Bool = false)
        {
            self.failure = failure
            self.failedContext = failedContext
            self.cancel = cancel
            self.urlError = urlError
        }

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            self.requests.append(request)
            if self.cancel {
                if self.urlError { throw URLError(.cancelled) }
                throw CancellationError()
            }
            let url = try #require(request.url)
            let context = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "contexts" })?.value ?? ""
            let failure = self.failedContext == nil || self.failedContext == context ? self.failure : nil
            if failure == .transport { throw URLError(.timedOut) }
            let responseURL = failure == .redirectedResponse ? URL(string: "http://example.com/data")! : url
            let status = failure == .status ? 503 : failure == .redirect ? 302 : 200
            let response = try #require(HTTPURLResponse(
                url: responseURL, statusCode: status, httpVersion: nil, headerFields: nil))
            if failure == .nonHTTP {
                return (Data(), URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil))
            }
            if failure == .oversized {
                return (Data(repeating: 32, count: NetdataReadOnlyFacade.maximumPayloadBytes + 1), response)
            }
            if failure == .malformed { return (Data("{}".utf8), response) }
            let dimensions = context == "system.cpu"
                ? ["guest_nice", "guest", "steal", "softirq", "irq", "user", "system", "nice", "iowait"]
                : ["avail"]
            let unit = context == "system.cpu" ? "percentage" : "MiB"
            let guid = failure == .wrongNode ? "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee" : NetdataLoopbackClientLinuxTests.guid
            let body: [String: Any] = [
                "api": 3,
                "summary": ["nodes": [["mg": guid]], "contexts": [["id": failure == .wrongContext ? "other" : context]]],
                "view": ["dimensions": ["ids": dimensions, "units": Array(repeating: unit, count: dimensions.count)]],
                "result": [
                    "labels": ["time"] + dimensions,
                    "point": ["value": 0, "arp": 1, "pa": 2],
                    "data": [[NetdataLoopbackClientLinuxTests.now.timeIntervalSince1970] as [Any]
                        + dimensions.map { _ in [context == "system.cpu" ? 1 : 512, 0, 0] }],
                ],
            ]
            return (try JSONSerialization.data(withJSONObject: body), response)
        }
    }
}
