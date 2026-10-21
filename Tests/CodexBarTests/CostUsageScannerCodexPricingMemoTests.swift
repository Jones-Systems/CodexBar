import Foundation
import Testing
@testable import CodexBarCore

private final class CodexPricingLookupCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        self.lock.withLock { self.count }
    }

    func increment() {
        self.lock.withLock { self.count += 1 }
    }
}

struct CostUsageScannerCodexPricingMemoTests {
    @Test(arguments: [40, 80])
    func `project pricing lookups depend on distinct models rather than rows or files`(rowsPerFile: Int) throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        #expect(CostUsagePricing.customPricingOverlay() == .empty)
        let day = try env.makeLocalNoon(
            year: 2026,
            month: 10,
            day: 20)
        let range = CostUsageScanner.CostUsageDayRange(
            since: day,
            until: day)
        let cache = self.cache(
            env,
            day: day,
            range: range,
            rowsPerFile: rowsPerFile)
        let catalog = try self.catalog(inputRate: 2)
        let reference = CostUsagePricing.$codexLookupMemoDisabledForTesting.withValue(true) {
            CostUsageScanner.buildCodexProjectBreakdownsFromCache(
                cache: cache,
                range: range,
                modelsDevCatalog: catalog)
        }
        let counter = CodexPricingLookupCounter()
        let counterObserver: @Sendable () -> Void = { counter.increment() }
        let result = CostUsagePricing.$codexModelsDevLookupObserverForTesting.withValue(counterObserver) {
            CostUsageScanner.buildCodexProjectBreakdownsFromCache(
                cache: cache,
                range: range,
                modelsDevCatalog: catalog)
        }
        #expect(result == reference)
        #expect(result.count == 2)
        #expect(result.reduce(0) { $0 + ($1.totalTokens ?? 0) } == 3 * rowsPerFile * 110)
        #expect(counter.value == 2)
        let knownCosts = result.flatMap { $0.modelBreakdowns ?? [] }
            .filter { $0.modelName == "gpt-5.4" }.compactMap(\.costUSD)
        #expect(knownCosts.count == 2)
        #expect(abs(knownCosts.reduce(0, +) - Double(3 * rowsPerFile / 2) * 0.00024) < 1e-9)
    }

    @Test
    func `separate project builds resolve changed catalogs independently`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        #expect(CostUsagePricing.customPricingOverlay() == .empty)
        let day = try env.makeLocalNoon(
            year: 2026,
            month: 10,
            day: 20)
        let range = CostUsageScanner.CostUsageDayRange(
            since: day,
            until: day)
        let cache = self.cache(
            env,
            day: day,
            range: range,
            rowsPerFile: 40)
        var previous: [CostUsageProjectBreakdown]?
        for inputRate in [2.0, 8.0] {
            let catalog = try self.catalog(inputRate: inputRate)
            let counter = CodexPricingLookupCounter()
            let counterObserver: @Sendable () -> Void = { counter.increment() }
            let report = CostUsagePricing.$codexModelsDevLookupObserverForTesting.withValue(counterObserver) {
                CostUsageScanner.buildCodexProjectBreakdownsFromCache(
                    cache: cache,
                    range: range,
                    modelsDevCatalog: catalog)
            }
            let reference = CostUsagePricing.$codexLookupMemoDisabledForTesting.withValue(true) {
                CostUsageScanner.buildCodexProjectBreakdownsFromCache(
                    cache: cache,
                    range: range,
                    modelsDevCatalog: catalog)
            }
            #expect(report == reference)
            #expect(counter.value == 2)
            if let previous {
                #expect(report != previous)
            }
            previous = report
        }
    }

    @Test
    func `session build shares lookups and preserves uncached reports`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(
            year: 2026,
            month: 10,
            day: 20)
        let range = CostUsageScanner.CostUsageDayRange(
            since: day,
            until: day)
        let cache = self.cache(
            env,
            day: day,
            range: range,
            rowsPerFile: 40)
        let catalog = try self.catalog(inputRate: 2)
        let reference = CostUsagePricing.$codexLookupMemoDisabledForTesting.withValue(true) {
            CostUsageScanner.buildCodexSessionBreakdownsFromCache(
                cache: cache,
                range: range,
                modelsDevCatalog: catalog)
        }
        let counter = CodexPricingLookupCounter()
        let counterObserver: @Sendable () -> Void = { counter.increment() }
        let result = CostUsagePricing.$codexModelsDevLookupObserverForTesting.withValue(counterObserver) {
            CostUsageScanner.buildCodexSessionBreakdownsFromCache(
                cache: cache,
                range: range,
                modelsDevCatalog: catalog)
        }
        #expect(result == reference)
        #expect(result.count == 3)
        #expect(counter.value == 2)
    }

    @Test
    func `missing catalog snapshot remains local to each standalone report`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(
            year: 2026,
            month: 10,
            day: 20)
        let range = CostUsageScanner.CostUsageDayRange(
            since: day,
            until: day)
        let cache = self.cache(
            env,
            day: day,
            range: range,
            rowsPerFile: 40)
        for _ in 0..<2 {
            var loads = 0
            let counter = CodexPricingLookupCounter()
            let counterObserver: @Sendable () -> Void = { counter.increment() }
            let result = CostUsagePricing.$codexModelsDevLookupObserverForTesting.withValue(counterObserver) {
                CostUsageScanner.buildCodexReportFromCache(
                    cache: cache,
                    range: range,
                    modelsDevCatalogLoader: { _ in
                        loads += 1
                        return nil
                    })
            }
            let reference = CostUsagePricing.$codexLookupMemoDisabledForTesting.withValue(true) {
                CostUsageScanner.buildCodexReportFromCache(
                    cache: cache,
                    range: range,
                    modelsDevCatalog: ModelsDevCatalog(providers: [:]))
            }
            #expect(result.data == reference.data)
            #expect(result.summary == reference.summary)
            #expect(loads == 1)
            #expect(counter.value == 2)
        }
    }

    @Test
    func `lookup bounds preserve negative results and exact model bytes`() {
        let catalog = ModelsDevCatalog(providers: [:])
        let resolver = CostUsagePricing.CodexResolver(catalog: catalog)
        let counter = CodexPricingLookupCounter()
        let counterObserver: @Sendable () -> Void = { counter.increment() }
        CostUsagePricing.$codexModelsDevLookupObserverForTesting.withValue(counterObserver) {
            for index in 0..<257 {
                for _ in 0..<2 {
                    #expect(self.scalarCost(
                        "fixture-missing-\(index)",
                        catalog: catalog,
                        resolver: resolver) == nil)
                }
            }
        }
        #expect(counter.value == 258)
        let exactResolver = CostUsagePricing.CodexResolver(catalog: catalog)
        let exactCounter = CodexPricingLookupCounter()
        let exactCounterObserver: @Sendable () -> Void = { exactCounter.increment() }
        CostUsagePricing.$codexModelsDevLookupObserverForTesting.withValue(exactCounterObserver) {
            for model in ["fixture-\u{00e9}", "fixture-e\u{0301}"] {
                for _ in 0..<2 {
                    #expect(self.scalarCost(
                        model,
                        catalog: catalog,
                        resolver: exactResolver) == nil)
                }
            }
        }
        #expect(exactCounter.value == 2)
        let longCounter = CodexPricingLookupCounter()
        let longCounterObserver: @Sendable () -> Void = { longCounter.increment() }
        CostUsagePricing.$codexModelsDevLookupObserverForTesting.withValue(longCounterObserver) {
            for _ in 0..<2 {
                #expect(self.scalarCost(
                    String(
                        repeating: "x",
                        count: 257),
                    catalog: catalog,
                    resolver: exactResolver) == nil)
            }
        }
        #expect(longCounter.value == 2)
    }

    @Test
    func `memoized catalog keeps dated priority and aggregate cost decisions per call`() throws {
        let catalog = try self.catalog(inputRate: 2)
        let resolver = CostUsagePricing.CodexResolver(catalog: catalog)
        let cutoff = CostUsagePricing.codexGPT56PricingCutoff
        let dates: [Date?] = [cutoff.addingTimeInterval(-1), cutoff, nil]
        for model in ["gpt-5.4", "gpt-5.6-sol", "gpt-fixture-missing"] {
            for date in dates {
                for input in [100, 272_000, 272_001] {
                    let reference = CostUsagePricing.codexCostUSD(
                        model: model,
                        inputTokens: input,
                        cachedInputTokens: 10,
                        outputTokens: 20,
                        pricingDate: date,
                        modelsDevCatalog: catalog,
                        customPricing: .empty)
                    let cached = CostUsagePricing.codexCostUSD(
                        model: model,
                        inputTokens: input,
                        cachedInputTokens: 10,
                        outputTokens: 20,
                        pricingDate: date,
                        modelsDevCatalog: catalog,
                        customPricing: .empty,
                        resolver: resolver)
                    #expect(cached == reference)
                    let priorityReference = CostUsagePricing.codexPriorityCostUSD(
                        model: model,
                        inputTokens: input,
                        cachedInputTokens: 10,
                        outputTokens: 20,
                        pricingDate: date,
                        modelsDevCatalog: catalog,
                        customPricing: .empty)
                    let priority = CostUsagePricing.codexPriorityCostUSD(
                        model: model,
                        inputTokens: input,
                        cachedInputTokens: 10,
                        outputTokens: 20,
                        pricingDate: date,
                        modelsDevCatalog: catalog,
                        customPricing: .empty,
                        resolver: resolver)
                    #expect(priority == priorityReference)
                    let aggregateReference = CostUsagePricing.codexAggregateCostUSD(
                        model: model,
                        inputTokens: input,
                        cachedInputTokens: 10,
                        outputTokens: 20,
                        pricingDate: date,
                        modelsDevCatalog: catalog,
                        customPricing: .empty)
                    let aggregate = CostUsagePricing.codexAggregateCostUSD(
                        model: model,
                        inputTokens: input,
                        cachedInputTokens: 10,
                        outputTokens: 20,
                        pricingDate: date,
                        modelsDevCatalog: catalog,
                        customPricing: .empty,
                        resolver: resolver)
                    #expect(aggregate == aggregateReference)
                    if input == 272_001 {
                        #expect(priority == nil)
                        if model == "gpt-5.4" {
                            #expect(aggregate == nil)
                        }
                    }
                }
            }
        }
    }

    @Test
    func `overlays and authoritative costs bypass warmed catalog memo`() throws {
        let catalog = try self.catalog(inputRate: 2)
        let resolver = CostUsagePricing.CodexResolver(catalog: catalog)
        _ = self.scalarCost(
            "gpt-5.4",
            catalog: catalog,
            resolver: resolver)
        let counter = CodexPricingLookupCounter()
        let counterObserver: @Sendable () -> Void = { counter.increment() }
        CostUsagePricing.$codexModelsDevLookupObserverForTesting.withValue(counterObserver) {
            for rate in [0.0, 8.0] {
                let overlay = CostUsageCustomPricing(
                    entries: ["openai/gpt-5.4": .init(
                        input: rate,
                        output: rate)],
                    fingerprint: "fixture-\(rate)")
                let expected = CostUsagePricing.codexCostUSD(
                    model: "gpt-5.4",
                    inputTokens: 100,
                    cachedInputTokens: 0,
                    outputTokens: 10,
                    modelsDevCatalog: catalog,
                    customPricing: overlay)
                let actual = CostUsagePricing.codexCostUSD(
                    model: "gpt-5.4",
                    inputTokens: 100,
                    cachedInputTokens: 0,
                    outputTokens: 10,
                    modelsDevCatalog: catalog,
                    customPricing: overlay,
                    resolver: resolver)
                #expect(actual == expected)
                #expect(abs((actual ?? -1) - rate * 110 / 1_000_000) < 1e-12)
            }
            let row = CostUsageScanner.CodexUsageRow(
                day: "2026-10-20",
                model: "gpt-fixture-missing",
                turnID: "authoritative",
                eventIndex: 0,
                input: 100,
                cached: 0,
                output: 10,
                knownCostNanos: 123_000_000)
            #expect(CostUsageScanner.codexResolvedCostUSD(
                for: row,
                modelsDevCatalog: catalog,
                modelsDevCacheRoot: nil,
                customPricing: .empty,
                resolver: resolver) == 0.123)
        }
        #expect(counter.value == 0)
    }

    private func scalarCost(
        _ model: String,
        catalog: ModelsDevCatalog,
        resolver: CostUsagePricing.CodexResolver) -> Double?
    {
        CostUsagePricing.codexCostUSD(
            model: model,
            inputTokens: 100,
            cachedInputTokens: 0,
            outputTokens: 10,
            modelsDevCatalog: catalog,
            customPricing: .empty,
            resolver: resolver)
    }

    private func catalog(inputRate: Double) throws -> ModelsDevCatalog {
        try JSONDecoder().decode(
            ModelsDevCatalog.self,
            from: Data("""
            {"openai":{"models":{"gpt-5.4":{"id":"gpt-5.4","cost":{"input":\(
                inputRate),"output":4}}}}}
            """.utf8))
    }

    private func cache(
        _ env: CostUsageTestEnvironment,
        day: Date,
        range: CostUsageScanner.CostUsageDayRange,
        rowsPerFile: Int) -> CostUsageCache
    {
        var cache = CostUsageCache()
        for file in 0..<3 {
            let rows = (0..<rowsPerFile).map { index in
                CostUsageScanner.CodexUsageRow(
                    day: range.sinceKey,
                    model: index.isMultiple(of: 2) ? "gpt-5.4" : "gpt-fixture-missing",
                    turnID: "file-\(file)-turn-\(index)",
                    eventIndex: index,
                    timestampUnixMs: Int64(day.timeIntervalSince1970 * 1000) + Int64(index),
                    input: 100,
                    cached: 0,
                    output: 10)
            }
            let projectPath = env.root.appendingPathComponent("project-\(file % 2)").path
            let packed = [rowsPerFile / 2 * 100, 0, rowsPerFile / 2 * 10]
            let usage = CostUsageScanner.makeFileUsage(
                mtimeUnixMs: Int64(day.timeIntervalSince1970 * 1000),
                size: Int64(rowsPerFile),
                days: [range.sinceKey: ["gpt-5.4": packed, "gpt-fixture-missing": packed]],
                parsedBytes: Int64(rowsPerFile),
                sessionId: "session-\(file)",
                projectPath: projectPath,
                canonicalProjectPath: projectPath,
                codexRows: rows,
                codexScanComplete: true)
            cache.files[env.codexSessionsRoot.appendingPathComponent("session-\(file).jsonl").path] = usage
            CostUsageScanner.applyFileDays(
                cache: &cache,
                fileDays: usage.days,
                sign: 1)
        }
        return cache
    }
}
