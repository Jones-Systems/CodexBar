import Foundation
import Testing
@testable import CodexBarCore

struct CAAMControlTransportLinuxTests {
    @Test
    func `relative PATH entries cannot choose a gateway from the working directory`() {
        #expect(CAAMEnvironmentClient.resolveLocalGateway(
            configuredPath: nil,
            environment: ["PATH": ".:relative/bin"]) == nil)
    }

    private func client(_ runner: CAAMControlFixtureRunner) -> CAAMEnvironmentClient {
        CAAMEnvironmentClient(runner: runner, environment: [:], resolveLocalGateway: { _ in "/fixture/caam-codexbar" })
    }

    private var operation: CAAMGatewayOperation {
        .executeSwitch(
            environmentID: CAAMControlFixtures.configuration.id,
            planDigest: String(repeating: "a", count: 64),
            operationID: CAAMControlFixtures.operationID,
            idempotencyKey: CAAMControlFixtures.operationID)
    }

    @Test
    func `typed plan is decoded from the exact read only operation`() async throws {
        let stdout = try CAAMControlFixtures.envelope(CAAMControlFixtures.plan(), kind: "plan-switch")
        let runner = CAAMControlFixtureRunner([.result(SubprocessResult(stdout: stdout, stderr: ""))])
        let plan = try await self.client(runner).fetchPlan(
            for: CAAMControlFixtures.configuration, profile: "secondary", expectedRevision: "1")
        #expect(plan == CAAMControlFixtures.plan())
        let commands = await runner.commands
        #expect(commands.count == 1)
        #expect(commands.first?.arguments == [
            "plan-switch", "--environment-id", "fixture", "--profile", "secondary", "--expected-revision", "1",
        ])
    }

    @Test
    func `nonzero error stdout retains typed effect but never diagnostic text`() async throws {
        let stdout = #"""
        {"schema":"caam.codexbar-control/v1","kind":"execute-switch","environment_id":"fixture",
         "protocol_version":"1.0","result":null,
         "error":{"code":"stale_revision","message":"private fixture diagnostic","effect":"known_no_effect"}}
        """#
        let runner = CAAMControlFixtureRunner([.result(SubprocessResult(
            stdout: stdout, stderr: "private stderr fixture", exitCode: 2))])
        do {
            _ = try await self.client(runner).perform(self.operation, for: CAAMControlFixtures.configuration)
            Issue.record("Expected a typed rejection")
        } catch let error as CAAMControlFailure {
            #expect(error.reason == .rejected)
            #expect(error.effect == .knownNoEffect)
            #expect(error.code == "stale_revision")
            #expect(!error.localizedDescription.contains("private"))
        }
    }

    @Test
    func `nonzero success envelope and invalid UTF8 cannot confirm a mutation`() async throws {
        let stdout = try CAAMControlFixtures.envelope(CAAMControlFixtures.committed(), kind: "execute-switch")
        for response in [
            SubprocessResult(stdout: stdout, stderr: "", exitCode: 2),
            SubprocessResult(stdout: stdout, stderr: "", stdoutWasValidUTF8: false),
            SubprocessResult(stdout: String(repeating: " ", count: 65537), stderr: ""),
        ] {
            let runner = CAAMControlFixtureRunner([.result(response)])
            do {
                _ = try await self.client(runner).perform(self.operation, for: CAAMControlFixtures.configuration)
                Issue.record("Expected ambiguous failure")
            } catch let error as CAAMControlFailure {
                #expect(error.effect == .unknown)
            }
        }
    }

    @Test
    func `transport failures distinguish no launch from potentially changed credentials`() async throws {
        let cases: [(CAAMControlFixtureRunner.Step, CAAMControlEffect)] = [
            (.failure(.binaryNotFound("fixture")), .knownNoEffect),
            (.failure(.launchFailed("fixture")), .knownNoEffect),
            (.failure(.timedOut("fixture")), .unknown),
            (.failure(.outputTooLarge("fixture")), .unknown),
            (.failure(.nonZeroExit(code: 1, stderr: "private fixture")), .unknown),
            (.cancelled, .unknown),
        ]
        for (step, effect) in cases {
            let runner = CAAMControlFixtureRunner([step])
            do {
                _ = try await self.client(runner).perform(self.operation, for: CAAMControlFixtures.configuration)
                Issue.record("Expected a transport failure")
            } catch let error as CAAMControlFailure {
                #expect(error.effect == effect)
                #expect(!error.localizedDescription.contains("private"))
            }
            #expect(await runner.commands.count == 1)
        }
    }

    @Test
    func `cancellation before launch records no effect and invokes no runner`() async {
        let runner = CAAMControlFixtureRunner([])
        let client = self.client(runner)
        let operation = self.operation
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.perform(operation, for: CAAMControlFixtures.configuration)
        }
        switch await task.result {
        case .success: Issue.record("Expected pre-launch cancellation")
        case let .failure(error):
            #expect((error as? CAAMControlFailure)?.effect == .knownNoEffect)
            #expect((error as? CAAMControlFailure)?.reason == .cancelled)
        }
        #expect(await runner.commands.isEmpty)
    }

    @Test
    func `mismatched bindings and unsupported protocol never become success`() async throws {
        let fixture = CAAMControlFixtures.self
        let responses = [
            try fixture.envelope(fixture.committed(), kind: "operation-status"),
            try fixture.envelope(fixture.committed(), kind: "execute-switch", environmentID: "other"),
            try fixture.envelope(fixture.committed(), kind: "execute-switch", version: "2.0"),
            try fixture.envelope(fixture.committed(), kind: "execute-switch", version: "1.invalid"),
        ]
        for stdout in responses {
            let runner = CAAMControlFixtureRunner([.result(SubprocessResult(stdout: stdout, stderr: ""))])
            do {
                _ = try await self.client(runner).perform(self.operation, for: fixture.configuration)
                Issue.record("Expected bound response rejection")
            } catch let error as CAAMControlFailure {
                #expect(error.effect == .unknown)
            }
        }
    }

    @Test
    func `credential and command fields are recursively rejected before typed decoding`() throws {
        let fixture = CAAMControlFixtures.self
        let original = try fixture.envelope(fixture.snapshot(), kind: "snapshot")
        for key in ["refresh_token", "auth_file_digest", "shellFragment", "commandText"] {
            var object = try #require(JSONSerialization.jsonObject(with: Data(original.utf8)) as? [String: Any])
            object["future_metadata"] = [key: "synthetic fixture"]
            let data = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: CAAMEnvironmentContractError.self) {
                try CAAMEnvironmentContract.decodeSnapshot(data, expectedEnvironmentID: fixture.configuration.id)
            }
        }
    }
}
