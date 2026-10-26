import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct UsageStoreAccountQuotaWarningTests {
    @MainActor
    private final class NotifierSpy: SessionQuotaNotifying {
        private(set) var quotaWarnings: [QuotaWarningEvent] = []

        func post(transition _: SessionQuotaTransition, provider _: UsageProvider, badge _: NSNumber?) {}

        func postQuotaWarning(
            event: QuotaWarningEvent,
            provider _: UsageProvider,
            soundEnabled _: Bool,
            onScreenAlertEnabled _: Bool)
        {
            self.quotaWarnings.append(event)
        }
    }

    @Test
    func `ordinary refresh keeps selected token account warning episodes independent`() async throws {
        let settings = self.makeSettingsStore(suiteName: "UsageStoreAccountQuotaWarningTests-selected-account")
        defer { settings.configFileWatcher?.stop() }
        settings.multiAccountMenuLayout = .segmented
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        settings.quotaWarningNotificationsEnabled = true
        settings.quotaWarningThresholds = [50]
        settings.setQuotaWarningWindowEnabled(.session, enabled: true)
        settings.setQuotaWarningWindowEnabled(.weekly, enabled: false)
        settings.sessionQuotaNotificationsEnabled = false
        settings.predictivePaceWarningNotificationsEnabled = false
        settings.addTokenAccount(provider: .claude, label: "First", token: "fixture")
        settings.addTokenAccount(provider: .claude, label: "Second", token: "fixture")
        #expect(settings.tokenAccounts(for: .claude).map(\.label) == ["First", "Second"])

        let notifier = NotifierSpy()
        let store = try self.makeStore(settings: settings, notifier: notifier)
        let sequence = [
            (accountIndex: 0, usedPercent: 40.0),
            (accountIndex: 1, usedPercent: 40.0),
            (accountIndex: 0, usedPercent: 55.0),
            (accountIndex: 1, usedPercent: 30.0),
            (accountIndex: 0, usedPercent: 55.0),
            (accountIndex: 1, usedPercent: 55.0),
        ]

        for (step, observation) in sequence.enumerated() {
            settings.setActiveTokenAccountIndex(observation.accountIndex, for: .claude)
            let outcome = Self.outcome(
                usedPercent: observation.usedPercent,
                updatedAt: Date(timeIntervalSince1970: 1_780_000_000 + Double(step)))
            var overrideCalls = 0
            store._test_providerFetchOutcomeOverride = { provider in
                #expect(provider == .claude)
                overrideCalls += 1
                return outcome
            }
            await store.refreshProvider(.claude, allowDisabled: true)
            #expect(overrideCalls == 1)
        }

        #expect(notifier.quotaWarnings.map(\.accountDisplayName) == ["First", "Second"])
        #expect(notifier.quotaWarnings.allSatisfy { $0.threshold == 50 })
    }

    @Test
    func `selected outcome keeps token account warning episodes independent`() async throws {
        let settings = self.makeSettingsStore(suiteName: "UsageStoreAccountQuotaWarningTests-selected-outcome")
        defer { settings.configFileWatcher?.stop() }
        settings.quotaWarningNotificationsEnabled = true
        settings.quotaWarningThresholds = [50]
        settings.setQuotaWarningWindowEnabled(.session, enabled: true)
        settings.setQuotaWarningWindowEnabled(.weekly, enabled: false)
        settings.sessionQuotaNotificationsEnabled = false
        settings.predictivePaceWarningNotificationsEnabled = false

        let accounts = try [
            ProviderTokenAccount(
                id: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
                label: "First",
                token: "fixture",
                addedAt: 0,
                lastUsed: nil),
            ProviderTokenAccount(
                id: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002")),
                label: "Second",
                token: "fixture",
                addedAt: 0,
                lastUsed: nil),
        ]
        let notifier = NotifierSpy()
        let store = try self.makeStore(settings: settings, notifier: notifier)
        let sequence = [
            (accountIndex: 0, usedPercent: 40.0),
            (accountIndex: 1, usedPercent: 40.0),
            (accountIndex: 0, usedPercent: 55.0),
            (accountIndex: 1, usedPercent: 30.0),
            (accountIndex: 0, usedPercent: 55.0),
            (accountIndex: 1, usedPercent: 55.0),
        ]

        for (step, observation) in sequence.enumerated() {
            await store.applySelectedOutcome(
                Self.outcome(
                    usedPercent: observation.usedPercent,
                    updatedAt: Date(timeIntervalSince1970: 1_780_000_000 + Double(step))),
                provider: .claude,
                account: accounts[observation.accountIndex],
                fallbackSnapshot: nil)
        }

        #expect(notifier.quotaWarnings.map(\.accountDisplayName) == ["First", "Second"])
        #expect(notifier.quotaWarnings.allSatisfy { $0.threshold == 50 })
    }

    private func makeSettingsStore(suiteName: String) -> SettingsStore {
        SettingsStore(
            userDefaults: InMemoryUserDefaults(),
            configStore: testConfigStore(suiteName: suiteName),
            codexCookieStore: InMemoryCookieHeaderStore(),
            claudeCookieStore: InMemoryCookieHeaderStore(),
            tokenAccountStore: InMemoryTokenAccountStore(),
            keychainAccessPolicy: SettingsStoreKeychainAccessPolicy(
                setDisabled: { _ in }, isExplicitlyDisabled: { true }),
            performInitialProviderDetection: false)
    }

    private func makeStore(settings: SettingsStore, notifier: NotifierSpy) throws -> UsageStore {
        let home = TestFixtureScratch.root
            .appendingPathComponent("UsageStoreAccountQuotaWarningTests-\(UUID().uuidString)")
        let environment = ["HOME": home.path, "CODEX_HOME": home.appendingPathComponent("codex").path]
        let store = UsageStore(
            fetcher: UsageFetcher(environment: environment),
            browserDetection: BrowserDetection(homeDirectory: home.path, cacheTTL: 0),
            settings: settings,
            sessionQuotaNotifier: notifier,
            startupBehavior: .testing,
            environmentBase: environment,
            widgetSnapshotURL: home.appendingPathComponent("widget.json"),
            widgetTimelineReloader: {})
        store._test_widgetSnapshotSaveOverride = { _ in }
        let base = try #require(store.providerSpecs[.claude])
        let descriptor = ProviderDescriptor(
            id: .claude,
            metadata: base.descriptor.metadata,
            branding: base.descriptor.branding,
            tokenCost: base.descriptor.tokenCost,
            fetchPlan: ProviderFetchPlan(
                sourceModes: base.descriptor.fetchPlan.sourceModes,
                pipeline: ProviderFetchPipeline { _ in
                    Issue.record("Warning episode tests must use their injected outcome, not a provider transport")
                    return []
                }),
            cli: base.descriptor.cli)
        store.providerSpecs[.claude] = ProviderSpec(
            style: base.style,
            isEnabled: base.isEnabled,
            descriptor: descriptor,
            makeFetchContext: base.makeFetchContext)
        return store
    }

    private static func outcome(usedPercent: Double, updatedAt: Date) -> ProviderFetchOutcome {
        ProviderFetchOutcome(
            result: .success(ProviderFetchResult(
                usage: UsageSnapshot(
                    primary: RateWindow(
                        usedPercent: usedPercent,
                        windowMinutes: 300,
                        resetsAt: nil,
                        resetDescription: nil),
                    secondary: nil,
                    updatedAt: updatedAt),
                credits: nil,
                dashboard: nil,
                sourceLabel: "fixture",
                strategyID: "fixture.api-token",
                strategyKind: .apiToken)),
            attempts: [])
    }
}
