import CodexBarCore
import Commander
import Foundation
import Testing
@testable import CodexBarCLI

struct CLIConfigCommandTests {
    @Test
    func `config set api key parses provider stdin and no enable flags`() throws {
        let parser = CommandParser(signature: CodexBarCLI._configSetAPIKeySignatureForTesting())
        let parsed = try parser.parse(arguments: [
            "--provider", "claude",
            "--stdin",
            "--no-enable",
            "--json",
        ])

        #expect(parsed.options["provider"] == ["claude"])
        #expect(parsed.flags.contains("stdin"))
        #expect(parsed.flags.contains("noEnable"))
        #expect(CodexBarCLI._decodeFormatForTesting(from: parsed) == .json)
    }

    @Test
    func `config set api key for codex provider rejects an unsupported credential source`() {
        #expect(ProviderConfigEnvironment.supportsAPIKeyOverride(for: .codex) == false)
        let codexMsg = CodexBarCLI.unsupportedAPIKeyErrorMessage(for: .codex, rawProvider: "codex")
        #expect(codexMsg ==
            "codex does not support config API keys.")
    }

    @Test
    func `config set api key stores key and enables provider`() {
        let config = CodexBarConfig.makeDefault()
        let updated = CodexBarCLI.configSettingAPIKey(
            config,
            provider: .claude,
            apiKey: "xi-test-token",
            enableProvider: true)
        let provider = updated.providerConfig(for: .claude)

        #expect(provider?.sanitizedAPIKey == "xi-test-token")
        #expect(provider?.enabled == true)
    }

    @Test
    func `config provider toggle parses provider and json flags`() throws {
        let parser = CommandParser(signature: CodexBarCLI._configProviderToggleSignatureForTesting())
        let parsed = try parser.parse(arguments: [
            "--provider", "codex",
            "--json",
            "--pretty",
        ])

        #expect(parsed.options["provider"] == ["codex"])
        #expect(CodexBarCLI._decodeFormatForTesting(from: parsed) == .json)
        #expect(parsed.flags.contains("pretty"))
    }

    @Test
    func `config provider toggle enables and disables provider`() {
        let config = CodexBarConfig.makeDefault()
        let enabled = CodexBarCLI.configSettingProviderEnabled(config, provider: .codex, enabled: true)
        let disabled = CodexBarCLI.configSettingProviderEnabled(enabled, provider: .codex, enabled: false)

        #expect(enabled.providerConfig(for: .codex)?.enabled == true)
        #expect(disabled.providerConfig(for: .codex)?.enabled == false)
    }

    @Test
    func `config provider status includes effective default`() throws {
        let config = CodexBarConfig(providers: [
            ProviderConfig(id: .codex, enabled: true),
            ProviderConfig(id: .claude, enabled: false),
        ])
        let statuses = CodexBarCLI.configProviderStatuses(config)
        let codex = try #require(statuses.first { $0.provider == "codex" })
        let claude = try #require(statuses.first { $0.provider == "claude" })

        #expect(codex.enabled)
        #expect(!claude.enabled)
        #expect(statuses.count == UsageProvider.allCases.count)
    }

    @Test
    func `config set api key only accepts consumed config keys`() {
        #expect(ProviderConfigEnvironment.supportsAPIKeyOverride(for: .claude))
        #expect(!ProviderConfigEnvironment.supportsAPIKeyOverride(for: .codex))
    }

    @Test
    func `config set api key preserves disabled provider when requested`() {
        var config = CodexBarConfig.makeDefault()
        config.setProviderConfig(ProviderConfig(id: .claude, enabled: false))

        let updated = CodexBarCLI.configSettingAPIKey(
            config,
            provider: .claude,
            apiKey: "xi-test-token",
            enableProvider: false)
        let provider = updated.providerConfig(for: .claude)

        #expect(provider?.sanitizedAPIKey == "xi-test-token")
        #expect(provider?.enabled == false)
    }

    @Test
    func `config set api key rejects ambiguous input`() {
        #expect(throws: CLIArgumentError.self) {
            try CodexBarCLI.resolveConfigAPIKeyInput(apiKey: "xi-test-token", readFromStdin: true)
        }
    }

    @Test
    func `config help documents set api key`() {
        let help = CodexBarCLI.configHelp(version: "0.0.0")

        #expect(help.contains("config set-api-key --provider <name>"))
        #expect(help.contains("config providers"))
        #expect(help.contains("config enable --provider <name>"))
        #expect(help.contains("config disable --provider <name>"))
        #expect(help.contains("--stdin"))
        #expect(help.contains("--usage-scope team"))
        #expect(help.contains("enables that provider by default"))
        #expect(help.contains("--show-secrets"))
    }

    @Test
    func `config dump parses show-secrets flag`() throws {
        let parser = CommandParser(signature: CodexBarCLI._configDumpSignatureForTesting())
        let parsed = try parser.parse(arguments: ["--show-secrets", "--pretty"])

        #expect(parsed.flags.contains("showSecrets"))
        #expect(parsed.flags.contains("pretty"))
    }

    @Test
    func `config dump redacts credentials by default`() {
        let rawAccount = ProviderTokenAccount(
            id: UUID(),
            label: "Team",
            token: "cb_test_token_123",
            addedAt: 1000,
            lastUsed: nil,
            usageScope: "team",
            organizationID: "org-1",
            workspaceID: "proj-1")
        let provider = ProviderConfig(
            id: .claude,
            apiKey: "cb_test_api_key_456",
            secretKey: "cb_test_secret_key_789",
            cookieHeader: "cb_test_cookie_abc",
            tokenAccounts: ProviderTokenAccountData(version: 1, accounts: [rawAccount], activeIndex: 0))
        let config = CodexBarConfig(providers: [provider])

        let redacted = config.sanitizedForDump(showSecrets: false)
        let redactedProvider = redacted.providerConfig(for: .claude)

        #expect(redactedProvider?.apiKey == "[REDACTED]")
        #expect(redactedProvider?.secretKey == "[REDACTED]")
        #expect(redactedProvider?.cookieHeader == "[REDACTED]")
        #expect(redactedProvider?.tokenAccounts?.accounts.first?.token == "[REDACTED]")
    }

    @Test
    func `config dump reveals credentials when show-secrets is true`() {
        let rawAccount = ProviderTokenAccount(
            id: UUID(),
            label: "Team",
            token: "cb_test_token_123",
            addedAt: 1000,
            lastUsed: nil,
            usageScope: "team",
            organizationID: "org-1",
            workspaceID: "proj-1")
        let provider = ProviderConfig(
            id: .claude,
            apiKey: "cb_test_api_key_456",
            secretKey: "cb_test_secret_key_789",
            cookieHeader: "cb_test_cookie_abc",
            tokenAccounts: ProviderTokenAccountData(version: 1, accounts: [rawAccount], activeIndex: 0))
        let config = CodexBarConfig(providers: [provider])

        let unredacted = config.sanitizedForDump(showSecrets: true)
        let unredactedProvider = unredacted.providerConfig(for: .claude)

        #expect(unredactedProvider?.apiKey == "cb_test_api_key_456")
        #expect(unredactedProvider?.secretKey == "cb_test_secret_key_789")
        #expect(unredactedProvider?.cookieHeader == "cb_test_cookie_abc")
        #expect(unredactedProvider?.tokenAccounts?.accounts.first?.token == "cb_test_token_123")
    }

    @Test
    func `config dump command redacts fixture secrets unless explicitly requested`() throws {
        let fixtureDirectory = TestFixtureScratch.root
            .appendingPathComponent("codexbar-config-dump-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureDirectory) }

        let secrets = [
            "fixture-api-key-value",
            "fixture-secret-key-value",
            "fixture-cookie-value",
            "fixture-token-account-value",
        ]
        let account = ProviderTokenAccount(
            id: UUID(),
            label: "Fixture account",
            token: secrets[3],
            addedAt: 1000,
            lastUsed: nil,
            usageScope: "team",
            organizationID: "fixture-org",
            workspaceID: "fixture-workspace")
        let config = CodexBarConfig(providers: [ProviderConfig(
            id: .claude,
            enabled: true,
            apiKey: secrets[0],
            secretKey: secrets[1],
            cookieHeader: secrets[2],
            tokenAccounts: ProviderTokenAccountData(version: 1, accounts: [account], activeIndex: 0))])
        let configURL = fixtureDirectory.appendingPathComponent("config.json")
        try CodexBarConfigStore(fileURL: configURL).save(config)

        let redactedData = try Self.runConfigDump(configURL: configURL, showSecrets: false)
        let redactedJSON = try JSONSerialization.jsonObject(with: redactedData)
        let redactedOutput = try #require(String(data: redactedData, encoding: .utf8))
        #expect(redactedJSON is [String: Any])
        #expect(redactedOutput.contains("[REDACTED]"))
        for secret in secrets {
            #expect(!redactedOutput.contains(secret))
        }

        let rawData = try Self.runConfigDump(configURL: configURL, showSecrets: true)
        let rawJSON = try JSONSerialization.jsonObject(with: rawData)
        let rawOutput = try #require(String(data: rawData, encoding: .utf8))
        #expect(rawJSON is [String: Any])
        for secret in secrets {
            #expect(rawOutput.contains(secret))
        }
    }

    private static func runConfigDump(configURL: URL, showSecrets: Bool) throws -> Data {
        let process = Process()
        process.executableURL = TestBuildProducts.executableURL(named: "CodexBarCLI")
        process.arguments = ["config", "dump"] + (showSecrets ? ["--show-secrets"] : [])
        process.environment = ProcessInfo.processInfo.environment.merging([
            CodexBarConfigStore.pathEnvironmentKey: configURL.path,
            // Spawned CLI binaries match no test-process name pattern; make the
            // keychain suppression explicit instead of relying on env inheritance.
            "CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS": "1",
        ]) { _, fixturePath in fixturePath }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorOutput, encoding: .utf8) ?? "CodexBarCLI exited without an error message"
            throw NSError(domain: "CLIConfigCommandTests", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: message,
            ])
        }
        return output
    }
}
