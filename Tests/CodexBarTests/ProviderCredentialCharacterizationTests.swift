import CodexBarCore
import Foundation
import Testing
@testable import CodexBarCLI

struct ProviderCredentialCharacterizationTests {
    @Test
    func `config API key projection is explicit for every supported provider`() {
        let supported: Set<UsageProvider> = [.claude]
        for provider in UsageProvider.allCases {
            let environment = ProviderConfigEnvironment.applyAPIKeyOverride(
                base: ["BASE": "preserved", "ANTHROPIC_ADMIN_KEY": "environment-token"],
                provider: provider,
                config: ProviderConfig(id: provider.instanceID, apiKey: "config-token"))
            #expect(environment["BASE"] == "preserved")
            #expect(ProviderConfigEnvironment.supportsAPIKeyOverride(for: provider) == supported.contains(provider))
            #expect(environment["ANTHROPIC_ADMIN_KEY"] == (
                supported.contains(provider) ? "config-token" : "environment-token"))
        }
    }

    @Test
    func `unsupported config fields do not project unrelated credentials`() {
        for provider in UsageProvider.allCases {
            let environment = ProviderConfigEnvironment.applyProviderConfigOverrides(
                base: ["BASE": "preserved"],
                provider: provider,
                config: ProviderConfig(
                    id: provider.instanceID,
                    apiKey: "key",
                    secretKey: "secret",
                    region: "custom",
                    workspaceID: "workspace",
                    enterpriseHost: "https://api.example"))
            let expected = provider == .claude
                ? ["BASE": "preserved", "ANTHROPIC_ADMIN_KEY": "key"]
                : ["BASE": "preserved"]
            #expect(environment == expected, Comment(rawValue: provider.rawValue))
        }
    }

    @Test
    func `token account catalog names every supported provider and injection mode`() {
        let support = TokenAccountSupportCatalog.support(for: .claude)
        guard case .cookieHeader = support?.injection else {
            Issue.record("Expected Claude cookie injection")
            return
        }
        #expect(support?.requiresManualCookieSource == true)
        #expect(TokenAccountSupportCatalog.normalizedCookieHeader(
            for: .claude,
            token: "account-token") == "sessionKey=account-token")
        let resolved = ProviderCookieSettingsResolver.resolve(
            provider: .claude,
            configuredSource: .auto,
            configuredHeader: "config-cookie",
            selectedAccount: ProviderTokenAccount(
                id: UUID(), label: "fixture", token: "account-token", addedAt: 0, lastUsed: nil))
        #expect(resolved.cookieSource == .manual)
        #expect(resolved.manualCookieHeader == "sessionKey=account-token")

        let actual = Set(ProviderDescriptorRegistry.all.compactMap { descriptor in
            TokenAccountSupportCatalog.support(for: descriptor.id) == nil ? nil : descriptor.id
        })
        #expect(actual == [.claude])
        #expect(TokenAccountSupportCatalog.support(for: .codex) == nil)
    }

    @Test
    func `token accounts override config and environment credentials`() {
        let fixtures: [(String, String)] = [
            ("sk-ant-admin-account", "ANTHROPIC_ADMIN_KEY"),
            ("sk-ant-oat01-account", ClaudeOAuthCredentialsStore.environmentTokenKey),
        ]
        for (token, key) in fixtures {
            let account = ProviderTokenAccount(
                id: UUID(), label: "fixture", token: token, addedAt: 0, lastUsed: nil)
            let environment = ProviderEnvironmentResolver.resolve(
                base: [
                    "BASE": "preserved",
                    "ANTHROPIC_ADMIN_KEY": "environment-token",
                    "ANTHROPIC_ADMIN_API_KEY": "alternate-token",
                    ClaudeOAuthCredentialsStore.environmentTokenKey: "ambient-oauth",
                ],
                provider: .claude,
                config: ProviderConfig(id: .claude, apiKey: "config-token"),
                selectedAccount: account)
            #expect(environment == ["BASE": "preserved", key: token])
        }
    }

    @Test
    func `provider validation verdicts remain stable`() {
        for provider in UsageProvider.allCases {
            let codes = Self.issueCodes(for: ProviderConfig(
                id: provider.instanceID,
                secretKey: "secret",
                region: "custom",
                workspaceID: "workspace",
                enterpriseHost: "https://api.example"))
            #expect(codes.contains("region_unused"))
            #expect(codes.contains("secret_key_unused"))
            #expect(codes.contains("workspace_unused"))
            #expect(codes.contains("enterprise_host_unused"))
        }
        let account = ProviderTokenAccount(
            id: UUID(), label: "fixture", token: "token", addedAt: 0, lastUsed: nil)
        let accounts = ProviderTokenAccountData(version: 1, accounts: [account], activeIndex: 0)
        #expect(Self.issueCodes(for: ProviderConfig(id: .codex, tokenAccounts: accounts))
            .contains("token_accounts_unused"))
        #expect(!Self.issueCodes(for: ProviderConfig(id: .claude, tokenAccounts: accounts))
            .contains("token_accounts_unused"))
    }

    @Test
    func `CLI diagnose classifies every credential environment`() {
        for key in ClaudeAdminAPISettingsReader.apiKeyEnvironmentKeys {
            let summary = CodexBarCLI._diagnosticAuthSummaryForTesting(
                provider: .claude,
                account: nil,
                config: nil,
                environment: [key: "token"],
                settings: nil)
            #expect(summary.configured)
            #expect(summary.modes == ["api"])
        }
    }

    private static func issueCodes(for provider: ProviderConfig) -> Set<String> {
        Set(CodexBarConfigValidator.validate(CodexBarConfig(providers: [provider])).map(\.code))
    }
}
