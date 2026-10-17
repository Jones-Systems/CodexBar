import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite(.serialized, CodexCredentialFixtures())
@MainActor
struct CodexSystemPromotionUITests {
    @Test
    func `cancelled ambient login retains promotion exclusion and immediate retries drain in order`() async throws {
        let container = try CodexAccountPromotionTestContainer(suiteName: "CodexSystemPromotionUITests-drain-retry")
        defer { container.tearDown() }
        let audit = SharedAuthWriterAudit()
        let runner = DrainingAmbientLoginRunner(audit: audit)
        let coordinator = CodexAccountPromotionCoordinator(
            service: container.makeService(sharedAuthWriter: CodexSharedAuthWriter()))
        let first = Task { await coordinator.authenticateLiveAccount(using: runner) }
        let started = await self.waitUntil { await runner.startCount == 1 }
        #expect(started)
        if !started { await runner.finishAll() }
        coordinator.cancelLiveAuthentication()
        #expect(!coordinator.isLiveAuthenticationRequested)
        #expect(coordinator.isAuthenticatingLiveAccount)
        #expect(coordinator.isInteractionBlocked())
        #expect(await self.waitUntil { await runner.cancellationCount == 1 })
        if case .success = await coordinator.promote(managedAccountID: UUID()) {
            Issue.record("Promotion must remain blocked during drain")
        }

        let cancelledRetry = Task { await coordinator.authenticateLiveAccount(using: runner) }
        #expect(await self.waitUntil { coordinator.isLiveAuthenticationRequested })
        coordinator.cancelLiveAuthentication()
        let retry = Task { await coordinator.authenticateLiveAccount(using: runner) }
        #expect(await self.waitUntil { coordinator.isLiveAuthenticationRequested })
        #expect(await runner.startCount == 1)
        #expect(coordinator.isInteractionBlocked())
        await runner.finish(1)
        let retryStarted = await self.waitUntil { await runner.startCount == 2 }
        #expect(retryStarted)
        if !retryStarted { await runner.finishAll() }
        #expect(await first.value == nil)
        #expect(await cancelledRetry.value == nil)
        #expect(coordinator.isLiveAuthenticationRequested)
        #expect(coordinator.isAuthenticatingLiveAccount)
        await runner.finishAll()
        #expect(await retry.value?.outcome == .success)
        #expect(!coordinator.isInteractionBlocked())
        #expect(!coordinator.isLiveAuthenticationRequested)
        #expect(audit.maximumWriters == 1)
        #expect(audit.activeWriters == 0)
    }

    // JONES(fleet-system-promotion): run the existing drain contract for both target kinds.
    @Test(arguments: [false, true])
    func `direct promotion waits for cancelled ambient writer to confirm completion`(fleet: Bool) async throws {
        let container = try CodexAccountPromotionTestContainer(suiteName: "CodexSystemPromotionUITests-drain-promote")
        defer { container.tearDown() }
        let target: JonesCodexSystemPromotionTarget
        let fleetPaths: [String]
        if fleet {
            let profile = try container.createFleetProfile()
            target = try jonesFleetTarget(profile)
            fleetPaths = [profile.codexHomePath]
        } else {
            let managed = try container.createManagedAccount(
                persistedEmail: "target@example.com", authAccountID: "acct-target")
            try container.persistAccounts([managed])
            target = .managedAccount(managed.id)
            fleetPaths = []
        }
        try container.removeLiveAuthFile()
        let audit = SharedAuthWriterAudit()
        let runner = DrainingAmbientLoginRunner(audit: audit)
        let writer = CodexSharedAuthWriter()
        let swapper = RecordingCodexLiveAuthSwapper(onSwap: { _, _ in
            audit.begin()
            defer { audit.end() }
        })
        let service = container.makeService(
            liveAuthSwapper: swapper, sharedAuthWriter: writer, fleetHomePaths: { fleetPaths })
        let coordinator = CodexAccountPromotionCoordinator(service: service)
        let login = Task { await coordinator.authenticateLiveAccount(using: runner) }
        let started = await self.waitUntil { await runner.startCount == 1 }
        #expect(started)
        if !started { await runner.finishAll() }
        coordinator.cancelLiveAuthentication()
        #expect(await self.waitUntil { await runner.cancellationCount == 1 })
        let promotion = Task { try await service.promote(target: target) }
        #expect(await self.waitUntil { writer._test_waitingWriterCount == 1 })
        #expect(swapper.swapCallCount == 0)
        #expect(audit.activeWriters == 1)
        await runner.finishAll()
        #expect(await login.value == nil)
        let result = try await promotion.value
        #expect(result.didMutateLiveAuth)
        #expect(swapper.swapCallCount == 1)
        #expect(audit.maximumWriters == 1)
        #expect(audit.activeWriters == 0)
    }

