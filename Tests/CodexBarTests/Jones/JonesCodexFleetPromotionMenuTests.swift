import AppKit
import CodexBarCore
import Foundation
import SwiftUI
import Testing
@testable import CodexBar

@Suite(.serialized, CodexCredentialFixtures())
@MainActor
struct JonesCodexFleetPromotionMenuTests {
    @Test
    func `named fleet System Account menu keeps friendly roster labels and live identity checkmark`() throws {
        let fixture = try CodexAccountPromotionTestContainer(suiteName: "JonesFleet-named-system-menu")
        defer { fixture.tearDown() }
        let profiles = try JonesAccountAggregate.codexAliases.map { alias in
            try fixture.createFleetProfile(alias: alias, email: "\(alias)@example.com", accountID: "acct-\(alias)")
        }
        let managed = try fixture.createManagedAccount(
            persistedEmail: "steven@example.com",
            authAccountID: "acct-other-workspace",
            workspaceLabel: "Extra workspace")
        let extra = try fixture.createFleetProfile(alias: "extra")
        let live = ObservedSystemCodexAccount(
            email: "steven@example.com",
            workspaceAccountID: "acct-steven",
            codexHomePath: fixture.liveHomeURL.path,
            observedAt: Date())
        let snapshot = CodexAccountReconciliationSnapshot(
            storedAccounts: [managed],
            activeStoredAccount: nil,
            liveSystemAccount: live,
            profileHomeAccounts: profiles + [extra],
            fleetProfileHomePaths: profiles.map(\.codexHomePath),
            matchingStoredAccountForLiveSystemAccount: nil,
            activeSource: .profileHome(path: profiles[1].codexHomePath),
            hasUnreadableAddedAccountStore: false)
        fixture.settings._test_codexAccountSnapshotLoader = { _ in snapshot }
        fixture.settings.invalidateCodexAccountReconciliationSnapshotCache()
        let namedItems = try self.systemAccountItems(fixture: fixture)
        #expect(namedItems.map(\.title) == [
            "Malcolm", "Jace", "UMICH", "Steven", "Wallace",
        ])
        if ProcessInfo.processInfo.environment["CODEXBAR_SYSTEM_ACCOUNT_MENU_CAPTURE"] == "1" {
            try self.captureSystemAccountMenu(
                fixture: fixture,
                projection: CodexVisibleAccountProjection.make(from: snapshot),
                items: namedItems)
        }
        let umich = try #require(CodexVisibleAccountProjection.make(from: snapshot).menuAccounts.first {
            $0.fleetProfileAlias == "umich"
        })
        fixture.settings.setAccountDisplayLabel(
            "UMICH local",
            provider: .codex,
            profileIdentity: JonesAccountDisplayLabel.codexProfileIdentity(for: umich))
        let coordinator = CodexAccountPromotionCoordinator(service: fixture.makeService())
        let items = try self.systemAccountItems(fixture: fixture, coordinator: coordinator)
        let expectedLabels = ["Malcolm", "Jace", "UMICH local", "Steven", "Wallace"]
        #expect(items.map(\.title) == expectedLabels)
        #expect(items.filter(\.isChecked).map(\.title) == ["Steven"])
        for (item, profile) in zip(items, profiles) {
            let expectedTarget = try jonesFleetTarget(profile)
            #expect(item.action == .requestCodexSystemPromotion(expectedTarget))
            #expect(item.isEnabled == (item.title != "Steven"))
        }
        coordinator.setLiveReauthenticationInProgress(true)
        defer { coordinator.setLiveReauthenticationInProgress(false) }
        let blockedItems = try self.systemAccountItems(fixture: fixture, coordinator: coordinator)
        #expect(blockedItems.allSatisfy { !$0.isEnabled })
        #expect(blockedItems.map(\.action) == items.map(\.action))
        #expect(blockedItems.filter(\.isChecked).map(\.title) == ["Steven"])
    }

    @Test(arguments: ["acct-shared", "acct-other-workspace"])
    func `ambiguous or different workspace identities do not fabricate a fleet checkmark`(
        liveWorkspaceID: String) throws
    {
        let fixture = try CodexAccountPromotionTestContainer(suiteName: "JonesFleet-ambiguous-system-menu")
        defer { fixture.tearDown() }
        let profiles = try ["jace", "malcolm"].map { alias in
            try fixture.createFleetProfile(alias: alias, email: "same@example.com", accountID: "acct-shared")
        }
        let snapshot = CodexAccountReconciliationSnapshot(
            storedAccounts: [],
            activeStoredAccount: nil,
            liveSystemAccount: ObservedSystemCodexAccount(
                email: "same@example.com",
                workspaceAccountID: liveWorkspaceID,
                codexHomePath: fixture.liveHomeURL.path,
                observedAt: Date()),
            profileHomeAccounts: profiles,
            fleetProfileHomePaths: profiles.map(\.codexHomePath),
            matchingStoredAccountForLiveSystemAccount: nil,
            activeSource: .profileHome(path: profiles[0].codexHomePath),
            hasUnreadableAddedAccountStore: false)
        fixture.settings._test_codexAccountSnapshotLoader = { _ in snapshot }
        fixture.settings.invalidateCodexAccountReconciliationSnapshotCache()
        let items = try self.systemAccountItems(fixture: fixture)
        #expect(items.count == 2)
        #expect(items.allSatisfy { !$0.isChecked && $0.isEnabled })
        #expect(items[0].action != nil && items[1].action != nil)
        #expect(items[0].action != items[1].action)
    }

    @Test
    func `System Account without named fleet preserves managed and live rows`() throws {
        let fixture = try CodexAccountPromotionTestContainer(suiteName: "JonesFleet-nonfleet-system-menu")
        defer { fixture.tearDown() }
        let managed = try fixture.createManagedAccount(
            persistedEmail: "managed@example.com", authAccountID: "acct-managed")
        let snapshot = CodexAccountReconciliationSnapshot(
            storedAccounts: [managed],
            activeStoredAccount: managed,
            liveSystemAccount: ObservedSystemCodexAccount(
                email: "live@example.com",
                workspaceAccountID: "acct-live",
                codexHomePath: fixture.liveHomeURL.path,
                observedAt: Date()),
            matchingStoredAccountForLiveSystemAccount: nil,
            activeSource: .managedAccount(id: managed.id),
            hasUnreadableAddedAccountStore: false)
        fixture.settings._test_codexAccountSnapshotLoader = { _ in snapshot }
        fixture.settings.invalidateCodexAccountReconciliationSnapshotCache()
        let projection = CodexVisibleAccountProjection.make(from: snapshot)
        let items = try self.systemAccountItems(fixture: fixture)
        #expect(items.map(\.title) == projection.visibleAccounts.map(\.displayName))
        let managedItem = try #require(items.first {
            $0.action == .requestCodexSystemPromotion(.managedAccount(managed.id))
        })
        #expect(managedItem.isEnabled && !managedItem.isChecked)
        let liveItem = try #require(items.first { $0.title == "live@example.com" })
        #expect(liveItem.isChecked && !liveItem.isEnabled && liveItem.action == nil)
    }

    private func systemAccountItems(
        fixture: CodexAccountPromotionTestContainer,
        coordinator: CodexAccountPromotionCoordinator? = nil) throws -> [MenuDescriptor.SubmenuItem]
    {
        let descriptor = MenuDescriptor.build(
            provider: .codex,
            store: fixture.usageStore,
            settings: fixture.settings,
            account: AccountInfo(email: nil, plan: nil),
            codexAccountPromotionCoordinator: coordinator,
            updateReady: false)
        let submenus: [[MenuDescriptor.SubmenuItem]] = descriptor.sections.flatMap(\.entries).compactMap { entry in
            if case let .submenu(title, _, items) = entry, title == "System Account" { return items }
            return nil
        }
        return try #require(submenus.first)
    }

    private func captureSystemAccountMenu(
        fixture: CodexAccountPromotionTestContainer,
        projection: CodexVisibleAccountProjection,
        items: [MenuDescriptor.SubmenuItem]) throws
    {
        let environment = ProcessInfo.processInfo.environment
        try #require(environment["CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS"] == "1")
        try #require(environment["CODEXBAR_TEST_CODEX_FILE_ISOLATION"] == "1")
        try #require(environment["CODEXBAR_TEST_SESSION_FILE_ISOLATION"] == "1")
        try #require(environment["CODEXBAR_ALLOW_TEST_KEYCHAIN_ACCESS"] != "1")
        let workspace = try #require(environment["CODEXBAR_TEST_WORKSPACE_ROOT"])
        let directory = URL(fileURLWithPath: workspace, isDirectory: true)
            .appendingPathComponent(".t3/pr-media/system-account-menu", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let content = MenuContent(
            store: fixture.usageStore,
            settings: fixture.settings,
            account: AccountInfo(email: nil, plan: nil),
            updater: DisabledUpdaterController(),
            provider: .codex,
            actions: MenuActions(
                installUpdate: {},
                refresh: {},
                openDashboard: {},
                openStatusPage: {},
                openChangelog: {},
                addCodexAccount: {},
                switchAccount: { _ in },
                openTerminal: { _ in },
                openSettings: {},
                openProviderSettings: { _ in },
                openAbout: {},
                quit: {},
                copyError: { _ in }))
        let previousItems = projection.visibleAccounts.map { account in
            let isChecked = account.id == projection.liveVisibleAccountID
            return MenuDescriptor.SubmenuItem(
                title: account.displayName,
                action: account.systemPromotionTarget.map(MenuDescriptor.MenuAction.requestCodexSystemPromotion),
                isEnabled: !isChecked && account.systemPromotionTarget != nil,
                isChecked: isChecked)
        }
        let symbol = MenuDescriptor.MenuActionSystemImage.systemAccount.rawValue
        // Both images use the current row consumer; the before image reconstructs prior descriptor data.
        try Self.capture(
            VStack(alignment: .leading, spacing: 12) {
                Text("Before reconstruction · synthetic accounts · current renderer").font(.caption)
                content.row(for: .submenu("System Account", symbol, previousItems))
            },
            to: directory.appendingPathComponent("before-reconstruction.png"))
        try Self.capture(
            VStack(alignment: .leading, spacing: 12) {
                Text("After · synthetic accounts · current renderer").font(.caption)
                content.row(for: .submenu("System Account", symbol, items))
            },
            to: directory.appendingPathComponent("after.png"))
    }

    private static func capture(_ content: some View, to url: URL) throws {
        let hosting = NSHostingView(rootView: content
            .padding(16)
            .frame(width: 540, alignment: .leading)
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

    @Test
    func `Authfleet usage row exposes typed System Account action and promotes through coordinator`() async throws {
        let fixture = try CodexAccountPromotionTestContainer(suiteName: "JonesFleet-menu-activation")
        defer { fixture.tearDown() }
        let profile = try fixture.createFleetProfile()
        let expectedTarget = try jonesFleetTarget(profile)
        fixture.settings._test_codexFleetProfileDiscovery = .available([profile.codexHomePath])
        let old = try fixture.writeLiveOAuthAuthFile(email: "old@example.com", accountID: "acct-old")
        fixture.settings.codexActiveSource = .profileHome(path: profile.codexHomePath)
        let projection = fixture.settings.codexVisibleAccountProjection
        let row = try #require(projection.visibleAccounts.first {
            $0.selectionSource == .profileHome(path: profile.codexHomePath)
        })
        #expect(row.isActive)
        #expect(!row.isLive)
        #expect(row.storedAccountID == nil)
        #expect(!row.canReauthenticate)
        #expect(row.systemPromotionTarget == expectedTarget)
        // Usage selection has not changed the default credentials.
        #expect(try fixture.liveAuthData() == old)
        let service = fixture.makeService(
            accountScopedRefresher: ClosureCodexAccountScopedRefresher { _ in },
            fleetHomePaths: { [profile.codexHomePath] })
        let coordinator = CodexAccountPromotionCoordinator(service: service)
        let descriptor = MenuDescriptor.build(
            provider: .codex,
            store: fixture.usageStore,
            settings: fixture.settings,
            account: UsageFetcher(environment: fixture.baseEnvironment).loadAccountInfo(),
            codexAccountPromotionCoordinator: coordinator,
            updateReady: false)
        let submenus: [[MenuDescriptor.SubmenuItem]] = descriptor.sections.flatMap(\.entries).compactMap { entry in
            if case let .submenu(title, _, items) = entry, title == "System Account" { return items }
            return nil
        }
        let items = try #require(submenus.first)
        let item = try #require(items.first { $0.action == .requestCodexSystemPromotion(expectedTarget) })
        #expect(item.isEnabled)
        #expect(!item.isChecked)
        let action = try #require(item.action)
        guard case let .requestCodexSystemPromotion(target) = action else {
            Issue.record("Missing typed fleet action")
            return
        }
        // Verify AppKit's representedObject preserves the value sent by the action mapping.
        let sender = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
        sender.representedObject = target
        let delivered = try #require(sender.representedObject as? JonesCodexSystemPromotionTarget)
        let result = await coordinator.promote(target: delivered)
        guard case let .success(promotion) = result else {
            Issue.record("Fleet menu promotion failed")
            return
        }
        #expect(promotion.target == expectedTarget)
        #expect(fixture.settings.codexActiveSource == .liveSystem)
        let canonicalBytes = try Data(contentsOf: CodexAuthFingerprint.authFileURL(homePath: profile.codexHomePath))
        #expect(try fixture.liveAuthData() == canonicalBytes)
    }

    @Test
    func `arbitrary profiles and ambiguous identities cannot manufacture fleet menu targets`() {
        let home = CodexCredentialFixtures.root.appendingPathComponent("profile").path
        let profile = ObservedSystemCodexAccount(
            email: "same@example.com",
            workspaceAccountID: "acct-same",
            authFingerprint: "synthetic",
            codexHomePath: home,
            observedAt: Date())
        #expect(JonesCodexFleetPromotionTarget(profile: profile, fleetHomePaths: []) == nil)
        let incomplete = ObservedSystemCodexAccount(
            email: "same@example.com", codexHomePath: home, observedAt: Date())
        #expect(JonesCodexFleetPromotionTarget(profile: incomplete, fleetHomePaths: [home]) == nil)
    }

    @Test
    func `identical account identities in two fleet homes retain distinct typed targets`() throws {
        let fixture = try CodexAccountPromotionTestContainer(suiteName: "JonesFleet-same-identity-rows")
        defer { fixture.tearDown() }
        let first = try fixture.createFleetProfile(alias: "first")
        let second = try fixture.createFleetProfile(alias: "second")
        let snapshot = CodexAccountReconciliationSnapshot(
            storedAccounts: [],
            activeStoredAccount: nil,
            liveSystemAccount: nil,
            profileHomeAccounts: [first, second],
            fleetProfileHomePaths: [first.codexHomePath, second.codexHomePath],
            matchingStoredAccountForLiveSystemAccount: nil,
            activeSource: .profileHome(path: first.codexHomePath),
            hasUnreadableAddedAccountStore: false)
        let projection = CodexVisibleAccountProjection.make(from: snapshot)
        #expect(projection.visibleAccounts.count == 2)
        let targets = projection.visibleAccounts.map(\.systemPromotionTarget)
        #expect(targets[0] != targets[1])
        #expect(projection.visibleAccounts.allSatisfy { $0.storedAccountID == nil })
        #expect(Set(projection.visibleAccounts.map(\.displayName)).count == 2)
    }
}
