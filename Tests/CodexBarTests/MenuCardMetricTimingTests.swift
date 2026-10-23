import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct MenuCardMetricTimingTests {
    static let now = Date(timeIntervalSince1970: 1_792_728_000)

    @Test(arguments: [UsageProvider.codex, .claude])
    func `each metric uses its own quota reset and preserves it without pace`(_ provider: UsageProvider) throws {
        let model = try Self.fixtureModel(provider: provider)
        let primary = try #require(model.metrics.first { $0.id == "primary" })
        let weekly = try #require(model.metrics.first { $0.id == "secondary" })
        #expect(primary.timing?.resetTime == Self.label(Self.now.addingTimeInterval(9000)))
        #expect(weekly.timing?.resetTime == Self.label(Self.now.addingTimeInterval(572_400)))
        #expect(primary.timing != weekly.timing)
        let hidden = UsageMenuCardView.Model.paceGatedMetrics(model.metrics, paceVisible: false)
        let redacted = UsageMenuCardView.Model.redactedMetrics(hidden, provider: provider, hidePersonalInfo: true)
        #expect(redacted.map(\.timing) == model.metrics.map(\.timing))
        #expect(redacted.allSatisfy { $0.linePresentation(title: $0.title).meta?.resetTime != nil })
        #expect(redacted.allSatisfy { $0.pacePercent == nil })
    }

    @Test
    func `approved metrics place forecast before balance and clock while other providers keep order`() throws {
        let timing = try #require(MenuCardMetricTiming.make(
            provider: .codex,
            window: Self.window(reset: Self.now.addingTimeInterval(3600)),
            now: Self.now))
        let metric = Self.metric(timing: timing)
        let presentation = metric.linePresentation(title: metric.title)
        #expect(try presentation.metaText == "Runs out in 1d 5m · 19% in deficit · \(#require(timing.resetTime))")
        #expect(presentation.meta?.accessibilityText.contains("Resets at") == true)
        #expect(MenuCardMetricTiming.clockSymbolName == MenuBarLayoutToken.resetAbsolute.editorSystemImage)
        #expect(MenuCardMetricTiming.clockSymbolName == "clock")
        #expect(Self.metric(timing: nil).linePresentation(title: "Weekly").metaText ==
            "19% in deficit · Runs out in 1d 5m")
        #expect(MenuCardMetricTiming.make(
            provider: .kimi,
            window: Self.window(reset: Self.now.addingTimeInterval(3600)),
            now: Self.now) == nil)
    }

    @Test(arguments: [Date?.none, Self.now, Self.now.addingTimeInterval(-1)])
    func `missing and elapsed reset dates do not fabricate absolute details`(_ reset: Date?) throws {
        let timing = MenuCardMetricTiming.make(provider: .claude, window: Self.window(reset: reset), now: Self.now)
        #expect(timing?.resetTime == nil)
        #expect(try !#require(Self.metric(timing: timing).linePresentation(title: "Weekly").metaText?
                .contains("Resets")))
    }

    @Test
    func `Eastern reset labels cross daylight saving without a visible timezone suffix`() throws {
        let parser = ISO8601DateFormatter()
        let before = try #require(parser.date(from: "2026-11-01T05:30:00Z"))
        let after = try #require(parser.date(from: "2026-11-01T06:30:00Z"))
        let labelBefore = MenuCardMetricTiming.make(
            provider: .codex,
            window: Self.window(reset: before),
            now: before.addingTimeInterval(-3600))
        let labelAfter = MenuCardMetricTiming.make(
            provider: .codex,
            window: Self.window(reset: after),
            now: before.addingTimeInterval(-3600))
        #expect(labelBefore?.resetTime == "Sun 1:30 AM")
        #expect(labelAfter?.resetTime == "Sun 1:30 AM")
    }

    @Test
    func `reset only metadata changes height identity and tracked layout presence`() throws {
        let bare = try Self.fixtureModel(provider: .claude, resetOffset: nil, paceVisible: false)
        let timed = try Self.fixtureModel(provider: .claude, paceVisible: false)
        let later = try Self.fixtureModel(provider: .claude, resetOffset: 3600, paceVisible: false)
        #expect(bare.heightFingerprint(section: "usage") != timed.heightFingerprint(section: "usage"))
        #expect(timed.heightFingerprint(section: "usage") != later.heightFingerprint(section: "usage"))
        #expect(!bare.hasCompatibleTrackedLayout(with: timed))
    }

    static func fixtureModel(
        provider: UsageProvider,
        resetOffset: TimeInterval? = 9000,
        paceVisible: Bool = true) throws -> UsageMenuCardView.Model
    {
        let metadata = try #require(ProviderDefaults.metadata[provider])
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 58,
                windowMinutes: 300,
                resetsAt: resetOffset.map { Self.now.addingTimeInterval($0) },
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: 51,
                windowMinutes: 10080,
                resetsAt: resetOffset.map { Self.now.addingTimeInterval($0 + 563_400) },
                resetDescription: nil),
            updatedAt: Self.now)
        let projection: CodexConsumerProjection? = provider == .codex ? .make(
            surface: .liveCard,
            context: .init(
                snapshot: snapshot,
                rawUsageError: nil,
                liveCredits: nil,
                rawCreditsError: nil,
                liveDashboard: nil,
                rawDashboardError: nil,
                dashboardAttachmentAuthorized: false,
                dashboardRequiresLogin: false,
                now: Self.now)) : nil
        return UsageMenuCardView.Model.make(.init(
            provider: provider,
            metadata: metadata,
            snapshot: snapshot,
            codexProjection: projection,
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: "synthetic@example.test", plan: nil),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: false,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            paceVisible: paceVisible,
            now: Self.now))
    }

    static func metric(timing: MenuCardMetricTiming?) -> UsageMenuCardView.Model.Metric {
        .init(
            id: "secondary",
            title: "Weekly",
            percent: 49,
            percentStyle: .left,
            resetText: "Resets in 6d 15h",
            detailText: nil,
            detailLeftText: "19% in deficit",
            detailRightText: "Runs out in 1d 5m",
            pacePercent: 68,
            detailIsPaceDerived: true,
            paceOnTop: true,
            timing: timing)
    }

    private static func window(reset: Date?) -> RateWindow {
        RateWindow(usedPercent: 51, windowMinutes: 10080, resetsAt: reset, resetDescription: nil)
    }

    private static func label(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "EEE h:mm a"
        return formatter.string(from: date)
    }
}
