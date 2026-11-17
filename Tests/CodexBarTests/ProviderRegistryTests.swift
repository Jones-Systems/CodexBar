import CodexBarCore
import Testing
@testable import CodexBar

struct ProviderRegistryTests {
    @Test
    func `descriptor registry is complete and deterministic`() {
        let descriptors = ProviderDescriptorRegistry.all
        let ids = descriptors.map(\.id)

        #expect(!descriptors.isEmpty, "ProviderDescriptorRegistry must not be empty.")
        #expect(Set(ids).count == ids.count, "ProviderDescriptorRegistry contains duplicate IDs.")

        let missing = Set(UsageProvider.allCases).subtracting(ids)
        #expect(missing.isEmpty, "Missing descriptors for providers: \(missing).")
        #expect(ids == UsageProvider.allCases, "Descriptor manifest order must match UsageProvider.")

        let secondPass = ProviderDescriptorRegistry.all.map(\.id)
        #expect(ids == secondPass, "ProviderDescriptorRegistry order changed between reads.")
    }

    @Test
    func `implementation registry is complete and deterministic`() {
        let implementations = ProviderImplementationRegistry.all
        let ids = implementations.map(\.id)

        #expect(!implementations.isEmpty, "ProviderImplementationRegistry must not be empty.")
        #expect(Set(ids).count == ids.count, "ProviderImplementationRegistry contains duplicate IDs.")

        let missing = Set(UsageProvider.allCases).subtracting(ids)
        #expect(missing.isEmpty, "Missing implementations for providers: \(missing).")
        #expect(ids == UsageProvider.allCases, "Implementation manifest order must match UsageProvider.")

        let secondPass = ProviderImplementationRegistry.all.map(\.id)
        #expect(ids == secondPass, "ProviderImplementationRegistry order changed between reads.")
    }

    @Test
    func `icon styles derive from provider identifiers for retained providers`() {
        #expect(IconStyle.allCases == UsageProvider.allCases.map(IconStyle.init(provider:)) + [.combined])

        for descriptor in ProviderDescriptorRegistry.all {
            #expect(
                descriptor.branding.iconStyle == IconStyle(provider: descriptor.id),
                "Unexpected icon style for \(descriptor.id.rawValue).")
        }
    }

    @Test
    func `provider log categories derive byte identical names`() {
        let actual = [
            LogCategories.provider(.claude, scope: "cli"),
            LogCategories.provider(.claude, scope: "probe"),
            LogCategories.provider(.claude, scope: "usage"),
            LogCategories.provider(.codex, scope: "rpc"),
            LogCategories.provider(.codex, scope: "web"),
            LogCategories.provider(.codex, scope: "webview"),
        ]
        #expect(actual == [
            "claude-cli", "claude-probe", "claude-usage", "codex-rpc", "codex-web", "codex-webview",
        ])
    }

    @Test
    func `provider confetti palettes are complete and branded`() {
        for descriptor in ProviderDescriptorRegistry.all {
            let palette = descriptor.branding.confettiPalette
            #expect(
                (2...3).contains(palette.count),
                "Invalid confetti palette for \(descriptor.id.rawValue).")
            let hasDistinctColors = palette.first.map { first in
                palette.dropFirst().contains { $0 != first }
            } ?? false
            #expect(
                hasDistinctColors,
                "Confetti palette for \(descriptor.id.rawValue) must contain distinct colors.")
        }

        #expect(ClaudeProviderDescriptor.descriptor.branding.confettiPalette == [
            ProviderColor(hex: 0xD97757),
            ProviderColor(hex: 0xF0EEE6),
            ProviderColor(hex: 0x141413),
        ])
        #expect(CodexProviderDescriptor.descriptor.branding.confettiPalette == [
            ProviderColor(hex: 0x736BD4),
            ProviderColor(hex: 0x97A9F7),
            ProviderColor(hex: 0xCFD4F7),
        ])
    }
}
