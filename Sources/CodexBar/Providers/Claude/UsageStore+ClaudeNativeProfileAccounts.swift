import CodexBarCore
import Foundation

struct ClaudeNativeProfileAccountsState {
    let selectedAlias: String
    let selectedIdentity: String
    let configRevision: UInt64
    var profiles: [ClaudeFleetProfileDiscovery.Profile]
    var identities: [String: String]
}

extension UsageStore {
    func claudeNativeProfileAccountsForDisplay() -> [ProviderAccountUsageSnapshot] {
        guard let state = self.claudeNativeProfileAccountsState,
              self.isEnabled(.claude),
              self.settings.claudeNativeProfileAlias == state.selectedAlias,
              self.settings.providerConfigRevision(for: .claude) == state.configRevision,
              self.settings.effectiveSelectedTokenAccount(for: .claude) == nil
        else { return [] }
        return self.claudeNativeProfileAccountSnapshots.map { account in
            guard let profile = state.profiles.first(where: { $0.alias == account.id.opaqueID }) else { return account }
            return self.nativeProfileAccount(
                profile: profile, selectedAlias: state.selectedAlias, snapshot: account.snapshot,
                error: account.error, sourceLabel: account.sourceLabel)
        }
    }

    func selectedClaudeNativeProfileDisplayLabel() -> String? {
        guard let alias = self.settings.claudeNativeProfileAlias,
              self.settings.effectiveSelectedTokenAccount(for: .claude) == nil,
              ClaudeNativeProfileSelection.applies(
                  alias: alias, source: self.settings.claudeUsageDataSource, hasTokenAccount: false,
                  hasManualCookie: self.settings.claudeCookieSource == .manual && !self.settings.claudeCookieHeader
                      .isEmpty,
                  environment: self.environmentBase),
              self.settings.claudeUsageDataSource != .auto || self.settings.claudeAdminAPIKey.isEmpty,
              let identity = (self.providerRuntimes[.claude] as? ClaudeProviderRuntime)?.lastNativeProfileIdentity
        else { return nil }
        let fields = identity.components(separatedBy: "\n")
        guard fields.count == 5, fields[0] == alias else { return nil }
        return self.settings.accountDisplayLabel(
            provider: .claude,
            profileIdentity: JonesAccountDisplayLabel.claudeProfileIdentity(
                alias: alias, home: fields[1], configDirectory: fields[2] == "<unset>" ? nil : fields[2]),
            verifiedAlias: alias)
    }

    func clearClaudeNativeProfileAccountState() {
        self.claudeNativeProfileAccountsTask?.cancel()
        self.claudeNativeProfileAccountsTask = nil
        self.claudeNativeProfileAccountsTaskID = nil
        let hadState = self.claudeNativeProfileAccountsState != nil ||
            !self.claudeNativeProfileAccountSnapshots.isEmpty || !self.claudeNativeProfileRefreshingAliases.isEmpty
        self.claudeNativeProfileAccountsState = nil
        self.claudeNativeProfileAccountSnapshots = []
        self.claudeNativeProfileRefreshingAliases = []
        if hadState { self.claudeNativeProfileAccountsRevision &+= 1 }
    }

