import CodexBarCore
import Foundation
import Testing

struct ProviderCookieSettingsResolverTests {
    @Test
    func `provider cookie settings remain distinct nominal types`() {
        let codex = ProviderSettingsSnapshot.CodexProviderSettings(
            usageDataSource: .auto,
            cookieSource: .auto,
            manualCookieHeader: nil)
        let claude = ProviderSettingsSnapshot.ClaudeProviderSettings(
            usageDataSource: .auto,
            webExtrasEnabled: false,
            cookieSource: .auto,
            manualCookieHeader: nil)

        #expect(Self.providerName(codex) == "codex")
        #expect(Self.providerName(claude) == "claude")
    }

    @Test
    func `selected cookie account overrides configured credentials`() {
        let settings = ProviderCookieSettingsResolver.resolve(
            provider: .claude,
            configuredSource: .auto,
            configuredHeader: "sessionKey=config",
            selectedAccount: Self.account(token: "account"))

        #expect(settings.cookieSource == .manual)
        #expect(settings.manualCookieHeader == "sessionKey=account")
    }

    @Test
    func `configured credentials remain when no account is selected`() {
        let settings = ProviderCookieSettingsResolver.resolve(
            provider: .claude,
            configuredSource: .manual,
            configuredHeader: "Cookie: session=config",
            selectedAccount: nil)

        #expect(settings.cookieSource == .manual)
        #expect(settings.manualCookieHeader == "Cookie: session=config")
    }

    @Test
    func `providers without token account support ignore selected account`() {
        let settings = ProviderCookieSettingsResolver.resolve(
            provider: .codex,
            configuredSource: .auto,
            configuredHeader: "configured=true",
            selectedAccount: Self.account(token: "account=true"))

        #expect(settings.cookieSource == .auto)
        #expect(settings.manualCookieHeader == "configured=true")
    }

    private static func account(token: String) -> ProviderTokenAccount {
        ProviderTokenAccount(
            id: UUID(),
            label: "Test",
            token: token,
            addedAt: 0,
            lastUsed: nil)
    }

    private static func providerName(_: ProviderSettingsSnapshot.CodexProviderSettings) -> String {
        "codex"
    }

    private static func providerName(_: ProviderSettingsSnapshot.ClaudeProviderSettings) -> String {
        "claude"
    }
}
