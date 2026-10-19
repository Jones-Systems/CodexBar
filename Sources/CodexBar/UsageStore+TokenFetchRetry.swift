import CodexBarCore

extension UsageStore {
    /// Fast failures may retry on the next scheduled pass instead of waiting out the fetch
    /// TTL; timed-out scans keep the TTL so a slow corpus cannot thrash back-to-back rescans.
    nonisolated static func tokenFetchFailureAllowsEarlyRetry(_ error: Error) -> Bool {
        if case CostUsageError.timedOut = error {
            return false
        }
        return true
    }
}
