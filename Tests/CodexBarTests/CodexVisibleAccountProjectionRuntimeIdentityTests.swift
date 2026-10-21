import CodexBarCore
import Foundation
import Testing

struct CodexVisibleAccountProjectionRuntimeIdentityTests {
    @Test
    func `visible projection preserves fleet enrollment even when selected profile has no account row`() {
        let paths = ["/synthetic/malcolm", "/synthetic/jace", "/synthetic/umich"]
        let snapshot = CodexAccountReconciliationSnapshot(
            storedAccounts: [],
            activeStoredAccount: nil,
            liveSystemAccount: nil,
            fleetProfileHomePaths: paths,
            matchingStoredAccountForLiveSystemAccount: nil,
            activeSource: .liveSystem,
            hasUnreadableAddedAccountStore: false)
        let projection = CodexVisibleAccountProjection.make(from: snapshot)
        #expect(projection.visibleAccounts.isEmpty)
        #expect(projection.fleetProfileHomePaths == paths)
    }

    @Test
    func `runtime provider identity supplies missing managed workspace id`() throws {
        let accountID = UUID()
        let storedAccount = ManagedCodexAccount(
            id: accountID,
            email: "user@example.com",
            workspaceAccountID: nil,
            managedHomePath: "/tmp/managed-a",
            createdAt: 1,
            updatedAt: 2,
            lastAuthenticatedAt: 3)
        let snapshot = CodexAccountReconciliationSnapshot(
            storedAccounts: [storedAccount],
            activeStoredAccount: storedAccount,
            liveSystemAccount: nil,
            matchingStoredAccountForLiveSystemAccount: nil,
            activeSource: .managedAccount(id: accountID),
            hasUnreadableAddedAccountStore: false,
            storedAccountRuntimeIdentities: [accountID: .providerAccount(id: " Account-Live ")])

        let account = try #require(CodexVisibleAccountProjection.make(from: snapshot).visibleAccounts.first)

        #expect(account.workspaceAccountID == "account-live")
        #expect(account.selectionSource == .managedAccount(id: accountID))
    }
}
