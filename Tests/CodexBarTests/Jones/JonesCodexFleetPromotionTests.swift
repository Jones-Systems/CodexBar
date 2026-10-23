import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite(.serialized, CodexCredentialFixtures())
@MainActor
struct JonesCodexFleetPromotionTests {
    @Test
    func `fleet promotion copies canonical bytes and preserves displaced system without enrolling fleet`() async
        throws
    {
        let fixture = try CodexAccountPromotionTestContainer(suiteName: "JonesFleet-copy")
        defer { fixture.tearDown() }
        let profile = try fixture.createFleetProfile()
        let target = try jonesFleetTarget(profile)
        let sourceURL = CodexAuthFingerprint.authFileURL(homePath: profile.codexHomePath)
        let original = try Data(contentsOf: sourceURL)
        let displaced = try fixture.writeLiveOAuthAuthFile(email: "old@example.com", accountID: "acct-old")
        let membership = JonesFleetMembershipFixture([profile.codexHomePath])
        let sourceWriter = JonesRecordingActiveSourceWriter()
        var refreshCount = 0
        let service = fixture.makeService(
            activeSourceWriter: sourceWriter,
            accountScopedRefresher: ClosureCodexAccountScopedRefresher { _ in refreshCount += 1 },
            fleetHomePaths: membership.load)

        let result = try await service.promote(target: target)

        #expect(result.target == target)
        #expect(result.targetManagedAccountID == nil)
        #expect(result.outcome == .promoted)
        #expect(result.didMutateLiveAuth)
        #expect(result.resultingActiveSource == .liveSystem)
        #expect(try fixture.liveAuthData() == original)
        #expect(try Data(contentsOf: sourceURL) == original)
        let accounts = try fixture.loadAccounts().accounts
        #expect(accounts.count == 1)
        let preserved = try #require(accounts.first)
        #expect(preserved.email == "old@example.com")
        #expect(try fixture.managedAuthData(for: preserved) == displaced)
        #expect(sourceWriter.sources == [.liveSystem])
        #expect(refreshCount == 1)
        #expect(membership.reads >= 2)
    }

    @Test
    func `same email profiles remain distinct and copy the selected workspace home`() async throws {
        let fixture = try CodexAccountPromotionTestContainer(suiteName: "JonesFleet-same-email")
        defer { fixture.tearDown() }
        let first = try fixture.createFleetProfile(alias: "first", email: "same@example.com", accountID: "acct-first")
        let second = try fixture.createFleetProfile(
            alias: "second", email: "same@example.com", accountID: "acct-second")
        let firstTarget = try jonesFleetTarget(first)
        let secondTarget = try jonesFleetTarget(second)
        #expect(firstTarget != secondTarget)
        let membership = JonesFleetMembershipFixture([first.codexHomePath, second.codexHomePath])
        let service = fixture.makeService(
            accountScopedRefresher: ClosureCodexAccountScopedRefresher { _ in },
            fleetHomePaths: membership.load)
        let firstBytes = try Data(contentsOf: CodexAuthFingerprint.authFileURL(homePath: first.codexHomePath))
        let secondBytes = try Data(contentsOf: CodexAuthFingerprint.authFileURL(homePath: second.codexHomePath))

        _ = try await service.promote(target: secondTarget)

        #expect(try fixture.liveAuthData() == secondBytes)
        #expect(try Data(contentsOf: CodexAuthFingerprint.authFileURL(homePath: first.codexHomePath)) == firstBytes)
        #expect(try Data(contentsOf: CodexAuthFingerprint.authFileURL(homePath: second.codexHomePath)) == secondBytes)
        let accounts = try fixture.loadAccounts()
        #expect(accounts.accounts.isEmpty)
    }

    @Test
    func `removed or rebound membership while queued fails before credential reads`() async throws {
        for rebound in [false, true] {
            let fixture = try CodexAccountPromotionTestContainer(suiteName: "JonesFleet-removed-\(rebound)")
            defer { fixture.tearDown() }
            let profile = try fixture.createFleetProfile()
            let target = try jonesFleetTarget(profile)
            let membership = JonesFleetMembershipFixture([profile.codexHomePath])
            let reader = JonesRecordingAuthReader()
            let snapshot = JonesRecordingSnapshotLoader()
            let swapper = RecordingCodexLiveAuthSwapper()
            let writer = CodexSharedAuthWriter()
            let service = fixture.makeService(
                liveAuthSwapper: swapper,
                snapshotLoader: snapshot,
                sharedAuthWriter: writer,
                authMaterialReader: reader,
                fleetHomePaths: membership.load)
            await writer.acquire()
            let promotion = Task { try await service.promote(target: target) }
            #expect(await jonesWaitForWriter(writer))
            #expect(reader.readHomes.isEmpty)
            membership.paths = rebound ? [fixture.rootURL.appendingPathComponent("rebound").path] : []
            writer.release()
            await #expect(throws: CodexAccountPromotionError.fleetTargetUnavailable) { try await promotion.value }
            #expect(reader.readHomes.isEmpty)
            #expect(snapshot.reads == 0)
            #expect(swapper.swapCallCount == 0)
        }
    }

