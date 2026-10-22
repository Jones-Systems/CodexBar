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
        let accessibilityTitle = resetCredit.map {
            value.replacingOccurrences(of: $0.markedText, with: $0.accessibilityLabel)
        } ?? Self.statusItemAccessibilityTitle(isDebugApp: isDebugApp)

        if self.shouldUseHighContrastStatusItemContent {
            button.image = nil
            button.imagePosition = .noImage
            let attributed = MenuBarResetCreditCountdown.stylingResetTimes(
                Self.highContrastButtonTitle(image: image, title: value),
                resetDates: resetDates,
                style: self.settings.resetTimeDisplayStyle,
                now: now)
            button.attributedTitle = resetCredit?.styling(attributed) ?? attributed
            button.setAccessibilityTitle(accessibilityTitle)
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
            button.setAccessibilityTitle(accessibilityTitle)
        } else {
            if button.title != value {
                button.title = value
            }
            button.setAccessibilityTitle(accessibilityTitle)
        }
        let position: NSControl.ImagePosition = value.isEmpty ? .imageOnly : .imageLeft
        if button.imagePosition != position {
            button.imagePosition = position
        }
    }
}