    /// The provider request awaits this task, including cancellation drain, before its replacement may fetch.
    /// Side environments never enter the main profile reconciliation path: that would retire the selected usage.
    func refreshClaudeNativeProfileAccountsAfterMain(generation: UInt64? = nil) async {
        guard !Task.isCancelled,
              self.isCurrentProviderRefreshGeneration(.claude, generation: generation) else { return }
        let environment = self.claudeNativeProfileFetchEnvironment()
        let discovery = self.nativeProfileAccountsDiscovery()
        guard self.isEnabled(.claude),
              !ClaudeNativeProfileSelection.isUnavailable(environment: environment),
              let selectedAlias = environment[ClaudeNativeProfileSelection.selectionKey],
              let selectedIdentity = environment[ClaudeNativeProfileSelection.identityKey],
              discovery.profiles.count >= 2,
              discovery.profiles.contains(where: { $0.alias == selectedAlias }),
              ClaudeNativeProfileSelection.environment(
                  base: self.environmentBase,
                  alias: selectedAlias,
                  discovery: discovery)[ClaudeNativeProfileSelection.identityKey]
              == selectedIdentity
        else {
            self.clearClaudeNativeProfileAccountState()
            return
        }

        let identities = Dictionary(uniqueKeysWithValues: discovery.profiles.map { profile in
            (profile.alias, ClaudeNativeProfileSelection.environment(
                base: self.environmentBase, alias: profile.alias,
                discovery: discovery)[ClaudeNativeProfileSelection.identityKey]!)
        })
        let previousIdentities = self.claudeNativeProfileAccountsState?.identities ?? [:]
        let previous = Dictionary(uniqueKeysWithValues: self.claudeNativeProfileAccountSnapshots.map {
            ($0.id.opaqueID, $0)
        })
        self.claudeNativeProfileAccountsState = ClaudeNativeProfileAccountsState(
            selectedAlias: selectedAlias, selectedIdentity: selectedIdentity,
            configRevision: self.settings.providerConfigRevision(for: .claude),
            profiles: discovery.profiles, identities: identities)
        self.claudeNativeProfileAccountSnapshots = discovery.profiles.map { profile in
            let old = previousIdentities[profile.alias] == identities[profile.alias] ? previous[profile.alias] : nil
            let selected = profile.alias == selectedAlias
            return self.nativeProfileAccount(
                profile: profile, selectedAlias: selectedAlias,
                snapshot: selected ? self.snapshots[.claude] : old?.snapshot,
                error: selected ? self.errors[.claude] : old?.error,
                sourceLabel: selected ? self.lastSourceLabels[.claude] : old?.sourceLabel)
        }
        let taskID = UUID()
        self.claudeNativeProfileAccountsTaskID = taskID
        self.claudeNativeProfileRefreshingAliases = Set(discovery.profiles.map(\.alias).filter { $0 != selectedAlias })
        self.claudeNativeProfileAccountsRevision &+= 1
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            for profile in discovery.profiles where profile.alias != selectedAlias {
                guard !Task.isCancelled,
                      self.nativeProfileAccountsRequestIsCurrent(taskID: taskID, generation: generation)
                else { break }
                let context = self.makeFetchContext(
                    provider: .claude, override: nil, claudeNativeProfileAliasOverride: profile.alias)
                guard context.env[ClaudeNativeProfileSelection.identityKey] == identities[profile.alias] else {
                    self.retireChangedNativeProfileRow(profile, taskID: taskID)
                    continue
                }
                let outcome: ProviderFetchOutcome = if let override = self
                    ._test_claudeNativeProfileFetchOutcomeOverride
                {
                    await override(context)
                } else {
                    await withTaskGroup(of: ProviderFetchOutcome.self) { group in
                        group.addTask {
                            await ProviderDescriptorRegistry.descriptor(for: .claude).fetchOutcome(context: context)
                        }
                        return await group.next()!
                    }
                }
                guard !Task.isCancelled,
                      self.nativeProfileAccountsRequestIsCurrent(taskID: taskID, generation: generation)
                else { break }
                let current = ClaudeNativeProfileSelection.environment(
                    base: self.environmentBase, alias: profile.alias, discovery: self.nativeProfileAccountsDiscovery())
                guard current[ClaudeNativeProfileSelection.identityKey] == identities[profile.alias] else {
                    self.retireChangedNativeProfileRow(profile, taskID: taskID)
                    continue
                }
                if case let .failure(error) = outcome.result, error is CancellationError { continue }
                let old = self.claudeNativeProfileAccountSnapshots.first { $0.id.opaqueID == profile.alias }
                let snapshot: UsageSnapshot?
                let error: String?
                let sourceLabel: String?
                switch outcome.result {
                case let .success(result):
                    snapshot = result.usage.scoped(to: .claude)
                    error = nil
                    sourceLabel = result.sourceLabel
                case let .failure(failure):
                    snapshot = old?.snapshot
                    error = failure.localizedDescription
                    sourceLabel = old?.sourceLabel
                }
                self.replaceNativeProfileRow(self.nativeProfileAccount(
                    profile: profile, selectedAlias: selectedAlias, snapshot: snapshot,
                    error: error, sourceLabel: sourceLabel))
                self.claudeNativeProfileRefreshingAliases.remove(profile.alias)
                self.claudeNativeProfileAccountsRevision &+= 1
            }
        }
        self.claudeNativeProfileAccountsTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        guard self.claudeNativeProfileAccountsTaskID == taskID else { return }
        self.claudeNativeProfileAccountsTask = nil
        self.claudeNativeProfileAccountsTaskID = nil
        self.claudeNativeProfileRefreshingAliases = []
        self.claudeNativeProfileAccountsRevision &+= 1
    }

    private func nativeProfileAccountsRequestIsCurrent(taskID: UUID, generation: UInt64?) -> Bool {
        guard self.claudeNativeProfileAccountsTaskID == taskID,
              let state = self.claudeNativeProfileAccountsState,
              self.isEnabled(.claude),
              self.isCurrentProviderRefreshGeneration(.claude, generation: generation),
              self.settings.providerConfigRevision(for: .claude) == state.configRevision,
              self.settings.claudeNativeProfileAlias == state.selectedAlias
        else { return false }
        let current = self.claudeNativeProfileFetchEnvironment()
        let discovered = ClaudeNativeProfileSelection.environment(
            base: self.environmentBase, alias: state.selectedAlias, discovery: self.nativeProfileAccountsDiscovery())
        let identityIsCurrent = current[ClaudeNativeProfileSelection.identityKey] == state.selectedIdentity &&
            discovered[ClaudeNativeProfileSelection.identityKey] == state.selectedIdentity &&
            !ClaudeNativeProfileSelection.isUnavailable(environment: current)
        if !identityIsCurrent { self.clearClaudeNativeProfileAccountState() }
        return identityIsCurrent
    }

    private func nativeProfileAccountsDiscovery() -> ClaudeFleetProfileDiscovery.Result {
        self._test_claudeNativeProfileDiscoveryOverride?() ?? ClaudeFleetProfileDiscovery.discover()
    }

    private func retireChangedNativeProfileRow(_ profile: ClaudeFleetProfileDiscovery.Profile, taskID: UUID) {
        guard self.claudeNativeProfileAccountsTaskID == taskID,
              let selectedAlias = self.claudeNativeProfileAccountsState?.selectedAlias else { return }
        self.claudeNativeProfileAccountsState?.identities.removeValue(forKey: profile.alias)
        self.replaceNativeProfileRow(self.nativeProfileAccount(
            profile: profile, selectedAlias: selectedAlias, snapshot: nil,
            error: ClaudeNativeProfileSelectionError.unavailable.localizedDescription, sourceLabel: nil))
        self.claudeNativeProfileRefreshingAliases.remove(profile.alias)
        self.claudeNativeProfileAccountsRevision &+= 1
    }

    private func replaceNativeProfileRow(_ account: ProviderAccountUsageSnapshot) {
        guard let index = self.claudeNativeProfileAccountSnapshots.firstIndex(where: { $0.id == account.id })
        else { return }
        self.claudeNativeProfileAccountSnapshots[index] = account
    }

    private func nativeProfileAccount(
        profile: ClaudeFleetProfileDiscovery.Profile, selectedAlias: String,
        snapshot: UsageSnapshot?, error: String?, sourceLabel: String?) -> ProviderAccountUsageSnapshot
    {
        ProviderAccountUsageSnapshot(
            id: ProviderAccountIdentity(source: "claude-native-profile", opaqueID: profile.alias),
            provider: .claude,
            displayLabel: self.settings.accountDisplayLabel(
                provider: .claude,
                profileIdentity: JonesAccountDisplayLabel.claudeProfileIdentity(
                    alias: profile.alias, home: profile.home, configDirectory: profile.configDirectory),
                verifiedAlias: profile.alias),
            accountEmail: snapshot?.accountEmail(for: .claude),
            isActive: profile.alias == selectedAlias,
            canActivate: false, snapshot: snapshot, error: error, sourceLabel: sourceLabel)
    }
}
