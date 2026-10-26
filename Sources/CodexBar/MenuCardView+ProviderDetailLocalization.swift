import CodexBarCore
import Foundation

extension UsageMenuCardView.Model {
    static func localizedProviderDetails(
        _ details: [ProviderDetailSection],
        provider: UsageProvider) -> [ProviderDetailSection]
    {
        details.compactMap { section in
            let rows = section.rows.compactMap { row in
                try? ProviderDetailSection.Row(
                    label: L(row.label),
                    value: row.value,
                    secondaryValue: row.secondaryValue)
            }
            return try? ProviderDetailSection(
                title: section.title.map(L),
                rows: rows,
                chart: section.chart)
        }
    }
}
