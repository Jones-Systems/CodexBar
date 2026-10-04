import CodexBarCore

extension ProvidersPane {
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
            // are historical provider-scoped observations, never attributed to a CAAM account.
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
