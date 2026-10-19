import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
enum ClaudeNativeProfileAccountsFixture {
    static func run(_ body: (SettingsStore, UsageStore, URL) async throws -> Void) async throws {
        let root = TestFixtureScratch.root.appendingPathComponent("native-accounts-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: root)
                #expect(!FileManager.default.fileExists(atPath: root.path))
            } catch {
                Issue.record("Could not clean native account fixture: \(error)")
            }
        }
        let configStore = CodexBarConfigStore(fileURL: root.appendingPathComponent("config.json"))
        try configStore.save(testConfigWithAllProvidersDisabled())
        let settings = SettingsStore(
            userDefaults: InMemoryUserDefaults(), configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(), syntheticTokenStore: NoopSyntheticTokenStore(),
            codexCookieStore: InMemoryCookieHeaderStore(), claudeCookieStore: InMemoryCookieHeaderStore(),
            cursorCookieStore: InMemoryCookieHeaderStore(), opencodeCookieStore: InMemoryCookieHeaderStore(),
            factoryCookieStore: InMemoryCookieHeaderStore(), minimaxCookieStore: InMemoryMiniMaxCookieStore(),
            minimaxAPITokenStore: InMemoryMiniMaxAPITokenStore(), kimiTokenStore: InMemoryKimiTokenStore(),
            augmentCookieStore: InMemoryCookieHeaderStore(), ampCookieStore: InMemoryCookieHeaderStore(),
            copilotTokenStore: InMemoryCopilotTokenStore(),
            tokenAccountStore: InMemoryTokenAccountStore(fileURL: root.appendingPathComponent("accounts.json")),
            antigravityOAuthCredentialsStore: AntigravityOAuthCredentialsStore(
                fileURL: root.appendingPathComponent("antigravity.json")),
            keychainAccessPolicy: SettingsStoreKeychainAccessPolicy(
                setDisabled: { _ in }, isExplicitlyDisabled: { true }), performInitialProviderDetection: false)
        defer { settings.configFileWatcher?.stop() }
        settings.setProviderEnabled(
            provider: .claude, metadata: ProviderDescriptorRegistry.descriptor(for: .claude).metadata, enabled: true)
        settings.claudeNativeProfileAlias = "default"
        settings.claudeUsageDataSource = .cli
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        settings.costUsageEnabled = false
        settings.mergeIcons = false
        let environment = ["HOME": root.path, "CODEX_HOME": root.appendingPathComponent("codex").path]
        let store = UsageStore(
            fetcher: UsageFetcher(environment: environment), browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings, startupBehavior: .testing, environmentBase: environment,
            widgetSnapshotURL: root.appendingPathComponent("widget.json"), widgetTimelineReloader: {})
        store._cancelPlanUtilizationHistoryLoadForTesting()
        defer { store.clearClaudeNativeProfileAccountState() }
        try await ClaudeFleetProfileDiscovery.$discoveryOverride.withValue(self.discovery(root: root)) {
            store.reconcileClaudeNativeProfileEnvironment(store.claudeNativeProfileFetchEnvironment())
            try await body(settings, store, root)
        }
    }

    static func discovery(root: URL, sideRoot: URL? = nil) -> ClaudeFleetProfileDiscovery.Result {
        .available([
            .init(
                alias: "default",
                home: root.path,
                configDirectory: nil,
                nativeCLI: root.appendingPathComponent("claude").path,
                store: "claude-keychain"),
            .init(
                alias: "jace",
                home: root.path,
                configDirectory: (sideRoot ?? root.appendingPathComponent(".claude-t3/jace")).path,
                nativeCLI: root.appendingPathComponent("claude").path,
                store: "claude-keychain"),
        ])
    }

    static func snapshot(_ percent: Double = 24, timestamp: TimeInterval = 1_800_000_000) -> UsageSnapshot {
        UsageSnapshot(
            primary: RateWindow(usedPercent: percent, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil, updatedAt: Date(timeIntervalSince1970: timestamp),
            identity: ProviderIdentitySnapshot(
                providerID: .claude, accountEmail: "synthetic@example.test", accountOrganization: nil,
                loginMethod: nil))
    }

    static func outcome(_ percent: Double = 24) -> ProviderFetchOutcome {
        ProviderFetchOutcome(result: .success(ProviderFetchResult(
            usage: self.snapshot(percent), credits: nil, dashboard: nil,
            sourceLabel: "CLI", strategyID: "synthetic-native", strategyKind: .cli)), attempts: [])
    }
}

