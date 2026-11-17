import CodexBarCore
import SwiftUI

extension UsageMenuCardView.Model {
    /// Resolves the displayed primary percentage/reset through the provider's binding quotas.
    /// Primary-owned detail text remains sourced from the raw primary window.
    static func bindingQuotaProjection(
        input: Input,
        primary: RateWindow,
        snapshot: UsageSnapshot) -> RateWindowBindingQuotaProjection?
    {
        let lanes = ProviderDescriptorRegistry.descriptor(for: input.provider)
            .presentation.primaryBindingQuotaLanes
        let bindingWindows = lanes.compactMap { lane -> RateWindow? in
            switch lane {
            case .primary: nil
            case .secondary: snapshot.secondary
            case .tertiary: snapshot.tertiary
            }
        }
        guard !bindingWindows.isEmpty else { return nil }
        return RateWindow.bindingQuotaProjection(
            primary: primary,
            bindingLanes: bindingWindows,
            now: input.now)
    }

    struct PaceDetail {
        let leftLabel: String
        let rightLabel: String?
        let pacePercent: Double?
        let paceOnTop: Bool
        /// True only for text produced by a pace calculation. Defaults to false
        /// so provider-owned text sharing the detail slot is preserved.
        let isPaceDerived: Bool

        init(
            leftLabel: String,
            rightLabel: String?,
            pacePercent: Double?,
            paceOnTop: Bool,
            isPaceDerived: Bool = false)
        {
            self.leftLabel = leftLabel
            self.rightLabel = rightLabel
            self.pacePercent = pacePercent
            self.paceOnTop = paceOnTop
            self.isPaceDerived = isPaceDerived
        }
    }

    struct PrimaryMetricPresentation {
        var statusText: String?
        var resetText: String?
        var detailText: String?
        var detailLeft: String?
        var detailRight: String?
        var pacePercent: Double?
        var paceOnTop = true
        var detailIsPaceDerived = false
    }

    static func applyPrimaryQuotaPresentation(
        _ presentation: inout PrimaryMetricPresentation,
        input: Input,
        primary: RateWindow)
    {
        let policy = ProviderDescriptorRegistry.descriptor(for: input.provider).presentation.menuCard
        guard let detail = self.trimmedResetDescription(primary) else { return }
        switch policy.primaryDescriptionPlacement {
        case .reset:
            presentation.resetText = detail
        case .detailLeft:
            presentation.detailLeft = detail
        case .detail:
            presentation.detailText = detail
        case .detailBySecondaryPresence:
            if input.snapshot?.secondary != nil {
                presentation.detailRight = detail
            } else {
                presentation.detailText = detail
            }
        case .standard:
            break
        }
    }

    static func applyPrimaryBalancePresentation(
        _ presentation: inout PrimaryMetricPresentation,
        input: Input,
        primary: RateWindow)
    {
        let policy = ProviderDescriptorRegistry.descriptor(for: input.provider).presentation.menuCard
        if policy.showsPrimaryBalanceDescription,
           let detail = nonEmptyResetDescription(primary)
        {
            presentation.detailText = detail
        }
        if policy.clearsPrimaryReset {
            presentation.resetText = nil
        }
    }

    static func applyPrimaryResetPresentation(
        _ presentation: inout PrimaryMetricPresentation,
        input: Input,
        primary: RateWindow)
    {
        let policy = ProviderDescriptorRegistry.descriptor(for: input.provider).presentation.menuCard
        if policy.usesRawPrimaryResetDescription {
            presentation.resetText = primary.resetDescription
        }
        if policy.hidesPrimaryResetWithoutDate, primary.resetsAt == nil {
            presentation.resetText = nil
        }
        if policy.hidesPrimaryResetWithoutSecondary, input.snapshot?.secondary == nil {
            presentation.resetText = nil
        }
    }

    static func applyPrimaryPacePresentation(
        _ presentation: inout PrimaryMetricPresentation,
        input: Input,
        primary: RateWindow)
    {
        let policy = ProviderDescriptorRegistry.descriptor(for: input.provider).presentation.menuCard
        if let paceDetail = sessionPaceDetail(
            provider: input.provider,
            window: primary,
            now: input.now,
            showUsed: input.usageBarsShowUsed)
        {
            self.apply(paceDetail, to: &presentation)
        }
        if let paceDetail = Self.resetWindowPaceDetail(
            window: primary,
            input: input,
            pace: policy.resetWindowUsesWeeklyPace ? input.weeklyPace : nil)
        {
            Self.apply(paceDetail, to: &presentation)
        }
    }

