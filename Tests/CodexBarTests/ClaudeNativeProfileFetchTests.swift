import Foundation
import Testing
@testable import CodexBarCore

struct ClaudeNativeProfileFetchTests {
    private struct NoFetch: ClaudeUsageFetching {
        func loadLatestUsage(model: String) async throws -> ClaudeUsageSnapshot {
            Issue.record("No credential or provider fetch may run for an unavailable selection")
            throw ClaudeNativeProfileSelectionError.unavailable
        }

        func debugRawProbe(model: String) async -> String {
            "unused"
        }

        func detectVersion() -> String? {
            nil
        }
    }

    private func context(environment: [String: String], source: ProviderSourceMode = .auto) -> ProviderFetchContext {
        ProviderFetchContext(
            runtime: .app, sourceMode: source, includeCredits: false,
            webTimeout: 1, webDebugDumpHTML: false, verbose: false, env: environment,
            settings: .make(claude: ClaudeProviderSettings(
                usageDataSource: .auto, webExtrasEnabled: true, cookieSource: .auto, manualCookieHeader: nil)),
            fetcher: UsageFetcher(environment: environment), claudeFetcher: NoFetch(),
            browserDetection: BrowserDetection(cacheTTL: 0))
    }

    @Test
    func `unavailable native enrollment produces selected source error before any native or web attempt`() async {
        let environment = ClaudeNativeProfileSelection.environment(base: [:], alias: "jace", discovery: .missing)
        for source in [ProviderSourceMode.auto, .oauth, .cli] {
            let outcome = await ClaudeProviderDescriptor.descriptor.fetchOutcome(
                context: self.context(environment: environment, source: source))
            guard case let .failure(error) = outcome.result else {
                Issue.record("Unavailable selected profile must fail")
                continue
            }
            #expect(error is ClaudeNativeProfileSelectionError)
            #expect(error.localizedDescription.contains("Selected Claude native profile"))
            #expect(outcome.attempts.count == 1)
            #expect(outcome.attempts.allSatisfy { $0.kind == .oauth || $0.kind == .cli })
        }
    }

    @Test
    func `selected native pipeline contains only native transports and follows explicit CLI`() throws {
        let env = try ClaudeNativeProfileSelection.environment(
            base: [:], alias: "jace", discovery: ClaudeFleetProfileDiscoveryTests.discovery())
        for source in [ProviderSourceMode.auto, .oauth] {
            let strategies = ClaudeNativeProfileFetchStrategy.strategies(context: self.context(
                environment: env,
                source: source))
            #expect(strategies.map(\.kind) == [.oauth, .cli])
        }
        #expect(ClaudeNativeProfileFetchStrategy.strategies(context: self.context(environment: env, source: .cli))
            .map(\.kind) == [.cli])
    }
}
