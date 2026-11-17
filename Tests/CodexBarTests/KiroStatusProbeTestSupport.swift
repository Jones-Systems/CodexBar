import Foundation
@testable import CodexBarCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

import Testing

/// Shared TTY cleanup and cancellation regressions retained after Kiro provider removal.
@Suite(.serialized)
struct KiroStatusProbeTests {}

enum KiroProcessTestSupport {
    private struct WaitTimeout: LocalizedError {
        let description: String
        let timeout: Duration

        var errorDescription: String? {
            "Timed out after \(self.timeout) waiting for \(self.description)"
        }
    }

    /// This bounds fixture setup only. Tests that exercise production timeout behavior pass their own exact budgets.
    static let fixtureSetupTimeout: Duration = .seconds(20)

    static func waitForFile(
        _ url: URL,
        timeout: Duration = fixtureSetupTimeout) async throws
    {
        _ = try await self.wait(
            for: "fixture file \(url.path)",
            timeout: timeout)
        {
            FileManager.default.fileExists(atPath: url.path) ? true : nil
        }
    }

    static func waitForPID(
        in url: URL,
        timeout: Duration = fixtureSetupTimeout) async throws -> pid_t
    {
        try await self.wait(
            for: "a valid PID in fixture file \(url.path)",
            timeout: timeout)
        {
            self.readPID(from: url)
        }
    }

    static func waitForExit(
        of pid: pid_t,
        timeout: Duration,
        description: String) async throws
    {
        try await self.waitForExit(of: [pid], timeout: timeout, description: description)
    }

    static func waitForExit(
        of pids: [pid_t],
        timeout: Duration,
        description: String) async throws
    {
        _ = try await self.wait(for: description, timeout: timeout) {
            pids.allSatisfy { kill($0, 0) == -1 } ? true : nil
        }
    }

    static func readPID(from url: URL) -> pid_t? {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid > 0
        else {
            return nil
        }
        return pid
    }

    static func touch(_ url: URL) throws {
        let fileDescriptor = open(url.path, O_WRONLY | O_CREAT | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fileDescriptor >= 0 else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        _ = close(fileDescriptor)
    }

    static func runTTYAfterFixtureReady(
        binary: URL,
        readyFile: URL,
        startFile: URL,
        options: TTYCommandRunner.Options,
        onURLDetected: (@Sendable () -> Void)? = nil) async throws -> TTYCommandRunner.Result
    {
        let task = Task.detached {
            try TTYCommandRunner().run(
                binary: binary.path,
                send: "",
                options: options,
                onURLDetected: onURLDetected)
        }
        do {
            try await self.waitForFile(readyFile)
            try self.touch(startFile)
        } catch {
            task.cancel()
            _ = try? await task.value
            throw error
        }
        return try await task.value
    }

    static func waitForCondition(
        _ description: String,
        timeout: Duration = fixtureSetupTimeout,
        condition: () -> Bool) async throws
    {
        _ = try await self.wait(for: description, timeout: timeout) {
            condition() ? true : nil
        }
    }

    private static func wait<Value>(
        for description: String,
        timeout: Duration,
        value: () -> Value?) async throws -> Value
    {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while true {
            if let value = value() {
                return value
            }
            guard clock.now < deadline else {
                throw WaitTimeout(description: description, timeout: timeout)
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

final class KiroTestInstantMarker: @unchecked Sendable {
    private let lock = NSLock()
    private var instant: ContinuousClock.Instant?

    func mark() {
        self.lock.withLock {
            if self.instant == nil {
                self.instant = ContinuousClock().now
            }
        }
    }

    func value() -> ContinuousClock.Instant? {
        self.lock.withLock { self.instant }
    }
}

final class KiroTestCompletionMarker: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false

    func markCompleted() {
        self.lock.withLock { self.completed = true }
    }

    func isCompleted() -> Bool {
        self.lock.withLock { self.completed }
    }
}
