import Foundation
import Testing
@testable import CodexBarCore

struct MiMoUsageScriptTests {
    @Test
    func `tracker and reader agree for stock Jones and explicit cache paths`() throws {
        let identity = JonesStateRoot.Identity(
            bundleID: "com.example.mimo-fixture",
            groupID: "FIXTURE.com.example.mimo-fixture",
            teamID: "FIXTURE",
            iCloudID: "iCloud.com.example.mimo-fixture")
        let cases: [(JonesStateRoot.Identity?, String?)] = [
            (nil, nil), (identity, nil), (nil, "custom/usage.json"), (identity, "custom/usage.json"),
        ]
        for (identity, cacheOverride) in cases {
            let usage = try self.runScript(
                files: ["session.jsonl": [self.assistantRow(outputTokens: 90)]],
                identity: identity,
                cacheOverride: cacheOverride)
            self.assertUsage(
                usage, expected: .init(input: 120, cacheCreate: 10, cacheRead: 5, output: 90, messages: 1))
        }
    }

    @Test
    func `script keeps final cumulative streaming usage`() throws {
        let rows = [
            self.assistantRow(outputTokens: 10),
            self.assistantRow(outputTokens: 40),
            self.assistantRow(outputTokens: 90),
        ]
        let allTime = try self.runScript(files: ["session.jsonl": rows])

        self.assertUsage(
            allTime,
            expected: .init(input: 120, cacheCreate: 10, cacheRead: 5, output: 90, messages: 1))
    }

    @Test
    func `script keeps final cumulative streaming usage without session id`() throws {
        let rows = [
            self.assistantRow(outputTokens: 10, sessionID: nil),
            self.assistantRow(outputTokens: 40, sessionID: nil),
            self.assistantRow(outputTokens: 90, sessionID: nil),
        ]
        let allTime = try self.runScript(files: ["session.jsonl": rows])

        self.assertUsage(
            allTime,
            expected: .init(input: 120, cacheCreate: 10, cacheRead: 5, output: 90, messages: 1))
    }

    @Test
    func `script keeps final cumulative usage without request id`() throws {
        let rows = [
            self.assistantRow(outputTokens: 10, requestID: nil),
            self.assistantRow(outputTokens: 40, requestID: nil),
            self.assistantRow(outputTokens: 90, requestID: nil),
        ]
        let allTime = try self.runScript(files: ["session.jsonl": rows])

        self.assertUsage(
            allTime,
            expected: .init(input: 120, cacheCreate: 10, cacheRead: 5, output: 90, messages: 1))
    }

    @Test
    func `script counts rows without session identity conservatively`() throws {
        let rows = [
            self.assistantRow(outputTokens: 10, sessionID: nil, requestID: nil),
            self.assistantRow(outputTokens: 40, sessionID: nil, requestID: nil),
            self.assistantRow(outputTokens: 90, sessionID: nil, requestID: nil),
        ]
        let allTime = try self.runScript(files: ["session.jsonl": rows])

        self.assertUsage(
            allTime,
            expected: .init(input: 360, cacheCreate: 30, cacheRead: 15, output: 140, messages: 3))
    }

    @Test
    func `script keeps distinct requests sharing a message id`() throws {
        let rows = [
            self.assistantRow(outputTokens: 40, requestID: "req_one"),
            self.assistantRow(outputTokens: 90, requestID: "req_two"),
        ]
        let allTime = try self.runScript(files: ["session.jsonl": rows])

        self.assertUsage(
            allTime,
            expected: .init(input: 240, cacheCreate: 20, cacheRead: 10, output: 130, messages: 2))
    }

    @Test
    func `script deduplicates copied rows from the same session`() throws {
        let rows = [self.assistantRow(outputTokens: 90)]
        let allTime = try self.runScript(files: [
            "session.jsonl": rows,
            "session-copy.jsonl": rows,
        ])

        self.assertUsage(
            allTime,
            expected: .init(input: 120, cacheCreate: 10, cacheRead: 5, output: 90, messages: 1))
    }

    @Test
    func `script deduplicates copied requests from different sessions`() throws {
        let allTime = try self.runScript(files: [
            "session-a.jsonl": [self.assistantRow(outputTokens: 90, sessionID: "session_a")],
            "session-b.jsonl": [self.assistantRow(outputTokens: 90, sessionID: "session_b")],
        ])

        self.assertUsage(
            allTime,
            expected: .init(input: 120, cacheCreate: 10, cacheRead: 5, output: 90, messages: 1))
    }

