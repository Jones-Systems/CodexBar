import AppKit
import CodexBarCore
import SwiftUI
import Testing
@testable import CodexBar

private final class RefreshShortcutRecorder: StatusItemMenuPersistentActionDelegate {
    var refreshCount = 0
    var refreshMenuIDs: [ObjectIdentifier] = []
    var refreshMenuInteractionGenerations: [Int] = []
    var settingsCount = 0
    var quitCount = 0
    var navigationDirections: [StatusItemMenuProviderNavigationDirection] = []

    func performPersistentRefreshAction(
        in menuID: ObjectIdentifier,
        menuInteractionGeneration: Int)
    {
        self.refreshCount += 1
        self.refreshMenuIDs.append(menuID)
        self.refreshMenuInteractionGenerations.append(menuInteractionGeneration)
    }

    func performPersistentSettingsAction() {
        self.settingsCount += 1
    }

    func performPersistentQuitAction() {
        self.quitCount += 1
    }

    func performProviderNavigation(_ direction: StatusItemMenuProviderNavigationDirection) {
        self.navigationDirections.append(direction)
    }
}

@MainActor
extension StatusMenuPersistentRefreshTests {
    @Test
    func `status item menu intercepts persistent shortcuts without native item selection`() throws {
        let menu = StatusItemMenu()
        let recorder = RefreshShortcutRecorder()
        menu.persistentActionDelegate = recorder
        menu.menuInteractionGeneration = 42

        #expect(try menu.performKeyEquivalent(with: self.keyEvent("r", keyCode: 15)) == true)
        #expect(try menu.performKeyEquivalent(with: self.keyEvent(",", keyCode: 43)) == true)
        #expect(try menu.performKeyEquivalent(with: self.keyEvent("q", keyCode: 12)) == true)

        #expect(recorder.refreshCount == 1)
        #expect(recorder.refreshMenuIDs == [ObjectIdentifier(menu)])
        #expect(recorder.refreshMenuInteractionGenerations == [42])
        #expect(recorder.settingsCount == 1)
        #expect(recorder.quitCount == 1)
    }

    func keyEvent(_ characters: String, keyCode: UInt16) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode))
    }

    @Test
    func `refresh row metrics match tuned native-style values`() {
        let metrics = PersistentRefreshRowMetrics.defaults
        #expect(metrics.rowHeight == 24)
        #expect(metrics.selectionHorizontalInset == 5)
        #expect(metrics.selectionVerticalInset == 0)
        #expect(metrics.selectionCornerRadius == 7)
        #expect(metrics.leadingPadding == 15)
        #expect(metrics.trailingPadding == 8)
        #expect(metrics.iconWidth == 16)
        #expect(metrics.iconSymbolPointSize == 16)
        #expect(metrics.iconSymbolWeight == .regular)
        #expect(metrics.iconTitleSpacing == 4.5)
        #expect(metrics.shortcutFontSize == 13)
        #expect(metrics.shortcutXOffset == -9.5)
        #expect(metrics.shortcutYOffset == 0)
    }

    @Test
    func `refresh shortcut display has stable native-style column`() throws {
        let previousRendering = StatusItemController.menuCardRenderingEnabled
        StatusItemController.menuCardRenderingEnabled = true
        defer { StatusItemController.menuCardRenderingEnabled = previousRendering }

        let settings = self.makeSettings()
        settings.refreshFrequency = .manual
        settings.mergeIcons = false

        let controller = self.makeController(settings: settings)
        let menu = controller.makeMenu(for: .codex)
        controller.menuWillOpen(menu)

        let refreshItem = try #require(menu.items.first { $0.title == "Refresh" })
        let refreshView = try #require(refreshItem.view as? PersistentRefreshMenuView)
        refreshView.applySize(width: 320, height: PersistentRefreshRowMetrics.defaults.rowHeight)
        refreshView.layoutSubtreeIfNeeded()

        let shortcutField = try #require(
            refreshView.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue == "⌘ R" })
        #expect(shortcutField.alignment == .left)
        #expect(shortcutField.lineBreakMode == .byClipping)
        #expect(shortcutField.frame.width >= 40)
        let shortcutFont = try #require(shortcutField.font)
        #expect(abs(shortcutFont.pointSize - PersistentRefreshRowMetrics.defaults.shortcutFontSize) < 0.001)

        let iconView = try #require(refreshView.subviews.compactMap { $0 as? NSImageView }.first)
        let titleField = try #require(
            refreshView.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue == "Refresh" })
        #expect(iconView.frame.minX == PersistentRefreshRowMetrics.defaults.leadingPadding)
        #expect(titleField.frame.minX == PersistentRefreshRowMetrics.defaults.leadingPadding
            + PersistentRefreshRowMetrics.defaults.iconWidth
            + PersistentRefreshRowMetrics.defaults.iconTitleSpacing)
        #expect(iconView.frame.width == PersistentRefreshRowMetrics.defaults.iconWidth)
        #expect(iconView.frame.height == PersistentRefreshRowMetrics.defaults.iconWidth)
    }

    @Test
    func `refresh row width follows final rendered menu width`() {
        let settings = self.makeSettings()
        let controller = self.makeController(settings: settings)
        defer { controller.releaseStatusItemsForTesting() }

        let metrics = PersistentRefreshRowMetrics.defaults
        let refreshView = PersistentRefreshMenuView(
            title: "Refresh",
            systemImageName: "arrow.clockwise",
            shortcutText: "⌘ R")
        refreshView.applySize(width: StatusItemController.menuCardBaseWidth, height: metrics.rowHeight)
        refreshView.frame.origin.x = 4

        let refreshItem = NSMenuItem()
        refreshItem.title = "Refresh"
        refreshItem.view = refreshView

        let wideNativeItem = NSMenuItem(
            title: String(repeating: "W", count: 60),
            action: nil,
            keyEquivalent: "")
        let menu = NSMenu()
        menu.addItem(refreshItem)
        menu.addItem(wideNativeItem)

        let expectedWidth = controller.renderedMenuWidth(for: menu)
        #expect(expectedWidth > StatusItemController.menuCardBaseWidth)

        controller.refreshMenuCardHeights(in: menu)

        #expect(abs(refreshView.frame.width - expectedWidth) <= 0.5)
        #expect(refreshView.frame.origin == .zero)
        #expect(refreshView.frame.height == metrics.rowHeight)
    }
}
