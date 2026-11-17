import SwiftUI
import Testing
@testable import CodexBar

struct MenuCardHeightFingerprintTests {
    @MainActor
    @Test
    func `compact height fingerprint and accessibility include banked expiry detail`() {
        var model = MenuCardCompactAccountRowView.Model(
            label: "Friendly account",
            headroomPercent: 80,
            severity: .healthy,
            constraintDetail: "Weekly 80% left",
            hasError: false,
            showsBestBadge: false)
        let bare = model.heightFingerprint
        model.trailingDetail = .init(
            text: "1d", count: 2, accessibilityLabel: "Limit Reset Credits, 2 available, Expires in 1d")
        let withExpiry = model.heightFingerprint
        let view = MenuCardCompactAccountRowView(model: model, progressColor: .blue, width: 360)

        #expect(withExpiry != bare)
        #expect(view.accessibilityText.contains("Weekly 80% left"))
        #expect(view.accessibilityText.contains("Limit Reset Credits, 2 available, Expires in 1d"))
        model.trailingDetail = .init(
            text: "2d", count: 2, accessibilityLabel: "Limit Reset Credits, 2 available, Expires in 2d")
        #expect(model.heightFingerprint != withExpiry)
        model.trailingDetail = .init(
            text: "1d", count: 3, accessibilityLabel: "Limit Reset Credits, 3 available, Expires in 1d")
        #expect(model.heightFingerprint != withExpiry)
    }

    @MainActor
    @Test
    func `compact rows reserve the same two line height for every detail state`() {
        let detail = MenuCardCompactAccountRowView.Model(
            label: "Synthetic account",
            headroomPercent: 80,
            severity: .healthy,
            constraintDetail: "Resets in 2h",
            hasError: false,
            showsBestBadge: false)
        let expectedHeight = Self.compactHeight(detail)
        #expect(expectedHeight > 0)
        for hasError in [false, true] {
            for isRefreshing in [false, true] {
                for hasTrailing in [false, true] {
                    let model = MenuCardCompactAccountRowView.Model(
                        label: "Synthetic account",
                        headroomPercent: hasError || isRefreshing ? nil : 80,
                        severity: .healthy,
                        constraintDetail: nil,
                        hasError: hasError,
                        showsBestBadge: false,
                        isRefreshing: isRefreshing,
                        trailingDetail: hasTrailing ? .init(
                            text: "2d", count: 2, accessibilityLabel: "2 reset credits, expires in 2d") : nil)
                    #expect(Self.compactHeight(model) == expectedHeight)
                    let accessible = MenuCardCompactAccountRowView(model: model, progressColor: .blue, width: 320)
                        .accessibilityText
                    #expect(!accessible.contains(",  "))
                    #expect(!accessible.hasSuffix(", "))
                }
            }
        }
    }

    @MainActor
    private static func compactHeight(_ model: MenuCardCompactAccountRowView.Model) -> CGFloat {
        let hosting = MenuHostingView(rootView: MenuCardCompactAccountRowView(
            model: model, progressColor: .blue, width: 320))
        hosting.frame = CGRect(x: 0, y: 0, width: 320, height: 1)
        hosting.layoutSubtreeIfNeeded()
        return ceil(hosting.fittingSize.height)
    }

    @Test
    func `height fingerprint does not retain raw text fields`() {
        let model = Self.model()

        let fingerprint = model.heightFingerprint(section: "card")

        #expect(!fingerprint.contains("very-secret@example.com"))
        #expect(!fingerprint.contains("Secret Provider Name"))
        #expect(!fingerprint.contains("Secret Metric"))
        #expect(!fingerprint.contains("Secret note"))
    }

    @Test
    func `height fingerprint field distinguishes nil from empty string`() {
        let nilField = UsageMenuCardView.Model.heightFingerprintField("storage", nil)
        let emptyField = UsageMenuCardView.Model.heightFingerprintField("storage", "")

        #expect(nilField != emptyField)
    }

    @Test
    func `height fingerprint ignores content changes inside fixed metric lines`() {
        let left = Self.model(percent: 42, percentStyle: .left).heightFingerprint(section: "card")
        let used = Self.model(percent: 42, percentStyle: .used).heightFingerprint(section: "card")
        let changedPercent = Self.model(percent: 43, percentStyle: .left).heightFingerprint(section: "card")

        #expect(left == used)
        #expect(left == changedPercent)
    }

