import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite(.serialized)
@MainActor
struct ManagedCodexAccountCoordinatorTests {
    @Test(arguments: [false, true])
    func `cancel releases busy state and ignores late login success during retry`(retrySameAccount: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = BlockingManagedCodexLoginRunner()
        let store = InMemoryManagedCodexAccountStoreForCoordinatorTests(
            accounts: ManagedCodexAccountSet(version: 1, accounts: []))
        let service = ManagedCodexAccountService(
            store: store,
            homeFactory: CoordinatorTestManagedCodexHomeFactory(root: root),
            loginRunner: runner,
            identityReader: CoordinatorStubManagedCodexIdentityReader(email: "user@example.com"),
            workspaceResolver: EmptyCoordinatorWorkspaceResolver())
        let coordinator = ManagedCodexAccountCoordinator(service: service)
        var notifications = 0
        coordinator.onManagedAccountsDidChange = { notifications += 1 }
        let firstID = UUID()
        let secondID = retrySameAccount ? firstID : UUID()
        let first = Task { try await coordinator.authenticateManagedAccount(existingAccountID: firstID) }
        await runner.waitUntilStarted()
        coordinator.cancelAuthentication()
        #expect(!coordinator.isAuthenticatingManagedAccount)
        #expect(coordinator.authenticatingManagedAccountID == nil)

        let second = Task { try await coordinator.authenticateManagedAccount(existingAccountID: secondID) }
        await runner.waitUntilStarted(count: 2)
        await runner.resumeFirst()
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(coordinator.isAuthenticatingManagedAccount)
        #expect(coordinator.authenticatingManagedAccountID == secondID)
        #expect(store.snapshot.accounts.isEmpty)
        #expect(notifications == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).count == 1)

        await runner.resumeFirst()
        _ = try await second.value
        #expect(!coordinator.isAuthenticatingManagedAccount)
        #expect(store.snapshot.accounts.count == 1)
        #expect(notifications == 1)
    }

    @Test
    func `coordinator exposes in flight state and rejects overlapping managed authentication`() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let existingAccountID = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-111111111111"))
        let runner = BlockingManagedCodexLoginRunner()
        let service = ManagedCodexAccountService(
            store: InMemoryManagedCodexAccountStoreForCoordinatorTests(
                accounts: ManagedCodexAccountSet(version: 1, accounts: [])),
            homeFactory: CoordinatorTestManagedCodexHomeFactory(root: root),
            loginRunner: runner,
            identityReader: CoordinatorStubManagedCodexIdentityReader(email: "user@example.com"))
        let coordinator = ManagedCodexAccountCoordinator(service: service)

        let authTask = Task { try await coordinator.authenticateManagedAccount(existingAccountID: existingAccountID) }
        await runner.waitUntilStarted()

        #expect(coordinator.isAuthenticatingManagedAccount)
        #expect(coordinator.authenticatingManagedAccountID == existingAccountID)

        await #expect(throws: ManagedCodexAccountCoordinatorError.authenticationInProgress) {
            try await coordinator.authenticateManagedAccount()
        }

        await runner.resume()
        let account = try await authTask.value

        #expect(account.email == "user@example.com")
        #expect(coordinator.isAuthenticatingManagedAccount == false)
        #expect(coordinator.authenticatingManagedAccountID == nil)
    }

    @Test
    func `coordinator clears in flight state after managed login timeout`() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let loginResult = CodexLoginRunner.Result(outcome: .timedOut, output: "timed out")
        let existingAccountID = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-222222222222"))
        let service = ManagedCodexAccountService(
            store: InMemoryManagedCodexAccountStoreForCoordinatorTests(
                accounts: ManagedCodexAccountSet(version: 1, accounts: [])),
            homeFactory: CoordinatorTestManagedCodexHomeFactory(root: root),
            loginRunner: TimedOutManagedCodexLoginRunner(result: loginResult),
            identityReader: CoordinatorStubManagedCodexIdentityReader(email: "user@example.com"))
        let coordinator = ManagedCodexAccountCoordinator(service: service)

        do {
            _ = try await coordinator.authenticateManagedAccount(existingAccountID: existingAccountID, timeout: 0.2)
            Issue.record("Expected managed login timeout to throw")
        } catch let error as ManagedCodexAccountServiceError {
            #expect(error == .loginFailed(loginResult))
        } catch {
            Issue.record("Expected ManagedCodexAccountServiceError.loginFailed, got \(error)")
        }

        #expect(coordinator.isAuthenticatingManagedAccount == false)
        #expect(coordinator.authenticatingManagedAccountID == nil)
    }
}

private actor BlockingManagedCodexLoginRunner: ManagedCodexLoginRunning {
    private var waiters: [CheckedContinuation<CodexLoginRunner.Result, Never>] = []
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var startCount = 0

    func run(homePath _: String, timeout _: TimeInterval) async -> CodexLoginRunner.Result {
        self.startCount += 1
        self.startedWaiters.forEach { $0.resume() }
        self.startedWaiters.removeAll()
        return await withCheckedContinuation { continuation in
            self.waiters.append(continuation)
        }
    }

    func waitUntilStarted(count: Int = 1) async {
        while self.startCount < count {
            await withCheckedContinuation { continuation in
                self.startedWaiters.append(continuation)
            }
        }
    }

    func resumeFirst() {
        self.waiters.removeFirst().resume(returning: .init(outcome: .success, output: "ok"))
    }

    func resume() {
        let result = CodexLoginRunner.Result(outcome: .success, output: "ok")
        self.waiters.forEach { $0.resume(returning: result) }
        self.waiters.removeAll()
    }
}

private struct TimedOutManagedCodexLoginRunner: ManagedCodexLoginRunning {
    let result: CodexLoginRunner.Result

    func run(homePath _: String, timeout _: TimeInterval) async -> CodexLoginRunner.Result {
        self.result
    }
}

private final class InMemoryManagedCodexAccountStoreForCoordinatorTests: ManagedCodexAccountStoring,
@unchecked Sendable {
    var snapshot: ManagedCodexAccountSet

    init(accounts: ManagedCodexAccountSet) {
        self.snapshot = accounts
    }

    func loadAccounts() throws -> ManagedCodexAccountSet {
        self.snapshot
    }

    func storeAccounts(_ accounts: ManagedCodexAccountSet) throws {
        self.snapshot = accounts
    }

    func ensureFileExists() throws -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
}

private final class CoordinatorTestManagedCodexHomeFactory: ManagedCodexHomeProducing, @unchecked Sendable {
    let root: URL

    init(root: URL) {
        self.root = root
    }

    func makeHomeURL() -> URL {
        self.root.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    func validateManagedHomeForDeletion(_ url: URL) throws {
        try ManagedCodexHomeFactory(root: self.root).validateManagedHomeForDeletion(url)
    }
}

private final class CoordinatorStubManagedCodexIdentityReader: ManagedCodexIdentityReading, @unchecked Sendable {
    let email: String

    init(email: String) {
        self.email = email
    }

    func loadAccountIdentity(homePath _: String) throws -> CodexAuthBackedAccount {
        CodexAuthBackedAccount(
            identity: CodexIdentityResolver.resolve(accountId: nil, email: self.email),
            email: self.email,
            plan: "Pro")
    }
}

private struct EmptyCoordinatorWorkspaceResolver: ManagedCodexWorkspaceResolving {
    func resolveWorkspaceIdentity(homePath _: String, providerAccountID _: String) async
        -> CodexOpenAIWorkspaceIdentity?
    {
        nil
    }
}