    @Test
    func `ambient login cancelled while queued behind promotion never launches`() async throws {
        let container = try CodexAccountPromotionTestContainer(suiteName: "CodexSystemPromotionUITests-queued-cancel")
        defer { container.tearDown() }
        let writer = CodexSharedAuthWriter()
        let audit = SharedAuthWriterAudit()
        let runner = DrainingAmbientLoginRunner(audit: audit)
        let coordinator = CodexAccountPromotionCoordinator(service: container.makeService(sharedAuthWriter: writer))
        await writer.acquire()
        let login = Task { await coordinator.authenticateLiveAccount(using: runner) }
        #expect(await self.waitUntil { writer._test_waitingWriterCount == 1 })
        coordinator.cancelLiveAuthentication()
        #expect(await runner.startCount == 0)
        #expect(coordinator.isAuthenticatingLiveAccount)
        writer.release()
        await runner.finishAll()
        #expect(await login.value == nil)
        #expect(await runner.startCount == 0)
        #expect(!coordinator.isInteractionBlocked())
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            await Task.yield()
        }
        return await condition()
    }

    @Test
    func `promotion coordinator promotes immediately`() async throws {
        let container = try CodexAccountPromotionTestContainer(
            suiteName: "CodexSystemPromotionUITests-coordinator-immediate")
        defer { container.tearDown() }

        let target = try container.createManagedAccount(
            persistedEmail: "managed@example.com",
            authAccountID: "acct-managed")
        try container.persistAccounts([target])
        _ = try container.writeLiveOAuthAuthFile(email: "live@example.com", accountID: "acct-live")

        let managedVisibleAccountID = try #require(container.settings.codexVisibleAccountProjection.visibleAccounts
            .first(where: { $0.storedAccountID == target.id })?
            .id)
        let coordinator = CodexAccountPromotionCoordinator(service: container.makeService())

        let result = await coordinator.promote(managedAccountID: target.id)

        let promotionResult: CodexAccountPromotionResult
        switch result {
        case let .success(value):
            promotionResult = value
        case let .failure(error):
            Issue.record("Expected successful promotion, got \(error)")
            throw PromotionTestError.unexpectedDisposition
        }

        #expect(promotionResult.outcome == .promoted)
        #expect(container.settings.codexActiveSource == .liveSystem)
        #expect(container.settings.codexVisibleAccountProjection.liveVisibleAccountID == managedVisibleAccountID)
        #expect(coordinator.userFacingError == nil)
    }

    @Test
    func `promotion coordinator blocks while live reauthentication is running`() async throws {
        let container = try CodexAccountPromotionTestContainer(
            suiteName: "CodexSystemPromotionUITests-coordinator-live-reauth")
        defer { container.tearDown() }

        let target = try container.createManagedAccount(
            persistedEmail: "managed@example.com",
            authAccountID: "acct-managed")
        try container.persistAccounts([target])
        _ = try container.writeLiveOAuthAuthFile(email: "live@example.com", accountID: "acct-live")
        container.settings.codexActiveSource = .managedAccount(id: target.id)

        let coordinator = CodexAccountPromotionCoordinator(service: container.makeService())
        coordinator.setLiveReauthenticationInProgress(true)

        let result = await coordinator.promote(managedAccountID: target.id)

        let error: CodexSystemAccountPromotionUserFacingError
        switch result {
        case .success:
            Issue.record("Expected blocked promotion while live reauthentication is running")
            throw PromotionTestError.unexpectedDisposition
        case let .failure(value):
            error = value
        }

        #expect(error.title == "Could not switch system account")
        #expect(error.message == "Finish the current managed account change before switching the system account.")
        #expect(coordinator.userFacingError == error)
        #expect(coordinator.isInteractionBlocked())
        #expect(container.settings.codexActiveSource == .managedAccount(id: target.id))
    }

    @Test
    func `promotion coordinator explains selected workspace auth mismatch`() {
        let error = CodexAccountPromotionCoordinator.mapUserFacingError(
            CodexAccountPromotionError.targetManagedAccountWorkspaceDiffersFromAuthDefault)

        #expect(error.title == "Could not switch system account")
        #expect(error.message.contains("differs from its saved Codex auth default"))
        #expect(error.message.contains("Keep it as a managed account"))
        #expect(error.message.contains("will not rewrite Codex-owned auth"))
    }

    @Test
    func `codex menu descriptor includes system account submenu`() throws {
        let container = try CodexAccountPromotionTestContainer(
            suiteName: "CodexSystemPromotionUITests-menu-descriptor")
        defer { container.tearDown() }

        let managedAccountID = UUID()
        let managedAccount = try container.createManagedAccount(
            id: managedAccountID,
            persistedEmail: "managed@example.com",
            authAccountID: "acct-managed")
        try container.persistAccounts([managedAccount])
        container.settings._test_liveSystemCodexAccount = ObservedSystemCodexAccount(
            email: "live@example.com",
            codexHomePath: container.liveHomeURL.path,
            observedAt: Date())

        let descriptor = MenuDescriptor.build(
            provider: .codex,
            store: container.usageStore,
            settings: container.settings,
            account: UsageFetcher().loadAccountInfo(),
            managedCodexAccountCoordinator: ManagedCodexAccountCoordinator(),
            codexAccountPromotionCoordinator: CodexAccountPromotionCoordinator(
                service: container.makeService()),
            updateReady: false)

        let submenu = try #require(descriptor.sections
            .flatMap(\.entries)
            .compactMap { entry -> (String, String?, [MenuDescriptor.SubmenuItem])? in
                guard case let .submenu(title, systemImageName, items) = entry else { return nil }
                return (title, systemImageName, items)
            }
            .first(where: { $0.0 == "System Account" }))

        #expect(submenu.1 == MenuDescriptor.MenuActionSystemImage.systemAccount.rawValue)
        #expect(submenu.2.map(\.title) == ["live@example.com", "managed@example.com"])
        #expect(submenu.2.count == 2)
        #expect(submenu.2[0].isChecked)
        #expect(submenu.2[0].isEnabled == false)
        #expect(submenu.2[0].action == nil)
        #expect(submenu.2[1].isChecked == false)
        #expect(submenu.2[1].isEnabled)
        #expect(submenu.2[1].action == .requestCodexSystemPromotion(.managedAccount(managedAccountID)))
    }

    @Test
    func `codex menu descriptor hides single live system account submenu`() throws {
        let container = try CodexAccountPromotionTestContainer(
            suiteName: "CodexSystemPromotionUITests-menu-single-live")
        defer { container.tearDown() }

        container.settings._test_liveSystemCodexAccount = ObservedSystemCodexAccount(
            email: "live@example.com",
            codexHomePath: container.liveHomeURL.path,
            observedAt: Date())

        let descriptor = MenuDescriptor.build(
            provider: .codex,
            store: container.usageStore,
            settings: container.settings,
            account: UsageFetcher().loadAccountInfo(),
            managedCodexAccountCoordinator: ManagedCodexAccountCoordinator(),
            codexAccountPromotionCoordinator: CodexAccountPromotionCoordinator(
                service: container.makeService()),
            updateReady: false)

        let hasSystemAccountSubmenu = descriptor.sections
            .flatMap(\.entries)
            .contains { entry in
                guard case let .submenu(title, _, _) = entry else { return false }
                return title == "System Account"
            }

        #expect(!hasSystemAccountSubmenu)
    }
}

