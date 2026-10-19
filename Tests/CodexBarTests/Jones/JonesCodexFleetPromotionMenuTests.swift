import AppKit
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite(.serialized, CodexCredentialFixtures())
@MainActor
struct JonesCodexFleetPromotionMenuTests {
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
