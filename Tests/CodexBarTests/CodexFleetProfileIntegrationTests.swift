import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCLI
@testable import CodexBarCore

@Suite(.serialized, CodexCredentialFixtures())
struct CodexFleetProfileIntegrationTests {
    @Test
    @MainActor
    func `fleet profile selection survives restart and discovery loss then recovers`() throws {
        let root = CodexCredentialFixtures.root
        let home = root.appendingPathComponent("fleet-profile", isDirectory: true)
        try Self.writeAuth(home: home, email: "fleet@example.com", accountID: "acct-fleet")
        let defaultsName = "CodexFleetProfileIntegrationTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let configStore = CodexBarConfigStore(fileURL: root.appendingPathComponent("config.json"))
        let settings = Self.makeSettings(defaults: defaults, configStore: configStore)
        settings._test_codexFleetProfileDiscovery = .available([home.path, home.path])
        settings.codexActiveSource = .profileHome(path: home.path)
        #expect(settings.codexProfileHomePaths == [home.path])
        #expect(settings.codexVisibleAccounts.map(\.email) == ["fleet@example.com"])
        #expect(settings.codexResolvedActiveSource == .profileHome(path: home.path))
        try configStore.save(settings.configSnapshot)

        let failures: [CodexFleetProfileDiscovery.Result] = [
            .missing,
            .unavailable("Fleet binding is invalid"),
            .unavailable("Fleet binding cannot be read safely"),
            .available([]),
        ]
        for failure in failures {
            let restarted = Self.makeSettings(defaults: defaults, configStore: configStore)
            restarted._test_codexFleetProfileDiscovery = failure
            #expect(restarted.codexProfileHomePaths.isEmpty)
            #expect(restarted.codexResolvedActiveSource == .profileHome(path: home.path))
            #expect(!restarted.persistResolvedCodexActiveSourceCorrectionIfNeeded())
            #expect(restarted.codexSettingsSnapshot(tokenOverride: nil).profileAccountTargetUnavailable)
            #expect(restarted.codexAccountReconciliationSnapshot.liveSystemAccount == nil)
            let environment = ProviderRegistry.makeEnvironment(
                base: ["CODEX_HOME": root.appendingPathComponent("ambient").path],
                provider: .codex,
                settings: restarted,
                tokenOverride: nil)
            #expect(environment["CODEX_HOME"] == home.path)

            restarted._test_codexFleetProfileDiscovery = .available([home.path])
            #expect(!restarted.codexSettingsSnapshot(tokenOverride: nil).profileAccountTargetUnavailable)
            #expect(restarted.codexVisibleAccounts.map(\.email) == ["fleet@example.com"])
            #expect(restarted.codexActiveSource == .profileHome(path: home.path))
        }
    }

