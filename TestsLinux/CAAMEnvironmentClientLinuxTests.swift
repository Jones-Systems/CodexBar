import Foundation
import Testing
@testable import CodexBarCore

struct CAAMEnvironmentClientLinuxTests {
    @Test
    func `local snapshot command uses a direct gateway binary without a shell`() throws {
        let client = CAAMEnvironmentClient(
            resolveLocalGateway: { _ in "/opt/homebrew/bin/caam-codexbar" })
        let configuration = CAAMEnvironmentConfiguration(id: "laptop", label: "Laptop", connection: .local())

        let command = try client.command(
            for: configuration,
            operation: .snapshot(environmentID: "laptop"))

        #expect(command.binary == "/opt/homebrew/bin/caam-codexbar")
        #expect(command.arguments == ["snapshot", "--environment-id", "laptop"])
        #expect(!command.arguments.contains("sh"))
        #expect(!command.arguments.contains("-lc"))
    }

    @Test
    func `SSH command fixes security options gateway and operation arguments`() throws {
        let operationID = try #require(UUID(uuidString: "11111111-2222-4333-8444-555555555555"))
        let idempotencyKey = try #require(UUID(uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"))
        let digest = String(repeating: "a", count: 64)
        let client = CAAMEnvironmentClient(
            resolveLocalGateway: { _ in nil },
            sshBinary: "/usr/bin/ssh")
        let configuration = CAAMEnvironmentConfiguration(
            id: "vps",
            label: "VPS",
            connection: .ssh(destination: "vps"))

        let command = try client.command(
            for: configuration,
            operation: .executeSwitch(
                environmentID: "vps",
                planDigest: digest,
                operationID: operationID,
                idempotencyKey: idempotencyKey))

        #expect(command.binary == "/usr/bin/ssh")
        #expect(command.arguments == [
            "-o", "BatchMode=yes",
            "-o", "RequestTTY=no",
            "-o", "ClearAllForwardings=yes",
            "-o", "ConnectTimeout=5",
            "vps",
            "caam-codexbar",
            "execute-switch",
            "--environment-id", "vps",
            "--plan-digest", digest,
            "--operation-id", "11111111-2222-4333-8444-555555555555",
            "--idempotency-key", "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
        ])
        #expect(!command.arguments.contains("sh"))
        #expect(!command.arguments.contains("-lc"))
    }

    @Test
    func `fallback restoration binds the plan revision and operation identity`() throws {
        let operationID = try #require(UUID(uuidString: "11111111-2222-4333-8444-555555555555"))
        let idempotencyKey = try #require(UUID(uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"))
        let digest = String(repeating: "b", count: 64)
        let client = CAAMEnvironmentClient(
            resolveLocalGateway: { _ in "/usr/local/bin/caam-codexbar" })
        let configuration = CAAMEnvironmentConfiguration(id: "laptop", label: "Laptop", connection: .local())

        let command = try client.command(
            for: configuration,
            operation: .restoreFallback(
                environmentID: "laptop",
                expectedRevision: "42",
                planDigest: digest,
                operationID: operationID,
                idempotencyKey: idempotencyKey))

        #expect(command.arguments == [
            "restore-fallback",
            "--environment-id", "laptop",
            "--expected-revision", "42",
            "--plan-digest", digest,
            "--operation-id", "11111111-2222-4333-8444-555555555555",
            "--idempotency-key", "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
        ])
    }

    @Test
    func `command rejects cross environment targeting and unsafe profile`() throws {
        let client = CAAMEnvironmentClient(resolveLocalGateway: { _ in "/usr/local/bin/caam-codexbar" })
        let configuration = CAAMEnvironmentConfiguration(id: "laptop", label: "Laptop", connection: .local())

        #expect(throws: CAAMEnvironmentContractError.self) {
            try client.command(for: configuration, operation: .snapshot(environmentID: "vps"))
        }
        #expect(throws: CAAMEnvironmentContractError.self) {
            try client.command(
                for: configuration,
                operation: .planSwitch(
                    environmentID: "laptop",
                    profile: "../../auth.json",
                    expectedRevision: "1"))
        }
    }

    @Test
    func `snapshot client decodes bounded output from injected runner`() async throws {
        let runner = RecordingCAAMEnvironmentRunner(result: SubprocessResult(
            stdout: CAAMEnvironmentContractLinuxTests.snapshotJSON,
            stderr: ""))
        let client = CAAMEnvironmentClient(
            runner: runner,
            resolveLocalGateway: { _ in "/usr/local/bin/caam-codexbar" })
        let configuration = CAAMEnvironmentConfiguration(id: "laptop", label: "Laptop", connection: .local())

        let snapshot = try await client.fetchSnapshot(for: configuration)
        let command = await runner.lastCommand

        #expect(snapshot.hostDefaultProfile == "primary")
        #expect(command?.arguments == ["snapshot", "--environment-id", "laptop"])
    }

    @Test
    func `snapshot client redacts subprocess failure detail`() async throws {
        let runner = RecordingCAAMEnvironmentRunner(
            error: SubprocessRunnerError.nonZeroExit(code: 1, stderr: "credential-adjacent diagnostic"))
        let client = CAAMEnvironmentClient(
            runner: runner,
            resolveLocalGateway: { _ in "/usr/local/bin/caam-codexbar" })
        let configuration = CAAMEnvironmentConfiguration(id: "laptop", label: "Laptop", connection: .local())

        do {
            _ = try await client.fetchSnapshot(for: configuration)
            Issue.record("Expected a redacted command failure")
        } catch let error as CAAMEnvironmentClientError {
            #expect(error == .commandFailed)
            #expect(error.localizedDescription == "The CAAM environment command failed.")
        }
    }
}

private actor RecordingCAAMEnvironmentRunner: CAAMEnvironmentCommandRunning {
    private let result: SubprocessResult?
    private let error: (any Error)?
    private(set) var lastCommand: CAAMEnvironmentCommand?

    init(result: SubprocessResult) {
        self.result = result
        self.error = nil
    }

    init(error: any Error) {
        self.result = nil
        self.error = error
    }

    func run(command: CAAMEnvironmentCommand, environment _: [String: String]) async throws -> SubprocessResult {
        self.lastCommand = command
        if let error {
            throw error
        }
        return try #require(self.result)
    }
}
