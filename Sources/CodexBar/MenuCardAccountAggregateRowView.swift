import SwiftUI

struct MenuCardAccountAggregateRowView: View {
    let model: JonesAccountAggregate
    let progressColor: Color
    let width: CGFloat
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
                                    .fill(Color(red: 243 / 255, green: 91 / 255, blue: 102 / 255))
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
        }
        .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
        .padding(.horizontal, UsageMenuCardLayout.horizontalPadding)
        .padding(.vertical, 5)
        .frame(width: self.width, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(self.model.accessibilityText)
    }
}
