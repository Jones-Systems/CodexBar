import CodexBarCore
import Darwin
import Foundation
import Testing
@testable import CodexBar

struct CodexLoginRunnerTests {
    @Test
    func `cancelling login terminates the owned process and returns cancelled`() async throws {
        let root = TestFixtureScratch.root
            .appendingPathComponent("codexbar-login-cancel-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let ready = root.appendingPathComponent("ready")
        let finished = root.appendingPathComponent("finished")
        let executable = root.appendingPathComponent("codex")
        try """
        #!/usr/bin/python3
        import os, time
        with open(os.environ["CODEXBAR_TEST_READY"], "w") as f:
            f.write(str(os.getpid()))
        time.sleep(30)
        with open(os.environ["CODEXBAR_TEST_FINISHED"], "w") as f:
            f.write("finished")
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let task = Task {
            await CodexLoginRunner.run(
                homePath: root.path,
                timeout: 5,
                outputDrainTimeout: 0.1,
                environment: [
                    "PATH": root.path,
                    "CODEXBAR_TEST_READY": ready.path,
                    "CODEXBAR_TEST_FINISHED": finished.path,
                ], loginPATH: nil)
        }
        for _ in 0..<200 {
            if FileManager.default.fileExists(atPath: ready.path) { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        let started = FileManager.default.fileExists(atPath: ready.path)
        let cancelledAt = Date()
        task.cancel()
        let result = await task.value
        #expect(started)
        #expect(result.outcome == .cancelled)
        #expect(Date().timeIntervalSince(cancelledAt) < 3)
        #expect(!FileManager.default.fileExists(atPath: finished.path))
        if let pidText = try? String(contentsOf: ready, encoding: .utf8), let pid = pid_t(pidText) {
            #expect(kill(pid, 0) == -1)
        }
    }

    @Test
    func `login runner returns timeout before hung codex exits`() async throws {
        let root = TestFixtureScratch.root
            .appendingPathComponent("codexbar-login-runner-\(UUID().uuidString)", isDirectory: true)
        let binDir = root.appendingPathComponent("bin", isDirectory: true)
        let homeDir = root.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: homeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let codex = binDir.appendingPathComponent("codex")
        let script = """
        #!/usr/bin/python3
        import time

        print("login-started", flush=True)
        time.sleep(5)
        print("login-finished", flush=True)
        """
        try script.write(to: codex, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: codex.path)

        let start = Date()
        let result = await CodexLoginRunner.run(
            homePath: homeDir.path,
            timeout: 0.2,
            environment: ["PATH": binDir.path],
            loginPATH: nil)
        let elapsed = Date().timeIntervalSince(start)

        #expect(result.outcome == .timedOut)
        #expect(result.output.contains("login-finished") == false)
        #expect(elapsed < 2.0, "Timeout should return promptly, took \(elapsed)s")
    }

    @Test
    func `login runner bounds output drain when detached child keeps pipes open`() async throws {
        let root = TestFixtureScratch.root
            .appendingPathComponent("codexbar-login-drain-\(UUID().uuidString)", isDirectory: true)
        let binDir = root.appendingPathComponent("bin", isDirectory: true)
        let homeDir = root.appendingPathComponent("home", isDirectory: true)
        let childPIDFile = root.appendingPathComponent("child.pid")
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: homeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        defer {
            if let text = try? String(contentsOf: childPIDFile, encoding: .utf8),
               let childPID = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
            {
                _ = kill(childPID, SIGKILL)
            }
        }

        let codex = binDir.appendingPathComponent("codex")
        let script = """
        #!/bin/sh
        /bin/sh -c 'trap "" TERM; /bin/sleep 20' &
        child_pid=$!
        printf '%s\\n' "$child_pid" > "$CODEXBAR_TEST_CHILD_PID_FILE"
        printf 'login-started\\n'
        /bin/sleep 20
        """
        try script.write(to: codex, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: codex.path)

        let start = Date()
        let result = await CodexLoginRunner.run(
            homePath: homeDir.path,
            timeout: 5,
            outputDrainTimeout: 0.5,
            environment: [
                "CODEXBAR_TEST_CHILD_PID_FILE": childPIDFile.path,
                "PATH": binDir.path,
            ],
            loginPATH: nil)
        let elapsed = Date().timeIntervalSince(start)

        #expect(result.outcome == .timedOut)
        #expect(result.output.contains("login-started"))
        #expect(elapsed < 8.0, "Output drain should stay bounded, took \(elapsed)s")
    }
}
