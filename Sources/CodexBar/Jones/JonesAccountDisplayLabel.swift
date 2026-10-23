import CodexBarCore
import CryptoKit
import Foundation

enum JonesAccountDisplayLabel {
    static func resolve(
        provider: UsageProvider,
        profileIdentity: String,
        verifiedAlias: String? = nil,
        override: String? = nil) -> String
    {
        if let override = self.nonempty(override) { return override }
        if let alias = self.nonempty(verifiedAlias) {
            if alias == "default" { return alias }
            if provider == .codex, alias.lowercased() == "umich" { return "UMICH" }
            return alias.prefix(1).uppercased() + alias.dropFirst()
        }
        let key = self.overrideKey(provider: provider, profileIdentity: profileIdentity)
        return "Account · " + self.digest(key).prefix(8)
    }

    static func overrideKey(provider: UsageProvider, profileIdentity: String) -> String {
        provider.rawValue + ":" + self.digest(profileIdentity)
    }

    static func codexProfileIdentity(for account: CodexVisibleAccount) -> String {
        self.codexProfileIdentity(for: account.selectionSource)
    }

    static func codexProfileIdentity(for source: CodexActiveSource) -> String {
        switch source {
        case .liveSystem: "system"
        case let .managedAccount(id): "managed:" + id.uuidString.lowercased()
        case let .profileHome(path): "profile:" + (CodexHomeScope.normalizedHomePath(path) ?? path)
        }
    }

    static func claudeProfileIdentity(alias: String, home: String, configDirectory: String?) -> String {
        // Provider-specific by design: Claude label overrides use the alias and effective config directory as identity.
        let effectiveDirectory = configDirectory ?? URL(fileURLWithPath: home).appendingPathComponent(".claude").path
        return "native-profile:" + alias + ":" + URL(fileURLWithPath: effectiveDirectory).standardizedFileURL.path
    }

    static func codexAlias(for account: CodexVisibleAccount) -> String? {
        if case .liveSystem = account.selectionSource { return "default" }
        return account.fleetProfileAlias
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
