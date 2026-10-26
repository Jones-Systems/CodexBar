import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

struct CodexCLIBackendConfigurationTests {
    private static let authenticationError =
        "Codex connection failed: codex account authentication required to read rate limits"

    @Test
    func `normal openai config keeps authentication failure unchanged`() throws {
        let config = try Self.fixture(named: "codex-config-openai")

        let classified = CodexCLIBackendRateLimitError.classify(
            errorDescription: Self.authenticationError,
            configContents: config)

        #expect(classified == nil)
        #expect(
            CodexUIErrorMapper.userFacingMessage(Self.authenticationError) ==
                "Codex CLI is not signed in. Run `codex login --device-auth`, then refresh.")
    }

    private static func fixture(named name: String) throws -> String {
        let url = try #require(Bundle.module.url(
            forResource: name,
            withExtension: "toml",
            subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }
}