@MainActor
struct ClaudeNativeProfileAccountsTests {
    @Test(arguments: [false, true])
    func `discovery change during side fetch discards result and retires prior owner usage`(removed: Bool) async throws {
        try await ClaudeNativeProfileAccountsFixture.run { _, store, root in
            store
                ._test_claudeNativeProfileFetchOutcomeOverride = { _ in ClaudeNativeProfileAccountsFixture.outcome(67) }
            await store.refreshClaudeNativeProfileAccountsAfterMain()
            var discovery = ClaudeNativeProfileAccountsFixture.discovery(root: root)
            store._test_claudeNativeProfileDiscoveryOverride = { discovery }
            store._test_claudeNativeProfileFetchOutcomeOverride = { _ in
                discovery = removed ? .available(discovery.profiles.filter { $0.alias == "default" })
                    : ClaudeNativeProfileAccountsFixture.discovery(
                        root: root, sideRoot: root.appendingPathComponent("replacement-owner"))
                return ClaudeNativeProfileAccountsFixture.outcome(99)
            }
            await store.refreshClaudeNativeProfileAccountsAfterMain()
            let changed = try #require(store.claudeNativeProfileAccountsForDisplay().last)
            #expect(changed.snapshot == nil)
            #expect(changed.error == ClaudeNativeProfileSelectionError.unavailable.localizedDescription)
            #expect(store.claudeNativeProfileAccountsState?.identities["jace"] == nil)
        }
    }