    static func applyPrimaryFinalOverrides(
        _ presentation: inout PrimaryMetricPresentation,
        input: Input,
        primary: RateWindow)
    {
        let policy = ProviderDescriptorRegistry.descriptor(for: input.provider).presentation.menuCard

        if policy.movesPrimaryDetailToStatus(snapshot: input.snapshot) {
            presentation.statusText = presentation.detailText
            presentation.detailText = nil
        }
    }

    private static func apply(_ paceDetail: PaceDetail, to presentation: inout PrimaryMetricPresentation) {
        presentation.detailLeft = paceDetail.leftLabel
        presentation.detailRight = paceDetail.rightLabel
        presentation.pacePercent = paceDetail.pacePercent
        presentation.paceOnTop = paceDetail.paceOnTop
        presentation.detailIsPaceDerived = paceDetail.isPaceDerived
    }

    private static func nonEmptyResetDescription(_ window: RateWindow) -> String? {
        guard let detail = window.resetDescription,
              !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return detail
    }

    private static func trimmedResetDescription(_ window: RateWindow) -> String? {
        guard let detail = window.resetDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
              !detail.isEmpty
        else { return nil }
        return detail
    }

    static func redactedMetricDetail(_ detail: String?, provider: UsageProvider, metricID: String) -> String? {
        PersonalInfoRedactor.redactEmails(in: detail, isEnabled: true)
    }

    /// Clears the pace stripe and the forecast text when the user hides pace.
    /// Copies every `Metric` field so unrelated decorations (quota and workday
    /// ticks) survive; dropping one here would silently disable them.
    static func paceGatedMetrics(_ metrics: [Metric], paceVisible: Bool) -> [Metric] {
        guard !paceVisible else { return metrics }
        return metrics.map { metric in
            // Detail slots also carry provider quota and reset text. Clear them only
            // when they carry a pace forecast.
            Metric(
                id: metric.id,
                title: metric.title,
                percent: metric.percent,
                percentStyle: metric.percentStyle,
                statusText: metric.statusText,
                resetText: metric.resetText,
                detailText: metric.detailText,
                detailLeftText: metric.detailIsPaceDerived ? nil : metric.detailLeftText,
                detailRightText: metric.detailIsPaceDerived ? nil : metric.detailRightText,
                pacePercent: nil,
                detailIsPaceDerived: metric.detailIsPaceDerived,
                paceOnTop: metric.paceOnTop,
                warningMarkerPercents: metric.warningMarkerPercents,
                workdayMarkerPercents: metric.workdayMarkerPercents,
                workdayTickAppearance: metric.workdayTickAppearance,
                cardStyle: metric.cardStyle,
                sessionEquivalentDetail: nil,
                timing: metric.timing)
        }
    }

    static func redactedMetrics(
        _ metrics: [Metric],
        provider: UsageProvider,
        hidePersonalInfo: Bool) -> [Metric]
    {
        guard hidePersonalInfo else { return metrics }
        return metrics.map { metric in
            Metric(
                id: metric.id,
                title: PersonalInfoRedactor.redactEmails(in: metric.title, isEnabled: true) ?? metric.title,
                percent: metric.percent,
                percentStyle: metric.percentStyle,
                statusText: PersonalInfoRedactor.redactEmails(in: metric.statusText, isEnabled: true),
                resetText: PersonalInfoRedactor.redactEmails(in: metric.resetText, isEnabled: true),
                detailText: Self.redactedMetricDetail(
                    metric.detailText,
                    provider: provider,
                    metricID: metric.id),
                detailLeftText: PersonalInfoRedactor.redactEmails(in: metric.detailLeftText, isEnabled: true),
                detailRightText: PersonalInfoRedactor.redactEmails(in: metric.detailRightText, isEnabled: true),
                pacePercent: metric.pacePercent,
                detailIsPaceDerived: metric.detailIsPaceDerived,
                paceOnTop: metric.paceOnTop,
                warningMarkerPercents: metric.warningMarkerPercents,
                workdayMarkerPercents: metric.workdayMarkerPercents,
                workdayTickAppearance: metric.workdayTickAppearance,
                cardStyle: metric.cardStyle,
                sessionEquivalentDetail: metric.sessionEquivalentDetail,
                timing: metric.timing)
        }
    }

