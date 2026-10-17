import Foundation

/// Routes an explicit enrolled reference inside one usage environment, never the process environment.
public enum ClaudeNativeProfileSelection {
    public static let selectionKey = "CODEXBAR_CLAUDE_NATIVE_PROFILE"
    public static let unavailableKey = "CODEXBAR_CLAUDE_NATIVE_PROFILE_UNAVAILABLE"
    public static let identityKey = "CODEXBAR_CLAUDE_NATIVE_PROFILE_IDENTITY"

    public static func applies(
        alias: String?, source: ClaudeUsageDataSource, hasTokenAccount: Bool,
        hasManualCookie: Bool, environment: [String: String]) -> Bool
    {
        guard alias != nil, !hasTokenAccount, source != .api, source != .web else { return false }
        if source == .auto {
            return !hasManualCookie && ClaudeAdminAPISettingsReader.apiKey(environment: environment) == nil
        }
        return true
    }

    public static func environment(
        base: [String: String], alias: String, discovery: ClaudeFleetProfileDiscovery.Result) -> [String: String]
    {
        // Match the producer's native environment allowlist. In particular, no ambient auth token,
        // cloud-provider mode, host marker, config override, or secure-storage override crosses this boundary.
        let allowed: Set = [
            "PATH",
            "LANG",
            "LC_ALL",
            "LC_CTYPE",
            "TERM",
            "TMPDIR",
            "DISPLAY",
            "SSH_AUTH_SOCK",
            "USER",
            "LOGNAME",
        ]
        var environment = base.filter { allowed.contains($0.key) }
        environment[self.selectionKey] = alias
        guard let profile = discovery.profiles.first(where: { $0.alias == alias }) else {
            environment[self.unavailableKey] = "1"
            environment[self.identityKey] = "unavailable:" + alias
            return environment
        }
        environment["HOME"] = profile.home
        environment[ClaudeConfigPaths.configDirectoryEnvironmentKey] = profile.configDirectory
        environment["CLAUDE_CLI_PATH"] = profile.nativeCLI
        environment[self.identityKey] = [
            profile.alias,
            profile.home,
            profile.configDirectory ?? "<unset>",
            profile.nativeCLI,
            profile.store,
        ].joined(separator: "\n")
        return environment
    }

    public static func isSelected(environment: [String: String]) -> Bool {
        environment[self.selectionKey] != nil
    }

    public static func isUnavailable(environment: [String: String]) -> Bool {
        environment[self.unavailableKey] != nil
    }

    public static func validateCredentialOwner(
        _ owner: ClaudeOAuthCredentialOwner, environment: [String: String]) throws
    {
        if self.isSelected(environment: environment), owner != .claudeCLI {
            throw ClaudeNativeProfileSelectionError.independentCredential
        }
    }

    public static func validate(environment: [String: String]) throws {
        if self.isUnavailable(environment: environment) { throw ClaudeNativeProfileSelectionError.unavailable }
    }
}

public enum ClaudeNativeProfileSelectionError: LocalizedError, Sendable {
    case unavailable
    case independentCredential
    case usageUnavailable(any Error)

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            "Selected Claude native profile is unavailable, removed, or has invalid enrollment metadata. " +
                "Choose an enrolled profile in Claude Settings."
        case .independentCredential:
            "Selected Claude native profile has no usable native credential. Independent CodexBar credentials " +
                "cannot stand in for this profile."
        case let .usageUnavailable(error):
            "Selected Claude native profile could not provide usage. Enrollment does not establish " +
                "authentication or usage access. " + error.localizedDescription
        }
    }
}
