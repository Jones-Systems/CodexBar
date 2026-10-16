import CodexBarCore

extension ProvidersPane {
    func observabilityAccountInputs() -> [HubAccountObservation] {
        guard let projection = self.settings.codexVisibleAccountProjectionForMenuDisplay else { return [] }
        return self.settings.orderedCodexAccounts(projection.visibleAccounts).map { account in
            HubAccountObservation(
                environmentID: "local",
                environmentLabel: L("This Mac"),
                profile: account.displayName,
                provider: "codex",
                stableID: nil,
                displayLabel: nil,
                hostDefault: account.isLive,
                health: account.authenticationHealthLabel == nil ? .unknown : .warning,
                evidence: HubEvidence(
                    source: "Existing local account projection", observedAt: nil, availability: .partial),
                id: "local:\(account.id)")
        }
    }

    func observabilityProviderInputs() -> [HubProviderInput] {
        self.store.enabledProvidersForDisplay().prefix(ObservabilityHub.maximumProviders).map { instanceID in
            let provider = instanceID.firstPartyProvider
            let publication = self.store.tokenSnapshotPublications[instanceID]
            let cost: CostUsageTokenSnapshot? = if let provider, let publication,
                                                   publication.providerConfigRevision ==
                                                   self.settings.providerConfigRevision(for: provider)
            {
                publication.snapshot
            } else {
                nil
            }
            // Deliberately do not call presentationSnapshot or scope-signature resolvers here:
            // some of those helpers load disk-backed identity/cookie caches. Published cost records
            // are historical provider-scoped observations, never attributed to a specific account.
            return HubProviderInput(
                id: instanceID.rawValue,
                label: provider.map { self.store.metadata(for: $0).displayName } ?? instanceID.rawValue,
                source: self.store.lastSourceLabels[instanceID] ?? "Existing provider snapshot",
                usage: self.store.snapshots[instanceID],
                cost: cost,
                usageFailed: self.store.errors[instanceID] != nil,
                costFailed: self.store.tokenErrors[instanceID] != nil)
        }
    }
}
