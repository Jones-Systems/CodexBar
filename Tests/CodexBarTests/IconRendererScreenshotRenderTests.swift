import AppKit
import CodexBarCore
import XCTest
@testable import CodexBar

/// Developer tool, skipped by default: renders a synthetic single-quota icon for PR proof.
///
/// Run with:
///   CODEXBAR_ICON_SCREENSHOT_DIR=docs/screenshots \
///     swift test --filter IconRendererScreenshotRenderTests
@MainActor
final class IconRendererScreenshotRenderTests: XCTestCase {
    private static let canvasSize = NSSize(width: 360, height: 240)

    func test_renderSyntheticSingleQuotaIcon() throws {
        guard let dir = ProcessInfo.processInfo.environment["CODEXBAR_ICON_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set CODEXBAR_ICON_SCREENSHOT_DIR to render the synthetic icon proof.")
        }
        let directory = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let icon = IconRenderer.makeIcon(
            primaryRemaining: 46,
            weeklyRemaining: nil,
            creditsRemaining: nil,
            stale: false,
            style: .combined,
            hideCritters: true,
            quotaLayoutPolicy: .provider(.codex))
        let data = try XCTUnwrap(Self.proofPNG(icon: icon), "synthetic icon proof render failed")
        let url = directory.appendingPathComponent("codex-single-quota-icon.png")
        try data.write(to: url, options: .atomic)
        print("Wrote \(url.lastPathComponent)")
    }

    func test_renderSyntheticSingleQuotaStatusBadge() throws {
        guard let dir = ProcessInfo.processInfo.environment["CODEXBAR_STATUS_ICON_PROOF_DIR"] else {
            throw XCTSkip("Set CODEXBAR_STATUS_ICON_PROOF_DIR to render the status badge proof.")
        }
        let directory = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let icon = IconRenderer.makeIcon(
            primaryRemaining: 100,
            weeklyRemaining: nil,
            creditsRemaining: nil,
            stale: false,
            style: .combined,
            statusIndicator: .minor,
            hideCritters: true,
            quotaLayoutPolicy: .provider(.codex))
        let data = try XCTUnwrap(
            Self.proofPNG(icon: icon, title: "Minor provider issue", subtitle: "single quota"),
            "synthetic status badge proof render failed")
        let url = directory.appendingPathComponent("codex-single-quota-status-badge-after.png")
        try data.write(to: url, options: .atomic)
        try Self.writeStatusOverlayMatrix(to: directory)
        print("Wrote \(url.lastPathComponent)")
    }

    private struct StatusOverlayLayout {
        let name: String
        var primary: Double?
        var secondary: Double?
        var credits: Double?
        var provider: UsageProvider = .codex
    }

    private static func writeStatusOverlayMatrix(to directory: URL) throws {
        let layouts: [StatusOverlayLayout] = [
            .init(name: "primary", primary: 100),
            .init(name: "empty-primary", primary: 0),
            .init(name: "secondary", secondary: 100),
            .init(name: "dual", primary: 100, secondary: 100),
            .init(name: "reserved", primary: 100, provider: .claude),
            .init(name: "secondary-zero", primary: 100, secondary: 0),
            .init(name: "credits", credits: 1000),
            .init(name: "unknown"),
        ]
        let indicators: [ProviderStatusIndicator] = [.none, .minor, .maintenance, .major, .critical, .unknown]
        var pixels: [String: String] = [:]
        for style in [IconStyle.codex, .combined] {
            for layout in layouts {
                for indicator in indicators {
                    let icon = IconRenderer.makeIcon(
                        primaryRemaining: layout.primary,
                        weeklyRemaining: layout.secondary,
                        creditsRemaining: layout.credits,
                        stale: false,
                        style: style,
                        statusIndicator: indicator,
                        hideCritters: true,
                        quotaLayoutPolicy: .provider(layout.provider))
                    let bitmap = try XCTUnwrap(icon.representations.compactMap { $0 as? NSBitmapImageRep }.first {
                        $0.pixelsWide == 36 && $0.pixelsHigh == 36
                    })
                    let bytes = try XCTUnwrap(bitmap.bitmapData)
                    pixels["\(style.rawValue):\(layout.name):\(indicator)"] = Data(
                        bytes: bytes, count: bitmap.bytesPerRow * bitmap.pixelsHigh).base64EncodedString()
                }
            }
        }
        let data = try JSONSerialization.data(withJSONObject: pixels, options: [.sortedKeys])
        try data.write(to: directory.appendingPathComponent("status-overlay-matrix.json"), options: .atomic)
    }

    private static func proofPNG(
        icon: NSImage,
        title: String = "Synthetic proof",
        subtitle: String = "46% remaining") -> Data?
    {
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(canvasSize.width),
            pixelsHigh: Int(canvasSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: representation)
        else { return nil }
        representation.size = Self.canvasSize

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(srgbRed: 0.10, green: 0.11, blue: 0.12, alpha: 1).setFill()
        NSRect(origin: .zero, size: Self.canvasSize).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 26, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .regular),
            .foregroundColor: NSColor(white: 0.72, alpha: 1),
            .paragraphStyle: paragraph,
        ]
        NSString(string: title).draw(
            in: NSRect(x: 24, y: 192, width: 312, height: 36),
            withAttributes: titleAttributes)
        NSString(string: subtitle).draw(
            in: NSRect(x: 24, y: 158, width: 312, height: 32),
            withAttributes: subtitleAttributes)

        context.imageInterpolation = .none
        icon.isTemplate = false
        icon.draw(
            in: NSRect(x: 108, y: 20, width: 144, height: 144),
            from: NSRect(origin: .zero, size: icon.size),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        return representation.representation(using: .png, properties: [.interlaced: false])
    }
}