    @Test
    func `queued source identity change and same identity credential rotation are rejected`() async throws {
        for mutation in ["account", "email", "tokens"] {
            let fixture = try CodexAccountPromotionTestContainer(suiteName: "JonesFleet-stale-\(mutation)")
            defer { fixture.tearDown() }
            let profile = try fixture.createFleetProfile()
            let target = try jonesFleetTarget(profile)
            let membership = JonesFleetMembershipFixture([profile.codexHomePath])
            let writer = CodexSharedAuthWriter()
            let sourceWriter = JonesRecordingActiveSourceWriter()
            let service = fixture.makeService(
                activeSourceWriter: sourceWriter,
                sharedAuthWriter: writer,
                fleetHomePaths: membership.load)
            await writer.acquire()
            let promotion = Task { try await service.promote(target: target) }
            #expect(await jonesWaitForWriter(writer))
            if mutation == "tokens" {
                let url = CodexAuthFingerprint.authFileURL(homePath: profile.codexHomePath)
                let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
                var json = try #require(object as? [String: Any])
                json["last_refresh"] = "2026-04-06T00:00:00Z"
                try JSONSerialization.data(withJSONObject: json).write(to: url)
            } else {
                _ = try fixture.createFleetProfile(
                    email: mutation == "email" ? "other@example.com" : "jace@example.com",
                    accountID: mutation == "account" ? "acct-other" : "acct-jace")
            }
            writer.release()
            await #expect(throws: CodexAccountPromotionError.fleetTargetIdentityChanged) { try await promotion.value }
            #expect(try fixture.liveAuthData() == nil)
            #expect(sourceWriter.sources.isEmpty)
        }
    }

    @Test
    func `missing and unreadable fleet sources never fall back to live or managed credentials`() async throws {
        for unreadable in [false, true] {
            let fixture = try CodexAccountPromotionTestContainer(suiteName: "JonesFleet-missing-\(unreadable)")
            defer { fixture.tearDown() }
            let profile = try fixture.createFleetProfile()
            let target = try jonesFleetTarget(profile)
            let old = try fixture.writeLiveOAuthAuthFile(
                email: profile.email, accountID: profile.workspaceAccountID)
            let home = URL(fileURLWithPath: profile.codexHomePath, isDirectory: true)
            let reader = JonesRecordingAuthReader(unreadableHome: unreadable ? home : nil)
            if !unreadable { try FileManager.default.removeItem(at: home.appendingPathComponent("auth.json")) }
            let sourceWriter = JonesRecordingActiveSourceWriter()
            let service = fixture.makeService(
                activeSourceWriter: sourceWriter,
                authMaterialReader: reader,
                fleetHomePaths: { [profile.codexHomePath] })
            let expected: CodexAccountPromotionError = unreadable ? .fleetTargetAuthUnreadable : .fleetTargetAuthMissing
            await #expect(throws: expected) { try await service.promote(target: target) }
            #expect(try fixture.liveAuthData() == old)
            #expect(sourceWriter.sources.isEmpty)
            let accounts = try fixture.loadAccounts()
            #expect(accounts.accounts.isEmpty)
        }
    }

    @Test
    func `source destination equality and inherited fleet home override fail before auth reads`() async throws {
        for sameDestination in [false, true] {
            let fixture = try CodexAccountPromotionTestContainer(suiteName: "JonesFleet-destination-\(sameDestination)")
            defer { fixture.tearDown() }
            let profile = try fixture.createFleetProfile()
            let target = try jonesFleetTarget(profile)
            let reader = JonesRecordingAuthReader()
            let snapshot = JonesRecordingSnapshotLoader()
            let service = fixture.makeService(
                snapshotLoader: snapshot,
                authMaterialReader: reader,
                fleetHomePaths: { [profile.codexHomePath] },
                baseEnvironment: ["CODEX_HOME": profile.codexHomePath],
                defaultHomeURL: sameDestination ? URL(fileURLWithPath: profile.codexHomePath) : fixture.liveHomeURL)
            let expectedError: CodexAccountPromotionError = sameDestination
                ? .fleetDestinationAmbiguous : .fleetLaunchHomeOverride
            await #expect(throws: expectedError) {
                try await service.promote(target: target)
            }
            #expect(reader.readHomes.isEmpty)
            #expect(snapshot.reads == 0)
            #expect(try fixture.liveAuthData() == nil)
        }
    }

    @Test
    func `cancelled queued fleet promotion never reads credentials or writes selection`() async throws {
        let fixture = try CodexAccountPromotionTestContainer(suiteName: "JonesFleet-cancel")
        defer { fixture.tearDown() }
        let profile = try fixture.createFleetProfile()
        let target = try jonesFleetTarget(profile)
        let reader = JonesRecordingAuthReader()
        let snapshot = JonesRecordingSnapshotLoader()
        let sourceWriter = JonesRecordingActiveSourceWriter()
        let membership = JonesFleetMembershipFixture([profile.codexHomePath])
        let writer = CodexSharedAuthWriter()
        let service = fixture.makeService(
            activeSourceWriter: sourceWriter,
            snapshotLoader: snapshot,
            sharedAuthWriter: writer,
            authMaterialReader: reader,
            fleetHomePaths: membership.load)
        await writer.acquire()
        let promotion = Task { try await service.promote(target: target) }
        #expect(await jonesWaitForWriter(writer))
        promotion.cancel()
        writer.release()
        await #expect(throws: CancellationError.self) { try await promotion.value }
        #expect(reader.readHomes.isEmpty)
        #expect(snapshot.reads == 0)
        #expect(membership.reads == 0)
        #expect(sourceWriter.sources.isEmpty)
    }
}