    @Test
    func `selected usage is reused and side context preserves selected runtime identity`() async throws {
        try await ClaudeNativeProfileAccountsFixture.run { settings, store, _ in
            let main = ClaudeNativeProfileAccountsFixture.snapshot(12)
            store.snapshots[.claude] = main
            let selectedEnvironment = store.claudeNativeProfileFetchEnvironment()
            let runtime = try #require(store.providerRuntimes[.claude] as? ClaudeProviderRuntime)
            let identity = runtime.lastNativeProfileIdentity
            var aliases: [String] = []
            store._test_claudeNativeProfileFetchOutcomeOverride = { context in
                aliases.append(context.env[ClaudeNativeProfileSelection.selectionKey] ?? "missing")
                #expect(context.env["CLAUDE_CONFIG_DIR"]?.hasSuffix(".claude-t3/jace") == true)
                #expect(context.env[ClaudeNativeProfileSelection.identityKey]
                    != selectedEnvironment[ClaudeNativeProfileSelection.identityKey])
                return ClaudeNativeProfileAccountsFixture.outcome(67)
            }
            await store.refreshClaudeNativeProfileAccountsAfterMain()
            let accounts = store.claudeNativeProfileAccountsForDisplay()
            #expect(aliases == ["jace"])
            #expect(accounts.count == 2)
            #expect(accounts.first(where: \.isActive)?.snapshot?.primary?.usedPercent == 12)
            #expect(accounts.first(where: { !$0.isActive })?.snapshot?.primary?.usedPercent == 67)
            #expect(accounts.map(\.displayLabel) == ["default", "Jace"])
            #expect(accounts.allSatisfy { !$0.canActivate })
            #expect(runtime.lastNativeProfileIdentity == identity)
            #expect(store.snapshots[.claude]?.updatedAt == main.updatedAt)
            #expect(settings.claudeNativeProfileAlias == "default")
        }
    }

    @Test
    func `failed and cancelled side refresh retain only same identity usage with original timestamp`() async throws {
        try await ClaudeNativeProfileAccountsFixture.run { _, store, root in
            store
                ._test_claudeNativeProfileFetchOutcomeOverride = { _ in ClaudeNativeProfileAccountsFixture.outcome(67) }
            await store.refreshClaudeNativeProfileAccountsAfterMain()
            store._test_claudeNativeProfileFetchOutcomeOverride = { _ in
                ProviderFetchOutcome(result: .failure(ClaudeNativeProfileSelectionError.unavailable), attempts: [])
            }
            await store.refreshClaudeNativeProfileAccountsAfterMain()
            let stale = try #require(store.claudeNativeProfileAccountsForDisplay().last)
            #expect(stale.snapshot?.primary?.usedPercent == 67)
            #expect(stale.snapshot?.updatedAt == Date(timeIntervalSince1970: 1_800_000_000))
            #expect(stale.error == ClaudeNativeProfileSelectionError.unavailable.localizedDescription)
            store._test_claudeNativeProfileFetchOutcomeOverride = { _ in
                ProviderFetchOutcome(result: .failure(CancellationError()), attempts: [])
            }
            await store.refreshClaudeNativeProfileAccountsAfterMain()
            #expect(store.claudeNativeProfileAccountsForDisplay().last?.snapshot?.updatedAt == stale.snapshot?
                .updatedAt)
            #expect(store.claudeNativeProfileAccountsForDisplay().last?.error == stale.error)

            await ClaudeFleetProfileDiscovery.$discoveryOverride.withValue(
                ClaudeNativeProfileAccountsFixture.discovery(
                    root: root,
                    sideRoot: root.appendingPathComponent("rebound")))
            {
                await store.refreshClaudeNativeProfileAccountsAfterMain()
                #expect(store.claudeNativeProfileAccountsForDisplay().last?.snapshot == nil)
            }
        }
    }

    @Test
    func `changed selected alias and invalidated generation discard suspended side results`() async throws {
        for changesSelection in [false, true] {
            try await ClaudeNativeProfileAccountsFixture.run { settings, store, _ in
                let started = AsyncStream<Void>.makeStream()
                var iterator = started.stream.makeAsyncIterator()
                var continuation: CheckedContinuation<Void, Never>?
                store._test_claudeNativeProfileFetchOutcomeOverride = { _ in
                    await withCheckedContinuation { continuation = $0; started.continuation.yield(()) }
                    return ClaudeNativeProfileAccountsFixture.outcome(91)
                }
                let request = store.providerRefreshCoordinator
                    .beginReplacingRequest(for: UsageProvider.claude.instanceID)
                store.providerRefreshPublicationContexts[.claude] = ProviderRefreshPublicationContext(
                    generation: request.generation,
                    enablementRevision: settings.providerEnablementRevision(for: .claude),
                    configRevision: settings.providerConfigRevision(for: .claude),
                    tokenCostScopeSignature: nil, allowDisabled: false)
                let refresh = Task {
                    await store.refreshClaudeNativeProfileAccountsAfterMain(generation: request.generation)
                }
                _ = await iterator.next()
                if changesSelection { settings.claudeNativeProfileAlias = "jace" } else {
                    store.invalidateProviderRefreshRequests(.claude)
                }
                continuation?.resume()
                await refresh.value
                #expect(store.claudeNativeProfileAccountSnapshots.last?.snapshot == nil)
                #expect(store.claudeNativeProfileRefreshingAliases.isEmpty)
                store.providerRefreshCoordinator.complete(request.state, for: .claude, retryRequired: false)
            }
        }
    }

    @Test
    func `native aggregation never overrides token source manual cookie or missing enrollment`() async throws {
        try await ClaudeNativeProfileAccountsFixture.run { settings, store, _ in
            var fetches = 0
            store._test_claudeNativeProfileFetchOutcomeOverride = { _ in
                fetches += 1
                return ClaudeNativeProfileAccountsFixture.outcome()
            }
            settings.claudeUsageDataSource = .web
            await store.refreshClaudeNativeProfileAccountsAfterMain()
            #expect(store.claudeNativeProfileAccountsForDisplay().isEmpty)
            settings.claudeUsageDataSource = .auto
            settings.claudeCookieSource = .manual
            settings.claudeCookieHeader = "synthetic-cookie"
            await store.refreshClaudeNativeProfileAccountsAfterMain()
            settings.claudeCookieHeader = ""
            settings.addTokenAccount(provider: .claude, label: "Token", token: "synthetic-token")
            await store.refreshClaudeNativeProfileAccountsAfterMain()
            #expect(fetches == 0)
            #expect(store.claudeNativeProfileAccountsForDisplay().isEmpty)
            await ClaudeFleetProfileDiscovery.$discoveryOverride.withValue(.missing) {
                await store.refreshClaudeNativeProfileAccountsAfterMain()
            }
            #expect(fetches == 0)
        }
    }

    @Test
    func `replacement main refresh waits for cancelled side work to drain`() async throws {
        try await ClaudeNativeProfileAccountsFixture.run { _, store, _ in
            let events = AsyncStream<Void>.makeStream()
            var iterator = events.stream.makeAsyncIterator()
            var blocked: CheckedContinuation<Void, Never>?
            var trace: [String] = []
            var sideCalls = 0
            var sideInFlight = 0
            var maximumSideInFlight = 0
            store._test_providerRefreshOverride = { _ in
                #expect(sideInFlight == 0)
                trace.append("main")
                store.snapshots[.claude] = ClaudeNativeProfileAccountsFixture.snapshot(12)
            }
            store._test_claudeNativeProfileFetchOutcomeOverride = { _ in
                sideCalls += 1
                sideInFlight += 1
                maximumSideInFlight = max(maximumSideInFlight, sideInFlight)
                defer { sideInFlight -= 1 }
                trace.append("side-start")
                if sideCalls == 1 {
                    await withCheckedContinuation { blocked = $0; events.continuation.yield(()) }
                }
                trace.append("side-end")
                return ClaudeNativeProfileAccountsFixture.outcome(67)
            }
            let first = Task { await store.refreshProvider(.claude) }
            _ = await iterator.next()
            let second = Task {
                events.continuation.yield(())
                await store.refreshProvider(.claude)
            }
            _ = await iterator.next()
            #expect(trace == ["main", "side-start"])
            blocked?.resume()
            await first.value
            await second.value
            #expect(trace == ["main", "side-start", "side-end", "main", "side-start", "side-end"])
            #expect(store.claudeNativeProfileAccountsTask == nil)
            #expect(maximumSideInFlight == 1)
        }
    }

    @Test(arguments: [false, true])
    func `disable and stop cancel side publication while its task drains`(stop: Bool) async throws {
        try await ClaudeNativeProfileAccountsFixture.run { settings, store, _ in
            let started = AsyncStream<Void>.makeStream()
            var iterator = started.stream.makeAsyncIterator()
            var blocked: CheckedContinuation<Void, Never>?
            var drained = false
            store._test_claudeNativeProfileFetchOutcomeOverride = { _ in
                await withCheckedContinuation { blocked = $0; started.continuation.yield(()) }
                drained = true
                return ClaudeNativeProfileAccountsFixture.outcome(99)
            }
            let refresh = Task { await store.refreshClaudeNativeProfileAccountsAfterMain() }
            _ = await iterator.next()
            let runtime = try #require(store.providerRuntimes[.claude] as? ClaudeProviderRuntime)
            let context = ProviderRuntimeContext(provider: .claude, settings: settings, store: store)
            if stop { runtime.stop(context: context) } else {
                settings.setProviderEnabled(
                    provider: .claude, metadata: ProviderDescriptorRegistry.descriptor(for: .claude).metadata,
                    enabled: false)
                runtime.settingsDidChange(context: context)
            }
            #expect(!drained)
            #expect(store.claudeNativeProfileAccountsForDisplay().isEmpty)
            blocked?.resume()
            await refresh.value
            #expect(drained)
            #expect(store.claudeNativeProfileAccountSnapshots.isEmpty)
            #expect(store.claudeNativeProfileAccountsTask == nil)
        }
    }
}
