import AppKit
import Foundation

extension StatusItemController {
    func setButtonContent(
        image: NSImage,
        title: String?,
        resetCredit: MenuBarResetCreditCountdown? = nil,
        resetDates: [Date] = [],
        now: Date = .init(),
        for button: NSStatusBarButton)
    {
        let isDebugApp = Self.isDebugApp(bundleIdentifier: Bundle.main.bundleIdentifier)
        let value = Self.buttonTitle(
            title,
            hasImage: true,
            isDebugApp: isDebugApp)

        if self.shouldUseHighContrastStatusItemContent {
            button.image = nil
            button.imagePosition = .noImage
            let attributed = MenuBarResetCreditCountdown.stylingResetTimes(
                Self.highContrastButtonTitle(image: image, title: value),
                resetDates: resetDates,
                style: self.settings.resetTimeDisplayStyle,
                now: now)
            button.attributedTitle = resetCredit?.styling(attributed) ?? attributed
            if let resetCredit {
                button.setAccessibilityTitle(value.replacingOccurrences(
                    of: resetCredit.markedText,
                    with: resetCredit.accessibilityLabel))
            } else {
                button.setAccessibilityTitle(nil)
            }
            return
        }

        if button.image !== image {
            button.image = image
        }
        if resetCredit != nil || !resetDates.isEmpty {
            let attributed = MenuBarResetCreditCountdown.stylingResetTimes(
                NSAttributedString(
                    string: value,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                        .foregroundColor: NSColor.controlTextColor,
                    ]),
                resetDates: resetDates,
                style: self.settings.resetTimeDisplayStyle,
                now: now)
            button.attributedTitle = resetCredit?.styling(attributed) ?? attributed
            button.setAccessibilityTitle(resetCredit.map {
                value.replacingOccurrences(of: $0.markedText, with: $0.accessibilityLabel)
            })
        } else {
            if button.title != value {
                button.title = value
            }
            button.setAccessibilityTitle(nil)
        }
        let position: NSControl.ImagePosition = value.isEmpty ? .imageOnly : .imageLeft
        if button.imagePosition != position {
            button.imagePosition = position
        }
    }
}
