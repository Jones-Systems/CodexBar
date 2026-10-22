import AppKit
import CodexBarCore
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct ClaudeNativeProfileMenuSelectionTests {
    @Test
    func `choices retain discovery order distinguish duplicate labels and check saved alias`() throws {
        let items = try ClaudeNativeProfileMenuSelection.items(
            selectedAlias: "jace", discovery: ClaudeFleetProfileDiscoveryTests.discovery(), label: { _ in "Work" })
        #expect(items.prefix(2).map(\.title) == ["Work (default)", "Work (jace)"])
        #expect(items.prefix(2).map(\.isChecked) == [false, true])
        #expect(items[0].action == .selectClaudeNativeProfile(alias: "default"))
        #expect(items[1].action == .selectClaudeNativeProfile(alias: "jace"))
        #expect(items[2].title == "Selects the profile shown in CodexBar.")
        #expect(!items[2].isEnabled)
        #expect(items.last?.action == .providerSettings(.claude))
    }

    @Test
    func `missing saved profile stays checked and settings remain available without discovery`() throws {
        for discovery in try [
            ClaudeFleetProfileDiscovery.Result.missing,
            ClaudeFleetProfileDiscoveryTests.discovery(),
        ] {
            let items = ClaudeNativeProfileMenuSelection.items(
                selectedAlias: "removed", discovery: discovery, label: { $0.alias })
            let saved = try #require(items.first { $0.title == "Unavailable saved profile" })
            #expect(saved.isChecked)
            #expect(!saved.isEnabled)
            #expect(saved.action == nil)
            #expect(items.contains { $0.title == "No available profiles" } == discovery.profiles.isEmpty)
            #expect(items.last?.title == "Profile settings…")
            #expect(items.last?.isEnabled == true)
        }
    }

    @Test
    func `selection persists only a changed available alias and invalidates former identity`() async throws {
        try await ClaudeNativeProfileAccountsFixture.run { settings, store, _ in
            let original = store.claudeNativeProfileFetchEnvironment()
            let revision = settings.backgroundWorkSettingsRevision
            #expect(ClaudeNativeProfileMenuSelection.select(alias: "default", store: store) == .unchanged)
            #expect(settings.backgroundWorkSettingsRevision == revision)
            store.snapshots[.claude] = ClaudeNativeProfileAccountsFixture.snapshot(12)
            #expect(ClaudeNativeProfileMenuSelection.select(alias: "jace", store: store) == .changed)
            #expect(settings.claudeNativeProfileAlias == "jace")
            let persisted = try? settings.configStore.load()
            #expect(persisted?.providerConfig(for: .claude)?.claudeNativeProfileAlias == "jace")
            store.updateProviderRuntimes()
            #expect(!store.claudeNativeProfileEnvironmentIsCurrent(original))
            #expect(store.snapshot(for: .claude) == nil)
            #expect(settings.backgroundWorkSettingsRevision > revision)
            #expect(ClaudeNativeProfileMenuSelection.select(alias: "default", store: store) == .changed)
            #expect(store.claudeNativeProfileFetchEnvironment()["CLAUDE_CONFIG_DIR"] == nil)
        }
    }

    @Test
    func `stale discovery and stale source mode cannot change saved selection`() async throws {
        try await ClaudeNativeProfileAccountsFixture.run { settings, store, _ in
            ClaudeFleetProfileDiscovery.$discoveryOverride.withValue(.missing) {
                #expect(ClaudeNativeProfileMenuSelection.select(alias: "jace", store: store) == .stale)
                #expect(settings.claudeNativeProfileAlias == "default")
            }
            settings.claudeUsageDataSource = .web
            #expect(ClaudeNativeProfileMenuSelection.select(alias: "jace", store: store) == .stale)
            #expect(settings.claudeNativeProfileAlias == "default")
        }
    }

    @Test
    func `available profile replaces an unavailable saved alias`() async throws {
        try await ClaudeNativeProfileAccountsFixture.run { settings, store, _ in
            settings.claudeNativeProfileAlias = "removed"
            #expect(ClaudeNativeProfileSelection
                .isUnavailable(environment: store.claudeNativeProfileFetchEnvironment()))
            #expect(ClaudeNativeProfileMenuSelection.select(alias: "jace", store: store) == .changed)
            #expect(settings.claudeNativeProfileAlias == "jace")
        }
    }

    @Test
    func `descriptor replaces manage entry and native menu dispatch selects profile`() async throws {
        try await ClaudeNativeProfileAccountsFixture.run { settings, store, _ in
            try withStatusItemControllerForTesting(store: store, settings: settings, fetcher: UsageFetcher()) {
                controller in
                let descriptor = controller.makeMenuDescriptor(provider: .claude, includeContextualActions: true)
                let entries = descriptor.sections.flatMap(\.entries)
                #expect(!entries.contains {
                    if case .action("Manage native profile…", _) = $0 { return true }
                    return false
                })
                let menu = NSMenu()
                menu.autoenablesItems = false
                controller.addActionableSections(descriptor.sections, to: menu, width: 320, provider: .claude)
                let submenu = try #require(menu.items.first { $0.title == "Claude profile" }?.submenu)
                #expect(submenu.items.first?.state == .on)
                let item = try #require(submenu.items.first { ($0.representedObject as? String) == "jace" })
                #expect(item.action == #selector(StatusItemController.selectClaudeNativeProfileFromMenu(_:)))
                controller.selectClaudeNativeProfileFromMenu(item)
                #expect(settings.claudeNativeProfileAlias == "jace")
                #expect(submenu.items.last?.action == #selector(StatusItemController.showProviderSettings(_:)))
            }
        }
    }

    @Test
    func `SwiftUI action uses the same validated selection and settings dispatch`() async throws {
        try await ClaudeNativeProfileAccountsFixture.run { settings, store, _ in
            withStatusItemControllerForTesting(
                store: store,
                settings: settings,
                fetcher: UsageFetcher())
            { controller in
                var openedProvider: UsageProvider?
                let content = MenuContent(
                    store: store, settings: settings, account: AccountInfo(email: nil, plan: nil),
                    updater: controller.updater, provider: .claude,
                    actions: MenuActions(
                        installUpdate: {}, refresh: {}, refreshAugmentSession: {}, openDashboard: {},
                        openStatusPage: {}, openChangelog: {}, addCodexAccount: {}, switchAccount: { _ in },
                        openTerminal: { _ in }, openSettings: {}, openProviderSettings: { openedProvider = $0 },
                        openAbout: {}, quit: {}, copyError: { _ in }))
                content.perform(.selectClaudeNativeProfile(alias: "jace"))
                #expect(settings.claudeNativeProfileAlias == "jace")
                settings.claudeUsageDataSource = .web
                content.perform(.selectClaudeNativeProfile(alias: "default"))
                #expect(settings.claudeNativeProfileAlias == "jace")
                content.perform(.providerSettings(.claude))
                #expect(openedProvider == .claude)
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CODEXBAR_CLAUDE_PROFILE_MENU_CAPTURE"] == "1"))
    func `capture actual SwiftUI profile menu rows with synthetic enrollment`() async throws {
        let environment = ProcessInfo.processInfo.environment
        try #require(environment["CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS"] == "1")
        try #require(environment["CODEXBAR_TEST_CODEX_FILE_ISOLATION"] == "1")
        try #require(environment["CODEXBAR_TEST_SESSION_FILE_ISOLATION"] == "1")
        try #require(environment["CODEXBAR_ALLOW_TEST_KEYCHAIN_ACCESS"] != "1")
        let workspace = try #require(environment["CODEXBAR_TEST_WORKSPACE_ROOT"])
        let directory = URL(fileURLWithPath: workspace, isDirectory: true)
            .appendingPathComponent(".t3/pr-media/claude-profile-menu", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try await ClaudeNativeProfileAccountsFixture.run { settings, store, _ in
            let content = MenuContent(
                store: store, settings: settings, account: AccountInfo(email: nil, plan: nil),
                updater: DisabledUpdaterController(), provider: .claude,
                actions: MenuActions(
                    installUpdate: {}, refresh: {}, refreshAugmentSession: {}, openDashboard: {},
                    openStatusPage: {}, openChangelog: {}, addCodexAccount: {}, switchAccount: { _ in },
                    openTerminal: { _ in }, openSettings: {}, openProviderSettings: { _ in },
                    openAbout: {}, quit: {}, copyError: { _ in }))
            let previous = try #require(ClaudeProviderImplementation().loginMenuAction(
                context: ProviderMenuLoginContext(
                    provider: .claude, store: store, settings: settings,
                    account: AccountInfo(email: nil, plan: nil), hasAccount: true)))
            // Reconstruct the prior action with the current consumer; this is not a prior-binary capture.
            try Self.capture(
                content.row(for: .action(previous.label, previous.action)),
                to: directory.appendingPathComponent("baseline-action-reconstruction.png"))
            for alias in ["default", "jace", "removed"] {
                settings.claudeNativeProfileAlias = alias
                let descriptor = MenuDescriptor.build(
                    provider: .claude, store: store, settings: settings,
                    account: AccountInfo(email: nil, plan: nil), updateReady: false)
                let entry = try #require(descriptor.sections.flatMap(\.entries).first {
                    if case .submenu("Claude profile", _, _) = $0 { return true }
                    return false
                })
                try Self.capture(
                    content.row(for: entry),
                    to: directory.appendingPathComponent("profile-\(alias).png"))
            }
        }
    }

    private static func capture(_ content: some View, to url: URL) throws {
        let hosting = NSHostingView(rootView: content
            .padding(16)
            .frame(width: 360, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor)))
        hosting.appearance = NSAppearance(named: .aqua)
        let size = hosting.fittingSize
        try #require(size.width > 0 && size.height > 0)
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = hosting.appearance
        window.contentView = hosting
        defer {
            window.contentView = nil
            window.close()
        }
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let representation = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: representation)
        let data = try #require(representation.representation(using: .png, properties: [:]))
        try #require(!data.isEmpty)
        try data.write(to: url, options: .atomic)
    }
}
