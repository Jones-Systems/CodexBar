import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite(.serialized)
struct CodexVisibleAccountTests {
    @Test
    @MainActor
    func `settings move persists and menu keeps chosen top account above the active account`() throws {
        let root = TestFixtureScratch.root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configStore = CodexBarConfigStore(fileURL: root.appendingPathComponent("config.json"))
        try configStore.save(CodexBarConfig(providers: [ProviderConfig(id: .codex)]))
        let settings = SettingsStore(
            userDefaults: InMemoryUserDefaults(),
            configStore: configStore,
            codexCookieStore: InMemoryCookieHeaderStore(),
            claudeCookieStore: InMemoryCookieHeaderStore(),
            tokenAccountStore: InMemoryTokenAccountStore(),
            keychainAccessPolicy: .init(setDisabled: { _ in }, isExplicitlyDisabled: { false }),
            performInitialProviderDetection: false)
        let first = self.profile("first@example.com", path: "/synthetic/first", visibleID: "first")
        let second = self.profile("second@example.com", path: "/synthetic/second", visibleID: "second")
        settings.moveCodexAccount(second, by: -1, in: [first, second])
        let reloaded = try #require(try CodexBarConfigStore(fileURL: configStore.fileURL).load())
        #expect(reloaded.providerConfig(for: .codex)?.codexAccountOrder == settings.codexAccountOrder)
        #expect(settings.orderedCodexAccounts([first, second]).map(\.id) == ["second", "first"])
        let usage = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
        #expect(usage.limitedCodexVisibleAccounts(
            [first, second], activeVisibleAccountID: first.id).map(\.id) == ["second", "first"])
        #expect(settings.codexActiveSource == .liveSystem)
    }

    @Test
    func `saved order keeps source identities when visible ids change and profiles disappear`() throws {
        let first = self.profile("first@example.com", path: "/synthetic/first", visibleID: "first@example.com")
        let second = self.profile("second@example.com", path: "/synthetic/second", visibleID: "second@example.com")
        let order = try #require(CodexAccountOrder.moving(second, by: -1, in: [first, second], savedOrder: []))
        #expect(CodexAccountOrder.ordered([first, second], savedOrder: order).map(\.id) == [second.id, first.id])
        let renamed = self.profile("first@example.com", path: "/synthetic/first", visibleID: "profile:/synthetic/first")
        let newAccount = self.profile("new@example.com", path: "/synthetic/new", visibleID: "new")
        #expect(CodexAccountOrder.ordered([newAccount, renamed], savedOrder: order).map(\.id) == [renamed.id, "new"])
        #expect(CodexAccountOrder.ordered([renamed, second, newAccount], savedOrder: order).map(\.id) == [
            second.id, renamed.id, "new",
        ])
        #expect(CodexAccountOrder.moving(second, by: -1, in: [first, second], savedOrder: order) == nil)
        let movedWithMissing = try #require(CodexAccountOrder.moving(
            newAccount, by: -1, in: [renamed, newAccount], savedOrder: order))
        #expect(movedWithMissing.contains(CodexAccountOrder.key(for: second)))
    }

    @Test
    func `workspace sections preserve explicitly interleaved account order`() {
        let first = self.profile("first@example.com", path: "/synthetic/first", visibleID: "first", workspace: "Team")
        let second = self.profile("second@example.com", path: "/synthetic/second", visibleID: "second")
        let third = self.profile("third@example.com", path: "/synthetic/third", visibleID: "third", workspace: "Team")
        #expect([first, second, third].codexWorkspaceSections().flatMap(\.accounts).map(\.id) == [
            "first", "second", "third",
        ])
    }

    private func profile(
        _ email: String, path: String, visibleID: String, workspace: String? = nil) -> CodexVisibleAccount
    {
        CodexVisibleAccount(
            id: visibleID,
            email: email,
            workspaceLabel: workspace,
            storedAccountID: nil,
            selectionSource: .profileHome(path: path),
            isActive: false,
            isLive: false,
            canReauthenticate: false,
            canRemove: false)
    }

    @Test
    func `menu display name suppresses personal workspace label`() {
        let personal = CodexVisibleAccount(
            id: "personal",
            email: "user@example.com",
            workspaceLabel: "Personal",
            workspaceAccountID: "account-personal",
            storedAccountID: nil,
            selectionSource: .liveSystem,
            isActive: true,
            isLive: true,
            canReauthenticate: true,
            canRemove: false)
        let team = CodexVisibleAccount(
            id: "team",
            email: "user@example.com",
            workspaceLabel: "Team Alpha",
            workspaceAccountID: "account-team",
            storedAccountID: nil,
            selectionSource: .managedAccount(id: UUID()),
            isActive: false,
            isLive: false,
            canReauthenticate: true,
            canRemove: true)

        #expect(personal.displayName == "user@example.com — Personal")
        #expect(personal.menuDisplayName == "user@example.com")
        #expect(personal.menuWorkspaceLabel == nil)
        #expect(team.displayName == "user@example.com — Team Alpha")
        #expect(team.menuDisplayName == "user@example.com — Team Alpha")
        #expect(team.menuWorkspaceLabel == "Team Alpha")
    }
}
