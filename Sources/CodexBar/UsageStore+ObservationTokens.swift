import Foundation

@MainActor
extension UsageStore {
    var menuObservationToken: Int {
        _ = self.snapshots
        _ = self.errors
        _ = self.diagnostics
        _ = self.knownLimitsAvailabilityByProvider
        _ = self.lastSourceLabels
        _ = self.lastFetchAttempts
        _ = (self.accountSnapshots, self.tokenAccountLiveStateProviders, self.codexAccountSnapshots)
        _ = self.claudeSwapAccountSnapshots
        _ = self.claudeSwapLastError
        _ = self.claudeSwapRevision
        _ = self.claudeNativeProfileAccountsRevision
        _ = self.tokenSnapshots
        _ = self.tokenErrors
        _ = self.tokenRefreshInFlight
        _ = self.codexCostCatchUpActivity
        _ = self.credits
        _ = self.lastCreditsError
        _ = self.openAIDashboard
        _ = self.lastOpenAIDashboardError
        _ = self.openAIDashboardRequiresLogin
        _ = self.openAIDashboardAttachmentRevision
        _ = self.versions
        _ = self.isRefreshing
        _ = self.hasForcedRefreshEnrichmentInFlight
        _ = self.refreshingProviders
        _ = self.pathDebugInfo
        _ = self.statuses
        _ = self.probeLogs
        _ = self.historicalPaceRevision
        _ = self.planUtilizationHistoryRevision
        _ = self.providerStorageFootprints
        return 0
    }

    var iconObservationToken: Int {
        _ = self.snapshots
        _ = self.claudeSwapAccountSnapshots
        _ = self.claudeSwapRevision
        _ = self.errors
        _ = self.diagnostics
        _ = self.knownLimitsAvailabilityByProvider
        _ = self.credits
        _ = self.lastCreditsError
        _ = self.openAIDashboard
        _ = self.lastOpenAIDashboardError
        _ = self.openAIDashboardRequiresLogin
        _ = self.refreshingProviders
        _ = self.statuses
        _ = self.tokenSnapshotPublications
        _ = self.spendDashboardTokenPublications
        _ = self.spendDashboardPublication.revision
        _ = self.historicalPaceRevision
        return 0
    }
}