    private func runScript(
        files: [String: [[String: Any]]],
        identity: JonesStateRoot.Identity? = nil,
        cacheOverride: String? = "usage.json") throws -> [String: Any]
    {
        let root = TestFixtureScratch.root
            .appendingPathComponent("mimo-usage-script-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let mimoHome = root.appendingPathComponent("mimo")
        let projects = mimoHome
            .appendingPathComponent(".claude")
            .appendingPathComponent("projects")
            .appendingPathComponent("project-a")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)

        for (name, rows) in files {
            let session = projects.appendingPathComponent(name)
            let jsonl = try rows
                .map { try JSONSerialization.data(withJSONObject: $0) }
                .map { try #require(String(bytes: $0, encoding: .utf8)) }
                .joined(separator: "\n")
            try jsonl.write(to: session, atomically: true, encoding: .utf8)
        }

        let readerEnvironment = cacheOverride.map {
            ["MIMO_LOCAL_USAGE_PATH": root.appendingPathComponent($0).path]
        } ?? [:]
        let cache = URL(fileURLWithPath: MiMoLocalUsageFallback.cachePath(
            environment: readerEnvironment, homeDirectory: root.path, identity: identity))
        let otherCache = root.appendingPathComponent(
            identity == nil ? ".codexbar-jones/mimo-local-usage.json" : ".codexbar/mimo-local-usage.json")
        try FileManager.default.createDirectory(
            at: otherCache.deletingLastPathComponent(), withIntermediateDirectories: true)
        let sentinel = Data("{\"stock_or_other_identity\":\"unchanged\"}".utf8)
        try sentinel.write(to: otherCache)
        #expect(MiMoLocalUsageFallback.snapshot(cachePath: cache.path) == nil)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-B", self.scriptURL.path, "--update"]
        var writerEnvironment = [
            "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin",
            "HOME": root.path,
            "MIMO_CLAUDE_HOME": mimoHome.path,
            "CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS": "1",
            "CODEXBAR_TEST_CODEX_FILE_ISOLATION": "1",
            TestFixtureScratch.parentEnvironmentKey: TestFixtureScratch.root.path,
            TestFixtureScratch.workspaceEnvironmentKey: ProcessInfo.processInfo.environment[
                TestFixtureScratch.workspaceEnvironmentKey,
            ]!,
            "CODEXBAR_TEST_SESSION_FILE_ISOLATION": "1",
        ]
        // The external tracker uses its existing explicit output override for the packaged fork.
        if identity != nil || cacheOverride != nil {
            writerEnvironment["MIMO_LOCAL_USAGE_PATH"] = readerEnvironment["MIMO_LOCAL_USAGE_PATH"]
                ?? root.appendingPathComponent(".codexbar-jones/mimo-local-usage.json").path
        }
        process.environment = writerEnvironment
        let stderr = Pipe()
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let errorText = try #require(String(
            bytes: stderr.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8))
        #expect(process.terminationStatus == 0, Comment(rawValue: errorText))
        #expect(try Data(contentsOf: otherCache) == sentinel)
        let snapshot = try #require(MiMoLocalUsageFallback.snapshot(cachePath: cache.path))
        #expect(snapshot.planCode?.contains("Local") == true)
        #expect(snapshot.planCode?.contains("\(files.count) sessions") == true)

        let cacheData = try Data(contentsOf: cache)
        let cacheObject = try JSONSerialization.jsonObject(with: cacheData)
        let payload = try #require(cacheObject as? [String: Any])
        let windows = try #require(payload["windows"] as? [String: Any])
        return try #require(windows["all_time"] as? [String: Any])
    }

    private func assertUsage(_ allTime: [String: Any], expected: UsageExpectation) {
        #expect(allTime["input"] as? Int == expected.input)
        #expect(allTime["cache_create"] as? Int == expected.cacheCreate)
        #expect(allTime["cache_read"] as? Int == expected.cacheRead)
        #expect(allTime["output"] as? Int == expected.output)
        #expect(allTime["messages"] as? Int == expected.messages)
    }

    private var scriptURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Scripts/mimo-usage.py")
    }

    private func assistantRow(
        outputTokens: Int,
        sessionID: String? = "session_stream",
        requestID: String? = "req_stream") -> [String: Any]
    {
        var row: [String: Any] = [
            "type": "assistant",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "message": [
                "id": "msg_stream",
                "usage": [
                    "input_tokens": 120,
                    "cache_creation_input_tokens": 10,
                    "cache_read_input_tokens": 5,
                    "output_tokens": outputTokens,
                ],
            ],
        ]
        if let sessionID {
            row["sessionId"] = sessionID
        }
        if let requestID {
            row["requestId"] = requestID
        }
        return row
    }

    private struct UsageExpectation {
        let input: Int
        let cacheCreate: Int
        let cacheRead: Int
        let output: Int
        let messages: Int
    }
}
