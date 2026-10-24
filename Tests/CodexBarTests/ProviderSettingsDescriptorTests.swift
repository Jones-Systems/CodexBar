import Foundation
import SwiftUI
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
@Suite(.serialized)
struct ProviderSettingsDescriptorTests {
    @Test
    func `provider settings refresh enables explicit browser retry`() async {
        var observedInteraction: ProviderInteraction?
        var browserRetryAllowed = false

        await KeychainAccessGate.withTaskOverrideForTesting(false) {
            await BrowserCookieAccessGate.withDeniedBrowsersForTesting([.chrome]) {
                await ProviderSettingsRefreshInteraction.perform {
                    observedInteraction = ProviderInteractionContext.current
                    browserRetryAllowed = BrowserCookieAccessGate.shouldAttempt(.chrome)
                }
            }
        }

        #expect(observedInteraction == .userInitiated)
        #expect(browserRetryAllowed)
    }

    @Test
    func `toggle I ds are unique across providers`() throws {
        let fixture = try self.makeSettingsFixture(suite: "ProviderSettingsDescriptorTests-unique")
        var seenToggleIDs: Set<String> = []
        var seenActionIDs: Set<String> = []
        var seenPickerIDs: Set<String> = []
        var seenSettingsActionGroupIDs: Set<String> = []

        for provider in UsageProvider.allCases {
            let context = fixture.settingsContext(provider: provider)
            let impl = try #require(ProviderCatalog.implementation(for: provider))
            let toggles = impl.settingsToggles(context: context)
            for toggle in toggles {
                #expect(!seenToggleIDs.contains(toggle.id))
                seenToggleIDs.insert(toggle.id)

                for action in toggle.actions {
                    #expect(!seenActionIDs.contains(action.id))
                    seenActionIDs.insert(action.id)
                }
            }

            let pickers = impl.settingsPickers(context: context)
            for picker in pickers {
                #expect(!seenPickerIDs.contains(picker.id))
                seenPickerIDs.insert(picker.id)
            }

            let actionGroups = impl.settingsActions(context: context)
            for actionGroup in actionGroups {
                #expect(!seenSettingsActionGroupIDs.contains(actionGroup.id))
                seenSettingsActionGroupIDs.insert(actionGroup.id)

                for action in actionGroup.actions {
                    #expect(!seenActionIDs.contains(action.id))
                    seenActionIDs.insert(action.id)
                }
            }
        }
    }

    @Test
    func `codex reauthentication remains account scoped`() throws {
        let fixture = try self.makeSettingsFixture(suite: "ProviderSettingsDescriptorTests-codex-login-scope")
        let context = fixture.settingsContext(provider: .codex)

        #expect(CodexProviderImplementation().settingsActions(context: context).isEmpty)
    }

    @Test
    func `codex exposes open AI web extras toggle as default off opt in`() throws {
        let fixture = try self.makeSettingsFixture(suite: "ProviderSettingsDescriptorTests-codex-openai-toggle")
        let context = fixture.settingsContext(provider: .codex)

        let toggles = CodexProviderImplementation().settingsToggles(context: context)
        let extrasToggle = try #require(toggles.first(where: { $0.id == "codex-openai-web-extras" }))
        #expect(extrasToggle.binding.wrappedValue == false)
        #expect(extrasToggle.subtitle.contains("Optional."))
        #expect(extrasToggle.subtitle.contains("Turn this on"))

        let batterySaverToggle = try #require(toggles.first(where: { $0.id == "codex-openai-web-battery-saver" }))
        #expect(batterySaverToggle.binding.wrappedValue == false)
        #expect(batterySaverToggle.isVisible?() == false)

        fixture.settings.openAIWebAccessEnabled = true
        #expect(batterySaverToggle.isVisible?() == true)
    }

    @Test
    func `claude exposes usage and cookie pickers`() throws {
        let fixture = try self.makeSettingsFixture(suite: "ProviderSettingsDescriptorTests-claude")
        fixture.settings.debugDisableKeychainAccess = false
        let context = fixture.settingsContext(provider: .claude)

        let pickers = ClaudeProviderImplementation().settingsPickers(context: context)
        let usagePicker = try #require(pickers.first(where: { $0.id == "claude-usage-source" }))
        #expect(usagePicker.placement == .connection)
        #expect(pickers.contains(where: { $0.id == "claude-cookie-source" }))
        let toggles = ClaudeProviderImplementation().settingsToggles(context: context)
        #expect(!toggles.contains(where: { $0.id == "claude-peak-hours" }))
        let keychainPicker = try #require(pickers.first(where: { $0.id == "claude-keychain-prompt-policy" }))
        let optionIDs = Set(keychainPicker.options.map(\.id))
        #expect(optionIDs.contains(ClaudeOAuthKeychainPromptMode.never.rawValue))
        #expect(optionIDs.contains(ClaudeOAuthKeychainPromptMode.onlyOnUserAction.rawValue))
        #expect(optionIDs.contains(ClaudeOAuthKeychainPromptMode.always.rawValue))
        #expect(keychainPicker.isEnabled?() ?? true)
    }

