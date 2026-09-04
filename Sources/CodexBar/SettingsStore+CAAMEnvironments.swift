import CodexBarCore
import Foundation

extension SettingsStore {
    var codexCAAMEnvironments: [CAAMEnvironmentConfiguration] {
        // Provider-specific by design: CAAM environment control is scoped to Codex accounts.
        self.config.providerConfig(for: .codex)?.codexCAAMEnvironments ?? []
    }

    func setCodexCAAMEnvironments(_ environments: [CAAMEnvironmentConfiguration]) throws {
        let validated = try CAAMEnvironmentContract.validateConfigurations(environments)
        self.updateProviderDetailConfig(provider: .codex) { config in
            config.codexCAAMEnvironments = validated.isEmpty ? nil : validated
        }
    }
}
