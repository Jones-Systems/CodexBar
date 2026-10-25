import Foundation
import Observation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct UsageStoreCoverageTests {
    private final class ObservationFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        func set() {
            self.lock.lock()
            self.value = true
            self.lock.unlock()
        }

        func get() -> Bool {
            self.lock.lock()
            defer { self.lock.unlock() }
            return self.value
        }
    }

    @Test
    func `provider with highest usage and icon style`() throws {
        let settings = Self.makeSettingsStore(suite: "UsageStoreCoverageTests-highest")
        let store = Self.makeUsageStore(settings: settings)
        let metadata = ProviderRegistry.shared.metadata

        try settings.setProviderEnabled(provider: .codex, metadata: #require(metadata[.codex]), enabled: true)
        try settings.setProviderEnabled(provider: .claude, metadata: #require(metadata[.claude]), enabled: true)

        let now = Date()
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 50, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                updatedAt: now),
            provider: .codex)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 10, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
                secondary: RateWindow(usedPercent: 70, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
                updatedAt: now),
            provider: .claude)
        let highest = store.providerWithHighestUsage()
        #expect(highest?.provider == .claude)
        #expect(highest?.usedPercent == 70)
        #expect(store.iconStyle == .combined)

        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 100, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                updatedAt: now),
            provider: .claude)
        #expect(store.providerWithHighestUsage()?.provider == .codex)
        #expect(store.providerWithHighestUsage()?.usedPercent == 50)

        try settings.setProviderEnabled(provider: .claude, metadata: #require(metadata[.claude]), enabled: false)
        #expect(store.iconStyle == store.style(for: .codex))

        store._setErrorForTesting("error", provider: .codex)
        #expect(store.isStale)
    }

    @Test
    func `source label adds open AI web`() {
        let settings = Self.makeSettingsStore(suite: "UsageStoreCoverageTests-source")
        settings.debugDisableKeychainAccess = false
        settings.codexUsageDataSource = .oauth
        settings.codexCookieSource = .manual

        let store = Self.makeUsageStore(settings: settings)
        store.openAIDashboard = OpenAIDashboardSnapshot(
            signedInEmail: "user@example.com",
            codeReviewRemainingPercent: nil,
            creditEvents: [],
            dailyBreakdown: [],
            usageBreakdown: [],
            creditsPurchaseURL: nil,
            updatedAt: Date())
        store.openAIDashboardRequiresLogin = false

        let label = store.sourceLabel(for: .codex)
        #expect(label.contains("openai-web"))
    }

    @Test(CodexCredentialFixtures())
    func `account info caches codex auth parsing until config revision changes`() throws {
        let settings = Self.makeSettingsStore(suite: "UsageStoreCoverageTests-account-info-cache")
        let home = CodexCredentialFixtures.root.appendingPathComponent(
            "usage-store-account-info-\(UUID().uuidString)",
            isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }

        try Self.writeCodexAuthFile(homeURL: home, email: "first@example.com", plan: "plus")
        let env = ["CODEX_HOME": home.path]
        settings._test_codexReconciliationEnvironment = env
        defer { settings._test_codexReconciliationEnvironment = nil }
        let store = UsageStore(
            fetcher: UsageFetcher(environment: env),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: env)

        let first = store.accountInfo(for: .codex)
        try Self.writeCodexAuthFile(homeURL: home, email: "second@example.com", plan: "pro")
        let cached = store.accountInfo(for: .codex)
        settings.configRevision &+= 1
        let refreshed = store.accountInfo(for: .codex)

        #expect(first.email == "first@example.com")
        #expect(cached.email == "first@example.com")
        #expect(refreshed.email == "second@example.com")
    }

    @Test
    func `permission prompt errors are detected for notifications`() {
        let errors: [LocalizedTestError] = [
            LocalizedTestError("Waiting for folder trust prompt"),
            LocalizedTestError("Permission prompt is waiting in the CLI"),
        ]

        for error in errors {
            #expect(UsageStore.isPermissionPromptWaiting(error))
        }
        #expect(!UsageStore.isPermissionPromptWaiting(LocalizedTestError("network timeout")))
    }

    @Test
    func `provider availability and subscription detection`() {
        let settings = Self.makeSettingsStore(
            suite: "UsageStoreCoverageTests-availability")
        let store = Self.makeUsageStore(settings: settings)

        #expect(store.isProviderAvailable(.codex))
        #expect(store.isProviderAvailable(.claude))

        let identity = ProviderIdentitySnapshot(
            providerID: .claude,
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: "Pro")
        store._setSnapshotForTesting(
            UsageSnapshot(primary: nil, secondary: nil, updatedAt: Date(), identity: identity),
            provider: .claude)
        #expect(store.isClaudeSubscription())
        #expect(UsageStore.isSubscriptionPlan("Team"))
        #expect(!UsageStore.isSubscriptionPlan("api"))
    }

    @Test
    func `background refresh only tracks enabled providers`() throws {
        let settings = Self.makeSettingsStore(suite: "UsageStoreCoverageTests-background-refresh")
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false

        let metadata = ProviderRegistry.shared.metadata
        for provider in UsageProvider.allCases {
            try settings.setProviderEnabled(
                provider: provider,
                metadata: #require(metadata[provider]),
                enabled: false)
        }
        try settings.setProviderEnabled(provider: .codex, metadata: #require(metadata[.codex]), enabled: true)

        let store = Self.makeUsageStore(settings: settings)
        let staleSnapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 25, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date())
        store._setSnapshotForTesting(staleSnapshot, provider: .claude)
        store._setErrorForTesting("stale", provider: .claude)
        store.statuses[.claude] = ProviderStatus(indicator: .major, description: "Outage", updatedAt: Date())
        store.statusComponents[.claude] = [
            ProviderStatusComponent(id: "api", name: "API", indicator: .major, status: "major_outage"),
        ]

        #expect(store.enabledProviders() == [.codex])

        store.clearDisabledProviderState(enabledProviders: Set(store.enabledProvidersForDisplay()))

        #expect(store.snapshot(for: .claude) == nil)
        #expect(store.errors[.claude] == nil)
        #expect(store.statuses[.claude] == nil)
        #expect(store.statusComponents(for: .claude).isEmpty)
    }

    @Test
    func `cleanup preserves enabled but unavailable provider state`() throws {
        let settings = Self.makeSettingsStore(suite: "UsageStoreCoverageTests-preserve-unavailable")
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false

        let metadata = ProviderRegistry.shared.metadata
        for provider in UsageProvider.allCases {
            try settings.setProviderEnabled(
                provider: provider,
                metadata: #require(metadata[provider]),
                enabled: false)
        }
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(metadata[.claude]),
            enabled: true)

        let store = Self.makeUsageStore(settings: settings)
        store._test_providerAvailabilityOverride = { _ in false }
        let staleSnapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 25, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date())
        store._setSnapshotForTesting(staleSnapshot, provider: .claude)
        store._setErrorForTesting("stale", provider: .claude)
        store.statuses[.claude] = ProviderStatus(indicator: .major, description: "Outage", updatedAt: Date())

        #expect(store.enabledProviders().isEmpty)
        #expect(store.enabledProvidersForDisplay() == [.claude])

        store.clearDisabledProviderState(enabledProviders: Set(store.enabledProvidersForDisplay()))

        #expect(store.snapshot(for: .claude) != nil)
        #expect(store.errors[.claude] == "stale")
        #expect(store.statuses[.claude]?.indicator == .major)
    }

    @Test
    func `background work excludes enabled but unavailable providers`() throws {
        let settings = Self.makeSettingsStore(suite: "UsageStoreCoverageTests-background-unavailable")
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false

        let metadata = ProviderRegistry.shared.metadata
        for provider in UsageProvider.allCases {
            try settings.setProviderEnabled(
                provider: provider,
                metadata: #require(metadata[provider]),
                enabled: false)
        }
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(metadata[.claude]),
            enabled: true)

        let store = Self.makeUsageStore(settings: settings)
        store._test_providerAvailabilityOverride = { _ in false }

        #expect(store.enabledProvidersForDisplay() == [.claude])
        #expect(store.enabledProviders().isEmpty)
        #expect(store.enabledProvidersForBackgroundWork().isEmpty)
    }

    @Test
    func `visible unavailable provider gets explicit user facing state`() throws {
        let settings = Self.makeSettingsStore(suite: "UsageStoreCoverageTests-unavailable-message")
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false

        let metadata = ProviderRegistry.shared.metadata
        for provider in UsageProvider.allCases {
            try settings.setProviderEnabled(
                provider: provider,
                metadata: #require(metadata[provider]),
                enabled: false)
        }
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(metadata[.claude]),
            enabled: true)

        let store = Self.makeUsageStore(settings: settings)
        store._test_providerAvailabilityOverride = { _ in false }

        #expect(store.errors[.claude] == nil)
        #expect(store.enabledProvidersForDisplay() == [.claude])
        #expect(store.isProviderAvailable(.claude) == false)
        #expect(store.userFacingError(for: .claude) == "Claude is unavailable in the current environment.")
        #expect(store.unavailableMessage(for: .claude) == "Claude is unavailable in the current environment.")
    }
}

