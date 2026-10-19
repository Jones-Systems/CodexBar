import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite(.serialized, CodexCredentialFixtures())
@MainActor
struct JonesCodexFleetPromotionBoundaryTests {
    @Test
    func `workspace identity disagreement rejects the source without a system write`() async throws {
        let fixture = try CodexAccountPromotionTestContainer(
            suiteName: "JonesFleet-workspace-mismatch",
            workspaceIdentities: ["acct-jace": .init(workspaceAccountID: "acct-other", workspaceLabel: "Other")])
        defer { fixture.tearDown() }
        let profile = try fixture.createFleetProfile()
        let target = try jonesFleetTarget(profile)
        let swapper = RecordingCodexLiveAuthSwapper()
        await #expect(throws: CodexAccountPromotionError.fleetTargetIdentityChanged) {
            try await fixture.makeService(liveAuthSwapper: swapper, fleetHomePaths: { [profile.codexHomePath] })
                .promote(target: target)
        }
        #expect(swapper.swapCallCount == 0)
        #expect(try fixture.liveAuthData() == nil)
    }

    @Test
    func `preservation metadata failure retains copied managed auth but leaves system and fleet untouched`() async
        throws
    {
        let fixture = try CodexAccountPromotionTestContainer(suiteName: "JonesFleet-preservation-failure")
        defer { fixture.tearDown() }
        let profile = try fixture.createFleetProfile()
        let target = try jonesFleetTarget(profile)
        let sourceURL = CodexAuthFingerprint.authFileURL(homePath: profile.codexHomePath)
        let source = try Data(contentsOf: sourceURL)
        let managed = try fixture.createManagedAccount(persistedEmail: "old@example.com", authAccountID: "acct-old")
        try fixture.persistAccounts([managed])
        let priorManaged = try fixture.managedAuthData(for: managed)
        let old = try fixture.writeLiveOAuthAuthFile(
            email: "old@example.com", accountID: "acct-old", apiKey: "synthetic-preserved-key")
        let store = RecordingManagedCodexAccountStore(base: fixture.fileStore) { _ in
            throw PromotionTestError.storeWriteFailed
        }
        let sourceWriter = JonesRecordingActiveSourceWriter()
        let swapper = RecordingCodexLiveAuthSwapper()
        let service = fixture.makeService(
            store: store,
            liveAuthSwapper: swapper,
            activeSourceWriter: sourceWriter,
            fleetHomePaths: { [profile.codexHomePath] })

        await #expect(throws: CodexAccountPromotionError.managedStoreCommitFailed) {
            try await service.promote(target: target)
        }

        let persisted = try fixture.loadAccounts().accounts
        #expect(persisted.first?.authFingerprint == managed.authFingerprint)
        #expect(try fixture.managedAuthData(for: managed) == old)
        #expect(try fixture.managedAuthData(for: managed) != priorManaged)
        #expect(try fixture.liveAuthData() == old)
        #expect(try Data(contentsOf: sourceURL) == source)
        #expect(swapper.swapCallCount == 0)
        #expect(sourceWriter.sources.isEmpty)
    }

    @Test
    func `swap failure leaves displaced import available and never claims a system switch`() async throws {
        let fixture = try CodexAccountPromotionTestContainer(suiteName: "JonesFleet-swap-failure")
        defer { fixture.tearDown() }
        let profile = try fixture.createFleetProfile()
        let target = try jonesFleetTarget(profile)
        let sourceURL = CodexAuthFingerprint.authFileURL(homePath: profile.codexHomePath)
        let source = try Data(contentsOf: sourceURL)
        let old = try fixture.writeLiveOAuthAuthFile(email: "old@example.com", accountID: "acct-old")
        let sourceWriter = JonesRecordingActiveSourceWriter()
        let swapper = RecordingCodexLiveAuthSwapper { _, _ in throw PromotionTestError.swapFailed }
        let service = fixture.makeService(
            liveAuthSwapper: swapper,
            activeSourceWriter: sourceWriter,
            fleetHomePaths: { [profile.codexHomePath] })

        await #expect(throws: CodexAccountPromotionError.liveAuthSwapFailed) {
            try await service.promote(target: target)
        }

        let accounts = try fixture.loadAccounts().accounts
        let preserved = try #require(accounts.first)
        #expect(accounts.count == 1)
        #expect(try fixture.managedAuthData(for: preserved) == old)
        #expect(try fixture.liveAuthData() == old)
        #expect(try Data(contentsOf: sourceURL) == source)
        #expect(sourceWriter.sources.isEmpty)
    }

    @Test
    func `displaced preservation refuses a managed record pointing into another canonical fleet home`() async throws {
        let fixture = try CodexAccountPromotionTestContainer(suiteName: "JonesFleet-protected-home")
        defer { fixture.tearDown() }
        let selected = try fixture.createFleetProfile()
        let protected = try fixture.createFleetProfile(alias: "old", email: "old@example.com", accountID: "acct-old")
        let target = try jonesFleetTarget(selected)
        let protectedURL = CodexAuthFingerprint.authFileURL(homePath: protected.codexHomePath)
        let protectedBytes = try Data(contentsOf: protectedURL)
        let managed = ManagedCodexAccount(
            id: UUID(),
            email: protected.email,
            providerAccountID: protected.workspaceAccountID,
            managedHomePath: protected.codexHomePath,
            createdAt: 1,
            updatedAt: 1,
            lastAuthenticatedAt: 1)
        try fixture.persistAccounts([managed])
        let old = try fixture.writeLiveOAuthAuthFile(
            email: protected.email, accountID: protected.workspaceAccountID, apiKey: "synthetic-new-bytes")
        let service = fixture.makeService(fleetHomePaths: { [selected.codexHomePath, protected.codexHomePath] })

        await #expect(throws: CodexAccountPromotionError.fleetDestinationAmbiguous) {
            try await service.promote(target: target)
        }

        #expect(try Data(contentsOf: protectedURL) == protectedBytes)
        #expect(try fixture.liveAuthData() == old)
    }

    @Test
    func `same identity still copies current canonical bytes without enrolling target`() async throws {
        let fixture = try CodexAccountPromotionTestContainer(suiteName: "JonesFleet-copy-same-identity")
        defer { fixture.tearDown() }
        let profile = try fixture.createFleetProfile()
        let target = try jonesFleetTarget(profile)
        let source = try Data(contentsOf: CodexAuthFingerprint.authFileURL(homePath: profile.codexHomePath))
        let old = try fixture.writeLiveOAuthAuthFile(
            email: profile.email, accountID: profile.workspaceAccountID, apiKey: "synthetic-old")
        #expect(source != old)
        let result = try await fixture.makeService(
            accountScopedRefresher: ClosureCodexAccountScopedRefresher { _ in },
            fleetHomePaths: { [profile.codexHomePath] }).promote(target: target)
        #expect(result.didMutateLiveAuth)
        #expect(result.displacedLiveDisposition == .none)
        #expect(try fixture.liveAuthData() == source)
        let accounts = try fixture.loadAccounts()
        #expect(accounts.accounts.isEmpty)
    }

    @Test
    func `ambiguous membership is rejected before snapshot or credential access`() async throws {
        let fixture = try CodexAccountPromotionTestContainer(suiteName: "JonesFleet-ambiguous")
        defer { fixture.tearDown() }
        let profile = try fixture.createFleetProfile()
        let target = try jonesFleetTarget(profile)
        let reader = JonesRecordingAuthReader()
        let snapshot = JonesRecordingSnapshotLoader()
        let service = fixture.makeService(
            snapshotLoader: snapshot,
            authMaterialReader: reader,
            fleetHomePaths: { [profile.codexHomePath, profile.codexHomePath] })
        await #expect(throws: CodexAccountPromotionError.fleetTargetUnavailable) {
            try await service.promote(target: target)
        }
        #expect(snapshot.reads == 0)
        #expect(reader.readHomes.isEmpty)
    }

    @Test
    func `membership is checked again after preparation before preservation writes`() async throws {
        let fixture = try CodexAccountPromotionTestContainer(suiteName: "JonesFleet-readmission")
        defer { fixture.tearDown() }
        let profile = try fixture.createFleetProfile()
        let target = try jonesFleetTarget(profile)
        let old = try fixture.writeLiveOAuthAuthFile(email: "old@example.com", accountID: "acct-old")
        var admissions = 0
        let sourceWriter = JonesRecordingActiveSourceWriter()
        let service = fixture.makeService(activeSourceWriter: sourceWriter, fleetHomePaths: {
            admissions += 1
            return admissions < 3 ? [profile.codexHomePath] : []
        })
        await #expect(throws: CodexAccountPromotionError.fleetTargetUnavailable) {
            try await service.promote(target: target)
        }
        #expect(admissions == 3)
        #expect(try fixture.liveAuthData() == old)
        let accounts = try fixture.loadAccounts()
        #expect(accounts.accounts.isEmpty)
        #expect(sourceWriter.sources.isEmpty)
    }

    @Test
    func `ordinary default destination uses the injected user home without CODEX_HOME`() async throws {
        let fixture = try CodexAccountPromotionTestContainer(suiteName: "JonesFleet-default-home")
        defer { fixture.tearDown() }
        let profile = try fixture.createFleetProfile()
        let target = try jonesFleetTarget(profile)
        let syntheticHome = fixture.rootURL.appendingPathComponent("synthetic-user", isDirectory: true)
        let expectedHome = syntheticHome.appendingPathComponent(".codex", isDirectory: true)
        let sourceWriter = JonesRecordingActiveSourceWriter()
        let reader = JonesRecordingAuthReader()
        let service = CodexAccountPromotionService(
            store: fixture.fileStore,
            homeFactory: fixture.homeFactory,
            identityReader: fixture.identityReader,
            workspaceResolver: fixture.workspaceResolver,
            snapshotLoader: JonesRecordingSnapshotLoader(),
            authMaterialReader: reader,
            liveAuthSwapper: DefaultCodexLiveAuthSwapper(),
            activeSourceWriter: sourceWriter,
            accountScopedRefresher: ClosureCodexAccountScopedRefresher { _ in },
            baseEnvironment: [:],
            fileManager: JonesSyntheticHomeFileManager(home: syntheticHome),
            sharedAuthWriter: CodexSharedAuthWriter(),
            fleetHomePaths: { [profile.codexHomePath] })

        _ = try await service.promote(target: target)

        let copied = try Data(contentsOf: expectedHome.appendingPathComponent("auth.json"))
        let canonical = try Data(contentsOf: CodexAuthFingerprint.authFileURL(homePath: profile.codexHomePath))
        #expect(copied == canonical)
        #expect(reader.readHomes.contains(expectedHome))
        #expect(try fixture.liveAuthData() == nil)
        #expect(sourceWriter.sources == [.liveSystem])
    }

    @Test
    func `a symlink alias of the canonical source cannot become the destination`() async throws {
        let fixture = try CodexAccountPromotionTestContainer(suiteName: "JonesFleet-alias")
        defer { fixture.tearDown() }
        let profile = try fixture.createFleetProfile()
        let target = try jonesFleetTarget(profile)
        let alias = fixture.rootURL.appendingPathComponent("aliased-default", isDirectory: true)
        try FileManager.default.createSymbolicLink(
            at: alias, withDestinationURL: URL(fileURLWithPath: profile.codexHomePath, isDirectory: true))
        let reader = JonesRecordingAuthReader()
        let snapshot = JonesRecordingSnapshotLoader()
        let service = fixture.makeService(
            snapshotLoader: snapshot,
            authMaterialReader: reader,
            fleetHomePaths: { [profile.codexHomePath] },
            baseEnvironment: ["CODEX_HOME": alias.path],
            defaultHomeURL: alias)
        await #expect(throws: CodexAccountPromotionError.fleetDestinationAmbiguous) {
            try await service.promote(target: target)
        }
        #expect(reader.readHomes.isEmpty)
        #expect(snapshot.reads == 0)
    }
}
