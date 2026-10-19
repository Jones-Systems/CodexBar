import CodexBarCore
import Foundation

extension SettingsStore {
    static let accountDisplayLabelOverridesKey = "accountDisplayLabelOverrides"

    func accountDisplayLabel(
        provider: UsageProvider,
        profileIdentity: String,
        verifiedAlias: String? = nil) -> String
    {
        let key = JonesAccountDisplayLabel.overrideKey(provider: provider, profileIdentity: profileIdentity)
        let overrides = self.userDefaults.dictionary(forKey: Self.accountDisplayLabelOverridesKey) as? [String: String]
        return JonesAccountDisplayLabel.resolve(
            provider: provider,
            profileIdentity: profileIdentity,
            verifiedAlias: verifiedAlias,
            override: overrides?[key])
    }

    func setAccountDisplayLabel(_ label: String?, provider: UsageProvider, profileIdentity: String) {
        let key = JonesAccountDisplayLabel.overrideKey(provider: provider, profileIdentity: profileIdentity)
        var overrides = self.userDefaults.dictionary(forKey: Self.accountDisplayLabelOverridesKey)
            as? [String: String] ?? [:]
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        overrides[key] = trimmed?.isEmpty == false ? trimmed : nil
        self.userDefaults.set(overrides, forKey: Self.accountDisplayLabelOverridesKey)
    }

    func codexAccountDisplayLabel(for account: CodexVisibleAccount) -> String {
        self.accountDisplayLabel(
            provider: .codex,
            profileIdentity: JonesAccountDisplayLabel.codexProfileIdentity(for: account),
            verifiedAlias: JonesAccountDisplayLabel.codexAlias(for: account))
    }

    func codexAccountDisplayLabels(for accounts: [CodexVisibleAccount]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, self.codexAccountDisplayLabel(for: $0)) })
    }
}