extension UsageStoreCoverageTests {
    @Test
    func `refresh clears enabled but unavailable cached state`() async throws {
        let settings = Self.makeSettingsStore(suite: "UsageStoreCoverageTests-background-cleanup")
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false

        let metadata = ProviderRegistry.shared.metadata
        for provider in UsageProvider.allCases {
            try settings.setProviderEnabled(
                provider: provider,
                metadata: #require(metadata[provider]),
                enabled: false)
        }
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(metadata[.claude]),
            enabled: true)

        let store = Self.makeUsageStore(settings: settings)
        store._test_providerAvailabilityOverride = { _ in false }
        let cachedSnapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 25, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date())
        store._setSnapshotForTesting(cachedSnapshot, provider: .claude)
        let account = ProviderTokenAccount(id: UUID(), label: "Account", token: "token", addedAt: 0, lastUsed: nil)
        store.accountSnapshots[.claude] = [
            TokenAccountUsageSnapshot(
                account: account,
                snapshot: cachedSnapshot,
                error: nil,
                sourceLabel: "api",
                cacheKey: store.tokenAccountSnapshotCacheKey(provider: .claude, account: account)),
        ]
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 10,
                sessionCostUSD: 1.23,
                last30DaysTokens: 100,
                last30DaysCostUSD: 4.56,
                daily: [],
                updatedAt: Date()),
            provider: .claude)

        #expect(store.enabledProvidersForDisplay() == [.claude])
        #expect(store.enabledProviders().isEmpty)
        #expect(store.enabledProvidersForBackgroundWork().isEmpty)

        await store.refresh()
        #expect(store.snapshot(for: .claude) == nil)
        #expect((store.accountSnapshots[.claude] ?? []).isEmpty)
        #expect(store.tokenSnapshots[.claude] == nil)
        #expect(store.enabledProvidersForBackgroundWork().isEmpty)
    }

    @Test
    func `refresh clears enabled but unavailable failure state`() async throws {
        let settings = Self.makeSettingsStore(suite: "UsageStoreCoverageTests-background-failure-cleanup")
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false

        let metadata = ProviderRegistry.shared.metadata
        for provider in UsageProvider.allCases {
            try settings.setProviderEnabled(
                provider: provider,
                metadata: #require(metadata[provider]),
                enabled: false)
        }
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(metadata[.claude]),
            enabled: true)

        let store = Self.makeUsageStore(settings: settings)
        store._test_providerAvailabilityOverride = { _ in false }
        store._setErrorForTesting("stale", provider: .claude)
        store.statuses[.claude] = ProviderStatus(indicator: .major, description: "Outage", updatedAt: Date())
        store.statusComponents[.claude] = [
            ProviderStatusComponent(id: "api", name: "API", indicator: .major, status: "major_outage"),
        ]
        store.tokenErrors[.claude] = "token stale"

        #expect(store.enabledProvidersForDisplay() == [.claude])
        #expect(store.enabledProviders().isEmpty)
        #expect(store.enabledProvidersForBackgroundWork().isEmpty)

        await store.refresh()

        #expect(store.errors[.claude] == nil)
        #expect(store.tokenErrors[.claude] == nil)
        #expect(store.statuses[.claude] == nil)
        #expect(store.statusComponents(for: .claude).isEmpty)
        #expect(store.enabledProvidersForBackgroundWork().isEmpty)
    }

    @Test
    func `widget snapshot preserves local token usage currency and labels`() async throws {
        let settings = Self.makeSettingsStore(suite: "UsageStoreCoverageTests-widget-provider-cost")
        settings.costUsageEnabled = true
        let store = Self.makeUsageStore(settings: settings)
        let formatter = ISO8601DateFormatter()
        let updatedAt = try #require(formatter.date(from: "2026-05-26T12:00:00Z"))
        let tokenSnapshot = CostUsageTokenSnapshot(
            sessionTokens: 15,
            sessionCostUSD: 9,
            last30DaysTokens: 15,
            last30DaysCostUSD: 9,
            currencyCode: "EUR",
            historyLabel: "This month",
            daily: [
                CostUsageDailyReport.Entry(
                    date: "2026-05-26",
                    inputTokens: 10,
                    outputTokens: 5,
                    totalTokens: 15,
                    costUSD: 9,
                    modelsUsed: nil,
                    modelBreakdowns: nil),
            ],
            updatedAt: updatedAt)
        store._setTokenSnapshotForTesting(tokenSnapshot, provider: .claude)

        var widgetSnapshots: [WidgetSnapshot] = []
        store._test_widgetSnapshotSaveOverride = { widgetSnapshots.append($0) }
        defer { store._test_widgetSnapshotSaveOverride = nil }

        store.persistWidgetSnapshot(reason: "provider-cost")
        await store.widgetSnapshotPersistTask?.value

        let claudeEntry = try #require(widgetSnapshots.last?.entries.first { $0.provider == .claude })
        #expect(claudeEntry.tokenUsage?.currencyCode == "EUR")
        #expect(claudeEntry.tokenUsage?.sessionLabel == "Today")
        #expect(claudeEntry.tokenUsage?.last30DaysLabel == "This month")
        #expect(claudeEntry.tokenUsage?.last30DaysCostUSD == 9)
    }

    @Test
    func `unavailable provider with only cached status gets single cleanup pass`() async throws {
        let settings = Self.makeSettingsStore(suite: "UsageStoreCoverageTests-background-status-cleanup")
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = true

        let metadata = ProviderRegistry.shared.metadata

        for provider in UsageProvider.allCases {
            try settings.setProviderEnabled(
                provider: provider,
                metadata: #require(metadata[provider]),
                enabled: false)
        }
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(metadata[.claude]),
            enabled: true)

        let store = Self.makeUsageStore(settings: settings)
        store._test_providerAvailabilityOverride = { _ in false }
        store.statuses[.claude] = ProviderStatus(indicator: .major, description: "Outage", updatedAt: Date())

        #expect(store.enabledProvidersForDisplay() == [.claude])
        #expect(store.enabledProviders().isEmpty)
        #expect(store.enabledProvidersForBackgroundWork().isEmpty)

        await store.refresh()

        #expect(store.statuses[.claude] == nil)
        #expect(store.enabledProvidersForBackgroundWork().isEmpty)
    }

    @Test
    func `status indicators and failure gate`() {
        #expect(!ProviderStatusIndicator.none.hasIssue)
        #expect(ProviderStatusIndicator.maintenance.hasIssue)
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(ProviderStatusIndicator.unknown.label == "Status unknown")
        }

        var gate = ConsecutiveFailureGate()
        let first = gate.shouldSurfaceError(onFailureWithPriorData: true)
        #expect(!first)
        let second = gate.shouldSurfaceError(onFailureWithPriorData: true)
        #expect(second)
        gate.recordSuccess()
        let third = gate.shouldSurfaceError(onFailureWithPriorData: false)
        #expect(third)
        gate.reset()
        #expect(gate.streak == 0)
    }

    @Test
    func `token account error message ignores cancellation`() {
        let settings = Self.makeSettingsStore(suite: "UsageStoreCoverageTests-token-account-cancel")
        let store = Self.makeUsageStore(settings: settings)

        #expect(store.tokenAccountErrorMessage(CancellationError()) == nil)
        #expect(store.tokenAccountErrorMessage(ProviderFetchError.noAvailableStrategy(.claude)) != nil)
    }

    @Test
    func `isPreservableNetworkTransportError classifies transport failures correctly`() {
        #expect(UsageStore.isPreservableNetworkTransportError(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost)))
        #expect(UsageStore.isPreservableNetworkTransportError(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)))
        #expect(UsageStore.isPreservableNetworkTransportError(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorDNSLookupFailed)))
        #expect(UsageStore.isPreservableNetworkTransportError(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)))
        #expect(UsageStore.isPreservableNetworkTransportError(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)))
        #expect(UsageStore.isPreservableNetworkTransportError(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost)))
        #expect(UsageStore.isPreservableNetworkTransportError(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)))
        #expect(!UsageStore.isPreservableNetworkTransportError(
            NSError(domain: NSCocoaErrorDomain, code: 0)))
    }

    @Test
    func `background work settings observation ignores menu provider selection churn`() async throws {
        let settings = Self.makeSettingsStore(suite: "UsageStoreCoverageTests-switcher-selection-observation")
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        try Self.enableOnly(.codex, settings: settings)

        let store = Self.makeUsageStore(settings: settings)
        let didChange = ObservationFlag()

        withObservationTracking {
            _ = store.backgroundWorkSettingsObservationToken
        } onChange: {
            didChange.set()
        }

        settings.selectedMenuProvider = .codex
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(didChange.get() == false)

        let refreshDidChange = ObservationFlag()
        withObservationTracking {
            _ = store.backgroundWorkSettingsObservationToken
        } onChange: {
            refreshDidChange.set()
        }

        settings.refreshFrequency = .oneMinute
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(refreshDidChange.get() == true)
    }

    @Test
    func `background work settings observation ignores display only settings churn`() async throws {
        let settings = Self.makeSettingsStore(suite: "UsageStoreCoverageTests-display-only-observation")
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        settings.mergeIcons = false
        settings.randomBlinkEnabled = false
        settings.usageBarsShowUsed = false
        settings.showOptionalCreditsAndExtraUsage = false
        try Self.enableOnly(.codex, settings: settings)

        let store = Self.makeUsageStore(settings: settings)
        let didChange = ObservationFlag()

        withObservationTracking {
            _ = store.backgroundWorkSettingsObservationToken
        } onChange: {
            didChange.set()
        }

        settings.usageBarsShowUsed = true
        settings.mergeIcons = true
        settings.randomBlinkEnabled = true
        settings.codexSparkUsageVisible.toggle()
        settings.debugLoadingPattern = .pulse
        settings.setProviderOrder(Array(settings.orderedProviders().reversed()))
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(didChange.get() == false)

        let refreshDidChange = ObservationFlag()
        withObservationTracking {
            _ = store.backgroundWorkSettingsObservationToken
        } onChange: {
            refreshDidChange.set()
        }

        settings.statusChecksEnabled = true
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(refreshDidChange.get() == true)

        let layoutDidChange = ObservationFlag()
        withObservationTracking {
            _ = store.backgroundWorkSettingsObservationToken
        } onChange: {
            layoutDidChange.set()
        }

        settings.multiAccountMenuLayout = .stacked
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(layoutDidChange.get() == true)

        let optionalUsageDidChange = ObservationFlag()
        withObservationTracking {
            _ = store.backgroundWorkSettingsObservationToken
        } onChange: {
            optionalUsageDidChange.set()
        }

        settings.showOptionalCreditsAndExtraUsage = true
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(optionalUsageDidChange.get() == true)
    }

    @Test
    func `display only settings do not invoke provider refresh while background work is active`() async throws {
        let settings = Self.makeSettingsStore(suite: "UsageStoreCoverageTests-display-only-no-provider-refresh")
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        settings.mergeIcons = false
        settings.randomBlinkEnabled = false
        settings.usageBarsShowUsed = false
        try Self.enableOnly(.codex, settings: settings)

        let store = Self.makeUsageStore(settings: settings)
        var refreshedProviders: [UsageProvider] = []
        store._test_providerRefreshOverride = { refreshedProviders.append($0) }
        defer { store._test_providerRefreshOverride = nil }

        func observeBackgroundSettingsForTest() {
            withObservationTracking {
                _ = store.backgroundWorkSettingsObservationToken
            } onChange: {
                Task { @MainActor in
                    await store.refreshForSettingsChange()
                }
            }
        }

        observeBackgroundSettingsForTest()

        settings.usageBarsShowUsed = true
        settings.mergeIcons = true
        settings.randomBlinkEnabled = true
        settings.codexSparkUsageVisible.toggle()
        settings.debugLoadingPattern = .pulse
        settings.setProviderOrder(Array(settings.orderedProviders().reversed()))
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(refreshedProviders.isEmpty)

        settings.codexUsageDataSource = .cli
        for _ in 0..<20 where !refreshedProviders.contains(.codex) {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        #expect(refreshedProviders.contains(.codex))
    }

    @Test
    func `startup status network failure schedules bounded retry`() async throws {
        let settings = Self.makeSettingsStore(suite: "UsageStoreCoverageTests-startup-status-retry")
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = true
        try Self.enableOnly(.codex, settings: settings)

        let store = Self.makeUsageStore(settings: settings)
        store._test_providerRefreshOverride = { _ in }
        defer { store._test_providerRefreshOverride = nil }
        store._test_providerStatusFetchOverride = { _ in
            throw URLError(.notConnectedToInternet)
        }
        defer { store._test_providerStatusFetchOverride = nil }

        var scheduled: [(attempt: Int, delay: TimeInterval)] = []
        store._test_startupConnectivityRetryScheduled = { attempt, delay in
            scheduled.append((attempt, delay))
        }
        defer { store._test_startupConnectivityRetryScheduled = nil }

        await store.refresh()
        defer {
            store.startupConnectivityRetryTask?.cancel()
            store.startupConnectivityRetryTask = nil
        }

        #expect(scheduled.map(\.attempt) == [1])
        #expect(scheduled.map(\.delay) == [15])
        #expect(store.statuses[.codex] == nil)
    }

    @Test
    func `status transport failure preserves last successful provider status`() async throws {
        let settings = Self.makeSettingsStore(suite: "UsageStoreCoverageTests-status-failure-preserves-success")
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = true
        try Self.enableOnly(.codex, settings: settings)

        let store = Self.makeUsageStore(settings: settings)
        let updatedAt = Date(timeIntervalSince1970: 1_750_000_000)
        store.statuses[.codex] = ProviderStatus(
            indicator: .major,
            description: "Service disruption",
            updatedAt: updatedAt)
        store._test_providerStatusFetchOverride = { _ in
            throw URLError(.timedOut)
        }
        defer {
            store._test_providerStatusFetchOverride = nil
            store.startupConnectivityRetryTask?.cancel()
            store.startupConnectivityRetryTask = nil
        }

        await store.refreshProviderStatus(.codex)

        let status = try #require(store.statuses[.codex])
        #expect(status.indicator == .major)
        #expect(status.description == "Service disruption")
        #expect(status.updatedAt == updatedAt)
    }

    @Test
    func `startup connectivity retry refreshes status and clears retry task after recovery`() async throws {
        let settings = Self.makeSettingsStore(suite: "UsageStoreCoverageTests-startup-status-recovery")
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = true
        try Self.enableOnly(.codex, settings: settings)

        let store = Self.makeUsageStore(settings: settings)
        store._test_providerRefreshOverride = { _ in }
        defer { store._test_providerRefreshOverride = nil }

        var statusAttempts = 0
        store._test_providerStatusFetchOverride = { _ in
            statusAttempts += 1
            if statusAttempts == 1 {
                throw URLError(.cannotFindHost)
            }
            return ProviderStatus(indicator: .none, description: "Operational", updatedAt: Date())
        }
        defer { store._test_providerStatusFetchOverride = nil }

        let sleepGate = StartupConnectivityRetrySleepGate()
        store._test_startupConnectivityRetrySleepOverride = { delay in
            try await sleepGate.sleep(delay)
        }
        defer { store._test_startupConnectivityRetrySleepOverride = nil }

        await store.refresh()
        await sleepGate.waitUntilSleeping()
        let retryTask = try #require(store.startupConnectivityRetryTask)

        await sleepGate.resume()
        await retryTask.value

        #expect(statusAttempts == 2)
        #expect(store.statuses[.codex]?.indicator == ProviderStatusIndicator.none)
        #expect(store.statuses[.codex]?.description == "Operational")
        #expect(store.startupConnectivityRetryTask == nil)
    }

    @Test
    func `startup connectivity retry classification is bounded and excludes cancellation`() {
        #expect(UsageStore.startupConnectivityRetryDelay(forAttempt: 1) == 15)
        #expect(UsageStore.startupConnectivityRetryDelay(forAttempt: 4) == 300)
        #expect(UsageStore.startupConnectivityRetryDelay(forAttempt: 5) == nil)
        #expect(UsageStore.isStartupConnectivityRetryableError(URLError(.timedOut)))
        #expect(UsageStore.isStartupConnectivityRetryableError(URLError(.notConnectedToInternet)))
        #expect(!UsageStore.isStartupConnectivityRetryableError(URLError(.cancelled)))
        #expect(!UsageStore.isStartupConnectivityRetryableError(CancellationError()))
    }

    private static func makeSettingsStore(
        suite: String)
        -> SettingsStore
    {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)

        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            codexCookieStore: InMemoryCookieHeaderStore(),
            claudeCookieStore: InMemoryCookieHeaderStore(),
            tokenAccountStore: InMemoryTokenAccountStore())
        settings.providerDetectionCompleted = true
        return settings
    }

    private static func makeUsageStore(settings: SettingsStore) -> UsageStore {
        UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            environmentBase: [:])
    }

    private static func writeCodexAuthFile(homeURL: URL, email: String, plan: String) throws {
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        let auth = try [
            "tokens": [
                "accessToken": "access-token",
                "refreshToken": "refresh-token",
                "idToken": Self.fakeCodexJWT(email: email, plan: plan),
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: auth)
        try data.write(to: homeURL.appendingPathComponent("auth.json"), options: .atomic)
    }

    private static func fakeCodexJWT(email: String, plan: String) throws -> String {
        let header = try JSONSerialization.data(withJSONObject: ["alg": "none"])
        let payload = try JSONSerialization.data(withJSONObject: [
            "email": email,
            "chatgpt_plan_type": plan,
            "https://api.openai.com/auth": [
                "chatgpt_plan_type": plan,
            ],
        ])
        return "\(Self.base64URL(header)).\(Self.base64URL(payload))."
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
    }

    private static func makeCopilotSnapshot(
        usedPercent: Double,
        extraRateWindows: [NamedRateWindow]?) -> UsageSnapshot
    {
        UsageSnapshot(
            primary: RateWindow(usedPercent: usedPercent, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            extraRateWindows: extraRateWindows,
            updatedAt: Date(timeIntervalSince1970: 1_780_358_400))
    }

    private static func makeCopilotBudgetWindow() -> NamedRateWindow {
        NamedRateWindow(
            id: "copilot-budget-test",
            title: "Budget - Copilot",
            window: RateWindow(usedPercent: 50, windowMinutes: nil, resetsAt: nil, resetDescription: nil))
    }

    private static func enableOnly(_ enabledProvider: UsageProvider, settings: SettingsStore) throws {
        let metadata = ProviderRegistry.shared.metadata
        for provider in UsageProvider.allCases {
            try settings.setProviderEnabled(
                provider: provider,
                metadata: #require(metadata[provider]),
                enabled: provider == enabledProvider)
        }
    }
}

private actor StartupConnectivityRetrySleepGate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func sleep(_ delay: TimeInterval) async throws {
        #expect(delay == 15)
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.resumeWaiters()
        }
    }

    func waitUntilSleeping() async {
        if self.continuation != nil {
            return
        }
        await withCheckedContinuation { continuation in
            self.waiters.append(continuation)
        }
    }

    func resume() {
        self.continuation?.resume()
        self.continuation = nil
    }

    private func resumeWaiters() {
        let waiters = self.waiters
        self.waiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

private struct LocalizedTestError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        self.message
    }
}
