import CodexBarCore
import Foundation
import SwiftUI

struct MenuCardMetricTiming: Equatable {
    let resetTime: String?

    static var clockSymbolName: String {
        MenuBarLayoutToken.resetAbsolute.editorSystemImage
    }

    static func make(provider: UsageProvider, window: RateWindow, now: Date) -> Self? {
        guard provider == .codex || provider == .claude else { return nil }
        guard let reset = window.resetsAt, reset > now else { return Self(resetTime: nil) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "EEE h:mm a"
        return Self(resetTime: formatter.string(from: reset))
    }
}

struct MenuCardMetricLine: Equatable {
    let prefix: String?
    let resetTime: String?

    var plainText: String {
        [self.prefix, self.resetTime].compactMap(\.self).joined(separator: " · ")
    }

    var accessibilityText: String {
        [self.prefix, self.resetTime.map { L("Resets at %@", $0) }]
            .compactMap(\.self).joined(separator: " · ")
    }

    var text: Text {
        if let resetTime = self.resetTime {
            let clock = Image(systemName: MenuCardMetricTiming.clockSymbolName)
            if let prefix = self.prefix {
                return Text("\(prefix) · \(clock) \(resetTime)")
            }
            return Text("\(clock) \(resetTime)")
        }
        return Text(self.prefix ?? "")
    }
}

extension UsageMenuCardView.Model.Metric {
    struct LinePresentation: Equatable {
        let titleText: String
        let resetText: String?
        let meta: MenuCardMetricLine?

        var metaText: String? {
            self.meta?.plainText
        }
    }

    func linePresentation(title: String) -> LinePresentation {
        // Keep the title aligned with the configured used/remaining label semantics.
        let paceParts = self.timing == nil
            ? [self.detailLeftText, self.detailRightText]
            : [self.detailRightText, self.detailLeftText]
        let metaParts = (paceParts + [
            self.sessionEquivalentDetail?.leftText,
            self.sessionEquivalentDetail?.rightText,
        ]).compactMap { text -> String? in
            guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                return nil
            }
            return text
        }
        return LinePresentation(
            titleText: "\(title) \(self.percentLabel)",
            resetText: self.resetText,
            meta: metaParts.isEmpty && self.timing?.resetTime == nil ? nil : MenuCardMetricLine(
                prefix: metaParts.isEmpty ? nil : metaParts.joined(separator: " · "),
                resetTime: self.timing?.resetTime))
    }
}
