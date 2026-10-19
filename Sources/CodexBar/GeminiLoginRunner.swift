import AppKit
import CodexBarCore
import Foundation

enum GeminiLoginRunner {
    private static let geminiConfigDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".gemini")
    private static let credentialsFile = "oauth_creds.json"

    private static func clearCredentials() {
        let fm = FileManager.default
        let filesToDelete = [credentialsFile, "google_accounts.json"]
        for file in filesToDelete {
            let path = self.geminiConfigDir.appendingPathComponent(file)
            try? fm.removeItem(at: path)
        }
    }

    struct Result {
        enum Outcome {
            case success
            case missingBinary
            case launchFailed(String)
            /// Google's consumer-tier shutdown was observed: launching Gemini CLI would only fail its
            /// OAuth step, so keep the stored credentials and steer the user to Antigravity instead.
            case consumerTierDeprecated
        }

        let outcome: Outcome
    }

    static func run(
        consumerTierDeprecationObserved: Bool = false,
        onCredentialsCreated: (@Sendable () -> Void)? = nil) async -> Result
    {
        guard !consumerTierDeprecationObserved else {
            return Result(outcome: .consumerTierDeprecated)
        }
        let task = Task(priority: .userInitiated) {
            let env = ProcessInfo.processInfo.environment
            guard let binary = BinaryLocator.resolveGeminiBinary(
                env: env,
                loginPATH: LoginShellPathCache.shared.current)
            else {
                return Result(outcome: .missingBinary)
            }

            guard !Task.isCancelled else {
                return Result(outcome: .launchFailed(CancellationError().localizedDescription))
            }

            // Clear existing credentials before auth (enables clean account switch)
            Self.clearCredentials()

            // Start watching for credentials file to be created
            if let callback = onCredentialsCreated {
                Self.watchForCredentials(callback: callback)
            }

            // Create a temporary shell script that runs gemini (auto-prompts for auth when no creds)
            let scriptContent = """
            #!/bin/bash
            cd ~
            "\(binary)"
            """

            return await Self.launchScript(
                scriptContent,
                scratchContext: .init(fileManager: .default, forkIdentity: JonesStateRoot.identity),
                write: { content, url in
                    try content.write(to: url, atomically: true, encoding: .utf8)
                },
                open: { url in
                    let config = NSWorkspace.OpenConfiguration()
                    config.activates = true
                    try await NSWorkspace.shared.open(url, configuration: config)
                },
                scheduleCleanup: { delay, cleanup in
                    DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: cleanup)
                })
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    struct ScratchContext {
        let fileManager: FileManager
        let forkIdentity: JonesStateRoot.Identity?
    }

    static func launchScript(
        _ content: String,
        scratchContext: ScratchContext,
        write: (String, URL) throws -> Void,
        open: (URL) async throws -> Void,
        scheduleCleanup: (TimeInterval, @escaping @Sendable () -> Void) -> Void) async -> Result
    {
        let fileManager = scratchContext.fileManager
        let forkIdentity = scratchContext.forkIdentity
        let tempDir = JonesProviderScratchRoot.directory(
            temporaryDirectory: fileManager.temporaryDirectory, identity: forkIdentity)
        let scriptURL = tempDir.appendingPathComponent("gemini_login_\(UUID().uuidString).command")
        let cleanup = ScriptCleanup(fileManager: fileManager, scriptURL: scriptURL)
        var cleanupScheduled = false
        defer {
            if !cleanupScheduled || Task.isCancelled {
                cleanup.remove()
            }
        }
        do {
            try Task.checkCancellation()
            if forkIdentity != nil {
                try fileManager.createDirectory(
                    at: tempDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            }
            try write(content, scriptURL)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
            try Task.checkCancellation()
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                try await open(scriptURL)
            } onCancel: {
                cleanup.remove()
            }
            try Task.checkCancellation()

            // Terminal needs time to read the script. This callback owns only this file for ten seconds.
            scheduleCleanup(10) {
                cleanup.remove()
            }
            cleanupScheduled = true
            return Result(outcome: .success)
        } catch {
            return Result(outcome: .launchFailed(error.localizedDescription))
        }
    }

    /// Only this script's removal crosses concurrency boundaries, after synchronous file preparation.
    /// The lock serializes cancellation, deferred and delayed removal using the original injected manager.
    private final class ScriptCleanup: @unchecked Sendable {
        private let fileManager: FileManager
        private let scriptURL: URL
        private let lock = NSLock()

        init(fileManager: FileManager, scriptURL: URL) {
            self.fileManager = fileManager
            self.scriptURL = scriptURL
        }

        func remove() {
            self.lock.withLock {
                try? self.fileManager.removeItem(at: self.scriptURL)
            }
        }
    }

    /// Watch for credentials file to be created, then call callback once
    private static func watchForCredentials(callback: @escaping @Sendable () -> Void, timeout: TimeInterval = 300) {
        let credsPath = self.geminiConfigDir.appendingPathComponent(self.credentialsFile).path

        DispatchQueue.global(qos: .utility).async {
            let startTime = Date()
            while Date().timeIntervalSince(startTime) < timeout {
                if FileManager.default.fileExists(atPath: credsPath) {
                    // Small delay to ensure file is fully written
                    Thread.sleep(forTimeInterval: 0.5)
                    callback()
                    return
                }
                Thread.sleep(forTimeInterval: 1.0)
            }
        }
    }
}
