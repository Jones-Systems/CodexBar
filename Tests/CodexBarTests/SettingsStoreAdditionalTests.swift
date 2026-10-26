import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct SettingsStoreAdditionalTests {
    @Test
    func `typed provider config bindings normalize every standard field`() {
        let settings = Self.makeSettingsStore(suite: "SettingsStoreAdditionalTests-provider-config-bindings")

        let fields: [(ProviderConfigStringField, String)] = [
            (.apiKey, "api"),
            (.secretKey, "secret"),
            (.region, "region"),
            (.endpoint, "https://example.test"),
            (.workspace, "workspace"),
            (.cookieHeader, "session=fixture"),
        ]
        for (field, value) in fields {
            settings[providerConfig: .claude, field: field] = "  \(value)  "
            #expect(settings[providerConfig: .claude, field: field] == value)
        }

        let binding = settings.providerConfigBinding(provider: .codex, field: .secretWorkspace(logField: "projectID"))
        binding.wrappedValue = "  project  "
        #expect(binding.wrappedValue == "project")

        let cookieSource = settings.providerCookieSourceBinding(provider: .claude, fallback: .auto)
        #expect(cookieSource.wrappedValue == .auto)
        cookieSource.wrappedValue = .manual
        #expect(cookieSource.wrappedValue == .manual)

        settings[providerConfig: .claude, field: .apiKey] = "   "
        #expect(settings.providerConfig(for: .claude)?.apiKey == nil)
    }

    @Test
    func `menu bar metric capability membership preserves every provider verdict`() {
        let settings = Self.makeSettingsStore(suite: "SettingsStoreAdditionalTests-menu-metric-capabilities")
        let standard: Set<MenuBarMetricPreference> = [.automatic, .primary, .secondary]
        let overrides: [UsageProvider: Set<MenuBarMetricPreference>] = [
            .codex: standard.union([.primaryAndSecondary]),
            .claude: standard.union([.primaryAndSecondary, .extraUsage]),
        ]

        for provider in UsageProvider.allCases {
            let supported = overrides[provider] ?? standard
            for preference in MenuBarMetricPreference.allCases {
                settings.setMenuBarMetricPreference(preference, for: provider)
                let expected = supported.contains(preference) ? preference : .automatic
                #expect(
                    settings.menuBarMetricPreference(for: provider) == expected,
                    "Unexpected \(preference.rawValue) verdict for \(provider.rawValue).")
            }
        }
    }

    @Test
    func `token accounts set manual cookie source when required`() {
        let settings = Self.makeSettingsStore(suite: "SettingsStoreAdditionalTests-token-accounts")

        settings.addTokenAccount(provider: .claude, label: "Primary", token: "token-1")

        #expect(settings.tokenAccounts(for: .claude).count == 1)
        #expect(settings.claudeCookieSource == .manual)
    }

    private static func makeSettingsStore(suite: String) -> SettingsStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)

        return SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            codexCookieStore: InMemoryCookieHeaderStore(),
            claudeCookieStore: InMemoryCookieHeaderStore(),
            tokenAccountStore: InMemoryTokenAccountStore())
    }
}
