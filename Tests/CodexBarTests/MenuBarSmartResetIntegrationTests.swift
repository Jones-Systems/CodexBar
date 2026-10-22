import AppKit
import CodexBarCore
import Foundation
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct MenuBarSmartResetIntegrationTests {
    @Test(arguments: [MenuBarDisplayMode.pace, .both])
    func `combined smart reset keeps exhausted session percent without a reset`(mode: MenuBarDisplayMode) {
        let settings = testSettingsStore(
            suiteName: "MenuBarSmartResetIntegrationTests-combined-fallback-\(mode.rawValue)")
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.selectedMenuProvider = .claude
        settings.menuBarShowsBrandIconWithPercent = true
        settings.menuBarDisplayMode = mode
        settings.menuBarShowsResetTimeWhenExhausted = true
        settings.usageBarsShowUsed = false
        settings.setMenuBarMetricPreference(.primaryAndSecondary, for: .claude)

        if let metadata = ProviderRegistry.shared.metadata[.claude] {
            settings.setProviderEnabled(provider: .claude, metadata: metadata, enabled: true)
        }

        let fetcher = UsageFetcher()
        let store = UsageStore(
            fetcher: fetcher,
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: .system)
        defer { controller.releaseStatusItemsForTesting() }

        let now = Date()
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 100,
                windowMinutes: 300,
                resetsAt: nil,
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: 50,
                windowMinutes: 7 * 24 * 60,
                resetsAt: now.addingTimeInterval(60 * 60),
                resetDescription: nil),
            updatedAt: now)
        store._setSnapshotForTesting(snapshot, provider: .claude)
        store._setErrorForTesting(nil, provider: .claude)

        // Weekly pace remains available, but it must not hide that the displayed session is exhausted.
        // Without a concrete future session reset there is no reset text or timer to surface instead.
        #expect(controller.menuBarDisplayText(for: .claude, snapshot: snapshot, now: now) == "0%")
        #expect(controller.menuBarDisplayedResetDates(for: .claude, now: now).isEmpty)
        #expect(!controller._test_isMenuBarCountdownRefreshScheduled())
    }
}

extension MenuBarSmartResetIntegrationTests {
    @Test
    func `banked credit expiry replaces the later reset without changing percentage`() throws {
        let settings = testSettingsStore(suiteName: "MenuBarSmartResetIntegrationTests-banked-expiry")
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.menuBarIconStyle = .iconAndPercent
        settings.usageBarsShowUsed = false
        settings.setMenuBarLayout(MenuBarLayout(lines: [[.percent(window: .automatic), .resetCountdown]]), for: .codex)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let expiry = now.addingTimeInterval(5 * 3600 + 13 * 60)
        let weekly = RateWindow(
            usedPercent: 96,
            windowMinutes: 10080,
            resetsAt: now.addingTimeInterval(399_600),
            resetDescription: nil)
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: weekly,
            codexResetCredits: CodexRateLimitResetCreditsSnapshot(
                credits: [CodexRateLimitResetCredit(
                    id: "synthetic-banked",
                    resetType: "weekly",
                    status: .available,
                    grantedAt: now.addingTimeInterval(-86400),
                    expiresAt: expiry,
                    redeemStartedAt: nil,
                    redeemedAt: nil,
                    title: nil,
                    description: nil)],
                availableCount: 1,
                updatedAt: now),
            updatedAt: now)
        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        store._setSnapshotForTesting(snapshot, provider: .codex)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: .system)
        defer { controller.releaseStatusItemsForTesting() }
        let data = controller.menuBarLayoutRenderData(
            provider: .codex,
            snapshot: snapshot,
            warningFlash: false,
            now: now)
        let output = MenuBarLayoutRenderer().render(
            layout: settings.menuBarLayoutResolution(for: .codex).layout,
            data: data,
            icon: nil,
            options: MenuBarLayoutRenderOptions(
                size: .regular,
                highContrast: false,
                showUsed: false,
                conditionals: [],
                appearanceName: "default",
                isDebugApp: false,
                now: now))
        try Self.captureResetDisplayIfRequested(output: output, snapshot: snapshot, now: now)
        #expect(output.attributedTitle.string.hasPrefix("4%"))
        #expect(output.attributedTitle.string.contains("5h 13m"))
        #expect(output.attributedTitle.attribute(
            .attachment,
            at: output.attributedTitle.length - 1,
            effectiveRange: nil) is NSTextAttachment)
        #expect(output.accessibilityLabel.contains("Limit Reset Credits"))
        #expect(controller.menuBarDisplayedResetDates(for: .codex, now: now).contains(expiry))
    }

    private static func captureResetDisplayIfRequested(
        output: MenuBarLayoutRenderedTitle,
        snapshot: UsageSnapshot,
        now: Date) throws
    {
        guard let directory = ProcessInfo.processInfo.environment["CODEXBAR_RESET_DISPLAY_CAPTURE_DIR"] else { return }
        let destination = URL(fileURLWithPath: directory, isDirectory: true)
        let model = JonesCompactAccountPresentation.overviewSummaryRow(
            .init(
                provider: .codex,
                label: "Synthetic account",
                snapshot: snapshot,
                hasError: false,
                isRefreshing: false),
            resetStyle: .countdown,
            now: now)
        let row = NSHostingView(rootView: MenuCardCompactAccountRowView(
            model: model,
            progressColor: .green,
            width: 340)
            .frame(width: 340, height: 54)
            .background(Color.white))
        row.frame = NSRect(x: 0, y: 0, width: 340, height: 54)
        row.appearance = NSAppearance(named: .aqua)
        row.layoutSubtreeIfNeeded()
        let bitmap = try #require(row.bitmapImageRepForCachingDisplay(in: row.bounds))
        row.cacheDisplay(in: row.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:]))
            .write(to: destination.appendingPathComponent("account-row.png"))
        let image = NSImage(size: NSSize(width: 340, height: 36))
        let appearance = try #require(NSAppearance(named: .aqua))
        appearance.performAsCurrentDrawingAppearance {
            image.lockFocus()
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: 340, height: 36).fill()
            output.attributedTitle.draw(at: NSPoint(x: 12, y: 10))
            image.unlockFocus()
        }
        let imageData = try #require(image.tiffRepresentation)
        let imageBitmap = try #require(NSBitmapImageRep(data: imageData))
        try #require(imageBitmap.representation(using: .png, properties: [:]))
            .write(to: destination.appendingPathComponent("menu-bar.png"))
    }
}

