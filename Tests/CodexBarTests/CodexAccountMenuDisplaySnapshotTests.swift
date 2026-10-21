import AppKit
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite(.serialized)
@MainActor
struct CodexAccountMenuDisplaySnapshotTests {
    private func makeSettings() -> SettingsStore {
        let suite = "CodexAccountMenuDisplaySnapshotTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(true, forKey: "providerDetectionCompleted")
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.providerDetectionCompleted = true
        return settings
    }

    private func enableOnlyCodex(_ settings: SettingsStore) {
        for provider in UsageProvider.allCases {
            guard let metadata = ProviderRegistry.shared.metadata[provider] else { continue }
            settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: provider == .codex)
        }
    }

    private func liveSnapshot(email: String) -> CodexAccountReconciliationSnapshot {
        CodexAccountReconciliationSnapshot(
            storedAccounts: [],
            activeStoredAccount: nil,
            liveSystemAccount: ObservedSystemCodexAccount(
                email: email,
                codexHomePath: "/tmp/\(email)",
                observedAt: Date()),
            matchingStoredAccountForLiveSystemAccount: nil,
            activeSource: .liveSystem,
            hasUnreadableAddedAccountStore: false)
    }

    private func cachedProjection(
        snapshot: CodexAccountReconciliationSnapshot,
        loadedAt: Date = Date(timeIntervalSinceNow: -3600)) -> CachedCodexAccountMenuProjection
    {
        CachedCodexAccountMenuProjection(
            activeSource: snapshot.activeSource,
            loadedAt: loadedAt,
            projection: CodexVisibleAccountProjection.make(from: snapshot))
    }

    private func rosterAccount(
        _ id: String,
        source: CodexActiveSource,
        alias: String? = nil) -> CodexVisibleAccount
    {
        CodexVisibleAccount(
            id: id,
            email: "",
            storedAccountID: nil,
            selectionSource: source,
            isActive: false,
            isLive: source == .liveSystem,
            canReauthenticate: false,
            canRemove: false,
            fleetProfileAlias: alias)
    }

    @Test(arguments: [false, true])
    func `fleet menu admits only unique enrolled roster homes without requiring account identity`(
        reversed: Bool) throws
    {
        let aliases = JonesAccountAggregate.codexAliases
        let named = aliases.map {
            self.rosterAccount($0, source: .profileHome(path: "/fixture/fleet/\($0)"), alias: $0)
        }
        let managedID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let excluded = [
            self.rosterAccount("live", source: .liveSystem),
            self.rosterAccount("managed", source: .managedAccount(id: managedID), alias: "malcolm"),
            self.rosterAccount("default", source: .profileHome(path: "/fixture/fleet/default"), alias: "default"),
            self.rosterAccount("hash", source: .profileHome(path: "/fixture/other")),
            self.rosterAccount("extra", source: .profileHome(path: "/fixture/fleet/extra"), alias: "extra"),
            self.rosterAccount("spoof", source: .profileHome(path: "/fixture/unregistered/jace"), alias: "jace"),
        ]
        let accounts = named + excluded
        let paths = aliases.map { "/fixture/fleet/\($0)/." } + ["/fixture/fleet/extra", "/fixture/fleet/default"]
        for active in excluded {
            let projection = CodexVisibleAccountProjection(
                visibleAccounts: reversed ? Array(accounts.reversed()) : accounts,
                activeVisibleAccountID: active.id,
                liveVisibleAccountID: "live",
                hasUnreadableAddedAccountStore: true,
                fleetProfileHomePaths: reversed ? Array(paths.reversed()) : paths)
            #expect(Set(projection.menuAccounts.map(\.id)) == Set(aliases))
            #expect(projection.menuAccounts.count == 5)
            #expect(projection.menuActiveAccount == nil)
            #expect(projection.omitsSummary)
            #expect(projection.visibleAccounts.count == accounts.count)
            #expect(projection.activeVisibleAccountID == active.id)
            #expect(projection.source(forVisibleAccountID: active.id) == active.selectionSource)
        }
    }

    @Test
    func `fleet menu rejects ambiguous enrollment and duplicate profile homes`() {
        let accounts = [
            self.rosterAccount("malcolm", source: .profileHome(path: "/fixture/fleet/malcolm")),
            self.rosterAccount("jace", source: .profileHome(path: "/fixture/fleet/jace")),
            self.rosterAccount("jace-duplicate", source: .profileHome(path: "/fixture/fleet/jace/.")),
            self.rosterAccount("umich", source: .profileHome(path: "/fixture/fleet/umich")),
            self.rosterAccount("hash", source: .profileHome(path: "/fixture/other")),
        ]
        let projection = CodexVisibleAccountProjection(
            visibleAccounts: accounts,
            activeVisibleAccountID: "hash",
            liveVisibleAccountID: nil,
            hasUnreadableAddedAccountStore: false,
            fleetProfileHomePaths: [
                "/fixture/fleet/malcolm", "/fixture/second/malcolm",
                "/fixture/fleet/jace", "/fixture/fleet/umich",
            ])
        #expect(projection.menuAccounts.map(\.id) == ["umich"])
        #expect(projection.menuActiveAccount == nil)
    }

    @Test
    func `nonfleet menu retains managed and profile accounts without admitting default or live`() throws {
        let managedID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let projection = CodexVisibleAccountProjection(
            visibleAccounts: [
                self.rosterAccount("managed", source: .managedAccount(id: managedID)),
                self.rosterAccount("profile", source: .profileHome(path: "/fixture/personal")),
                self.rosterAccount("live", source: .liveSystem),
                self.rosterAccount("default", source: .profileHome(path: "/fixture/default"), alias: "default"),
            ],
            activeVisibleAccountID: "managed",
            liveVisibleAccountID: "live",
            hasUnreadableAddedAccountStore: false,
            fleetProfileHomePaths: ["/fixture/default"])
        #expect(projection.menuAccounts.map(\.id) == ["managed", "profile"])
        #expect(projection.menuActiveAccount?.id == "managed")
    }

    @Test(arguments: [MultiAccountMenuLayout.segmented, .stacked])
    func `menu hides sole default recovery account without selecting it or loading auth`(
        layout: MultiAccountMenuLayout)
    {
        let settings = self.makeSettings()
        self.enableOnlyCodex(settings)
        settings.multiAccountMenuLayout = layout
        let source = CodexActiveSource.profileHome(path: "/fixture/removed")
        let snapshot = CodexAccountReconciliationSnapshot(
            storedAccounts: [],
            activeStoredAccount: nil,
            liveSystemAccount: ObservedSystemCodexAccount(
                email: "recovery@example.com", codexHomePath: "/fixture/live", observedAt: Date()),
            matchingStoredAccountForLiveSystemAccount: nil,
            activeSource: source,
            hasUnreadableAddedAccountStore: false)
        let probe = CodexAccountSnapshotLoaderProbe(snapshot: snapshot)
        settings._test_codexAccountSnapshotLoader = { _ in probe.load() }
        defer { settings._test_codexAccountSnapshotLoader = nil }
        settings.codexActiveSource = source
        settings.cachedCodexAccountMenuProjection = self.cachedProjection(snapshot: snapshot, loadedAt: Date())
        let store = UsageStore(
            fetcher: UsageFetcher(), browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: AccountInfo(email: nil, plan: nil),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: .system)
        defer { controller.releaseStatusItemsForTesting() }
        let callsBeforeDisplay = probe.callCount
        #expect(controller.codexAccountMenuDisplay(for: .codex) == nil)
        #expect(settings.codexActiveSource == source)
        #expect(probe.callCount == callsBeforeDisplay)
    }

    @Test
    func `cold menu projection read never loads auth state`() async {
        let settings = self.makeSettings()
        let probe = CodexAccountSnapshotLoaderProbe(snapshot: self.liveSnapshot(email: "loaded@example.com"))
        settings._test_codexAccountSnapshotLoader = { _ in probe.load() }
        defer { settings._test_codexAccountSnapshotLoader = nil }

        #expect(settings.codexVisibleAccountProjectionForMenuDisplay == nil)
        #expect(probe.callCount == 0)

        let result = await settings.revalidateCodexAccountMenuProjection()

        #expect(result == .updated)
        #expect(probe.callCount == 1)
        #expect(probe.loadedOffMainThread)
        #expect(
            settings.codexVisibleAccountProjectionForMenuDisplay?.visibleAccounts.first?.email ==
                "loaded@example.com")
    }

    @Test
    func `override snapshot load preserves persisted account menu projection`() {
        let settings = self.makeSettings()
        let activeSnapshot = self.liveSnapshot(email: "active@example.com")
        settings.cachedCodexAccountMenuProjection = self.cachedProjection(snapshot: activeSnapshot)

        let otherID = UUID()
        let otherAccount = ManagedCodexAccount(
            id: otherID,
            email: "other@example.com",
            managedHomePath: "/tmp/other",
            createdAt: 1,
            updatedAt: 1,
            lastAuthenticatedAt: 1)
        let overrideSnapshot = CodexAccountReconciliationSnapshot(
            storedAccounts: [otherAccount],
            activeStoredAccount: otherAccount,
            liveSystemAccount: nil,
            matchingStoredAccountForLiveSystemAccount: nil,
            activeSource: .managedAccount(id: otherID),
            hasUnreadableAddedAccountStore: false)
        settings._test_codexAccountSnapshotLoader = { _ in overrideSnapshot }
        defer { settings._test_codexAccountSnapshotLoader = nil }

        _ = settings.codexAccountReconciliationSnapshot(activeSourceOverride: .managedAccount(id: otherID))

        #expect(
            settings.codexVisibleAccountProjectionForMenuDisplay?.visibleAccounts.first?.email ==
                "active@example.com")
    }

    @Test
    func `managed account change refreshes account menu projection`() {
        let settings = self.makeSettings()
        let activeSnapshot = self.liveSnapshot(email: "active@example.com")
        settings.cachedCodexAccountMenuProjection = self.cachedProjection(snapshot: activeSnapshot, loadedAt: Date())

        let addedAccount = ManagedCodexAccount(
            id: UUID(),
            email: "added@example.com",
            managedHomePath: "/tmp/added",
            createdAt: 1,
            updatedAt: 1,
            lastAuthenticatedAt: 1)
        let refreshedSnapshot = CodexAccountReconciliationSnapshot(
            storedAccounts: [addedAccount],
            activeStoredAccount: nil,
            liveSystemAccount: activeSnapshot.liveSystemAccount,
            matchingStoredAccountForLiveSystemAccount: nil,
            activeSource: .liveSystem,
            hasUnreadableAddedAccountStore: false)
        settings._test_codexAccountSnapshotLoader = { _ in refreshedSnapshot }
        defer { settings._test_codexAccountSnapshotLoader = nil }

        settings.refreshCodexAccountReconciliationAfterManagedAccountsDidChange()

        #expect(
            settings.codexVisibleAccountProjectionForMenuDisplay?.visibleAccounts.contains {
                $0.email == "added@example.com"
            } == true)
    }

    @Test
    func `stacked menu matches runtime enriched snapshot for legacy managed workspace`() throws {
        let settings = self.makeSettings()
        settings.multiAccountMenuLayout = .stacked
        let legacyID = UUID()
        let siblingID = UUID()
        let legacy = ManagedCodexAccount(
            id: legacyID,
            email: "legacy@example.com",
            workspaceAccountID: nil,
            managedHomePath: "/tmp/legacy",
            createdAt: 1,
            updatedAt: 1,
            lastAuthenticatedAt: 1)
        let sibling = ManagedCodexAccount(
            id: siblingID,
            email: "sibling@example.com",
            workspaceAccountID: "account-sibling",
            managedHomePath: "/tmp/sibling",
            createdAt: 1,
            updatedAt: 1,
            lastAuthenticatedAt: 1)
        let snapshot = CodexAccountReconciliationSnapshot(
            storedAccounts: [legacy, sibling],
            activeStoredAccount: legacy,
            liveSystemAccount: nil,
            matchingStoredAccountForLiveSystemAccount: nil,
            activeSource: .managedAccount(id: legacyID),
            hasUnreadableAddedAccountStore: false,
            storedAccountRuntimeIdentities: [
                legacyID: .providerAccount(id: " Account-Runtime "),
                siblingID: .providerAccount(id: "account-sibling"),
            ])
        let projection = CodexVisibleAccountProjection.make(from: snapshot)
        let legacyProjected = try #require(projection.visibleAccounts.first {
            $0.selectionSource == .managedAccount(id: legacyID)
        })
        let siblingProjected = try #require(projection.visibleAccounts.first {
            $0.selectionSource == .managedAccount(id: siblingID)
        })
        let runtimeEnrichedLegacy = CodexVisibleAccount(
            id: legacyProjected.id,
            email: legacyProjected.email,
            workspaceLabel: legacyProjected.workspaceLabel,
            workspaceAccountID: "account-runtime",
            authFingerprint: legacyProjected.authFingerprint,
            storedAccountID: legacyProjected.storedAccountID,
            selectionSource: legacyProjected.selectionSource,
            isActive: legacyProjected.isActive,
            isLive: legacyProjected.isLive,
            canReauthenticate: legacyProjected.canReauthenticate,
            canRemove: legacyProjected.canRemove)

        settings.codexActiveSource = .managedAccount(id: legacyID)
        settings.cachedCodexAccountMenuProjection = self.cachedProjection(snapshot: snapshot, loadedAt: Date())
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        store.codexAccountSnapshots = [runtimeEnrichedLegacy, siblingProjected].map {
            CodexAccountUsageSnapshot(account: $0, snapshot: nil, error: nil, sourceLabel: "test")
        }
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: AccountInfo(email: nil, plan: nil),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: .system)
        defer { controller.releaseStatusItemsForTesting() }

        let display = try #require(controller.codexAccountMenuDisplay(for: .codex))

        #expect(legacyProjected.workspaceAccountID == "account-runtime")
        #expect(display.snapshots.map(\.id).sorted() == [legacyProjected.id, siblingProjected.id].sorted())
    }

    @Test
    func `stale menu projection returns immediately then refreshes concurrently`() async {
        let settings = self.makeSettings()
        let staleSnapshot = self.liveSnapshot(email: "before@example.com")
        let probe = CodexAccountSnapshotLoaderProbe(snapshot: self.liveSnapshot(email: "after@example.com"))
        settings.cachedCodexAccountMenuProjection = self.cachedProjection(snapshot: staleSnapshot)
        settings._test_codexAccountSnapshotLoader = { _ in probe.load() }
        SettingsStore.codexAccountReconciliationSnapshotCacheIntervalOverrideForTesting = 60
        defer {
            SettingsStore.codexAccountReconciliationSnapshotCacheIntervalOverrideForTesting = nil
            settings._test_codexAccountSnapshotLoader = nil
        }

        #expect(
            settings.codexVisibleAccountProjectionForMenuDisplay?.visibleAccounts.first?.email ==
                "before@example.com")
        #expect(probe.callCount == 0)
        #expect(settings.codexAccountMenuProjectionNeedsRevalidation)

        let result = await settings.revalidateCodexAccountMenuProjection()

        #expect(result == .updated)
        #expect(probe.callCount == 1)
        #expect(probe.loadedOffMainThread)
        #expect(
            settings.codexVisibleAccountProjectionForMenuDisplay?.visibleAccounts.first?.email ==
                "after@example.com")
    }

    @Test
    func `revalidation discards result after reconciliation generation changes`() async {
        let settings = self.makeSettings()
        let staleSnapshot = self.liveSnapshot(email: "before@example.com")
        let probe = CodexAccountSnapshotLoaderProbe(
            snapshot: self.liveSnapshot(email: "discarded@example.com"),
            blocks: true)
        settings.cachedCodexAccountMenuProjection = self.cachedProjection(snapshot: staleSnapshot)
        settings._test_codexAccountSnapshotLoader = { _ in probe.load() }
        SettingsStore.codexAccountReconciliationSnapshotCacheIntervalOverrideForTesting = 60
        defer {
            probe.release()
            SettingsStore.codexAccountReconciliationSnapshotCacheIntervalOverrideForTesting = nil
            settings._test_codexAccountSnapshotLoader = nil
        }

        let task = Task { await settings.revalidateCodexAccountMenuProjection() }
        await probe.waitUntilCalled()
        settings.invalidateCodexAccountReconciliationSnapshotCache()
        probe.release()

        #expect(await task.value == .discarded)
        #expect(
            settings.codexVisibleAccountProjectionForMenuDisplay?.visibleAccounts.first?.email ==
                "before@example.com")
    }

    @Test
    func `fresh menu open coalesces account projection revalidation and identity stays read only`() async throws {
        StatusItemController.menuCardRenderingEnabled = false
        StatusItemController.setMenuRefreshEnabledForTesting(false)
        StatusItemController.setCodexAccountMenuProjectionRevalidationEnabledForTesting(true)
        defer {
            StatusItemController.resetCodexAccountMenuProjectionRevalidationEnabledForTesting()
            StatusItemController.resetMenuRefreshEnabledForTesting()
        }

        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        self.enableOnlyCodex(settings)
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        store._cancelPlanUtilizationHistoryLoadForTesting()
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: AccountInfo(email: nil, plan: nil),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: .system)
        defer { controller.releaseStatusItemsForTesting() }

        let staleSnapshot = self.liveSnapshot(email: "before@example.com")
        let probe = CodexAccountSnapshotLoaderProbe(
            snapshot: self.liveSnapshot(email: "after@example.com"),
            blocks: true)
        settings.cachedCodexAccountMenuProjection = self.cachedProjection(snapshot: staleSnapshot)
        settings._test_codexAccountSnapshotLoader = { _ in probe.load() }
        SettingsStore.codexAccountReconciliationSnapshotCacheIntervalOverrideForTesting = 60
        defer {
            probe.release()
            SettingsStore.codexAccountReconciliationSnapshotCacheIntervalOverrideForTesting = nil
            settings._test_codexAccountSnapshotLoader = nil
        }

        let menu = NSMenu()
        controller.menuProviders[ObjectIdentifier(menu)] = .codex
        controller.markMenuFresh(menu)
        #expect(controller.codexAccountMenuDisplay(for: .codex) == nil)
        #expect(probe.callCount == 0)

        let versionBeforeOpen = controller.menuContentVersion
        controller.menuWillOpen(menu)
        let revalidation = try #require(controller.codexAccountMenuProjectionRevalidationTask)
        controller.menuWillOpen(menu)
        await probe.waitUntilCalled()

        #expect(probe.callCount == 1)
        #expect(probe.loadedOffMainThread)
        probe.release()
        await revalidation.value

        #expect(controller.codexAccountMenuProjectionRevalidationTask == nil)
        #expect(controller.menuContentVersion == versionBeforeOpen + 1)
    }

    @Test
    func `selecting displayed account uses captured source without reconciliation`() throws {
        let settings = self.makeSettings()
        let firstID = UUID()
        let secondID = UUID()
        let first = ManagedCodexAccount(
            id: firstID,
            email: "first@example.com",
            managedHomePath: "/tmp/first",
            createdAt: 1,
            updatedAt: 1,
            lastAuthenticatedAt: 1)
        let second = ManagedCodexAccount(
            id: secondID,
            email: "second@example.com",
            managedHomePath: "/tmp/second",
            createdAt: 1,
            updatedAt: 1,
            lastAuthenticatedAt: 1)
        let snapshot = CodexAccountReconciliationSnapshot(
            storedAccounts: [first, second],
            activeStoredAccount: first,
            liveSystemAccount: nil,
            matchingStoredAccountForLiveSystemAccount: nil,
            activeSource: .managedAccount(id: firstID),
            hasUnreadableAddedAccountStore: false)
        let projection = CodexVisibleAccountProjection.make(from: snapshot)
        let displayedAccount = try #require(projection.visibleAccounts.first {
            $0.selectionSource == .managedAccount(id: secondID)
        })
        let probe = CodexAccountSnapshotLoaderProbe(snapshot: snapshot)
        settings.cachedCodexAccountMenuProjection = self.cachedProjection(snapshot: snapshot)
        settings._test_codexAccountSnapshotLoader = { _ in probe.load() }
        defer { settings._test_codexAccountSnapshotLoader = nil }

        settings.selectDisplayedCodexVisibleAccount(displayedAccount)

        #expect(probe.callCount == 0)
        #expect(settings.codexActiveSource == .managedAccount(id: secondID))
        #expect(settings.cachedCodexAccountMenuProjection == nil)
    }
}

private final class CodexAccountSnapshotLoaderProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let snapshot: CodexAccountReconciliationSnapshot
    private let blocks: Bool
    private let releaseSemaphore = DispatchSemaphore(value: 0)
    private var _callCount = 0
    private var _loadedOffMainThread = false
    private var released = false

    init(snapshot: CodexAccountReconciliationSnapshot, blocks: Bool = false) {
        self.snapshot = snapshot
        self.blocks = blocks
    }

    var callCount: Int {
        self.lock.withLock { self._callCount }
    }

    var loadedOffMainThread: Bool {
        self.lock.withLock { self._loadedOffMainThread }
    }

    func load() -> CodexAccountReconciliationSnapshot {
        self.lock.withLock {
            self._callCount += 1
            self._loadedOffMainThread = self._loadedOffMainThread || !Thread.isMainThread
        }
        if self.blocks {
            self.releaseSemaphore.wait()
        }
        return self.snapshot
    }

    func waitUntilCalled() async {
        while self.callCount == 0 {
            await Task.yield()
        }
    }

    func release() {
        let shouldSignal = self.lock.withLock {
            guard !self.released else { return false }
            self.released = true
            return true
        }
        if shouldSignal {
            self.releaseSemaphore.signal()
        }
    }
}