    static func usageNotes(input: Input) -> [String] {
        let subscriptionNotes = self.subscriptionMetadataNotes(snapshot: input.snapshot, provider: input.provider)

        if input.provider == .claude, input.snapshot?.dataConfidence == .percentOnly {
            // Both CLI scraping and restored history carry percentages without full usage detail.
            return [L("claude_limited_usage_detail")] + subscriptionNotes
        }

        return subscriptionNotes
    }

    var isOverviewErrorOnly: Bool {
        self.subtitleStyle == .error &&
            self.metrics.isEmpty &&
            self.usageNotes.isEmpty &&
            self.providerDetails.isEmpty &&
            self.inlineUsageDashboard == nil &&
            self.creditsRemaining == nil &&
            self.providerCost == nil &&
            self.tokenUsage == nil &&
            self.placeholder == nil
    }

    var hasUsageContent: Bool {
        !self.metrics.isEmpty ||
            !self.usageNotes.isEmpty ||
            !self.providerDetails.isEmpty ||
            self.inlineUsageDashboard != nil ||
            self.codexResetCredits != nil ||
            self.placeholder != nil
    }

    var creditsOnlyInlineUsageDashboard: Bool {
        self.creditsText != nil &&
            self.inlineUsageDashboard != nil &&
            self.metrics.isEmpty &&
            self.usageNotes.isEmpty &&
            self.providerDetails.isEmpty &&
            self.codexResetCredits == nil &&
            self.placeholder == nil
    }

    var usesStackedDetailLayout: Bool {
        !self.metrics.isEmpty ||
            self.creditsText != nil ||
            self.codexResetCredits != nil ||
            self.providerCost != nil ||
            self.tokenUsage != nil
    }

    func hasCompatibleTrackedLayout(with candidate: Self) -> Bool {
        self.hasCompatibleTrackedLayout(with: candidate, includeMetrics: true)
    }

    func hasCompatibleTrackedLayoutIgnoringMetrics(with candidate: Self) -> Bool {
        self.hasCompatibleTrackedLayout(with: candidate, includeMetrics: false)
    }

    func hasCompatibleTrackedMetricSubset(of candidate: Self) -> Bool {
        guard self.metrics.count < candidate.metrics.count,
              self.hasCompatibleTrackedLayoutIgnoringMetrics(with: candidate)
        else {
            return false
        }
        return self.metrics.allSatisfy { metric in
            candidate.metrics.contains { Self.hasCompatibleMetricLayout(metric, $0) }
        }
    }

    private func hasCompatibleTrackedLayout(with candidate: Self, includeMetrics: Bool) -> Bool {
        guard self.provider == candidate.provider,
              self.accountIdentityFingerprint == candidate.accountIdentityFingerprint,
              !includeMetrics || self.metrics.count == candidate.metrics.count,
              self.usageNotes == candidate.usageNotes,
              self.providerDetails == candidate.providerDetails,
              Self.hasCompatibleCreditsLayout(
                  currentText: self.creditsText,
                  currentRemaining: self.creditsRemaining,
                  candidateText: candidate.creditsText,
                  candidateRemaining: candidate.creditsRemaining),
              self.creditsHintText == candidate.creditsHintText,
              Self.hasCompatibleCodexResetCreditsLayout(self.codexResetCredits, candidate.codexResetCredits),
              self.placeholder == candidate.placeholder,
              Self.hasCompatibleDashboardLayout(self.inlineUsageDashboard, candidate.inlineUsageDashboard),
              Self.hasCompatibleProviderCostLayout(self.providerCost, candidate.providerCost),
              Self.hasCompatibleTokenUsageLayout(self.tokenUsage, candidate.tokenUsage)
        else {
            return false
        }

        guard includeMetrics else { return true }
        return zip(self.metrics, candidate.metrics).allSatisfy(Self.hasCompatibleMetricLayout)
    }

    private static func hasCompatibleCodexResetCreditsLayout(
        _ current: CodexResetCreditsPresentation?,
        _ candidate: CodexResetCreditsPresentation?) -> Bool
    {
        // The hosted section has a fixed shape; its count and expiry strings can update in place.
        (current == nil) == (candidate == nil)
    }

