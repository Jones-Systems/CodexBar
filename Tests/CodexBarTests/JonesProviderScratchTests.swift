import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

struct JonesProviderScratchTests {
    @Test
    func `fork scratch has an owned parent while stock keeps its exact temporary root`() {
        let temporary = URL(fileURLWithPath: "/synthetic/tmp")
        #expect(JonesProviderScratchRoot.directory(temporaryDirectory: temporary, identity: nil) == temporary)
        #expect(JonesProviderScratchRoot.directory(
            temporaryDirectory: temporary, identity: ScratchFixture.identity).path
            == "/synthetic/tmp/CodexBar Jones/provider-scratch")
    }
}

struct GeminiLoginScratchTests {
    @Test(arguments: ["create", "write", "permissions", "launch"])
    func `script failures remove partial files without scheduling retention`(failure: String) async {
        let files = ScratchFixture(failure: failure)
        var scheduled = false
        let result = await GeminiLoginRunner.launchScript(
            "synthetic script", fileManager: files, forkIdentity: ScratchFixture.identity,
            write: { content, url in try files.write(Data(content.utf8), to: url) },
            open: { _ in try files.failIfNeeded("launch") },
            scheduleCleanup: { _, _ in scheduled = true })
        guard case .launchFailed = result.outcome else {
            Issue.record("Expected script failure")
            return
        }
        #expect(files.filePaths.isEmpty)
        #expect(files.removed.count == 1)
        #expect(!scheduled)
    }

    @Test(arguments: [false, true])
    func `success keeps stock paths or fork parent and releases only its script at ten seconds`(overlay: Bool) async {
        let files = ScratchFixture()
        var cleanup: (@Sendable () -> Void)?
        var delay: TimeInterval?
        var opened: URL?
        let result = await GeminiLoginRunner.launchScript(
            "synthetic script", fileManager: files, forkIdentity: overlay ? ScratchFixture.identity : nil,
            write: { content, url in try files.write(Data(content.utf8), to: url) },
            open: { opened = $0 },
            scheduleCleanup: { delay = $0; cleanup = $1 })
        defer { cleanup?() }
        guard case .success = result.outcome, let opened else {
            Issue.record("Expected simulated Terminal success")
            return
        }
        let expectedRoot = JonesProviderScratchRoot.directory(
            temporaryDirectory: files.temporaryDirectory, identity: overlay ? ScratchFixture.identity : nil)
        #expect(opened.deletingLastPathComponent() == expectedRoot)
        #expect(opened.lastPathComponent.hasPrefix("gemini_login_"))
        #expect(opened.pathExtension == "command")
        #expect(files.filePaths == [opened.path])
        #expect(files.removed.isEmpty)
        #expect(delay == 10)
        #expect(cleanup != nil)
        let sentinel = expectedRoot.appendingPathComponent("another-invocation.command")
        files.seed(Data(), at: sentinel)
        cleanup?()
        cleanup = nil
        #expect(files.filePaths == [sentinel.path])
        #expect(files.removed == [opened.path])
    }

    @Test
    func `cancellation after launch removes the script immediately`() async {
        let files = ScratchFixture()
        let task = Task {
            await GeminiLoginRunner.launchScript(
                "synthetic script", fileManager: files, forkIdentity: ScratchFixture.identity,
                write: { content, url in try files.write(Data(content.utf8), to: url) },
                open: { _ in
                    #expect(!files.filePaths.isEmpty)
                    withUnsafeCurrentTask { $0?.cancel() }
                    #expect(files.filePaths.isEmpty)
                },
                scheduleCleanup: { _, _ in Issue.record("Cancelled script must not be retained") })
        }
        let result = await task.value
        guard case .launchFailed = result.outcome else {
            Issue.record("Expected cancellation failure")
            return
        }
        #expect(files.filePaths.isEmpty)
        #expect(!files.removed.isEmpty)
        #expect(Set(files.removed).count == 1)
    }

    @Test
    func `cancellation during cleanup scheduling removes immediately and keeps delayed cleanup scoped`() async {
        let files = ScratchFixture()
        let sentinel = files.temporaryDirectory.appendingPathComponent("another-invocation.command")
        files.seed(Data(), at: sentinel)
        let task = Task {
            var cleanup: (@Sendable () -> Void)?
            var opened: URL?
            _ = await GeminiLoginRunner.launchScript(
                "synthetic script", fileManager: files, forkIdentity: ScratchFixture.identity,
                write: { content, url in try files.write(Data(content.utf8), to: url) },
                open: { opened = $0 },
                scheduleCleanup: { delay, callback in
                    #expect(delay == 10)
                    cleanup = callback
                    withUnsafeCurrentTask { $0?.cancel() }
                })
            #expect(files.filePaths == [sentinel.path])
            #expect(cleanup != nil)
            cleanup?()
            #expect(files.filePaths == [sentinel.path])
            #expect(opened != nil)
            #expect(Set(files.removed) == Set(opened.map { [$0.path] } ?? []))
        }
        await task.value
    }

