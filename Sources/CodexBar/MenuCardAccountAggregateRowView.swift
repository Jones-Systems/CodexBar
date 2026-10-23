import SwiftUI

struct MenuCardAccountAggregateRowView: View {
    let model: JonesAccountAggregate
    let progressColor: Color
    let width: CGFloat
    var isExpanded = false
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(L("Total remaining"))
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 12)
                if let percent = self.model.normalizedPercent {
                    Capsule()
                        .fill(MenuHighlightStyle.progressTrack(self.isHighlighted))
                        .frame(width: MenuCardCompactAccountRowView.miniBarWidth, height: 4)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(self.isHighlighted ? MenuHighlightStyle.selectionText : self.progressColor)
                                .frame(width: MenuCardCompactAccountRowView.miniBarWidth * percent / 100)
                        }
                        .overlay(alignment: .leading) {
                            if let target = self.model.paceMarkerPercent {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(self.toneColor(self.model.balanceTone))
                                    .frame(width: 2, height: 8)
                                    .offset(x: min(
                                        MenuCardCompactAccountRowView.miniBarWidth - 2,
                                        max(0, MenuCardCompactAccountRowView.miniBarWidth * target / 100 - 1)))
                            }
                        }
                        .accessibilityHidden(true)
                }
                Text(self.model.normalizedLabel)
                    .font(.footnote.monospacedDigit())
                    .lineLimit(1)
            }
            HStack {
                Text(self.model.countLabel)
                Spacer(minLength: 8)
                if let remainingLabel = self.model.remainingLabel {
                    Text(remainingLabel)
                }
            }
            .font(.footnote.monospacedDigit())
            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            .lineLimit(1)
            if self.isExpanded {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(self.model.compactBalanceLabel)
                        .foregroundStyle(self.toneColor(self.model.balanceTone))
                    Spacer(minLength: 8)
                    Text(self.model.compactCapacityLabel)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                }
                .font(.footnote.monospacedDigit())
                .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(L("Runs out ≈"))
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    Spacer(minLength: 8)
                    Text(self.model.compactExhaustionLabel)
                }
                .font(.footnote.monospacedDigit())
                .lineLimit(1)
            }
        }
        .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
        .padding(.horizontal, UsageMenuCardLayout.horizontalPadding)
        .padding(.vertical, 5)
        .frame(width: self.width, alignment: .leading)
        .help(self.model.expandedHelpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(self.model.accessibilityText(isExpanded: self.isExpanded))
        .accessibilityValue(self.isExpanded ? L("Expanded") : L("Collapsed"))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(self.isExpanded ? L("Hide pace details") : L("Show pace details"))
    }

    private func toneColor(_ tone: JonesAccountAggregate.Tone) -> Color {
        if self.isHighlighted { return MenuHighlightStyle.selectionText }
        switch tone {
        case .reserve: return .green
        case .deficit: return .red
        case .neutral: return MenuHighlightStyle.secondary(false)
        }
    }
}
