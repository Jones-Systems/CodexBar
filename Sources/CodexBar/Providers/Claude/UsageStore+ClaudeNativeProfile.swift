import CodexBarCore

extension UsageStore {
    func shouldWithholdClaudeNativeProfileHistory() -> Bool {
        guard self.snapshots[.claude] == nil else { return false }
        return (self.providerRuntimes[.claude] as? ClaudeProviderRuntime)?.nativeProfileTransitionPending == true
            || ClaudeNativeProfileSelection.isSelected(environment: self.claudeNativeProfileFetchEnvironment())
    }

    func claudeNativeProfileFetchEnvironment() -> [String: String] {
        ProviderRegistry.makeEnvironment(
            base: self.environmentBase, provider: .claude, settings: self.settings, tokenOverride: nil)
    }

    func reconcileClaudeNativeProfileEnvironment(_ environment: [String: String]) {
        (self.providerRuntimes[.claude] as? ClaudeProviderRuntime)?.reconcileNativeProfileEnvironment(
            environment, store: self, invalidateInFlight: false)
    }

    func claudeNativeProfileEnvironmentIsCurrent(_ environment: [String: String]) -> Bool {
        let current = self.claudeNativeProfileFetchEnvironment()
        guard current[ClaudeNativeProfileSelection.identityKey] != environment[ClaudeNativeProfileSelection.identityKey]
        else { return true }
        self.reconcileClaudeNativeProfileEnvironment(current)
        return false
    }
}
