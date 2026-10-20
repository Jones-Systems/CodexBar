import AppKit
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct StatusMenuClaudeNativeProfileAccountsTests {
    @Test
    func `native profile settings action keeps merged provider and overview menus at baseline width`() async throws {
        try await ClaudeNativeProfileAccountsFixture.run { settings, store, _ in
            settings.mergeIcons = true
            settings.setProviderEnabled(
                provider: .codex,
                metadata: ProviderDescriptorRegistry.descriptor(for: .codex).metadata,
                enabled: true)
            store.snapshots[.claude] = ClaudeNativeProfileAccountsFixture.snapshot(12)
            try withStatusItemControllerForTesting(
                store: store,
                settings: settings,
                fetcher: UsageFetcher())
            { controller in
                let action = try #require(ClaudeProviderImplementation().loginMenuAction(
                    context: ProviderMenuLoginContext(
                        provider: .claude,
                        store: store,
                        settings: settings,
                        account: AccountInfo(email: nil, plan: nil),
                        hasAccount: true)))
                #expect(action.action == .providerSettings(.claude))
                for (provider, includeContextualActions) in [
                    (UsageProvider.codex, true), (.claude, true), (.codex, false),
                ] {
                    let descriptor = controller.makeMenuDescriptor(
                        provider: provider,
                        includeContextualActions: includeContextualActions)
                    let width = controller.menuCardWidth(
                        for: [.codex, .claude],
                        selectedProvider: provider,
                        descriptor: descriptor)
                    #expect(width == StatusItemController.menuCardBaseWidth)
                }
            }
        }
    }

    @Test
    func `two native profiles render selected card and side row without switching or hidden tail`() async throws {
        try await ClaudeNativeProfileAccountsFixture.run { settings, store, root in
            settings.setAccountDisplayLabel(
                "Side account",
                provider: .claude,
                profileIdentity: JonesAccountDisplayLabel.claudeProfileIdentity(
                    alias: "jace",
                    home: root.path,
                    configDirectory: root.appendingPathComponent(".claude-t3/jace").path))
            store.snapshots[.claude] = ClaudeNativeProfileAccountsFixture.snapshot(12)
            store
                ._test_claudeNativeProfileFetchOutcomeOverride = { _ in ClaudeNativeProfileAccountsFixture.outcome(67) }
            await store.refreshClaudeNativeProfileAccountsAfterMain()
            StatusItemController.menuCardRenderingEnabled = false
            StatusItemController.setMenuRefreshEnabledForTesting(false)
            defer {
                StatusItemController.menuCardRenderingEnabled = true
                StatusItemController.setMenuRefreshEnabledForTesting(true)
            }
            try withStatusItemControllerForTesting(
                store: store,
                settings: settings,
                fetcher: UsageFetcher())
            { controller in
                let accounts = store.claudeNativeProfileAccountsForDisplay()
                let plan = controller.compactAccountPlan(for: .claude, accounts: accounts)
                #expect(plan.usesCompactLayout)
                #expect(plan.rows.count == 2)
                #expect(accounts.last?.displayLabel == "Side account")
                let menu = controller.makeMenu(for: .claude)
                controller.refreshMenuForOpenIfNeeded(menu, provider: .claude)
                let ids = menu.items.compactMap { $0.representedObject as? String }
                    .filter { $0.hasPrefix("claudeNativeProfile") }
                #expect(ids == ["claudeNativeProfileCard-default", "claudeNativeProfileCompact-jace"])
                #expect(accounts.allSatisfy { !$0.canActivate })
                let side = try #require(accounts.last)
                #expect(controller.claudeNativeProfileCardModel(for: side)?.email == "Side account")
                #expect(controller.menuCardModel(for: .claude)?.email == "default")
                settings.hidePersonalInfo = true
                #expect(controller.claudeNativeProfileCardModel(for: side)?.email.isEmpty == true)
            }
        }
    }

    @Test
    func `native loading is visible and retained usage keeps its original timestamp`() async throws {
        try await ClaudeNativeProfileAccountsFixture.run { settings, store, _ in
            let started = AsyncStream<Void>.makeStream()
            var iterator = started.stream.makeAsyncIterator()
            var blocked: CheckedContinuation<Void, Never>?
            store._test_claudeNativeProfileFetchOutcomeOverride = { _ in
                await withCheckedContinuation { blocked = $0; started.continuation.yield(()) }
                return ClaudeNativeProfileAccountsFixture.outcome(67)
            }
            let refresh = Task { await store.refreshClaudeNativeProfileAccountsAfterMain() }
            _ = await iterator.next()
            withStatusItemControllerForTesting(
                store: store,
                settings: settings,
                fetcher: UsageFetcher())
            { controller in
                let side = store.claudeNativeProfileAccountsForDisplay().last
                #expect(side?.snapshot == nil)
                #expect(store.claudeNativeProfileRefreshingAliases == ["jace"])
                if let side {
                    let model = controller.claudeNativeProfileCardModel(for: side)
                    #expect(model?.subtitleText == "\(L("Refreshing"))…")
                    #expect(model?.placeholder == nil)
                }
            }
            blocked?.resume()
            await refresh.value
            let previous = store.claudeNativeProfileAccountsForDisplay().last?.snapshot
            let second = Task { await store.refreshClaudeNativeProfileAccountsAfterMain() }
            _ = await iterator.next()
            withStatusItemControllerForTesting(
                store: store,
                settings: settings,
                fetcher: UsageFetcher())
            { controller in
                if let side = store.claudeNativeProfileAccountsForDisplay().last {
                    let model = controller.claudeNativeProfileCardModel(for: side)
                    #expect(side.snapshot?.updatedAt == previous?.updatedAt)
                    #expect(side.snapshot?.primary?.usedPercent == 67)
                    #expect(model?.subtitleText != "\(L("Refreshing"))…")
                    #expect(model?.metrics.isEmpty == false)
                }
            }
            blocked?.resume()
            await second.value
        }
    }

    @Test(arguments: [false, true])
    func `compact loading accessibility preserves existing quota display`(hasUsage: Bool) {
        let model = MenuCardCompactAccountRowView.Model(
            label: "Side account",
            headroomPercent: hasUsage ? 33 : nil,
            severity: hasUsage ? .warning : nil,
            constraintDetail: nil,
            hasError: false,
            showsBestBadge: false,
            isRefreshing: true)
        let view = MenuCardCompactAccountRowView(model: model, progressColor: .blue, width: 320)
        #expect(view.accessibilityText.contains("Refreshing") == !hasUsage)
        #expect(view.accessibilityText.contains("33%") == hasUsage)
        var idle = model
        idle.isRefreshing = false
        #expect(!MenuCardCompactAccountRowView(model: idle, progressColor: .blue, width: 320)
            .accessibilityText.contains("Refreshing"))
        #expect(idle.heightFingerprint != model.heightFingerprint)
    }

    @Test
    func `unavailable native row keeps its error and swap and token presentation policies stay unchanged`()
        async throws
    {
        try await ClaudeNativeProfileAccountsFixture.run { settings, store, _ in
            store._test_claudeNativeProfileFetchOutcomeOverride = { _ in
                ProviderFetchOutcome(result: .failure(ClaudeNativeProfileSelectionError.unavailable), attempts: [])
            }
            await store.refreshClaudeNativeProfileAccountsAfterMain()
            try withStatusItemControllerForTesting(
                store: store,
                settings: settings,
                fetcher: UsageFetcher())
            { controller in
                let accounts = store.claudeNativeProfileAccountsForDisplay()
                let side = try #require(accounts.last)
                #expect(side.snapshot == nil)
                #expect(controller.claudeNativeProfileCardModel(for: side)?.subtitleText
                    == ClaudeNativeProfileSelectionError.unavailable.localizedDescription)
                let plan = controller.compactAccountPlan(for: .claude, accounts: accounts)
                let compact = try #require(plan.rows.compactMap { row in
                    if case let .compact(value) = row { return value }
                    return nil
                }.first)
                let rendering = StatusItemController.CompactAccountMenuRendering(
                    plan: plan,
                    accounts: accounts,
                    idPrefix: "claudeNativeProfile",
                    cardModel: { _ in nil },
                    accountStatusText: [side.id: "Unavailable synthetic@example.test"])
                let row = controller.compactAccountRowModel(for: compact, rendering: rendering)
                #expect(row.constraintDetail == "Unavailable synthetic@example.test")
                #expect(row.heightFingerprint.contains("Unavailable synthetic@example.test"))
                settings.hidePersonalInfo = true
                let hidden = controller.compactAccountRowModel(for: compact, rendering: rendering)
                #expect(hidden.constraintDetail == PersonalInfoRedactor.redactEmails(
                    in: "Unavailable synthetic@example.test", isEnabled: true))
                #expect(hidden.constraintDetail?.contains("synthetic@example.test") == false)
                #expect(hidden.heightFingerprint != row.heightFingerprint)
                for source in ["claude-swap", "token-account"] {
                    let other = accounts.map {
                        ProviderAccountUsageSnapshot(
                            id: ProviderAccountIdentity(source: source, opaqueID: $0.id.opaqueID),
                            provider: .claude,
                            displayLabel: $0.displayLabel,
                            isActive: $0.isActive,
                            canActivate: !$0.isActive,
                            snapshot: $0.snapshot,
                            error: $0.error,
                            sourceLabel: $0.sourceLabel)
                    }
                    #expect(!controller.compactAccountPlan(for: .claude, accounts: other).usesCompactLayout)
                }
                let baseline = controller.menuAdjunctReadinessSignature()
                store.claudeNativeProfileAccountsRevision &+= 1
                #expect(controller.menuAdjunctReadinessSignature() != baseline)
            }
        }
    }
}
