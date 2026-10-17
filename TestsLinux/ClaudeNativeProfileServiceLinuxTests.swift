import Foundation
import Testing
@testable import CodexBarCore

struct ClaudeNativeProfileServiceLinuxTests {
    @Test
    func `native service vectors preserve default named and Unicode boundaries`() {
        let vectors: [([String: String], String)] = [
            (["HOME": "/synthetic/home"], "Claude Code-credentials"),
            (["CLAUDE_CONFIG_DIR": ""], "Claude Code-credentials"),
            (["CLAUDE_CONFIG_DIR": "/synthetic/home/.claude"], "Claude Code-credentials-2eb62ada"),
            (["CLAUDE_CONFIG_DIR": "/synthetic/home/.claude-t3/jace"], "Claude Code-credentials-9a9e7cae"),
            (["CLAUDE_CONFIG_DIR": "/synthetic/café"], "Claude Code-credentials-fdc632a8"),
            (["CLAUDE_CONFIG_DIR": "/synthetic/cafe\u{301}"], "Claude Code-credentials-fdc632a8"),
            ([
                "CLAUDE_CONFIG_DIR": "/synthetic/home/.claude-t3/jace",
                "CLAUDE_SECURESTORAGE_CONFIG_DIR": "",
            ], "Claude Code-credentials"),
            ([
                "CLAUDE_CONFIG_DIR": "/synthetic/home/.claude-t3/jace",
                "CLAUDE_SECURESTORAGE_CONFIG_DIR": "/synthetic/secure",
            ], "Claude Code-credentials-2d16d9a4"),
        ]
        for (environment, expected) in vectors {
            #expect(ClaudeConfigPaths.keychainService(environment: environment) == expected)
        }
    }

    @Test
    func `explicit default cannot inherit a path only cache or fingerprint`() {
        ClaudeOAuthCredentialsStore.withEnvironmentCredentialsURLForTesting {
            let implicit = ["HOME": "/synthetic/home"]
            let explicit = ["HOME": "/synthetic/home", "CLAUDE_CONFIG_DIR": "/synthetic/home/.claude"]
            #expect(ClaudeConfigPaths.credentialsURL(environment: implicit)
                == ClaudeConfigPaths.credentialsURL(environment: explicit))
            #expect(ClaudeOAuthCredentialsStore.credentialsProfileIdentifier(environment: implicit)
                != ClaudeOAuthCredentialsStore.credentialsProfileIdentifier(environment: explicit))
            #expect(ClaudeOAuthCredentialsStore.claudeKeychainFingerprintStorageKey(environment: implicit)
                != ClaudeOAuthCredentialsStore.claudeKeychainFingerprintStorageKey(environment: explicit))
        }
    }
}
