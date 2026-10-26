import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct CodexSelectedAccountCacheTests {
    @Test
    func `selection hydrates the cached owner synchronously with its original timestamp`() throws {
        let fixture = self.fixture()
        let accounts = fixture.settings.codexVisibleAccountProjection.visibleAccounts
        let first = try #require(accounts.first)
        let second = try #require(accounts.last)
        fixture.store.lastCodexAccountScopedRefreshGuard = UsageStore.codexScopedRefreshGuard(for: first)
        fixture.store.codexAccountSnapshots = accounts.map(self.cachedRow)
        fixture.store.snapshots[.codex] = self.usage(email: first.email)
        fixture.settings.codexActiveSource = second.selectionSource

        #expect(fixture.store.prepareCodexAccountScopedRefreshIfNeeded())

        #expect(fixture.store.snapshots[.codex]?.accountEmail(for: .codex) == second.email)
        #expect(fixture.store.snapshots[.codex]?.updatedAt == Self.cachedAt)
        #expect(fixture.store.lastSourceLabels[.codex] == "cached")
        #expect(fixture.store.codexAccountSnapshots.count == 2)
        #expect(fixture.store.lastCodexUsagePublicationGuard?.source == second.selectionSource)
    }

    @Test
    func `hydration uses supplied projection evidence without loading account state`() throws {
        let fixture = self.fixture()
        let projection = fixture.settings.codexVisibleAccountProjection
        let active = try #require(projection.visibleAccounts.first { $0.isActive })
        fixture.store.codexAccountSnapshots = projection.visibleAccounts.map(self.cachedRow)
        let calls = fixture.loader.calls

        let hydrated = fixture.store.hydrateSelectedCodexAccountSnapshot(
            expectedGuard: UsageStore.codexScopedRefreshGuard(for: active), projection: projection)

        #expect(hydrated?.id == active.id)
        #expect(fixture.loader.calls == calls)
    }

    @Test
    func `cached rows from removed or changed owners are pruned before hydration`() throws {
        let fixture = self.fixture()
        let projection = fixture.settings.codexVisibleAccountProjection
        let active = try #require(projection.visibleAccounts.first { $0.isActive })
        let sibling = try #require(projection.visibleAccounts.first { !$0.isActive })
        let wrongWorkspace = self.replacingIdentity(of: active, workspace: "other-workspace")
        let removed = CodexVisibleAccount(
            id: "removed",
            email: "removed@example.test",
            workspaceAccountID: "removed-workspace",
            storedAccountID: nil,
            selectionSource: .profileHome(path: "/fixture/removed"),
            isActive: false,
            isLive: false,
            canReauthenticate: false,
            canRemove: false)
        fixture.store.codexAccountSnapshots = [wrongWorkspace, sibling, removed].map(self.cachedRow)

        #expect(fixture.store.hydrateSelectedCodexAccountSnapshot(
            expectedGuard: UsageStore.codexScopedRefreshGuard(for: active), projection: projection) == nil)
        #expect(fixture.store.snapshots[.codex] == nil)
        #expect(fixture.store.codexAccountSnapshots.map(\.id) == [sibling.id])

        fixture.store.codexAccountSnapshots = [self.cachedRow(self.replacingIdentity(
            of: active,
            fingerprint: "changed"))]
        #expect(fixture.store.hydrateSelectedCodexAccountSnapshot(
            expectedGuard: UsageStore.codexScopedRefreshGuard(for: active), projection: projection) == nil)
        #expect(fixture.store.codexAccountSnapshots.isEmpty)
    }

    @Test
    func `ambiguous cached rows never hydrate selected usage`() throws {
        let fixture = self.fixture()
        let projection = fixture.settings.codexVisibleAccountProjection
        let active = try #require(projection.visibleAccounts.first { $0.isActive })
        fixture.store.codexAccountSnapshots = [self.cachedRow(active), self.cachedRow(active)]

        #expect(fixture.store.hydrateSelectedCodexAccountSnapshot(
            expectedGuard: UsageStore.codexScopedRefreshGuard(for: active), projection: projection) == nil)
        #expect(fixture.store.snapshots[.codex] == nil)
    }

    @Test
    func `segmented success persists updated selected row and untouched sibling`() async throws {
        let fixture = self.fixture()
        let accounts = fixture.settings.codexVisibleAccountProjection.visibleAccounts
        let active = try #require(accounts.first { $0.isActive })
        let sibling = try #require(accounts.first { !$0.isActive })
        fixture.store.codexAccountSnapshots = accounts.map(self.cachedRow)
        let fresh = self.usage(email: active.email, usedPercent: 35, updatedAt: Self.cachedAt.addingTimeInterval(60))
        self.installProvider(on: fixture.store) { fresh }

        await fixture.store.refreshProvider(.codex, allowDisabled: true)

        #expect(Set(fixture.store.codexAccountSnapshots.map(\.id)) == Set(accounts.map(\.id)))
        #expect(fixture.store.codexAccountSnapshots.first { $0.id == active.id }?.snapshot?.updatedAt == fresh
            .updatedAt)
        #expect(fixture.store.codexAccountSnapshots.first { $0.id == sibling.id }?.snapshot?.updatedAt == Self.cachedAt)
        #expect(Set(fixture.persistence.storedSnapshots.map(\.id)) == Set(accounts.map(\.id)))
        fixture.settings.codexActiveSource = sibling.selectionSource
        #expect(fixture.store.prepareCodexAccountScopedRefreshIfNeeded())
        #expect(fixture.store.snapshots[.codex]?.updatedAt == Self.cachedAt)
        #expect(fixture.store.snapshots[.codex]?.accountEmail(for: .codex) == sibling.email)
    }

    @Test
    func `segmented transient failure keeps cached usage and its timestamp`() async throws {
        let fixture = self.fixture()
        let accounts = fixture.settings.codexVisibleAccountProjection.visibleAccounts
        let active = try #require(accounts.first { $0.isActive })
        fixture.store.codexAccountSnapshots = accounts.map(self.cachedRow)
        self.installProvider(on: fixture.store) { throw CacheFailure.offline }

        await fixture.store.refreshProvider(.codex, allowDisabled: true)

        let row = try #require(fixture.store.codexAccountSnapshots.first { $0.id == active.id })
        #expect(row.snapshot?.updatedAt == Self.cachedAt)
        #expect(row.error == CacheFailure.offline.localizedDescription)
        #expect(fixture.store.codexAccountSnapshots.count == 2)
    }

    @Test
    func `authentication failure cannot resurrect rejected cached usage after reselection`() async throws {
        let fixture = self.fixture()
        let accounts = fixture.settings.codexVisibleAccountProjection.visibleAccounts
        let active = try #require(accounts.first { $0.isActive })
        let sibling = try #require(accounts.first { !$0.isActive })
        fixture.store.codexAccountSnapshots = accounts.map(self.cachedRow)
        self.installProvider(on: fixture.store) { throw CacheFailure.unauthorized }

        await fixture.store.refreshProvider(.codex, allowDisabled: true)

        let failed = try #require(fixture.store.codexAccountSnapshots.first { $0.id == active.id })
        #expect(failed.snapshot == nil)
        #expect(failed.error == CacheFailure.unauthorized.localizedDescription)
        #expect(fixture.persistence.storedSnapshots.first { $0.id == active.id }?.snapshot == nil)
        fixture.settings.codexActiveSource = sibling.selectionSource
        fixture.store.prepareCodexAccountScopedRefreshIfNeeded()
        #expect(fixture.store.snapshots[.codex]?.accountEmail(for: .codex) == sibling.email)
        fixture.settings.codexActiveSource = active.selectionSource
        fixture.store.prepareCodexAccountScopedRefreshIfNeeded()
        #expect(fixture.store.snapshots[.codex] == nil)
    }

    @Test
    func `cancelled segmented fetch retains every cached account`() async {
        let fixture = self.fixture()
        let accounts = fixture.settings.codexVisibleAccountProjection.visibleAccounts
        fixture.store.codexAccountSnapshots = accounts.map(self.cachedRow)
        self.installProvider(on: fixture.store) { throw CancellationError() }

        await fixture.store.refreshProvider(.codex, allowDisabled: true)

        #expect(Set(fixture.store.codexAccountSnapshots.map(\.id)) == Set(accounts.map(\.id)))
        #expect(fixture.store.codexAccountSnapshots
            .allSatisfy { $0.snapshot?.updatedAt == Self.cachedAt && $0.error == nil })
    }

    private static let cachedAt = Date(timeIntervalSince1970: 1_782_000_000)

    private func usage(email: String, usedPercent: Double = 20, updatedAt: Date? = nil) -> UsageSnapshot {
        UsageSnapshot(
            primary: RateWindow(usedPercent: usedPercent, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: updatedAt ?? Self.cachedAt,
            identity: ProviderIdentitySnapshot(
                providerID: .codex, accountEmail: email, accountOrganization: nil, loginMethod: "fixture"))
    }

    private func cachedRow(_ account: CodexVisibleAccount) -> CodexAccountUsageSnapshot {
        CodexAccountUsageSnapshot(
            account: account, snapshot: self.usage(email: account.email), error: nil, sourceLabel: "cached")
    }

    private func replacingIdentity(
        of account: CodexVisibleAccount, workspace: String? = nil, fingerprint: String? = nil) -> CodexVisibleAccount
    {
        CodexVisibleAccount(
            id: account.id,
            email: account.email,
            workspaceAccountID: workspace ?? account.workspaceAccountID,
            authFingerprint: fingerprint ?? account.authFingerprint,
            storedAccountID: account.storedAccountID,
            selectionSource: account.selectionSource,
            isActive: account.isActive,
            isLive: account.isLive,
            canReauthenticate: false,
            canRemove: false)
    }

    private func installProvider(on store: UsageStore, loader: @escaping @Sendable () async throws -> UsageSnapshot) {
        store.providerSpecs[.codex] = CodexAccountScopedRefreshTests.makeCodexProviderSpec(
            baseSpec: store.providerSpecs[.codex]!, loader: loader)
    }

    private func fixture() -> Fixture {
        let root = TestFixtureScratch.root.appendingPathComponent("CodexSelectedAccountCacheTests-\(UUID().uuidString)")
        let profiles = ["north", "south"].map { alias in
            ObservedSystemCodexAccount(
                email: "\(alias)@example.test",
                workspaceAccountID: "workspace-\(alias)",
                authFingerprint: "fingerprint-\(alias)",
                codexHomePath: root.appendingPathComponent(alias).path,
                observedAt: Self.cachedAt,
                identity: .providerAccount(id: "workspace-\(alias)"))
        }
        let loader = CacheAccountSnapshotLoader(profiles: profiles)
        let settings = SettingsStore(
            userDefaults: InMemoryUserDefaults(),
            configStore: testConfigStore(suiteName: "CodexSelectedAccountCacheTests-\(UUID().uuidString)"),
            codexCookieStore: InMemoryCookieHeaderStore(),
            claudeCookieStore: InMemoryCookieHeaderStore(),
            tokenAccountStore: InMemoryTokenAccountStore(),
            keychainAccessPolicy: SettingsStoreKeychainAccessPolicy(
                setDisabled: { _ in }, isExplicitlyDisabled: { true }),
            performInitialProviderDetection: false)
        settings.configFileWatcher?.stop()
        settings._test_codexAccountSnapshotLoader = { loader.load(source: $0) }
        settings.updateProviderConfig(provider: .codex) { $0.codexProfileHomePaths = profiles.map(\.codexHomePath) }
        settings.codexActiveSource = .profileHome(path: profiles[0].codexHomePath)
        settings.codexUsageDataSource = .oauth
        settings.codexCookieSource = .off
        settings.multiAccountMenuLayout = .segmented
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        let environment = ["HOME": root.path, "CODEX_HOME": root.appendingPathComponent("unused").path]
        let persistence = RecordingCodexAccountUsageSnapshotStore(initialSnapshots: [])
        let store = UsageStore(
            fetcher: UsageFetcher(environment: environment),
            browserDetection: BrowserDetection(homeDirectory: root.path, cacheTTL: 0),
            settings: settings,
            codexAccountUsageSnapshotStore: persistence,
            startupBehavior: .testing,
            environmentBase: environment)
        store._test_codexResetCreditsFetcherOverride = { _ in nil }
        store._test_widgetSnapshotSaveOverride = { _ in }
        return Fixture(settings: settings, store: store, persistence: persistence, loader: loader)
    }

    private struct Fixture {
        let settings: SettingsStore
        let store: UsageStore
        let persistence: RecordingCodexAccountUsageSnapshotStore
        let loader: CacheAccountSnapshotLoader
    }
}

private enum CacheFailure: LocalizedError {
    case offline
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .offline: "Network connection was lost"
        case .unauthorized: "Authentication failed"
        }
    }
}

private final class CacheAccountSnapshotLoader: @unchecked Sendable {
    private let profiles: [ObservedSystemCodexAccount]
    private let lock = NSLock()
    private var count = 0

    init(profiles: [ObservedSystemCodexAccount]) {
        self.profiles = profiles
    }

    var calls: Int {
        self.lock.withLock { self.count }
    }

    func load(source: CodexActiveSource) -> CodexAccountReconciliationSnapshot {
        self.lock.withLock { self.count += 1 }
        return CodexAccountReconciliationSnapshot(
            storedAccounts: [],
            activeStoredAccount: nil,
            liveSystemAccount: nil,
            profileHomeAccounts: self.profiles,
            matchingStoredAccountForLiveSystemAccount: nil,
            activeSource: source,
            hasUnreadableAddedAccountStore: false)
    }
}