    @Test
    func `sendable delayed cleanup preserves another pending login script`() async throws {
        let files = ScratchFixture()
        var cleanups: [@Sendable () -> Void] = []
        var opened: [URL] = []
        for _ in 0..<2 {
            let result = await GeminiLoginRunner.launchScript(
                "synthetic script", fileManager: files, forkIdentity: ScratchFixture.identity,
                write: { content, url in try files.write(Data(content.utf8), to: url) },
                open: { opened.append($0) },
                scheduleCleanup: { delay, callback in
                    #expect(delay == 10)
                    cleanups.append(callback)
                })
            guard case .success = result.outcome else {
                Issue.record("Expected simulated Terminal success")
                return
            }
        }
        defer { cleanups.forEach { $0() } }
        try #require(opened.count == 2 && cleanups.count == 2)
        #expect(opened[0] != opened[1])
        let firstCleanup = cleanups[0]
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<2 {
                group.addTask { firstCleanup() }
            }
        }
        #expect(files.filePaths == [opened[1].path])
        #expect(Set(files.removed) == [opened[0].path])
        cleanups[1]()
        #expect(files.filePaths.isEmpty)
    }

    @Test
    func `already cancelled login creates no script and never opens Terminal`() async {
        let files = ScratchFixture()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await GeminiLoginRunner.launchScript(
                "synthetic script", fileManager: files, forkIdentity: ScratchFixture.identity,
                write: { _, _ in Issue.record("Cancelled login must not write") },
                open: { _ in Issue.record("Cancelled login must not launch") },
                scheduleCleanup: { _, _ in Issue.record("Cancelled login must not retain") })
        }
        let result = await task.value
        guard case .launchFailed = result.outcome else {
            Issue.record("Expected cancellation failure")
            return
        }
        #expect(files.filePaths.isEmpty)
    }
}

struct AliyunCookieScratchTests {
    @Test(arguments: ["copy", "read", "cancel", ""])
    func `database scratch is cleaned after copy failure read failure cancellation and success`(failure: String) throws {
        let files = ScratchFixture(failure: failure)
        let source = files.root.appendingPathComponent("browser/Cookies")
        for suffix in ["", "-wal", "-shm"] {
            files.seed(Data("synthetic".utf8), at: URL(fileURLWithPath: source.path + suffix))
        }
        let original = files.filePaths
        var didRead = false
        do {
            try AliyunOneConsoleChromiumCookieFallbackImporter.withCopiedCookieDatabase(
                sourceDB: source, fileManager: files, forkIdentity: ScratchFixture.identity)
            { copied in
                didRead = true
                #expect(copied.path.contains("/CodexBar Jones/provider-scratch/"))
                for suffix in ["", "-wal", "-shm"] {
                    #expect(files.filePaths.contains(copied.path + suffix))
                }
                if failure == "cancel" { throw CancellationError() }
                try files.failIfNeeded("read")
            }
            #expect(failure.isEmpty)
        } catch {
            #expect(!failure.isEmpty)
        }
        #expect(didRead == (failure != "copy"))
        #expect(files.filePaths == original)
        #expect(files.removed.count == 1)
    }

    @Test(arguments: ["-wal", "-shm"])
    func `partial sidecar copy is contained and stock paths stay unchanged`(suffix: String) throws {
        let files = ScratchFixture(failure: "copy" + suffix)
        let source = files.root.appendingPathComponent("browser/Cookies")
        for suffix in ["", "-wal", "-shm"] {
            files.seed(Data(), at: URL(fileURLWithPath: source.path + suffix))
        }
        let original = files.filePaths
        try AliyunOneConsoleChromiumCookieFallbackImporter.withCopiedCookieDatabase(
            sourceDB: source, fileManager: files, forkIdentity: nil)
        { copied in
            #expect(copied.deletingLastPathComponent().deletingLastPathComponent() == files.temporaryDirectory)
            #expect(copied.deletingLastPathComponent().lastPathComponent
                .hasPrefix("aliyun-oneconsole-chromium-cookies-"))
        }
        #expect(files.filePaths == original)
        #expect(files.removed.count == 1)
    }
}

