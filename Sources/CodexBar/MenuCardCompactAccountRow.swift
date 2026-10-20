import CodexBarCore
import SwiftUI

/// Compact menu row for a collapsed account in the multi-account layout:
/// label and headroom above a reserved detail line for quota or reset-credit details.
/// Clicking the row expands it into the full usage card.
struct MenuCardCompactAccountRowView: View {
    struct TrailingDetail: Equatable {
        let text: String
        let count: Int
        let accessibilityLabel: String
    }

    struct Model: Equatable {
        let label: String
        let headroomPercent: Double?
        let severity: AccountMenuLayoutPlanner.Severity?
        let constraintDetail: String?
        let hasError: Bool
        let showsBestBadge: Bool
        var isActiveAccount: Bool = false
        var isRefreshing: Bool = false
        var trailingDetail: TrailingDetail?

        var headroomLabel: String? {
            self.headroomPercent.map { "\(Int($0.rounded()))%" }
        }

        var heightFingerprint: String {
            [
                "compactAccount",
                self.label,
                self.headroomLabel ?? "-",
                self.constraintDetail ?? "-",
                self.hasError ? "error" : "ok",
                self.showsBestBadge ? "best" : "plain",
                self.isActiveAccount ? "active" : "inactive",
                self.isRefreshing ? "refreshing" : "idle",
                self.trailingDetail?.text ?? "-",
                self.trailingDetail.map { String($0.count) } ?? "-",
            ].joined(separator: "|")
        }
    }

    static let miniBarWidth: CGFloat = 56
    static let miniBarHeight: CGFloat = 4

    let model: Model
    let progressColor: Color
    let width: CGFloat
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(self.model.label)
                    .font(.subheadline)
                    .foregroundStyle(self.labelColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if self.model.showsBestBadge {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(self.isHighlighted
                            ? MenuHighlightStyle.selectionText
                            : Color(nsColor: .systemYellow))
                        .accessibilityLabel(L("Most usable account"))
                }
                Spacer(minLength: 12)
                if self.model.isRefreshing, self.model.headroomPercent == nil {
                    Text("\(L("Refreshing"))…")
                        .font(.caption)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                } else if self.model.hasError, self.model.headroomPercent == nil {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(MenuHighlightStyle.error(self.isHighlighted))
                        .accessibilityLabel(L("Account unavailable"))
                } else if let headroom = self.model.headroomPercent, let label = self.model.headroomLabel {
                    Capsule()
                        .fill(MenuHighlightStyle.progressTrack(self.isHighlighted))
                        .frame(width: Self.miniBarWidth, height: Self.miniBarHeight)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(self.severityColor)
                                .frame(width: Self.miniBarWidth * min(100, max(0, headroom)) / 100)
                        }
                        .accessibilityHidden(true)
                    Text(label)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(self.percentColor)
                        .lineLimit(1)
                        .frame(minWidth: 34, alignment: .trailing)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(self.model.constraintDetail ?? " ")
                    .font(.footnote)
                    .foregroundStyle(self.model.severity == .critical
                        ? MenuHighlightStyle.error(self.isHighlighted)
                        : MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(1)
                    .layoutPriority(1)
                    .accessibilityHidden(self.model.constraintDetail == nil)
                Spacer(minLength: 4)
                if let trailing = self.model.trailingDetail {
                    ViewThatFits(in: .horizontal) {
                        self.resetCreditDetail(trailing, showsCount: true)
                        self.resetCreditDetail(trailing, showsCount: false)
                    }
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .accessibilityHidden(true)
                }
            }
        }
        .padding(.horizontal, UsageMenuCardLayout.horizontalPadding)
        .padding(.vertical, 5)
        .frame(width: self.width, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(self.accessibilityText)
    }

    private func resetCreditDetail(_ detail: TrailingDetail, showsCount: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Image(systemName: "clock")
            Text(detail.text)
            if showsCount, detail.count > 1 {
                Text("×\(detail.count)")
            }
        }
        .font(.caption.monospacedDigit())
        .fixedSize()
    }

    /// The active (system) account keeps its menu position; a blue name marks it instead.
    private var labelColor: Color {
        guard self.model.isActiveAccount, !self.isHighlighted else {
            return MenuHighlightStyle.primary(self.isHighlighted)
        }
        return Color(nsColor: .systemBlue)
    }

    private var severityColor: Color {
        guard !self.isHighlighted else { return MenuHighlightStyle.selectionText }
        switch self.model.severity {
        case .critical: return Color(nsColor: .systemRed)
        case .warning: return Color(nsColor: .systemOrange)
        case .healthy, .none: return self.progressColor
        }
    }

    private var percentColor: Color {
        guard !self.isHighlighted else { return MenuHighlightStyle.selectionText }
        switch self.model.severity {
        case .critical: return Color(nsColor: .systemRed)
        case .warning: return Color(nsColor: .systemOrange)
        case .healthy, .none: return MenuHighlightStyle.normalSecondaryText
        }
    }

    var accessibilityText: String {
        var parts = [self.model.label]
        if self.model.isActiveAccount {
            parts.append(L("Active"))
        }
        if self.model.isRefreshing, self.model.headroomPercent == nil {
            parts.append("\(L("Refreshing"))…")
        }
        if let label = self.model.headroomLabel {
            parts.append(String(format: L("%@ remaining"), label))
        }
        if let detail = self.model.constraintDetail {
            parts.append(detail)
        }
        if let detail = self.model.trailingDetail {
            parts.append(detail.accessibilityLabel)
        }
        if self.model.hasError {
            parts.append(L("Account unavailable"))
        }
        return parts.joined(separator: ", ")
    }
}

/// Summary row standing in for the healthy accounts hidden by the compact
/// multi-account layout; clicking it reveals the individual rows.
struct MenuCardCollapsedAccountsRowView: View {
    let count: Int
    let width: CGFloat
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var title: String {
        String(format: L("%d more accounts ready"), self.count)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.footnote)
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            Text(self.title)
                .font(.footnote)
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            Spacer(minLength: 12)
            Image(systemName: "chevron.down")
                .font(.caption2)
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
        }
        .padding(.horizontal, UsageMenuCardLayout.horizontalPadding)
        .padding(.vertical, 5)
        .frame(width: self.width, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(self.title)
        .accessibilityHint(L("Shows the hidden accounts"))
    }
}