    @Test
    func `claude daily routines toggle follows global optional usage setting`() throws {
        let fixture = try self.makeSettingsFixture(suite: "ProviderSettingsDescriptorTests-claude-routines")
        let context = fixture.settingsContext(provider: .claude)
        let toggles = ClaudeProviderImplementation().settingsToggles(context: context)
        let routinesToggle = try #require(toggles.first {
            $0.id == "claude-daily-routines-usage-visible"
        })

        #expect(routinesToggle.binding.wrappedValue)
        #expect(routinesToggle.isEnabled?() == true)

        routinesToggle.binding.wrappedValue = false
        #expect(fixture.settings.claudeDailyRoutinesUsageVisible == false)

        fixture.settings.showOptionalCreditsAndExtraUsage = false
        #expect(routinesToggle.isEnabled?() == false)
    }

    @Test
    func `claude model scoped widget usage toggle is default off and independent`() throws {
        let fixture = try self.makeSettingsFixture(suite: "ProviderSettingsDescriptorTests-claude-model-scoped-widget")
        let context = fixture.settingsContext(provider: .claude)
        let toggles = ClaudeProviderImplementation().settingsToggles(context: context)
        let widgetToggle = try #require(toggles.first {
            $0.id == "claude-model-scoped-weekly-usage-visible"
        })

        #expect(widgetToggle.binding.wrappedValue == false)
        #expect(widgetToggle.isEnabled == nil)
        #expect(widgetToggle.subtitle.contains("Fable"))

        widgetToggle.binding.wrappedValue = true
        #expect(fixture.settings.claudeModelScopedWeeklyUsageVisible)

        fixture.settings.showOptionalCreditsAndExtraUsage = false
        #expect(widgetToggle.isEnabled == nil)
    }

    @Test
    func `claude single swap account toggle persists and follows integration visibility`() throws {
        let fixture = try self.makeSettingsFixture(suite: "ProviderSettingsDescriptorTests-claude-swap-single")
        let context = fixture.settingsContext(provider: .claude)
        let toggles = ClaudeProviderImplementation().settingsToggles(context: context)
        let singleAccountToggle = try #require(toggles.first {
            $0.id == "claude-swap-show-single-account"
        })

        #expect(singleAccountToggle.binding.wrappedValue == false)
        #expect(singleAccountToggle.isVisible?() == false)

        fixture.settings.claudeSwapEnabled = true
        #expect(singleAccountToggle.isVisible?() == true)
        singleAccountToggle.binding.wrappedValue = true

        #expect(fixture.settings.claudeSwapShowSingleAccount)
        #expect(fixture.settings.configSnapshot.providerConfig(for: .claude)?.claudeSwapShowSingleAccount == true)
    }

    @Test
    func `claude prompt policy picker remains visible for prompt free toggle`() throws {
        let fixture = try self.makeSettingsFixture(
            suite: "ProviderSettingsDescriptorTests-claude-prompt-visible-prompt-free")
        fixture.settings.debugDisableKeychainAccess = false
        fixture.settings.claudeOAuthPromptFreeCredentialsEnabled = true
        let context = fixture.settingsContext(provider: .claude)

        let pickers = ClaudeProviderImplementation().settingsPickers(context: context)
        let keychainPicker = try #require(pickers.first(where: { $0.id == "claude-keychain-prompt-policy" }))
        #expect(keychainPicker.isVisible?() ?? true)
        #expect(keychainPicker.binding.wrappedValue == ClaudeOAuthKeychainPromptMode.never.rawValue)
    }

    @Test
    func `claude avoid keychain prompts toggle is disabled when global keychain disabled`() throws {
        let fixture = try self.makeSettingsFixture(suite: "ProviderSettingsDescriptorTests-claude-prompt-free-disabled")
        fixture.settings.debugDisableKeychainAccess = true
        fixture.settings.claudeOAuthPromptFreeCredentialsEnabled = true
        let context = fixture.settingsContext(provider: .claude)

        let toggles = ClaudeProviderImplementation().settingsToggles(context: context)
        let promptFreeToggle = try #require(toggles.first(where: { $0.id == "claude-oauth-prompt-free-credentials" }))
        #expect(promptFreeToggle.isEnabled?() == false)
        #expect(promptFreeToggle.binding.wrappedValue == true)

        promptFreeToggle.binding.wrappedValue = false
        #expect(fixture.settings.claudeOAuthPromptFreeCredentialsEnabled == true)

        fixture.settings.debugDisableKeychainAccess = false
        #expect(promptFreeToggle.isEnabled?() == true)
        #expect(promptFreeToggle.binding.wrappedValue == true)
    }

    @Test
    func `claude keychain prompt policy picker disabled when global keychain disabled`() throws {
        let fixture = try self.makeSettingsFixture(suite: "ProviderSettingsDescriptorTests-claude-keychain-disabled")
        fixture.settings.debugDisableKeychainAccess = true
        let context = fixture.settingsContext(provider: .claude)

        let pickers = ClaudeProviderImplementation().settingsPickers(context: context)
        let keychainPicker = try #require(pickers.first(where: { $0.id == "claude-keychain-prompt-policy" }))
        #expect(keychainPicker.isEnabled?() == false)
        let subtitle = keychainPicker.dynamicSubtitle?() ?? ""
        #expect(subtitle.localizedCaseInsensitiveContains("inactive"))
    }

    @Test
    func `claude web extras auto disables when leaving CLI`() throws {
        let fixture = try self.makeSettingsFixture(suite: "ProviderSettingsDescriptorTests-claude-invariant")
        let settings = fixture.settings
        settings.debugMenuEnabled = true
        settings.claudeUsageDataSource = .cli
        settings.claudeWebExtrasEnabled = true

        settings.claudeUsageDataSource = .oauth
        #expect(settings.claudeWebExtrasEnabled == false)
    }
}