struct GeminiCurlScratchTests {
    @Test(arguments: ["write", "permissions", "process", "parse", "cancel", ""])
    func `curl scratch is removed on every completion path`(failure: String) async throws {
        let files = ScratchFixture(failure: failure)
        var request = try URLRequest(url: #require(URL(string: "https://example.invalid/synthetic")))
        request.httpBody = Data("synthetic body".utf8)
        do {
            let (data, response) = try await Task {
                try await GeminiStatusProbe.curlDataLoader(
                    for: request, fileManager: files, forkIdentity: ScratchFixture.identity,
                    write: { try files.write($0, to: $1) },
                    run: { config, timeout in
                        #expect(config.path.contains("/CodexBar Jones/provider-scratch/"))
                        #expect(config.lastPathComponent == "curl.conf")
                        #expect(timeout == max(5, request.timeoutInterval + 2))
                        let body = config.deletingLastPathComponent().appendingPathComponent("body")
                        #expect(files.filePaths.contains(body.path))
                        try files.failIfNeeded("process")
                        if failure == "cancel" { withUnsafeCurrentTask { $0?.cancel() } }
                        return failure == "parse" ? "invalid" : "{}__CODEXBAR_HTTP_STATUS__:200"
                    })
            }.value
            #expect(failure.isEmpty)
            #expect(data == Data("{}".utf8))
            #expect((response as? HTTPURLResponse)?.statusCode == 200)
        } catch {
            #expect(!failure.isEmpty)
        }
        #expect(files.filePaths.isEmpty)
        #expect(files.removed.count == 1)
    }

    @Test
    func `stock curl retains its directory name and config format`() async throws {
        let files = ScratchFixture()
        let request = try URLRequest(url: #require(URL(string: "https://example.invalid/synthetic")))
        _ = try await GeminiStatusProbe.curlDataLoader(
            for: request, fileManager: files, forkIdentity: nil,
            write: { data, url in
                let config = String(decoding: data, as: UTF8.self)
                #expect(config.contains("url = \"https://example.invalid/synthetic\""))
                #expect(config.contains("write-out = \"__CODEXBAR_HTTP_STATUS__:%{http_code}\""))
                try files.write(data, to: url)
            },
            run: { config, _ in
                let directory = config.deletingLastPathComponent()
                #expect(directory.deletingLastPathComponent() == files.temporaryDirectory)
                #expect(directory.lastPathComponent.hasPrefix("codexbar-gemini-curl-"))
                return "{}__CODEXBAR_HTTP_STATUS__:200"
            })
        #expect(files.filePaths.isEmpty)
        #expect(files.removed.count == 1)
    }
}

/// All operations are in memory, including partial failures; no browser, auth, or home files are read.
private final class ScratchFixture: FileManager, @unchecked Sendable {
    static let identity = JonesStateRoot.Identity(
        bundleID: "com.example.scratch", groupID: "FIXTURE.com.example.scratch",
        teamID: "FIXTURE", iCloudID: "iCloud.com.example.scratch")

    enum FixtureError: Error { case injected }

    let root = URL(fileURLWithPath: "/synthetic/provider-scratch-\(UUID().uuidString)")
    private let lock = NSLock()
    private let failure: String
    private var contents: [String: Data] = [:]
    private var removals: [String] = []

    init(failure: String = "") {
        self.failure = failure
        super.init()
    }

    override var temporaryDirectory: URL {
        self.root.appendingPathComponent("tmp", isDirectory: true)
    }

    var filePaths: Set<String> {
        self.lock.withLock { Set(self.contents.keys) }
    }

    var removed: [String] {
        self.lock.withLock { self.removals }
    }

    func failIfNeeded(_ operation: String) throws {
        if self.failure == operation { throw FixtureError.injected }
    }

    func seed(_ data: Data, at url: URL) {
        #expect(url.path.hasPrefix(self.root.path + "/"))
        self.lock.withLock { self.contents[url.path] = data }
    }

    func write(_ data: Data, to url: URL) throws {
        self.seed(data, at: url)
        try self.failIfNeeded("write")
    }

    override func createDirectory(
        at url: URL, withIntermediateDirectories _: Bool, attributes _: [FileAttributeKey: Any]? = nil) throws
    {
        #expect(url.path.hasPrefix(self.temporaryDirectory.path + "/"))
        try self.failIfNeeded("create")
    }

    override func setAttributes(_ attributes: [FileAttributeKey: Any], ofItemAtPath path: String) throws {
        #expect(self.filePaths.contains(path))
        #expect(attributes[.posixPermissions] != nil)
        try self.failIfNeeded("permissions")
    }

    override func fileExists(atPath path: String) -> Bool {
        #expect(path.hasPrefix(self.root.path + "/"))
        return self.filePaths.contains(path)
    }

    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        #expect(srcURL.path.hasPrefix(self.root.path + "/"))
        let data = try self.lock.withLock {
            guard let data = self.contents[srcURL.path] else { throw FixtureError.injected }
            return data
        }
        self.seed(data, at: dstURL)
        try self.failIfNeeded("copy")
        for suffix in ["-wal", "-shm"] where srcURL.path.hasSuffix(suffix) {
            try self.failIfNeeded("copy" + suffix)
        }
    }

    override func removeItem(at url: URL) throws {
        #expect(url.path.hasPrefix(self.temporaryDirectory.path + "/"))
        self.lock.withLock {
            self.removals.append(url.path)
            self.contents = self.contents.filter { $0.key != url.path && !$0.key.hasPrefix(url.path + "/") }
        }
    }
}
