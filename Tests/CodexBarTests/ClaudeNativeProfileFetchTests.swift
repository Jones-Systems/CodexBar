import Foundation
import Testing
@testable import CodexBarCore

struct ClaudeNativeProfileFetchTests {
    private struct StubStrategy: ProviderFetchStrategy {
        let id = "synthetic-oauth"
        let kind = ProviderFetchKind.oauth
        let operation: @Sendable (ProviderFetchContext) async throws -> ProviderFetchResult

        func isAvailable(_: ProviderFetchContext) async -> Bool {
            true
        }

        func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
            try await self.operation(context)
        }

        func shouldFallback(on error: Error, context _: ProviderFetchContext) -> Bool {
            error is ClaudeNativeProfileSelectionError
        }
    }

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
            runtime: .app,
            sourceMode: source,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: environment,
            settings: .make(claude: ClaudeProviderSettings(
                usageDataSource: .auto, webExtrasEnabled: true, cookieSource: .auto, manualCookieHeader: nil)),
            fetcher: UsageFetcher(environment: environment),
            claudeFetcher: NoFetch(),
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

    #if os(macOS)
    private static func writeAccountID(_ accountID: String?, environment: [String: String]) throws {
        let url = ClaudeConfigPaths.accountConfigURL(environment: environment)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let config: [String: Any] = accountID.map { ["oauthAccount": ["accountUuid": $0]] } ?? [:]
        try JSONSerialization.data(withJSONObject: config).write(to: url)
    }

    private static func oauthResult(identity: ProviderIdentitySnapshot? = nil) -> ProviderFetchResult {
        ProviderFetchResult(
            usage: UsageSnapshot(
                primary: RateWindow(usedPercent: 65, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
                secondary: RateWindow(usedPercent: 90, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
                updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                identity: identity ?? ProviderIdentitySnapshot(
                    providerID: .claude, accountEmail: nil, accountOrganization: nil, loginMethod: "OAuth"),
                dataConfidence: .percentOnly),
            credits: nil,
            dashboard: nil,
            sourceLabel: "OAuth",
            strategyID: "synthetic-oauth",
            strategyKind: .oauth,
            diagnostic: "synthetic diagnostic",
            claudeOAuthKeychainPersistentRefHash: "synthetic-reference",
            claudeOAuthHistoryOwnerIdentifier: "synthetic-owner",
            claudeOAuthCredentialOwner: .claudeCLI,
            claudeOAuthKeychainCredentialMismatch: true,
            claudeOAuthKeychainCredentialAbsent: true,
            claudeOAuthKeychainCredentialUnavailable: true)
    }

    @Test(arguments: [false, true])
    func `native aliases expose account UUIDs and duplicate UUIDs stay identical`(duplicate: Bool) async throws {
        var identities: [String?] = []
        for named in [false, true] {
            try await self.withNativeFixture(named: named, expired: false) { environment, _ in
                let accountID = named && !duplicate ? "synthetic-second-uuid" : "synthetic-first-uuid"
                try Self.writeAccountID(accountID, environment: environment)
                let original = Self.oauthResult()
                let strategy = ClaudeNativeProfileFetchStrategy(base: StubStrategy { _ in original })
                let result = try await strategy.fetch(self.context(environment: environment))
                identities.append(result.usage.identity?.accountID)
                #expect(result.usage.identity?.accountID == accountID)
                #expect(result.usage.identity?.accountEmail == nil)
                #expect(result.usage.identity?.accountOrganization == nil)
                let encoder = JSONEncoder()
                encoder.outputFormatting = .sortedKeys
                #expect(try encoder.encode(result.usage.withIdentity(original.usage.identity))
                    == encoder.encode(original.usage))
                #expect(result.sourceLabel == original.sourceLabel)
                #expect(result.strategyID == original.strategyID)
                #expect(result.strategyKind == original.strategyKind)
                #expect(result.diagnostic == original.diagnostic)
                #expect(result.claudeOAuthKeychainPersistentRefHash == original.claudeOAuthKeychainPersistentRefHash)
                #expect(result.claudeOAuthHistoryOwnerIdentifier == original.claudeOAuthHistoryOwnerIdentifier)
                #expect(result.claudeOAuthCredentialOwner == original.claudeOAuthCredentialOwner)
                #expect(result.claudeOAuthKeychainCredentialMismatch)
                #expect(result.claudeOAuthKeychainCredentialAbsent)
                #expect(result.claudeOAuthKeychainCredentialUnavailable)
            }
        }
        #expect((identities[0] == identities[1]) == duplicate)
    }

    @Test
    func `missing selected UUID keeps OAuth quota usable and identity unknown`() async throws {
        try await self.withNativeFixture(named: true, expired: false) { environment, _ in
            let strategy = ClaudeNativeProfileFetchStrategy(base: ClaudeOAuthFetchStrategy())
            let result = try await strategy.fetch(self.context(environment: environment))
            #expect(result.usage.identity?.accountID == nil)
            #expect(result.usage.primary?.usedPercent == 7)
            #expect(result.usage.secondary?.usedPercent == 21)
        }
    }

    @Test(arguments: ["changed", "disappeared", "appeared"])
    func `selected UUID transitions reject a completed quota fetch`(transition: String) async throws {
        try await self.withNativeFixture(named: true, expired: false) { environment, _ in
            try Self.writeAccountID(transition == "appeared" ? nil : "before", environment: environment)
            let strategy = ClaudeNativeProfileFetchStrategy(base: StubStrategy { context in
                try Self.writeAccountID(transition == "disappeared" ? nil : "after", environment: context.env)
                return Self.oauthResult()
            })
            await #expect(throws: ClaudeNativeProfileSelectionError.self) {
                try await strategy.fetch(self.context(environment: environment))
            }
        }
    }

    @Test(arguments: [false, true])
    func `returned Claude account UUID must match selected profile`(matches: Bool) async throws {
        try await self.withNativeFixture(named: true, expired: false) { environment, _ in
            try Self.writeAccountID("selected-uuid", environment: environment)
            let strategy = ClaudeNativeProfileFetchStrategy(base: StubStrategy { _ in
                Self.oauthResult(identity: ProviderIdentitySnapshot(
                    providerID: .claude,
                    accountEmail: "synthetic@example.test",
                    accountOrganization: "synthetic organization",
                    loginMethod: "OAuth",
                    accountID: matches ? "SELECTED-UUID" : "different-uuid"))
            })
            if matches {
                let result = try await strategy.fetch(self.context(environment: environment))
                #expect(result.usage.identity?.accountID == "selected-uuid")
                #expect(result.usage.identity?.accountEmail == "synthetic@example.test")
                #expect(result.usage.identity?.accountOrganization == "synthetic organization")
                #expect(result.usage.identity?.loginMethod == "OAuth")
            } else {
                await #expect(throws: ClaudeNativeProfileSelectionError.self) {
                    try await strategy.fetch(self.context(environment: environment))
                }
            }
        }
    }

    @Test(arguments: [false, true])
    func `identity admission preserves base fallback and cancellation`(cancelled: Bool) async throws {
        try await self.withNativeFixture(named: true, expired: false) { environment, _ in
            try Self.writeAccountID("selected-uuid", environment: environment)
            let strategy = ClaudeNativeProfileFetchStrategy(base: StubStrategy { _ in
                if cancelled { throw CancellationError() }
                throw ClaudeNativeProfileSelectionError.unavailable
            })
            let context = self.context(environment: environment)
            do {
                _ = try await strategy.fetch(context)
                Issue.record("Stub failure must propagate")
            } catch {
                #expect((error is CancellationError) == cancelled)
                #expect(strategy.shouldFallback(on: error, context: context) == !cancelled)
            }
        }
    }

    @Test(arguments: [false, true])
    func `identity admission leaves other provider and unselected snapshots unchanged`(
        otherProvider: Bool) async throws
    {
        try await self.withNativeFixture(named: true, expired: false) { environment, _ in
            try Self.writeAccountID("selected-uuid", environment: environment)
            var environment = environment
            if !otherProvider { environment.removeValue(forKey: ClaudeNativeProfileSelection.selectionKey) }
            let original = Self.oauthResult(identity: ProviderIdentitySnapshot(
                providerID: otherProvider ? .codex : .claude,
                accountEmail: nil, accountOrganization: nil, loginMethod: nil, accountID: "transport-uuid"))
            let strategy = ClaudeNativeProfileFetchStrategy(base: StubStrategy { _ in original })
            let result = try await strategy.fetch(self.context(environment: environment))
            #expect(result.usage.identity?.providerID == original.usage.identity?.providerID)
            #expect(result.usage.identity?.accountID == "transport-uuid")
            #expect(result.usage.primary?.usedPercent == 65)
        }
    }

    @Test(arguments: [false, true])
    func `expired selected OAuth cannot delegate to a fallback executable`(named: Bool) async throws {
        try await self.withNativeFixture(named: named, expired: true) { environment, root in
            let strategy = ClaudeNativeProfileFetchStrategy(base: ClaudeOAuthFetchStrategy())
            let context = self.context(environment: environment)
            try await ProviderInteractionContext.$current.withValue(.userInitiated) {
                let record = try ClaudeOAuthCredentialsStore.loadRecord(
                    environment: environment,
                    allowKeychainPrompt: false,
                    allowClaudeKeychainRepairWithoutPrompt: false)
                #expect(record.owner == .claudeCLI)
                #expect(record.credentials.isExpired)
                do {
                    _ = try await strategy.fetch(context)
                    Issue.record("Expired selected OAuth must fail when its enrolled executable is missing")
                } catch let error as ClaudeNativeProfileSelectionError {
                    #expect(error.localizedDescription.contains("Claude CLI is not available for delegated refresh"))
                }
            }
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("launched").path))
        }
    }

    @Test(arguments: [false, true])
    func `valid selected OAuth stays usable without its enrolled executable`(named: Bool) async throws {
        try await self.withNativeFixture(named: named, expired: false) { environment, root in
            let accountID = named ? "synthetic-jace-uuid" : "synthetic-default-uuid"
            try Data("{\"oauthAccount\":{\"accountUuid\":\"\(accountID)\"}}".utf8)
                .write(to: ClaudeConfigPaths.accountConfigURL(environment: environment))
            let strategy = ClaudeNativeProfileFetchStrategy(base: ClaudeOAuthFetchStrategy())
            let result = try await ProviderInteractionContext.$current.withValue(.background) {
                try await strategy.fetch(self.context(environment: environment))
            }
            #expect(result.strategyKind == .oauth)
            #expect(result.usage.primary?.usedPercent == 7)
            #expect(result.usage.identity?.accountID == accountID)
            #expect(result.usage.identity?.accountEmail == nil)
            #expect(result.usage.identity?.accountOrganization == nil)
            #expect(result.claudeOAuthCredentialOwner == .claudeCLI)
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("launched").path))
        }
    }

    @Test
    func `selected executable resolution never substitutes PATH login PATH or a test override`() async throws {
        try await self.withNativeFixture(named: true, expired: true) { environment, root in
            let fallback = root.appendingPathComponent("claude").path
            let enrolled = try #require(environment["CLAUDE_CLI_PATH"])
            var ambient = environment
            ambient.removeValue(forKey: ClaudeNativeProfileSelection.selectionKey)
            #expect(ClaudeCLIResolver.resolvedBinaryPath(environment: ambient, loginPATH: []) == fallback)

            for path in [nil, "", "claude", enrolled] as [String?] {
                var selected = environment
                selected["CLAUDE_CLI_PATH"] = path
                #expect(ClaudeCLIResolver.resolvedBinaryPath(environment: selected, loginPATH: [root.path]) == nil)
            }
            try FileManager.default.copyItem(atPath: fallback, toPath: enrolled)
            #expect(ClaudeCLIResolver.resolvedBinaryPath(environment: environment, loginPATH: [root.path]) == enrolled)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: enrolled)
            #expect(ClaudeCLIResolver.resolvedBinaryPath(environment: environment, loginPATH: [root.path]) == nil)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: enrolled)
            var unavailable = environment
            unavailable[ClaudeNativeProfileSelection.unavailableKey] = "1"
            #expect(ClaudeCLIResolver.resolvedBinaryPath(environment: unavailable, loginPATH: [root.path]) == nil)

            try FileManager.default.removeItem(atPath: enrolled)
            await ClaudeCLIResolver.withResolvedBinaryPathOverrideForTesting(fallback) {
                #expect(ClaudeCLIResolver.resolvedBinaryPath(environment: environment, loginPATH: [root.path]) == nil)
            }
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("launched").path))
        }
    }

    private func withNativeFixture(
        named: Bool,
        expired: Bool,
        operation: ([String: String], URL) async throws -> Void) async throws
    {
        let workspace = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let scratchParent: URL
        if let explicitParent = ProcessInfo.processInfo.environment["CODEXBAR_TEST_SCRATCH_PARENT"] {
            try #require(
                explicitParent.hasPrefix("/") && !explicitParent.contains("\0"),
                "Explicit scratch parent must be an absolute path")
            let parent = URL(fileURLWithPath: explicitParent, isDirectory: true)
            var isDirectory: ObjCBool = false
            try #require(
                FileManager.default.fileExists(atPath: explicitParent, isDirectory: &isDirectory)
                    && isDirectory.boolValue,
                "Explicit scratch parent must be an existing directory")
            try #require(
                parent.standardizedFileURL.path == explicitParent
                    && parent.resolvingSymlinksInPath().path == explicitParent,
                "Explicit scratch parent must be canonical")
            let canonicalWorkspace = workspace.resolvingSymlinksInPath().standardizedFileURL.path
            try #require(
                explicitParent.hasPrefix(canonicalWorkspace + "/"),
                "Explicit scratch parent must be a strict workspace descendant")
            scratchParent = parent
        } else {
            scratchParent = workspace.appendingPathComponent(".build", isDirectory: true)
        }
        let root = scratchParent.appendingPathComponent("native-refresh-" + UUID().uuidString, isDirectory: true)
        defer {
            do {
                if FileManager.default.fileExists(atPath: root.path) {
                    try FileManager.default.removeItem(at: root)
                }
                #expect(!FileManager.default.fileExists(atPath: root.path))
            } catch {
                Issue.record("Could not clean owned native refresh fixture: \(error)")
            }
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var environment = [
            "HOME": root.path,
            "PATH": root.path,
            "CLAUDE_CLI_PATH": root.appendingPathComponent("enrolled-claude").path,
            ClaudeNativeProfileSelection.selectionKey: named ? "jace" : "default",
        ]
        if named { environment["CLAUDE_CONFIG_DIR"] = root.appendingPathComponent(".claude-t3/jace").path }
        let credentialsURL = ClaudeConfigPaths.credentialsURL(environment: environment)
        try FileManager.default.createDirectory(
            at: credentialsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let expiresAt = Int(Date(timeIntervalSinceNow: expired ? -3600 : 3600).timeIntervalSince1970 * 1000)
        try Data("""
        {"claudeAiOauth":{"accessToken":"synthetic-native","refreshToken":"synthetic-refresh",
        "expiresAt":\(expiresAt),"scopes":["user:profile"]}}
        """.utf8).write(to: credentialsURL)
        let fallback = root.appendingPathComponent("claude")
        try Data("#!/bin/sh\nprintf 'unexpected launch' > \"$HOME/launched\"\nexit 1\n".utf8).write(to: fallback)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fallback.path)

        try await KeychainCacheStore.withServiceOverrideForTesting("native-refresh-" + UUID().uuidString) {
            try await KeychainCacheStore.withImplicitTestStoreForTesting {
                try await KeychainAccessGate.withTaskOverrideForTesting(true) {
                    try await ClaudeOAuthCredentialsStore.withKeychainAccessOverrideForTesting(false) {
                        try await ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(.onlyOnUserAction) {
                            try await ClaudeOAuthCredentialsStore.withEnvironmentCredentialsURLForTesting {
                                try await ClaudeOAuthCredentialsStore.withIsolatedMemoryCacheForTesting {
                                    try await ClaudeOAuthCredentialsStore
                                        .withIsolatedCredentialsFileTrackingForTesting {
                                            try await self.withNativeRefreshStubs {
                                                try await operation(environment, root)
                                            }
                                        }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func withNativeRefreshStubs(operation: () async throws -> Void) async throws {
        let response = try ClaudeOAuthUsageFetcher._decodeUsageResponseForTesting(Data("""
        {"five_hour":{"utilization":7},"seven_day":{"utilization":21}}
        """.utf8))
        try await ClaudeOAuthKeychainAccessGate.withDeniedUntilStoreOverrideForTesting(.init()) {
            try await ClaudeOAuthKeychainReadStrategyPreference.withTaskOverrideForTesting(.securityFramework) {
                try await self.withNativeRefreshTransportStubs(response: response, operation: operation)
            }
        }
    }

    private func withNativeRefreshTransportStubs(
        response: OAuthUsageResponse,
        operation: () async throws -> Void) async throws
    {
        let fetchOverride: @Sendable (String, Bool) async throws -> OAuthUsageResponse = { token, _ in
            #expect(token == "synthetic-native")
            return response
        }
        try await ClaudeUsageFetcher.$fetchOAuthUsageOverride.withValue(fetchOverride) {
            try await ClaudeOAuthDelegatedRefreshCoordinator.withIsolatedStateForTesting {
                try await ClaudeOAuthDelegatedRefreshCoordinator.withKeychainFingerprintOverrideForTesting {
                    nil
                } operation: {
                    // Keep a regressed resolver from launching even the sentinel through the native PTY/session stack.
                    // The real coordinator and its availability gate still run; reaching the touch is a test failure.
                    try await ClaudeOAuthDelegatedRefreshCoordinator.withTouchAuthPathOverrideForTesting { _, _ in
                        Issue.record("Selected native refresh must not touch an alternate executable")
                        throw CancellationError()
                    } operation: {
                        try await operation()
                    }
                }
            }
        }
    }
    #endif
}