extension ProviderSettingsDescriptorTests {
}

extension ProviderSettingsDescriptorTests {

    @Test
    func `provider settings labels an empty transition as refreshing`() {
        #expect(ProviderMetricsInlineView.placeholderText(
            isEnabled: true,
            isRefreshing: true,
            modelPlaceholder: nil) == "Refreshing")
        #expect(ProviderMetricsInlineView.placeholderText(
            isEnabled: true,
            isRefreshing: false,
            modelPlaceholder: nil) == "No usage yet")
    }
}

extension ProviderSettingsDescriptorTests {
    private func makeSettingsFixture(
        suite: String,
        environmentBase: [String: String] = [:]) throws -> ProviderSettingsFixture
    {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite))
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            environmentBase: environmentBase)
        return ProviderSettingsFixture(settings: settings, store: store)
    }

    private struct ProviderSettingsFixture {
        let settings: SettingsStore
        let store: UsageStore
        private let state = ProviderSettingsContextState()

        @MainActor
        func settingsContext(
            provider: UsageProvider,
            runLoginFlow: @escaping () async -> Void = {}) -> ProviderSettingsContext
        {
            let settings = self.settings
            let store = self.store
            let state = self.state
            return ProviderSettingsContext(
                provider: provider,
                settings: settings,
                store: store,
                boolBinding: { keyPath in
                    Binding(
                        get: { settings[keyPath: keyPath] },
                        set: { settings[keyPath: keyPath] = $0 })
                },
                stringBinding: { keyPath in
                    Binding(
                        get: { settings[keyPath: keyPath] },
                        set: { settings[keyPath: keyPath] = $0 })
                },
                statusText: { id in state.statusByID[id] },
                setStatusText: { id, text in
                    if let text {
                        state.statusByID[id] = text
                    } else {
                        state.statusByID.removeValue(forKey: id)
                    }
                },
                lastAppActiveRunAt: { id in state.lastRunAtByID[id] },
                setLastAppActiveRunAt: { id, date in
                    if let date {
                        state.lastRunAtByID[id] = date
                    } else {
                        state.lastRunAtByID.removeValue(forKey: id)
                    }
                },
                requestConfirmation: { _ in },
                runLoginFlow: runLoginFlow)
        }

        @MainActor
        func presentationContext(provider: UsageProvider, metadata: ProviderMetadata) -> ProviderPresentationContext {
            ProviderPresentationContext(
                provider: provider,
                settings: self.settings,
                store: self.store,
                metadata: metadata)
        }
    }

    private final class ProviderSettingsContextState {
        var statusByID: [String: String] = [:]
        var lastRunAtByID: [String: Date] = [:]
    }
}
