import Foundation
import Testing
@testable import CodexBarCore

private final class ClaudeDelegatedProfileTouchCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        self.lock.withLock { self.value += 1 }
    }

    func count() -> Int {
        self.lock.withLock { self.value }
    }
}

@Suite(.serialized)
struct ClaudeOAuthDelegatedRefreshMCPProfileTests {
    @Test
    func `selected profile file and refresh observation use the same native service`() async throws {
        let root = TestFixtureScratch.root
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let profile = root.appendingPathComponent("selected-profile", isDirectory: true)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let environment = ["CLAUDE_CONFIG_DIR": profile.path]
        try self.makeCredentialsData(
            accessToken: "selected-profile-expired",
            expiresAt: Date(timeIntervalSinceNow: -3600))
            .write(to: ClaudeConfigPaths.credentialsURL(environment: environment))
        let mcpOAuthOnly = Data(#"{"mcpOAuth":{"plugin:test":{"accessToken":"other-profile"}}}"#.utf8)
        let refreshedCredentials = self.makeCredentialsData(
            accessToken: "selected-after-touch",
            expiresAt: Date(timeIntervalSinceNow: 3600))
        let touches = ClaudeDelegatedProfileTouchCounter()
        let touchAuthPath: @Sendable (TimeInterval, [String: String]) async -> Void = { _, _ in
            touches.increment()
        }

        let outcome = await ClaudeOAuthCredentialsStore.withEnvironmentCredentialsURLForTesting {
            await KeychainAccessGate.withTaskOverrideForTesting(false) {
                await ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(.always) {
                    await ClaudeOAuthKeychainReadStrategyPreference.withTaskOverrideForTesting(
                        .securityCLIExperimental)
                    {
                        await ClaudeOAuthDelegatedRefreshCoordinator.withIsolatedStateForTesting {
                            ClaudeOAuthDelegatedRefreshCoordinator.resetForTesting()
                            defer { ClaudeOAuthDelegatedRefreshCoordinator.resetForTesting() }
                            return await ClaudeOAuthDelegatedRefreshCoordinator
                                .withCLIAvailableOverrideForTesting(true) {
                                    await ClaudeOAuthDelegatedRefreshCoordinator.withTouchAuthPathOverrideForTesting(
                                        touchAuthPath)
                                    {
                                        await ClaudeOAuthCredentialsStore.withSecurityCLIReadOverrideForTesting(
                                            .dynamic { request in
                                                guard request.service == ClaudeConfigPaths.keychainService(
                                                    environment: environment)
                                                else { return nil }
                                                return touches.count() > 0 ? refreshedCredentials : mcpOAuthOnly
                                            }) {
                                                await ProviderInteractionContext.$current.withValue(.background) {
                                                    await ClaudeOAuthDelegatedRefreshCoordinator.attempt(
                                                        now: Date(timeIntervalSince1970: 64000),
                                                        timeout: 0.1,
                                                        environment: environment)
                                                }
                                            }
                                    }
                                }
                        }
                    }
                }
            }
        }

        #expect(outcome == .attemptedSucceeded)
        #expect(touches.count() == 1)
    }

    @Test
    func `default service rotation cannot verify a named profile refresh`() async {
        let environment = ["CLAUDE_CONFIG_DIR": "/synthetic/home/.claude-t3/jace"]
        let selectedService = "Claude Code-credentials-9a9e7cae"
        let selected = self.makeCredentialsData(
            accessToken: "selected-unchanged", expiresAt: Date(timeIntervalSinceNow: 3600))
        let defaultBefore = self.makeCredentialsData(
            accessToken: "default-before", expiresAt: Date(timeIntervalSinceNow: 3600))
        let defaultAfter = self.makeCredentialsData(
            accessToken: "default-after", expiresAt: Date(timeIntervalSinceNow: 3600))
        let touches = ClaudeDelegatedProfileTouchCounter()
        let outcome = await KeychainAccessGate.withTaskOverrideForTesting(false) {
            await ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(.always) {
                await ClaudeOAuthKeychainReadStrategyPreference.withTaskOverrideForTesting(.securityCLIExperimental) {
                    await ClaudeOAuthDelegatedRefreshCoordinator.withIsolatedStateForTesting {
                        await ClaudeOAuthDelegatedRefreshCoordinator.withCLIAvailableOverrideForTesting(true) {
                            await ClaudeOAuthDelegatedRefreshCoordinator.withTouchAuthPathOverrideForTesting({ _, env in
                                #expect(env == environment)
                                touches.increment()
                            }) {
                                await ClaudeOAuthCredentialsStore.withSecurityCLIReadOverrideForTesting(.dynamic {
                                    request in
                                    if request.service == selectedService { return selected }
                                    return touches.count() == 0 ? defaultBefore : defaultAfter
                                }) {
                                    await ProviderInteractionContext.$current.withValue(.userInitiated) {
                                        await ClaudeOAuthDelegatedRefreshCoordinator.attempt(
                                            now: Date(timeIntervalSince1970: 65000),
                                            timeout: 0.1,
                                            environment: environment)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        guard case .attemptedFailed = outcome else {
            Issue.record("Unchanged selected service was incorrectly reported as refreshed")
            return
        }
        #expect(touches.count() == 1)
    }

    private func makeCredentialsData(accessToken: String, expiresAt: Date) -> Data {
        let millis = Int(expiresAt.timeIntervalSince1970 * 1000)
        return Data("""
        {
          "claudeAiOauth": {
            "accessToken": "\(accessToken)",
            "expiresAt": \(millis),
            "scopes": ["user:profile"]
          }
        }
        """.utf8)
    }
}