    @Test
    func `height fingerprint tracks wrapping metric text content`() {
        let bare = Self.model(statusText: nil).heightFingerprint(section: "card")
        let withReset = Self.model(statusText: nil, resetText: "Resets in 2h").heightFingerprint(section: "card")
        let withMeta = Self.model(statusText: nil, detailLeftText: "20% in reserve")
            .heightFingerprint(section: "card")
        let withChangedMeta = Self.model(statusText: nil, detailLeftText: "45% in deficit")
            .heightFingerprint(section: "card")
        let withFoldedForecast = Self.model(
            statusText: nil,
            detailLeftText: "20% in reserve",
            sessionEquivalentDetail: .init(
                leftText: "Est. 2 session quotas left",
                rightText: "6 windows until reset",
                accessibilityLabel: "Est. 2 session quotas left · 6 windows until reset"))
            .heightFingerprint(section: "card")

        #expect(bare != withReset)
        #expect(bare != withMeta)
        // Meta and reset rows can wrap to a second line, so any text change
        // must invalidate the cached height instead of reusing a short frame.
        #expect(withMeta != withChangedMeta)
        #expect(withMeta != withFoldedForecast)
    }

    @Test
    func `height fingerprint invalidates when wrapping text grows from short to long`() {
        let shortReset = Self.model(statusText: nil, resetText: "Resets in 2h")
            .heightFingerprint(section: "card")
        let widerTitle = Self.model(percent: 100, statusText: nil, resetText: "Resets in 2h")
            .heightFingerprint(section: "card")
        let longReset = Self.model(
            statusText: nil,
            resetText: "Resets tomorrow at 6:00 AM after a very long localized description")
            .heightFingerprint(section: "card")
        let shortMeta = Self.model(statusText: nil, detailLeftText: "On pace")
            .heightFingerprint(section: "card")
        let longMeta = Self.model(
            statusText: nil,
            detailLeftText: "Estimated 2 session quotas left with a generously long localized pace explanation")
            .heightFingerprint(section: "card")

        #expect(shortReset != widerTitle)
        #expect(shortReset != longReset)
        #expect(shortMeta != longMeta)
    }

    @Test
    func `height fingerprint tracks reset-credit inventory shape`() {
        let one = Self.model(resetCredits: CodexResetCreditsPresentation(
            text: "1 available",
            items: [.init(expiryText: "Expires in 1d", compactExpiryText: "1d")]))
        let two = Self.model(resetCredits: CodexResetCreditsPresentation(
            text: "2 available",
            items: [
                .init(expiryText: "Expires in 1d", compactExpiryText: "1d"),
                .init(expiryText: "No expiry", compactExpiryText: "No expiry"),
            ]))

        #expect(one.heightFingerprint(section: "card") != two.heightFingerprint(section: "card"))
    }

    private static func model(
        percent: Double = 42,
        percentStyle: UsageMenuCardView.Model.PercentStyle = .left,
        resetCredits: CodexResetCreditsPresentation? = nil,
        statusText: String? = "Secret status",
        resetText: String? = nil,
        detailLeftText: String? = nil,
        sessionEquivalentDetail: UsagePaceText.SessionEquivalentDetail? = nil) -> UsageMenuCardView.Model
    {
        UsageMenuCardView.Model(
            provider: .codex,
            providerName: "Secret Provider Name",
            email: "very-secret@example.com",
            subtitleText: "Signed in as very-secret@example.com",
            subtitleStyle: .info,
            planText: "Secret Plan",
            metrics: [
                .init(
                    id: "primary",
                    title: "Secret Metric",
                    percent: percent,
                    percentStyle: percentStyle,
                    statusText: statusText,
                    resetText: resetText,
                    detailText: nil,
                    detailLeftText: detailLeftText,
                    detailRightText: nil,
                    pacePercent: nil,
                    paceOnTop: true,
                    sessionEquivalentDetail: sessionEquivalentDetail),
            ],
            usageNotes: ["Secret note"],
            inlineUsageDashboard: nil,
            creditsText: nil,
            creditsRemaining: nil,
            creditsProgressPercent: nil,
            creditsScaleText: nil,
            creditsHintText: nil,
            creditsHintCopyText: nil,
            codexResetCredits: resetCredits,
            providerCost: nil,
            tokenUsage: nil,
            placeholder: nil,
            progressColor: .blue)
    }
}
