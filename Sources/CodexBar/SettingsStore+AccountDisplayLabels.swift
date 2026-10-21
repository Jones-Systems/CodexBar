import CodexBarCore
import Foundation

extension SettingsStore {
    static let accountDisplayLabelOverridesKey = "accountDisplayLabelOverrides"

    func accountDisplayLabel(
        provider: UsageProvider,
        profileIdentity: String,
        verifiedAlias: String? = nil) -> String
    {
        JonesAccountDisplayLabel.resolve(
            provider: provider,
            profileIdentity: profileIdentity,
            verifiedAlias: verifiedAlias,
            override: self.accountDisplayLabelOverride(provider: provider, profileIdentity: profileIdentity))
    }

    func accountDisplayLabelOverride(provider: UsageProvider, profileIdentity: String) -> String? {
        let key = JonesAccountDisplayLabel.overrideKey(provider: provider, profileIdentity: profileIdentity)
        let overrides = self.userDefaults.dictionary(forKey: Self.accountDisplayLabelOverridesKey) as? [String: String]
        guard let label = overrides?[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty else {
            return nil
        }
        return label
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