    private static func hasCompatibleMetricLayout(_ current: Metric, _ candidate: Metric) -> Bool {
        let currentMetaText = current.linePresentation(title: current.title).metaText
        let candidateMetaText = candidate.linePresentation(title: candidate.title).metaText
        return current.id == candidate.id &&
            current.title == candidate.title &&
            current.percentStyle == candidate.percentStyle &&
            (current.statusText == nil) == (candidate.statusText == nil) &&
            (current.resetText == nil) == (candidate.resetText == nil) &&
            (current.detailText == nil) == (candidate.detailText == nil) &&
            (candidateMetaText == nil || currentMetaText != nil) &&
            current.cardStyle == candidate.cardStyle
    }

    private static func hasCompatibleCreditsLayout(
        currentText: String?,
        currentRemaining: Double?,
        candidateText: String?,
        candidateRemaining: Double?) -> Bool
    {
        switch (currentText, candidateText) {
        case (nil, nil):
            return true
        case let (currentText?, candidateText?):
            guard (currentRemaining == nil) == (candidateRemaining == nil) else { return false }
            // Numeric balances render as a fixed single line beside the full-scale label.
            // Multiline workspace balances retain their measured text until the menu reopens.
            return currentRemaining != nil || currentText == candidateText
        default:
            return false
        }
    }

    private static func hasCompatibleDashboardLayout(
        _ current: InlineUsageDashboardModel?,
        _ candidate: InlineUsageDashboardModel?) -> Bool
    {
        switch (current, candidate) {
        case (nil, nil):
            true
        case let (current?, candidate?):
            current.valueStyle == candidate.valueStyle &&
                current.kpis.count == candidate.kpis.count &&
                current.points.count == candidate.points.count &&
                current.detailLines.count == candidate.detailLines.count &&
                zip(current.kpis, candidate.kpis).allSatisfy {
                    $0.title == $1.title && $0.emphasis == $1.emphasis
                } &&
                zip(current.points, candidate.points).allSatisfy {
                    $0.id == $1.id && $0.label == $1.label
                }
        default:
            false
        }
    }

    private static func hasCompatibleProviderCostLayout(
        _ current: ProviderCostSection?,
        _ candidate: ProviderCostSection?) -> Bool
    {
        switch (current, candidate) {
        case (nil, nil):
            true
        case let (current?, candidate?):
            current.title == candidate.title &&
                (current.percentUsed == nil) == (candidate.percentUsed == nil) &&
                (current.percentLine == nil) == (candidate.percentLine == nil) &&
                (current.personalSpendLine == nil) == (candidate.personalSpendLine == nil)
        default:
            false
        }
    }

    private static func hasCompatibleTokenUsageLayout(
        _ current: TokenUsageSection?,
        _ candidate: TokenUsageSection?) -> Bool
    {
        switch (current, candidate) {
        case (nil, nil):
            true
        case let (current?, candidate?):
            current.hintLine == candidate.hintLine &&
                current.errorLine == candidate.errorLine &&
                current.comparisonLines.count == candidate.comparisonLines.count
        default:
            false
        }
    }

    static func progressColor(for provider: UsageProvider) -> Color {
        let branding = ProviderDescriptorRegistry.descriptor(for: provider).branding
        if branding.progressColorStyle == .label {
            return Color(nsColor: .labelColor)
        }

        let color = ProviderAccentPalette.color(for: provider)
        return Color(red: color.red, green: color.green, blue: color.blue)
    }

    static func rateWindowLabels(
        input: Input,
        snapshot: UsageSnapshot) -> (primary: String, secondary: String, tertiary: String, showsTertiary: Bool)
    {
        let primaryLabel = input.metadata.sessionLabel
        let secondaryLabel = input.metadata.weeklyLabel
        let tertiaryLabel = input.metadata.opusLabel.map(L) ?? L("Sonnet")
        return (
            localizedSessionQuotaLabel(primaryLabel, windowMinutes: snapshot.primary?.windowMinutes),
            L(secondaryLabel),
            tertiaryLabel,
            input.metadata.supportsOpus)
    }

    static func resetText(
        for window: RateWindow,
        style: ResetTimeDisplayStyle,
        now: Date) -> String?
    {
        UsageFormatter.resetLine(for: window, style: style, now: now)
    }

