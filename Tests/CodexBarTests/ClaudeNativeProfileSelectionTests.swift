import Foundation
import Testing
@testable import CodexBarCore

struct ClaudeNativeProfileSelectionTests {
    @Test
    func `selected default clears automation and profile overrides without changing base`() throws {
        let base = [
            "HOME": "/ambient/home", "PATH": "/bin", "LANG": "en_US.UTF-8",
            "CLAUDE_CONFIG_DIR": "/ambient/config", "CLAUDE_SECURESTORAGE_CONFIG_DIR": "/ambient/secure",
            "CLAUDE_CODE_OAUTH_TOKEN": "synthetic-automation", "CODEXBAR_CLAUDE_OAUTH_TOKEN": "synthetic-token",
            "ANTHROPIC_API_KEY": "synthetic-key", "ANTHROPIC_AUTH_TOKEN": "synthetic-auth",
            "CLAUDE_CODE_USE_BEDROCK": "1", "CLAUDE_CODE_USE_VERTEX": "1", "CLAUDE_CODE_USE_FOUNDRY": "1",
            "CLAUDECODE": "1", "CLAUDE_CODE_ENTRYPOINT": "automation", "AUTH_FLEET_PROFILE": "other",
        ]
        let env = try ClaudeNativeProfileSelection.environment(
            base: base, alias: "default", discovery: ClaudeFleetProfileDiscoveryTests.discovery())
        #expect(env["HOME"] == ClaudeFleetProfileDiscoveryTests.home.path)
        #expect(env["PATH"] == "/bin")
        #expect(env["CLAUDE_CLI_PATH"] == "/fixture/bin/claude")
        #expect(env["CLAUDE_CONFIG_DIR"] == nil)
        #expect(env["CLAUDE_SECURESTORAGE_CONFIG_DIR"] == nil)
        for key in base.keys where !["HOME", "PATH", "LANG"].contains(key) {
            #expect(env[key] == nil)
        }
        #expect(base["CLAUDE_CONFIG_DIR"] == "/ambient/config")
        #expect(ClaudeConfigPaths.keychainService(environment: env) == "Claude Code-credentials")
        var explicitDefault = env
        explicitDefault["CLAUDE_CONFIG_DIR"] = ClaudeFleetProfileDiscoveryTests.home.path + "/.claude"
        #expect(ClaudeConfigPaths.keychainService(environment: explicitDefault) !=
            ClaudeConfigPaths.keychainService(environment: env))
        #expect(ClaudeOAuthCredentialsStore.credentialsProfileIdentifier(environment: explicitDefault) !=
            ClaudeOAuthCredentialsStore.credentialsProfileIdentifier(environment: env))
    }

    @Test
    func `named profile scopes native service files and cache independently of default`() throws {
        let discovery = try ClaudeFleetProfileDiscoveryTests.discovery()
        let named = ClaudeNativeProfileSelection.environment(base: [:], alias: "jace", discovery: discovery)
        let standard = ClaudeNativeProfileSelection.environment(base: [:], alias: "default", discovery: discovery)
        #expect(ClaudeConfigPaths.credentialsURL(environment: named).path ==
            ClaudeFleetProfileDiscoveryTests.home.path + "/.claude-t3/jace/.credentials.json")
        #expect(ClaudeConfigPaths.keychainService(environment: named) != ClaudeConfigPaths
            .keychainService(environment: standard))
        #expect(ClaudeOAuthCredentialsStore.credentialsProfileIdentifier(environment: named) !=
            ClaudeOAuthCredentialsStore.credentialsProfileIdentifier(environment: standard))
        #expect(named[ClaudeNativeProfileSelection.identityKey] != standard[ClaudeNativeProfileSelection.identityKey])
    }

    @Test
    func `independent credential web and admin selections retain precedence`() {
        for source in [ClaudeUsageDataSource.auto, .api, .web, .oauth, .cli] {
            #expect(!ClaudeNativeProfileSelection.applies(
                alias: "jace", source: source, hasTokenAccount: true, hasManualCookie: false, environment: [:]))
            #expect(!ClaudeNativeProfileSelection.applies(
                alias: nil, source: source, hasTokenAccount: false, hasManualCookie: false, environment: [:]))
        }
        for source in [ClaudeUsageDataSource.api, .web] {
            #expect(!ClaudeNativeProfileSelection.applies(
                alias: "jace", source: source, hasTokenAccount: false, hasManualCookie: false, environment: [:]))
        }
        for key in ClaudeAdminAPISettingsReader.apiKeyEnvironmentKeys {
            #expect(!ClaudeNativeProfileSelection.applies(
                alias: "jace",
                source: .auto,
                hasTokenAccount: false,
                hasManualCookie: false,
                environment: [key: "synthetic-admin-key"]))
        }
        #expect(!ClaudeNativeProfileSelection.applies(
            alias: "jace", source: .auto, hasTokenAccount: false, hasManualCookie: true, environment: [:]))
        #expect(ClaudeNativeProfileSelection.applies(
            alias: "jace",
            source: .auto,
            hasTokenAccount: false,
            hasManualCookie: false,
            environment: ["ANTHROPIC_AUTH_TOKEN": "synthetic-automation"]))
    }

    @Test
    func `removed malformed and unavailable selections remain selected and fail closed`() throws {
        for discovery in [ClaudeFleetProfileDiscovery.Result.missing, .unavailable("bad metadata"), .available([])] {
            let env = ClaudeNativeProfileSelection.environment(
                base: ["HOME": "/ambient"],
                alias: "jace",
                discovery: discovery)
            #expect(ClaudeNativeProfileSelection.isSelected(environment: env))
            #expect(throws: ClaudeNativeProfileSelectionError.self) {
                try ClaudeNativeProfileSelection.validate(environment: env)
            }
        }
        let invalid = try ClaudeNativeProfileSelection.environment(
            base: [:], alias: "malcolm", discovery: ClaudeFleetProfileDiscoveryTests.discovery())
        #expect(ClaudeNativeProfileSelection.isUnavailable(environment: invalid))
    }

    @Test
    func `persisted alias round trips and malformed selection never becomes ambient`() throws {
        var config = ProviderConfig(id: .claude)
        config.claudeNativeProfileAlias = "default"
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(ProviderConfig.self, from: data).claudeNativeProfileAlias == "default")
        config.claudeNativeProfileAlias = nil
        #expect(try JSONDecoder().decode(ProviderConfig.self, from: JSONEncoder().encode(config))
            .claudeNativeProfileAlias == nil)
        config.claudeNativeProfileAlias = ""
        #expect(config.claudeNativeProfileAlias == "<invalid>")
        let malformed = Data(#"{"id":"claude","claudeNativeProfileAlias":17}"#.utf8)
        #expect(try JSONDecoder().decode(ProviderConfig.self, from: malformed).claudeNativeProfileAlias == "<invalid>")
    }

    @Test
    func `selected native refuses independent cached credential ownership before refresh`() throws {
        let env = try ClaudeNativeProfileSelection.environment(
            base: [:], alias: "default", discovery: ClaudeFleetProfileDiscoveryTests.discovery())
        for owner in [ClaudeOAuthCredentialOwner.codexbar, .environment] {
            #expect(throws: ClaudeNativeProfileSelectionError.self) {
                try ClaudeNativeProfileSelection.validateCredentialOwner(owner, environment: env)
            }
            try ClaudeNativeProfileSelection.validateCredentialOwner(owner, environment: [:])
        }
        try ClaudeNativeProfileSelection.validateCredentialOwner(.claudeCLI, environment: env)
    }
}
