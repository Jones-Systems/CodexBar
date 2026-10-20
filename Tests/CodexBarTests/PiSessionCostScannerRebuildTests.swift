import Foundation
import Testing
@testable import CodexBarCore

private final class PiRebuildWorkCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        self.lock.withLock { self.count }
    }

    func increment() {
        self.lock.withLock { self.count += 1 }
    }
}

struct PiSessionCostScannerRebuildTests {
    @Test
    func `unchanged refresh preserves totals and advances freshness without rebuilding`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 7, day: 10)
        _ = try self.writeSession(env, name: "a", day: day, tokens: 10)
        let options = self.options(env)
        let original = try self.scan(day, options: options)
        let before = PiSessionCostCacheIO.load(cacheRoot: env.cacheRoot)
        let refreshed = try self.observing(rebuilds: 0, parses: 0) {
            try self.scan(day, now: day.addingTimeInterval(1), options: options)
        }
        let after = PiSessionCostCacheIO.load(cacheRoot: env.cacheRoot)
        #expect(refreshed.data == original.data)
        #expect(refreshed.summary?.totalTokens == original.summary?.totalTokens)
        #expect(refreshed.summary?.totalCostUSD == original.summary?.totalCostUSD)
        #expect(after.daysByProvider == before.daysByProvider)
        #expect(after.lastScanUnixMs == before.lastScanUnixMs + 1000)
        #expect(after.scanSinceKey == before.scanSinceKey)
        #expect(after.scanUntilKey == before.scanUntilKey)
        #expect(after.pricingKey == before.pricingKey)
    }

    @Test
    func `every changed file is scanned before one rebuild and deletion removes totals`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 7, day: 10)
        let a = try self.writeSession(env, name: "a", day: day, tokens: 10)
        let b = try self.writeSession(env, name: "b", day: day, tokens: 20)
        let options = self.options(env)
        #expect(try self.scan(day, options: options).summary?.totalTokens == 30)
        for url in [a, b] {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(env.jsonl([self.entry(env, day: day, id: "append", tokens: 5)]).utf8))
        }
        let appended = try self.observing(rebuilds: 1, parses: 2) { try self.scan(day, options: options) }
        #expect(appended.summary?.totalTokens == 40)
        try FileManager.default.removeItem(at: a)
        let deleted = try self.observing(rebuilds: 1, parses: 0) { try self.scan(day, options: options) }
        #expect(deleted.summary?.totalTokens == 25)
        try FileManager.default.removeItem(at: b)
        let empty = try self.observing(rebuilds: 1, parses: 0) { try self.scan(day, options: options) }
        #expect(empty.data.isEmpty)
    }

    @Test
    func `root precedence and duplicate survivor changes rebuild without parsing`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 7, day: 10)
        let first = try self.writeSession(env, name: "a", day: day, tokens: 10, session: "shared")
        let second = try self.writeSession(env, name: "b", day: day, tokens: 20, session: "shared")
        let omp = env.root.appendingPathComponent("omp", isDirectory: true)
        try FileManager.default.createDirectory(at: omp, withIntermediateDirectories: true)
        let moved = omp.appendingPathComponent(second.lastPathComponent)
        try FileManager.default.moveItem(at: second, to: moved)
        var options = self.options(env)
        options.ompSessionsRoot = omp
        #expect(try self.scan(day, options: options).summary?.totalTokens == 10)
        options.piSessionsRoot = omp
        options.ompSessionsRoot = env.piSessionsRoot
        let reversed = try self.observing(rebuilds: 1, parses: 0) { try self.scan(day, options: options) }
        #expect(reversed.summary?.totalTokens == 20)
        let unchanged = try self.observing(rebuilds: 0, parses: 0) { try self.scan(day, options: options) }
        #expect(unchanged.data == reversed.data)
        try FileManager.default.removeItem(at: moved)
        let survivor = try self.observing(rebuilds: 1, parses: 0) { try self.scan(day, options: options) }
        #expect(survivor.summary?.totalTokens == 10)
        #expect(PiSessionCostCacheIO.load(cacheRoot: env.cacheRoot).files[first.path] != nil)
    }

    @Test
    func `cache without root binding rebuilds once then reuses persisted days`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 7, day: 10)
        _ = try self.writeSession(env, name: "a", day: day, tokens: 10)
        let options = self.options(env)
        let original = try self.scan(day, options: options)
        let url = PiSessionCostCacheIO.cacheFileURL(cacheRoot: env.cacheRoot)
        var legacy = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        legacy.removeValue(forKey: "sessionRootPaths")
        try JSONSerialization.data(withJSONObject: legacy).write(to: url, options: .atomic)
        let adopted = try self.observing(rebuilds: 1, parses: 0) { try self.scan(day, options: options) }
        #expect(adopted.data == original.data)
        let unchanged = try self.observing(rebuilds: 0, parses: 0) { try self.scan(day, options: options) }
        #expect(unchanged.data == original.data)
    }

    @Test(arguments: ["force", "pricing", "timezone", "window"])
    func `invalidated aggregates rebuild from unchanged files`(invalidation: String) throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 7, day: 10)
        _ = try self.writeSession(env, name: "a", day: day, tokens: 10)
        var options = self.options(env)
        let original = try self.scan(day, options: options)
        var since = day
        switch invalidation {
        case "force":
            options.forceRescan = true
        case "pricing":
            var cache = PiSessionCostCacheIO.load(cacheRoot: env.cacheRoot)
            cache.pricingKey = "stale-pricing"
            PiSessionCostCacheIO.save(cache: cache, cacheRoot: env.cacheRoot, calendar: options.calendar)
        case "timezone":
            let identifier = options.calendar.timeZone.identifier == "GMT" ? "America/New_York" : "GMT"
            options.calendar.timeZone = try #require(TimeZone(identifier: identifier))
        case "window":
            since = day.addingTimeInterval(-7 * 86400)
        default:
            Issue.record("Unexpected invalidation")
        }
        let refreshed = try self.observing(rebuilds: 1, parses: 1) {
            try PiSessionCostScanner.loadDailyReportCancellable(
                provider: .codex,
                since: since,
                until: day,
                now: day.addingTimeInterval(1),
                options: options,
                checkCancellation: nil)
        }
        #expect(refreshed.summary?.totalTokens == original.summary?.totalTokens)
        #expect(refreshed.summary?.totalCostUSD == original.summary?.totalCostUSD)
    }

    private func options(_ env: CostUsageTestEnvironment) -> PiSessionCostScanner.Options {
        PiSessionCostScanner.Options(
            piSessionsRoot: env.piSessionsRoot,
            ompSessionsRoot: env.root.appendingPathComponent("empty-omp"),
            cacheRoot: env.cacheRoot,
            refreshMinIntervalSeconds: 0)
    }

    private func scan(
        _ day: Date,
        now: Date? = nil,
        options: PiSessionCostScanner.Options) throws -> CostUsageDailyReport
    {
        try PiSessionCostScanner.loadDailyReportCancellable(
            provider: .codex,
            since: day,
            until: day,
            now: now ?? day,
            options: options,
            checkCancellation: nil)
    }

    private func observing(
        rebuilds: Int,
        parses: Int,
        body: () throws -> CostUsageDailyReport) rethrows -> CostUsageDailyReport
    {
        let rebuildCounter = PiRebuildWorkCounter()
        let parseCounter = PiRebuildWorkCounter()
        let rebuildObserver: @Sendable () -> Void = { rebuildCounter.increment() }
        let parseObserver: @Sendable () -> Void = { parseCounter.increment() }
        let result = try PiSessionCostScanner.$dailyUsageRebuildObserverForTesting.withValue(rebuildObserver) {
            try PiSessionCostScanner.$sessionParseObserverForTesting.withValue(parseObserver, operation: body)
        }
        #expect(rebuildCounter.value == rebuilds)
        #expect(parseCounter.value == parses)
        return result
    }

    private func writeSession(
        _ env: CostUsageTestEnvironment,
        name: String,
        day: Date,
        tokens: Int,
        session: String? = nil) throws -> URL
    {
        try env.writePiSessionFile(relativePath: "\(name).jsonl", contents: env.jsonl([
            ["type": "session", "id": session ?? name],
            self.entry(env, day: day, id: "entry", tokens: tokens),
        ]))
    }

    private func entry(_ env: CostUsageTestEnvironment, day: Date, id: String, tokens: Int) -> [String: Any] {
        [
            "type": "message", "id": id, "timestamp": env.isoString(for: day),
            "message": [
                "role": "assistant", "provider": "openai-codex", "model": "gpt-5.4",
                "usage": ["input": tokens, "output": 0, "totalTokens": tokens],
            ],
        ]
    }
}