    @Test
    @MainActor
    func `discovery loss invalidates cached authorization without caching fleet paths`() throws {
        let root = CodexCredentialFixtures.root
        let home = root.appendingPathComponent("cached-profile", isDirectory: true)
        try Self.writeAuth(home: home, email: "cached@example.com", accountID: "acct-cached")
        let defaultsName = "CodexFleetProfileIntegrationTests-cache-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let settings = Self.makeSettings(
            defaults: defaults,
            configStore: CodexBarConfigStore(fileURL: root.appendingPathComponent("config.json")))
        let previousInterval = SettingsStore.codexAccountReconciliationSnapshotCacheIntervalOverrideForTesting
        SettingsStore.codexAccountReconciliationSnapshotCacheIntervalOverrideForTesting = 60
        defer { SettingsStore.codexAccountReconciliationSnapshotCacheIntervalOverrideForTesting = previousInterval }
        settings._test_codexFleetProfileDiscovery = .available([home.path])
        settings.codexActiveSource = .profileHome(path: home.path)
        _ = settings.codexAccountReconciliationSnapshot
        #expect(settings.cachedCodexAccountReconciliationSnapshot != nil)
        settings._test_codexFleetProfileDiscovery = .missing
        #expect(settings.cachedCodexAccountReconciliationSnapshot != nil)
        #expect(settings.codexSettingsSnapshot(tokenOverride: nil).profileAccountTargetUnavailable)
        #expect(settings.codexAccountReconciliationSnapshot.profileHomePaths.isEmpty)
    }

    @Test
    @MainActor
    func `explicit homes retain authorization and deduplicate discovered homes`() throws {
        let root = CodexCredentialFixtures.root
        let home = root.appendingPathComponent("explicit", isDirectory: true)
        try Self.writeAuth(home: home, email: "explicit@example.com", accountID: "acct-explicit")
        let defaultsName = "CodexFleetProfileIntegrationTests-explicit-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let settings = Self.makeSettings(
            defaults: defaults,
            configStore: CodexBarConfigStore(fileURL: root.appendingPathComponent("config.json")))
        settings.updateProviderConfig(provider: .codex) { entry in
            entry.codexProfileHomePaths = [home.path, home.path]
        }
        settings._test_codexFleetProfileDiscovery = .available([home.path])
        settings.codexActiveSource = .profileHome(path: home.path)
        #expect(settings.codexProfileHomePaths == [home.path])
        settings._test_codexFleetProfileDiscovery = .unavailable("Fleet binding is invalid")
        #expect(!settings.codexSettingsSnapshot(tokenOverride: nil).profileAccountTargetUnavailable)
        #expect(settings.codexVisibleAccounts.map(\.email) == ["explicit@example.com"])
    }

    @Test
    func `unavailable selection keeps live recovery when managed storage is unreadable`() {
        let root = CodexCredentialFixtures.root
        let removed = root.appendingPathComponent("removed").path
        let live = ObservedSystemCodexAccount(
            email: "recovery@example.com",
            codexHomePath: root.appendingPathComponent("ambient").path,
            observedAt: Date())
        let snapshot = DefaultCodexAccountReconciler(
            storeLoader: { throw FileManagedCodexAccountStoreError.unsupportedVersion(999) },
            systemObserver: RecoverySystemObservation(account: live),
            activeSource: .profileHome(path: removed),
            baseEnvironment: ["CODEX_HOME": live.codexHomePath])
            .loadSnapshot()
        let projection = CodexVisibleAccountProjection.make(from: snapshot)
        #expect(snapshot.hasUnreadableAddedAccountStore)
        #expect(snapshot.profileHomeAccounts.isEmpty)
        #expect(projection.visibleAccounts.map(\.email) == [live.email])
        #expect(projection.activeVisibleAccountID == nil)
        #expect(projection.showsAccountSelection)
        #expect(CodexActiveSourceResolver.resolve(from: snapshot).resolvedSource == .profileHome(path: removed))
    }

    @Test
    func `fleet profile remains visible and active when ambient and managed homes match`() {
        let home = CodexCredentialFixtures.root.appendingPathComponent("same-home").path
        let account = ObservedSystemCodexAccount(
            email: "fleet@example.com",
            workspaceAccountID: "acct-fleet",
            authFingerprint: "fleet-fingerprint",
            codexHomePath: home,
            observedAt: Date(),
            identity: .providerAccount(id: "acct-fleet"))
        let managed = ManagedCodexAccount(
            id: UUID(),
            email: account.email,
            providerAccountID: "acct-fleet",
            managedHomePath: home,
            createdAt: 1,
            updatedAt: 2,
            lastAuthenticatedAt: nil)
        let snapshot = CodexAccountReconciliationSnapshot(
            storedAccounts: [managed],
            activeStoredAccount: nil,
            liveSystemAccount: account,
            profileHomeAccounts: [account],
            profileHomePaths: [home],
            fleetProfileHomePaths: [home],
            matchingStoredAccountForLiveSystemAccount: managed,
            activeSource: .profileHome(path: home),
            hasUnreadableAddedAccountStore: false)
        #expect(CodexActiveSourceResolver.resolve(from: snapshot).resolvedSource == .profileHome(path: home))
        #expect(!CodexActiveSourceResolver.resolve(from: snapshot).requiresPersistenceCorrection)
        let projection = CodexVisibleAccountProjection.make(from: snapshot)
        #expect(projection.visibleAccounts.count == 1)
        #expect(projection.visibleAccounts.first?.selectionSource == .profileHome(path: home))
        #expect(projection.visibleAccounts.first?.isActive == true)
        #expect(projection.activeVisibleAccountID == projection.visibleAccounts.first?.id)
    }

    @Test
    func `verified fleet profile replaces exact managed selection and missing-auth duplicate`() {
        let root = CodexCredentialFixtures.root
        let home = root.appendingPathComponent("fleet").path
        let stale = ManagedCodexAccount(
            id: UUID(),
            email: "fleet@example.com",
            providerAccountID: "acct-fleet",
            managedHomePath: root.appendingPathComponent("stale-managed").path,
            createdAt: 1,
            updatedAt: 2,
            lastAuthenticatedAt: nil)
        let otherWorkspace = ManagedCodexAccount(
            id: UUID(),
            email: stale.email,
            providerAccountID: "acct-other",
            managedHomePath: root.appendingPathComponent("other-managed").path,
            createdAt: 1,
            updatedAt: 2,
            lastAuthenticatedAt: nil)
        let profile = ObservedSystemCodexAccount(
            email: stale.email,
            workspaceAccountID: "acct-fleet",
            authFingerprint: "fleet-fingerprint",
            codexHomePath: home,
            observedAt: Date(),
            identity: .providerAccount(id: "acct-fleet"))
        for source in [CodexActiveSource.profileHome(path: home), .managedAccount(id: stale.id)] {
            let snapshot = CodexAccountReconciliationSnapshot(
                storedAccounts: [stale, otherWorkspace],
                activeStoredAccount: source == .managedAccount(id: stale.id) ? stale : nil,
                liveSystemAccount: nil,
                profileHomeAccounts: [profile],
                profileHomePaths: [home],
                fleetProfileHomePaths: [home],
                matchingStoredAccountForLiveSystemAccount: nil,
                activeSource: source,
                hasUnreadableAddedAccountStore: false)
            let projection = CodexVisibleAccountProjection.make(from: snapshot)
            #expect(projection.visibleAccounts.contains { $0.selectionSource == .profileHome(path: home) })
            #expect(projection.visibleAccounts.contains { $0.storedAccountID == otherWorkspace.id })
            let staleRow = projection.visibleAccounts.first { $0.storedAccountID == stale.id }
            #expect(staleRow == nil)
            #expect(projection.visibleAccounts.count == 2)
            #expect(projection.visibleAccounts.first { $0.isActive }?.selectionSource == .profileHome(path: home))
            let resolution = CodexActiveSourceResolver.resolve(from: snapshot)
            #expect(resolution.resolvedSource == .profileHome(path: home))
            #expect(resolution.requiresPersistenceCorrection == (source == .managedAccount(id: stale.id)))
        }
    }

    @Test
    @MainActor
    func `exact fleet authority preference persists the existing managed selection correction`() throws {
        let root = CodexCredentialFixtures.root
        let home = root.appendingPathComponent("preferred-fleet", isDirectory: true)
        try Self.writeAuth(home: home, email: "fleet@example.com", accountID: "acct-fleet")
        let defaultsName = "CodexFleetProfileIntegrationTests-preference-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let settings = Self.makeSettings(
            defaults: defaults,
            configStore: CodexBarConfigStore(fileURL: root.appendingPathComponent("config.json")))
        for fingerprint in [nil, "historical-managed-fingerprint"] {
            let managed = ManagedCodexAccount(
                id: UUID(),
                email: "Fleet@Example.com",
                providerAccountID: "acct-fleet",
                authFingerprint: fingerprint,
                managedHomePath: root.appendingPathComponent("managed-copy").path,
                createdAt: 1,
                updatedAt: 2,
                lastAuthenticatedAt: nil)
            settings._test_activeManagedCodexAccount = managed
            settings._test_codexFleetProfileDiscovery = .available([home.path])
            settings.codexActiveSource = .managedAccount(id: managed.id)
            #expect(settings.codexResolvedActiveSource == .profileHome(path: home.path))
            #expect(settings.persistResolvedCodexActiveSourceCorrectionIfNeeded())
            #expect(settings.codexActiveSource == .profileHome(path: home.path))
            #expect(settings.codexVisibleAccounts.first { $0.isActive }?
                .selectionSource == .profileHome(path: home.path))
        }
    }

    @Test
    func `fleet authority preference refuses mismatches unknown identities and ambiguous homes`() {
        let root = CodexCredentialFixtures.root
        let home = root.appendingPathComponent("fleet").path
        let otherHome = root.appendingPathComponent("other-fleet").path
        struct IdentityCase {
            let managedID: String?
            let managedEmail: String
            let profileID: String?
            let profileEmail: String
            let ambiguous: Bool
        }
        let cases = [
            IdentityCase(
                managedID: "acct-managed",
                managedEmail: "managed@example.com",
                profileID: "acct-other",
                profileEmail: "managed@example.com",
                ambiguous: false),
            IdentityCase(
                managedID: "acct-managed",
                managedEmail: "managed@example.com",
                profileID: "acct-managed",
                profileEmail: "other@example.com",
                ambiguous: false),
            IdentityCase(
                managedID: nil,
                managedEmail: "managed@example.com",
                profileID: nil,
                profileEmail: "managed@example.com",
                ambiguous: false),
            IdentityCase(
                managedID: "acct-managed",
                managedEmail: "managed@example.com",
                profileID: nil,
                profileEmail: "managed@example.com",
                ambiguous: false),
            IdentityCase(
                managedID: "acct-managed",
                managedEmail: "managed@example.com",
                profileID: "acct-managed",
                profileEmail: "managed@example.com",
                ambiguous: true),
        ]
        for fixture in cases {
            let managedID = fixture.managedID
            let managedEmail = fixture.managedEmail
            let profileID = fixture.profileID
            let profileEmail = fixture.profileEmail
            let ambiguous = fixture.ambiguous
            let managed = ManagedCodexAccount(
                id: UUID(),
                email: managedEmail,
                providerAccountID: managedID,
                managedHomePath: root.appendingPathComponent("managed").path,
                createdAt: 1,
                updatedAt: 2,
                lastAuthenticatedAt: nil)
            let profiles = (ambiguous ? [home, otherHome] : [home]).map { path in
                ObservedSystemCodexAccount(
                    email: profileEmail,
                    workspaceAccountID: profileID,
                    authFingerprint: "fixture-fingerprint",
                    codexHomePath: path,
                    observedAt: Date(),
                    identity: profileID.map { .providerAccount(id: $0) } ?? .emailOnly(normalizedEmail: profileEmail))
            }
            let source = CodexActiveSource.managedAccount(id: managed.id)
            let snapshot = CodexAccountReconciliationSnapshot(
                storedAccounts: [managed],
                activeStoredAccount: managed,
                liveSystemAccount: nil,
                profileHomeAccounts: profiles,
                profileHomePaths: profiles.map(\.codexHomePath),
                fleetProfileHomePaths: profiles.map(\.codexHomePath),
                matchingStoredAccountForLiveSystemAccount: nil,
                activeSource: source,
                hasUnreadableAddedAccountStore: false)
            let resolution = CodexActiveSourceResolver.resolve(from: snapshot)
            #expect(resolution.resolvedSource == source)
            #expect(!resolution.requiresPersistenceCorrection)
            #expect(CodexVisibleAccountProjection.make(from: snapshot).visibleAccounts.contains {
                $0.selectionSource == source && $0.isActive
            })
        }
    }

    @Test
    func `unavailable selection blocks OAuth and CLI before credential access or process launch`() async {
        let environment = ["CODEX_HOME": CodexCredentialFixtures.root.appendingPathComponent("removed").path]
        let browserDetection = BrowserDetection(cacheTTL: 0)
        let context = ProviderFetchContext(
            runtime: .app,
            sourceMode: .oauth,
            includeCredits: false,
            webTimeout: 60,
            webDebugDumpHTML: false,
            verbose: false,
            env: environment,
            settings: .make(codex: CodexProviderSettings(
                usageDataSource: .oauth,
                cookieSource: .off,
                manualCookieHeader: nil,
                profileAccountTargetUnavailable: true)),
            fetcher: UsageFetcher(environment: environment),
            claudeFetcher: ClaudeUsageFetcher(browserDetection: browserDetection),
            browserDetection: browserDetection)
        let access = UnavailableProfileAccessProbe()
        let ioOverride: @Sendable (CodexCredentialFileAccess.Operation, URL) throws -> Data = { _, _ in
            access.recordIO()
            return Data()
        }
        await CodexCredentialFileAccess.$testIO.withValue(ioOverride) {
            let nativeRefresh = CodexOAuthNativeRefreshCLIStrategy(binaryResolver: { _ in
                access.recordLaunch()
                Issue.record("Unavailable selection must not resolve or launch the CLI")
                return nil
            })
            #expect(await !CodexOAuthFetchStrategy().isAvailable(context))
            #expect(await !CodexCLIUsageStrategy().isAvailable(context))
            #expect(await !nativeRefresh.isAvailable(context))
            await #expect(throws: CodexProfileSelectionError.self) {
                _ = try await CodexOAuthFetchStrategy().fetch(context)
            }
            await #expect(throws: CodexProfileSelectionError.self) {
                _ = try await CodexCLIUsageStrategy().fetch(context)
            }
            await #expect(throws: CodexProfileSelectionError.self) {
                _ = try await nativeRefresh.fetch(context)
            }
            let outcome = await CodexProviderDescriptor.descriptor.fetchPlan.fetchOutcome(
                context: context,
                provider: .codex)
            #expect(outcome.attempts.map(\.strategyID) == ["codex.profile-unavailable"])
            guard case let .failure(error) = outcome.result else {
                Issue.record("Unavailable profile must fail through the existing error state")
                return
            }
            #expect(error is CodexProfileSelectionError)
            #expect(error.localizedDescription.contains("unavailable or removed"))
        }
        #expect(access.ioCount == 0)
        #expect(access.launchCount == 0)
    }

    @Test
    func `CLI discovers scoped profiles and preserves unavailable selections`() throws {
        let root = CodexCredentialFixtures.root
        let home = root.appendingPathComponent("cli-profile", isDirectory: true)
        try Self.writeAuth(home: home, email: "cli@example.com", accountID: "acct-cli")
        var provider = ProviderConfig(id: .codex)
        provider.codexActiveSource = .profileHome(path: home.path)
        let config = CodexBarConfig(providers: [provider])
        let environment = ["CODEX_HOME": root.appendingPathComponent("ambient").path]
        let results: [CodexFleetProfileDiscovery.Result] = [.available([home.path]), .missing]
        for result in results {
            let context = try TokenAccountCLIContext(
                selection: TokenAccountCLISelection(label: nil, index: nil, allAccounts: false),
                config: config,
                verbose: false,
                baseEnvironment: environment,
                managedCodexAccountStoreURL: root.appendingPathComponent("managed.json"),
                codexFleetProfileDiscovery: { result })
            let scoped = context.environment(base: environment, provider: .codex, account: nil)
            #expect(scoped["CODEX_HOME"] == home.path)
            let settings = try #require(context.settingsSnapshot(for: .codex, account: nil)?.codex)
            if case .missing = result {
                #expect(settings.profileAccountTargetUnavailable)
            } else {
                #expect(!settings.profileAccountTargetUnavailable)
            }
            #expect(settings.openAIWebCacheScope == .profileHome(home.path))
        }
    }

    @MainActor
    private static func makeSettings(defaults: UserDefaults, configStore: CodexBarConfigStore) -> SettingsStore {
        defaults.set(true, forKey: "providerDetectionCompleted")
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: configStore)
        settings._test_codexReconciliationEnvironment = [
            "CODEX_HOME": CodexCredentialFixtures.root.appendingPathComponent("ambient").path,
        ]
        return settings
    }

    private static func writeAuth(home: URL, email: String, accountID: String) throws {
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let payload = try JSONSerialization.data(withJSONObject: [
            "email": email,
            "https://api.openai.com/auth": ["chatgpt_account_id": accountID],
        ])
        let encoded = payload.base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        let data = try JSONSerialization.data(withJSONObject: ["tokens": [
            "access_token": "fixture-access",
            "refresh_token": "fixture-refresh",
            "id_token": "e30.\(encoded).",
            "account_id": accountID,
        ]])
        try data.write(to: home.appendingPathComponent("auth.json"))
    }

    private struct RecoverySystemObservation: CodexSystemAccountObserving {
        let account: ObservedSystemCodexAccount

        func loadSystemAccount(environment _: [String: String]) throws -> ObservedSystemCodexAccount? {
            self.account
        }
    }
}

private final class UnavailableProfileAccessProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var io = 0
    private var launches = 0

    var ioCount: Int {
        self.lock.withLock { self.io }
    }

    var launchCount: Int {
        self.lock.withLock { self.launches }
    }

    func recordIO() {
        self.lock.withLock { self.io += 1 }
    }

    func recordLaunch() {
        self.lock.withLock { self.launches += 1 }
    }
}
