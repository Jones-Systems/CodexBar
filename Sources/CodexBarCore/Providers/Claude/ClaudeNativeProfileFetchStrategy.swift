import Foundation

/// Keeps the existing native transports and their consent gates inside one selected authority.
struct ClaudeNativeProfileFetchStrategy: ProviderFetchStrategy {
    let base: any ProviderFetchStrategy
    var id: String {
        self.base.id
    }

    var kind: ProviderFetchKind {
        self.base.kind
    }

    func isAvailable(_: ProviderFetchContext) async -> Bool {
        true
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        try ClaudeNativeProfileSelection.validate(environment: context.env)
        let isSelected = ClaudeNativeProfileSelection.isSelected(environment: context.env)
        let accountID = isSelected ? ClaudeAccountProfile.accountUuid(environment: context.env)?.lowercased() : nil
        do {
            if self.kind == .cli {
                guard let binary = context.env["CLAUDE_CLI_PATH"],
                      FileManager.default.isExecutableFile(atPath: binary),
                      ClaudeAccountProfile.accountUuid(environment: context.env) != nil,
                      await self.base.isAvailable(context)
                else { throw ClaudeNativeProfileSelectionError.unavailable }
            }
            let result = try await self.base.fetch(context)
            guard isSelected else { return result }
            guard accountID == ClaudeAccountProfile.accountUuid(environment: context.env)?.lowercased() else {
                throw ClaudeNativeProfileSelectionError.unavailable
            }
            guard let accountID else { return result }
            let identity = result.usage.identity
            guard identity?.providerID == nil || identity?.providerID == .claude else { return result }
            if let returnedID = identity?.accountID,
               returnedID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != accountID
            {
                throw ClaudeNativeProfileSelectionError.unavailable
            }
            let usage = result.usage.withIdentity(ProviderIdentitySnapshot(
                providerID: .claude,
                accountEmail: identity?.accountEmail,
                accountOrganization: identity?.accountOrganization,
                loginMethod: identity?.loginMethod,
                accountID: accountID))
            return ProviderFetchResult(
                usage: usage,
                credits: result.credits,
                dashboard: result.dashboard,
                sourceLabel: result.sourceLabel,
                strategyID: result.strategyID,
                strategyKind: result.strategyKind,
                codexResetCreditsAttempted: result.codexResetCreditsAttempted,
                codexMonthlyLimitEnrichmentFailed: result.codexMonthlyLimitEnrichmentFailed,
                diagnostic: result.diagnostic,
                claudeOAuthKeychainPersistentRefHash: result.claudeOAuthKeychainPersistentRefHash,
                claudeOAuthHistoryOwnerIdentifier: result.claudeOAuthHistoryOwnerIdentifier,
                claudeOAuthCredentialOwner: result.claudeOAuthCredentialOwner,
                claudeOAuthKeychainCredentialMismatch: result.claudeOAuthKeychainCredentialMismatch,
                claudeOAuthKeychainCredentialAbsent: result.claudeOAuthKeychainCredentialAbsent,
                claudeOAuthKeychainCredentialUnavailable: result.claudeOAuthKeychainCredentialUnavailable)
        } catch {
            if Task.isCancelled || ClaudeOAuthFetchError.isCancellation(error) { throw error }
            throw ClaudeNativeProfileSelectionError.usageUnavailable(error)
        }
    }

    func shouldFallback(on error: Error, context: ProviderFetchContext) -> Bool {
        guard !ClaudeNativeProfileSelection.isUnavailable(environment: context.env) else { return false }
        if case let ClaudeNativeProfileSelectionError.usageUnavailable(underlying) = error {
            return self.base.shouldFallback(on: underlying, context: context)
        }
        return false
    }

    static func strategies(context: ProviderFetchContext) -> [any ProviderFetchStrategy] {
        let cli = Self(base: ClaudeCLIFetchStrategy(
            useWebExtras: false,
            includePrepaidBalance: false,
            manualCookieHeader: nil,
            browserDetection: context.browserDetection,
            hasWebFallback: false))
        if context.sourceMode == .cli || context.claudeOwnerCLIRecoveryOnly { return [cli] }
        return [Self(base: ClaudeOAuthFetchStrategy()), cli]
    }
}
