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
                ForEach(Array(self.model.expandedLines.enumerated()), id: \.offset) { _, line in
                    Text(line.text)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(self.toneColor(line.tone))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
        .padding(.horizontal, UsageMenuCardLayout.horizontalPadding)
        .padding(.vertical, 5)
        .frame(width: self.width, alignment: .leading)
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