    static func placeholder(input: Input) -> String? {
        if self.shouldShowRateLimitsUnavailablePlaceholder(input: input) {
            return L("Limits not available")
        }

        if input.snapshot == nil, !input.isRefreshing, input.lastError == nil {
            return self.hasLocalCodexTokenUsage(input) ? nil : L("No usage yet")
        }

        return nil
    }

    static func lastError(input: Input) -> String? {
        guard let lastError = input.lastError?.trimmingCharacters(in: .whitespacesAndNewlines),
              !lastError.isEmpty
        else {
            return nil
        }
        // Local Codex session costs are independent from OAuth, CLI quota, and OpenAI web
        // dashboard access. Do not present a failed account-level quota fetch as a failure of
        // a valid local API-key ledger.
        if input.codexLocalSessionCostLedgerEnabled,
           self.hasLocalCodexTokenUsage(input),
           self.isRemoteCodexQuotaFetchError(lastError)
        {
            return nil
        }
        if self.shouldShowRateLimitsUnavailablePlaceholder(input: input, lastError: lastError) {
            return nil
        }
        if self.hasCodexCreditOrRateMeters(input) {
            if UsageError.isNoRateLimitsFoundDescription(lastError)
                || ClaudeStatusProbe.isSubscriptionQuotaUnavailableDescription(lastError)
            {
                return nil
            }
        }
        return lastError
    }

    static func dashboardHint(error: String?) -> String? {
        guard let error, !error.isEmpty else { return nil }
        return error
    }

    static func subscriptionMetadataNotes(snapshot: UsageSnapshot?, provider: UsageProvider) -> [String] {
        guard let snapshot else { return [] }
        if let renewsAt = snapshot.subscriptionRenewsAt {
            return [String(format: L("Renews: %@"), self.subscriptionDateString(renewsAt, provider: provider))]
        }
        if let expiresAt = snapshot.subscriptionExpiresAt {
            return [String(format: L("Plan expires: %@"), self.subscriptionDateString(expiresAt, provider: provider))]
        }
        return []
    }