extension MenuBarSmartResetIntegrationTests {
    @Test(arguments: [ResetTimeDisplayStyle.countdown, .absolute])
    func `legacy reset modes select credit expiry and return to quota reset after expiry`(
        style: ResetTimeDisplayStyle) throws
    {
        let settings = testSettingsStore(suiteName: "MenuBarSmartResetIntegrationTests-legacy-credit-\(style)")
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.menuBarIconStyle = .iconAndPercent
        settings.menuBarDisplayMode = .resetTime
        settings.resetTimesShowAbsolute = style == .absolute
        settings.usageBarsShowUsed = false
        #expect(settings.menuBarLayoutResolution(for: .codex).usesLegacyRendering)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let expiry = now.addingTimeInterval(3600)
        let resetAt = now.addingTimeInterval(399_600)
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: RateWindow(usedPercent: 96, windowMinutes: 10080, resetsAt: resetAt, resetDescription: nil),
            codexResetCredits: .init(
                credits: [CodexRateLimitResetCredit(
                    id: "synthetic-legacy",
                    resetType: "weekly",
                    status: .available,
                    grantedAt: now.addingTimeInterval(-86400),
                    expiresAt: expiry,
                    redeemStartedAt: nil,
                    redeemedAt: nil,
                    title: nil,
                    description: nil)],
                availableCount: 1,
                updatedAt: now),
            updatedAt: now)
        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        store._setSnapshotForTesting(snapshot, provider: .codex)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: .system)
        defer { controller.releaseStatusItemsForTesting() }
        #expect(controller.menuBarDisplayText(for: .codex, snapshot: snapshot, now: now) == "in 1h\u{2009}\u{FFFC}")
        #expect(controller.menuBarDisplayedResetDates(for: .codex, now: now).contains(expiry))
        let after = try #require(controller.menuBarDisplayText(for: .codex, snapshot: snapshot, now: expiry))
        #expect(after.hasPrefix("↻ "))
        #expect(!after.contains("\u{FFFC}"))
        #expect(!controller.menuBarDisplayedResetDates(for: .codex, now: expiry).contains(expiry))
        settings.menuBarDisplayMode = .percent
        settings.menuBarShowsResetTimeWhenExhausted = false
        #expect(controller.menuBarDisplayText(for: .codex, snapshot: snapshot, now: now) == "4%")
        #expect(controller.menuBarResetCreditCountdown(for: .codex, snapshot: snapshot, now: now) == nil)
        settings.menuBarShowsResetTimeWhenExhausted = true
        let exhausted = UsageSnapshot(
            primary: nil,
            secondary: RateWindow(usedPercent: 100, windowMinutes: 10080, resetsAt: resetAt, resetDescription: nil),
            codexResetCredits: snapshot.codexResetCredits,
            updatedAt: now)
        #expect(controller.menuBarDisplayText(for: .codex, snapshot: exhausted, now: now) == "in 1h\u{2009}\u{FFFC}")
    }
}
