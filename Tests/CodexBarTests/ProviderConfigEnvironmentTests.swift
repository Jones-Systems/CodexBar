import CodexBarCore
import Testing

struct ProviderConfigEnvironmentTests {
    @Test
    func `Claude config override uses the preferred admin key environment`() {
        let config = ProviderConfig(id: .claude, apiKey: "config-admin-token")
        let environment = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [
                ClaudeAdminAPISettingsReader.adminAPIKeyEnvironmentKey: "ambient-admin-token",
                ClaudeAdminAPISettingsReader.alternateAdminAPIKeyEnvironmentKey: "ambient-alternate-token",
            ],
            provider: .claude,
            config: config)

        #expect(environment[ClaudeAdminAPISettingsReader.adminAPIKeyEnvironmentKey] == "config-admin-token")
        #expect(environment[ClaudeAdminAPISettingsReader.alternateAdminAPIKeyEnvironmentKey] == "ambient-alternate-token")
        #expect(ProviderTokenResolver.token(for: .claude, environment: environment) == "config-admin-token")
    }

    @Test
    func `leaves environment when API key missing`() {
        let config = ProviderConfig(id: .claude, apiKey: nil)
        let environment = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [ClaudeAdminAPISettingsReader.adminAPIKeyEnvironmentKey: "existing"],
            provider: .claude,
            config: config)

        #expect(environment[ClaudeAdminAPISettingsReader.adminAPIKeyEnvironmentKey] == "existing")
    }
}
