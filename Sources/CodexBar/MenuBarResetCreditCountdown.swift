import AppKit
import CodexBarCore
import Foundation

struct MenuBarResetCreditCountdown: Hashable {
    static let symbolName = "hourglass.bottomhalf.filled"

    let expiresAt: Date
    let text: String
    let isUrgent: Bool

    init?(expiresAt: Date?, now: Date) {
        guard let expiresAt, expiresAt > now else { return nil }
        self.expiresAt = expiresAt
        self.text = UsageFormatter.resetCountdownDescription(from: expiresAt, now: now)
        self.isUrgent = expiresAt.timeIntervalSince(now) <= 24 * 3600
    }

    static func preferredExpiry(
        provider: UsageProvider,
        snapshot: UsageSnapshot?,
        resetAt: Date?,
        now: Date) -> Date?
    {
        // Provider-specific by design: only Codex snapshots carry banked limit reset credits.
        guard provider == .codex,
              let resetAt,
              let expiry = snapshot?.codexResetCredits?.availableInventory(at: now).nextExpiringCredit?.expiresAt,
              expiry < resetAt
        else { return nil }
        return expiry
    }

    var markedText: String {
        self.text + "\u{2009}\u{FFFC}"
    }

    var accessibilityLabel: String {
        "\(L("Limit Reset Credits")), \(L("Expires")) \(self.text)"
    }

    @MainActor
    var color: NSColor {
        self.isUrgent ? .systemRed : .systemOrange
    }

    @MainActor
    static func resetColor(resetAt: Date, now: Date) -> NSColor {
        resetAt.timeIntervalSince(now) <= 24 * 3600 ? .systemRed : .systemOrange
    }

    @MainActor
    static func stylingResetTimes(
        _ title: NSAttributedString,
        resetDates: [Date],
        style: ResetTimeDisplayStyle,
        now: Date) -> NSAttributedString
    {
        let result = NSMutableAttributedString(attributedString: title)
        for resetAt in resetDates {
            let description = switch style {
            case .countdown: UsageFormatter.resetCountdownDescription(from: resetAt, now: now)
            case .absolute: UsageFormatter.resetDescription(from: resetAt, now: now)
            }
            let range = (result.string as NSString).range(of: "↻ \(description)")
            if range.location != NSNotFound {
                result.addAttribute(.foregroundColor, value: self.resetColor(resetAt: resetAt, now: now), range: range)
            }
        }
        return result
    }

    @MainActor
    func attributedTitle(attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        self.styling(NSAttributedString(string: self.markedText, attributes: attributes))
    }

    @MainActor
    func styling(_ title: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: title)
        let range = (result.string as NSString).range(of: self.markedText)
        guard range.location != NSNotFound else { return result }
        let font = result.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        result.addAttribute(.foregroundColor, value: self.color, range: range)
        let attachment = NSTextAttachment()
        attachment.image = NSImage(systemSymbolName: Self.symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: font.pointSize, weight: .regular))?
            .withSymbolConfiguration(.init(paletteColors: [self.color]))
        let height = font.capHeight
        let imageSize = attachment.image?.size ?? NSSize(width: height, height: height)
        let width = imageSize.height > 0 ? imageSize.width * height / imageSize.height : height
        attachment.bounds = NSRect(x: 0, y: 0, width: width, height: height)
        result.addAttribute(.attachment, value: attachment, range: NSRange(location: NSMaxRange(range) - 1, length: 1))
        return result
    }
}

extension StatusItemController {
    func menuBarResetCreditCountdown(
        for provider: UsageProvider,
        snapshot: UsageSnapshot?,
        now: Date) -> MenuBarResetCreditCountdown?
    {
        let resolution = self.settings.menuBarLayoutResolution(for: provider)
        if resolution.usesLegacyRendering,
           self.settings.menuBarDisplayMode != .resetTime,
           !self.settings.menuBarShowsResetTimeWhenExhausted
        {
            return nil
        }
        let resetAt = self.menuBarQuotaResetDates(for: provider, snapshot: snapshot, now: now).min()
        return MenuBarResetCreditCountdown(
            expiresAt: MenuBarResetCreditCountdown.preferredExpiry(
                provider: provider, snapshot: snapshot, resetAt: resetAt, now: now),
            now: now)
    }

    func menuBarDisplayedResetDates(for provider: UsageProvider, now: Date) -> [Date] {
        let snapshot = self.store.menuBarSnapshot(for: provider.instanceID)
        let dates = self.menuBarQuotaResetDates(for: provider, snapshot: snapshot, now: now)
        guard let credit = self.menuBarResetCreditCountdown(for: provider, snapshot: snapshot, now: now) else {
            return dates
        }
        return dates + [credit.expiresAt]
    }

    func menuBarDisplayText(
        for provider: UsageProvider,
        snapshot: UsageSnapshot?,
        now: Date = .init()) -> String?
    {
        let text = self.menuBarQuotaDisplayText(for: provider, snapshot: snapshot, now: now)
        guard let credit = self.menuBarResetCreditCountdown(for: provider, snapshot: snapshot, now: now),
              let resetAt = self.menuBarQuotaResetDates(for: provider, snapshot: snapshot, now: now).min()
        else { return text }
        let resetText = switch self.settings.resetTimeDisplayStyle {
        case .countdown: UsageFormatter.resetCountdownDescription(from: resetAt, now: now)
        case .absolute: UsageFormatter.resetDescription(from: resetAt, now: now)
        }
        return text?.replacingOccurrences(of: "↻ \(resetText)", with: credit.markedText)
    }
}