    private static func subscriptionDateString(_ date: Date, provider: UsageProvider) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = self.subscriptionDateTimeZone(provider: provider)
        formatter.setLocalizedDateFormatFromTemplate("MMM d, yyyy")
        return formatter.string(from: date)
    }

    private static func subscriptionDateTimeZone(provider: UsageProvider) -> TimeZone {
        .current
    }

    private static func hasLocalCodexTokenUsage(_ input: Input) -> Bool {
        input.provider == .codex &&
            input.tokenCostUsageEnabled &&
            self.tokenUsageSnapshot(input: input) != nil
    }

    private static func isRemoteCodexQuotaFetchError(_ error: String) -> Bool {
        error.localizedCaseInsensitiveContains("Codex usage is temporarily unavailable")
    }

    private static func shouldShowRateLimitsUnavailablePlaceholder(input: Input, lastError: String? = nil) -> Bool {
        let currentError = lastError ?? input.lastError
        if let currentError = currentError?.trimmingCharacters(in: .whitespacesAndNewlines),
           !currentError.isEmpty,
           !UsageError.isNoRateLimitsFoundDescription(currentError),
           !ClaudeStatusProbe.isSubscriptionQuotaUnavailableDescription(currentError)
        {
            return false
        }
        if self.hasCodexCreditOrRateMeters(input) {
            return false
        }
        if input.limitsAvailability?.isUnavailable == true {
            return true
        }
        return self.rateLimitsUnavailable(input: input, lastError: currentError)
    }

    private static func hasCodexCreditOrRateMeters(_ input: Input) -> Bool {
        if let lanes = input.codexProjection?.displayedRateLanes(
            showOptionalCreditsAndExtraUsage: input.showOptionalCreditsAndExtraUsage),
            !lanes.isEmpty
        {
            return true
        }
        guard input.showOptionalCreditsAndExtraUsage else { return false }
        return input.credits?.codexCreditLimit != nil
    }

    private static func rateLimitsUnavailable(input: Input, lastError: String? = nil) -> Bool {
        UsageLimitsAvailability.resolve(
            provider: input.provider,
            snapshot: input.snapshot,
            account: input.account,
            lastErrorDescription: lastError ?? input.lastError)
            .isUnavailable
    }

    static func sessionPaceDetail(
        provider: UsageProvider,
        window: RateWindow,
        now: Date,
        showUsed: Bool) -> PaceDetail?
    {
        guard let detail = UsagePaceText.sessionDetail(provider: provider, window: window, now: now) else { return nil }
        let expectedUsed = detail.expectedUsedPercent
        let actualUsed = window.usedPercent
        let expectedPercent = showUsed ? expectedUsed : (100 - expectedUsed)
        let actualPercent = showUsed ? actualUsed : (100 - actualUsed)
        if expectedPercent.isFinite == false || actualPercent.isFinite == false {
            return nil
        }
        let paceOnTop = actualUsed <= expectedUsed
        let pacePercent: Double? = if detail.stage == .onTrack {
            nil
        } else {
            expectedPercent
        }
        return PaceDetail(
            leftLabel: detail.leftLabel,
            rightLabel: detail.rightLabel,
            pacePercent: pacePercent,
            paceOnTop: paceOnTop,
            isPaceDerived: true)
    }

    static func weeklyPaceDetail(
        provider: UsageProvider,
        window: RateWindow,
        now: Date,
        pace: UsagePace?,
        showUsed: Bool) -> PaceDetail?
    {
        guard let pace, window.remainingPercent > 0 else { return nil }
        let detail = UsagePaceText.weeklyDetail(provider: provider, pace: pace, now: now)
        let expectedUsed = detail.expectedUsedPercent
        let actualUsed = window.usedPercent
        let expectedPercent = showUsed ? expectedUsed : (100 - expectedUsed)
        let actualPercent = showUsed ? actualUsed : (100 - actualUsed)
        if expectedPercent.isFinite == false || actualPercent.isFinite == false {
            return nil
        }
        let paceOnTop = actualUsed <= expectedUsed
        let pacePercent: Double? = if detail.stage == .onTrack {
            nil
        } else {
            expectedPercent
        }
        return PaceDetail(
            leftLabel: detail.leftLabel,
            rightLabel: detail.rightLabel,
            pacePercent: pacePercent,
            paceOnTop: paceOnTop,
            isPaceDerived: true)
    }

    static func standardWeeklyPace(input: Input, window: RateWindow) -> UsagePace? {
        if let weeklyPace = input.weeklyPace {
            return weeklyPace
        }
        return Self.displayableWeeklyPace(UsagePace.weekly(
            window: window,
            now: input.now,
            defaultWindowMinutes: 10080,
            workDays: input.workDaysPerWeek))
    }

    private static func displayableWeeklyPace(_ pace: UsagePace?) -> UsagePace? {
        guard let pace else { return nil }
        return pace.expectedUsedPercent >= 3 || pace.etaSeconds == 0 ? pace : nil
    }

    static func resetWindowPaceDetail(
        window: RateWindow,
        input: Input,
        pace: UsagePace? = nil) -> PaceDetail?
    {
        let capability = ProviderDescriptorRegistry.descriptor(for: input.provider).pace
        guard capability.supportsResetWindowPace(window: window, now: input.now),
              window.remainingPercent > 0
        else { return nil }
        let paceWindow = Self.resetWindowForPace(provider: input.provider, window: window)
        // A caller-supplied pace was measured against the raw window, so reuse it only when resolution
        // left the duration alone. Trusting it for a monthly sentinel would score the billing period as
        // a flat 30 days and silently undo the calendar-cycle resolution one line above.
        let reusablePace = paceWindow.windowMinutes == window.windowMinutes ? pace : nil
        let resolved = reusablePace ?? UsagePace.weekly(
            window: paceWindow,
            now: input.now,
            defaultWindowMinutes: 10080,
            workDays: input.workDaysPerWeek)
        guard let resolved = Self.displayableWeeklyPace(resolved) else { return nil }
        return Self.weeklyPaceDetail(
            provider: input.provider,
            window: paceWindow,
            now: input.now,
            pace: resolved,
            showUsed: input.usageBarsShowUsed)
    }

    private static func resetWindowForPace(provider: UsageProvider, window: RateWindow) -> RateWindow {
        // Provider snapshots use 30 days as a monthly sentinel; use the reset date for the real calendar-cycle length.
        ProviderDescriptorRegistry.descriptor(for: provider).pace.resolvedResetWindowForPace(window)
    }

    static func extraRateWindowMetrics(
        snapshot: UsageSnapshot,
        input: Input,
        percentStyle: PercentStyle) -> [Metric]
    {
        guard let extraRateWindows = snapshot.extraRateWindows else { return [] }
        // Codex additional limits (e.g. Codex Spark) are optional extra usage and follow the
        // "optional credits and extra usage" setting. Claude's model-specific quotas stay visible.
        if input.provider == .codex, !input.showOptionalCreditsAndExtraUsage {
            return []
        }

        var visibleRateWindows = if input.provider == .codex, !input.codexSparkUsageVisible {
            extraRateWindows.filter { !Self.isCodexSparkRateWindow($0) }
        } else {
            extraRateWindows
        }
        if input.provider == .claude,
           !input.showOptionalCreditsAndExtraUsage || !input.claudeDailyRoutinesUsageVisible
        {
            visibleRateWindows.removeAll(where: Self.isClaudeDailyRoutinesRateWindow)
        }
        return visibleRateWindows.map { namedWindow in
            let paceDetail = Self.extraRateWindowPaceDetail(
                provider: input.provider,
                window: namedWindow.window,
                input: input)
            let usageKnown = namedWindow.usageKnown
            let resolvedResetText = Self.extraRateWindowResetText(
                namedWindow: namedWindow,
                input: input)
            let resetText = resolvedResetText
            let detailText: String? = nil
            let statusText: String? = if usageKnown {
                nil
            } else if let resetText {
                "\(L("Unavailable")) - \(resetText)"
            } else {
                L("Unavailable")
            }
            let title = L(namedWindow.title)
            let detailLeftText = usageKnown ? paceDetail?.leftLabel : nil
            return Metric(
                id: namedWindow.id,
                title: title,
                percent: Self.clamped(
                    input.usageBarsShowUsed
                        ? namedWindow.window.usedPercent
                        : namedWindow.window.remainingPercent),
                percentStyle: percentStyle,
                statusText: statusText,
                resetText: usageKnown ? resetText : nil,
                detailText: usageKnown ? detailText : nil,
                detailLeftText: detailLeftText,
                detailRightText: usageKnown ? paceDetail?.rightLabel : nil,
                pacePercent: usageKnown ? paceDetail?.pacePercent : nil,
                detailIsPaceDerived: paceDetail?.isPaceDerived ?? false,
                paceOnTop: paceDetail?.paceOnTop ?? true,
                sessionEquivalentDetail: usageKnown
                    ? Self.sessionEquivalentDetail(
                        input: input,
                        weeklyWindow: namedWindow.window,
                        weeklyWindowID: namedWindow.id)
                    : nil)
        }
    }

    private static func isCodexSparkRateWindow(_ namedWindow: NamedRateWindow) -> Bool {
        namedWindow.id == CodexAdditionalRateLimitMapper.sparkWindowID ||
            namedWindow.id == CodexAdditionalRateLimitMapper.sparkWeeklyWindowID
    }

    private static func isClaudeDailyRoutinesRateWindow(_ namedWindow: NamedRateWindow) -> Bool {
        namedWindow.id == "claude-routines"
    }

    private static func extraRateWindowResetText(
        namedWindow: NamedRateWindow,
        input: Input) -> String?
    {
        if namedWindow.window.resetsAt != nil {
            return self.resetText(
                for: namedWindow.window,
                style: input.resetTimeDisplayStyle,
                now: input.now)
        }

        return self.resetText(
            for: namedWindow.window,
            style: input.resetTimeDisplayStyle,
            now: input.now)
    }

    private static func extraRateWindowPaceDetail(
        provider: UsageProvider,
        window: RateWindow,
        input: Input) -> PaceDetail?
    {
        if provider == .claude, window.windowMinutes != 10080 {
            return nil
        }
        switch window.windowMinutes {
        case 300:
            return self.sessionPaceDetail(
                provider: provider,
                window: window,
                now: input.now,
                showUsed: input.usageBarsShowUsed)
        case 10080:
            let pace = Self.displayableWeeklyPace(UsagePace.weekly(
                window: window,
                now: input.now,
                defaultWindowMinutes: 10080,
                workDays: input.workDaysPerWeek))
            return Self.weeklyPaceDetail(
                provider: provider,
                window: window,
                now: input.now,
                pace: pace,
                showUsed: input.usageBarsShowUsed)
        default:
            return nil
        }
    }
}