private final class SharedAuthWriterAudit: @unchecked Sendable {
    private let lock = NSLock()
    private var active = 0
    private var maximum = 0

    var activeWriters: Int {
        self.lock.withLock { self.active }
    }

    var maximumWriters: Int {
        self.lock.withLock { self.maximum }
    }

    func begin() {
        self.lock.withLock {
            self.active += 1
            self.maximum = max(self.maximum, self.active)
        }
    }

    func end() {
        self.lock.withLock { self.active -= 1 }
    }
}

private actor DrainingAmbientLoginRunner: CodexAmbientLoginRunning {
    let audit: SharedAuthWriterAudit
    private(set) var startCount = 0
    private(set) var cancellationCount = 0
    private var completions: [Int: CheckedContinuation<Void, Never>] = [:]
    private var isFinished = false

    init(audit: SharedAuthWriterAudit) {
        self.audit = audit
    }

    func run(timeout _: TimeInterval) async -> CodexLoginRunner.Result {
        self.startCount += 1
        let id = self.startCount
        self.audit.begin()
        defer { self.audit.end() }
        await withTaskCancellationHandler {
            if !self.isFinished {
                await withCheckedContinuation { self.completions[id] = $0 }
            }
        } onCancel: {
            Task { await self.recordCancellation() }
        }
        // Deliberately return success even after cancellation: the caller must suppress stale UI results.
        return CodexLoginRunner.Result(outcome: .success, output: "synthetic")
    }

    private func recordCancellation() {
        self.cancellationCount += 1
    }

    func finish(_ id: Int) {
        self.completions.removeValue(forKey: id)?.resume()
    }

    func finishAll() {
        self.isFinished = true
        let pending = self.completions.values
        self.completions.removeAll()
        for completion in pending {
            completion.resume()
        }
    }
}
