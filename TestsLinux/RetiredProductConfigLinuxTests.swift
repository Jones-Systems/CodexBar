import Foundation
import Testing
@testable import CodexBarCore

struct RetiredProductConfigLinuxTests {
    @Test
    func `retired providers are skipped before their malformed credentials can affect retained providers`() throws {
        let data = Data(#"""
        {
          "version": 1,
          "providers": [
            {"id":"cursor","enabled":true,"apiKey":{"obsolete":"retired-secret"},"source":[]},
            {"id":"codex","enabled":true,"cookieHeader":"codex-fixture-cookie"},
            {"id":"fixture-plugin","enabled":true,"tokenAccounts":"obsolete-secret-shape"},
            {"id":"claude","enabled":false,"apiKey":"claude-fixture-key"}
          ],
          "hooks": {"enabled":true,"rules":"obsolete-rule-shape"}
        }
        """#.utf8)
        let config = try JSONDecoder().decode(CodexBarConfig.self, from: data).normalized()

        #expect(config.providers.map(\.id) == [.codex, .claude])
        #expect(config.providerConfig(for: .codex)?.cookieHeader == "codex-fixture-cookie")
        #expect(config.providerConfig(for: .codex)?.apiKey == nil)
        #expect(config.providerConfig(for: .claude)?.apiKey == "claude-fixture-key")
        #expect(config.providerConfig(for: .claude)?.cookieHeader == nil)
        #expect(config.providerConfig(for: .claude)?.enabled == false)
        let encoded = try JSONEncoder().encode(config)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["hooks"] == nil)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("retired-secret"))
    }

    @Test
    func `obsolete plugin settings and secrets are inert even when their old value types are invalid`() throws {
        let data = Data(#"""
        {
          "version":1,
          "providers":[
            {"id":"codex","enabled":false,"pluginSettings":17,"pluginSecrets":["retired-secret"]},
            {"id":"claude","enabled":true,"pluginSettings":false,"pluginSecrets":{"token":"retired-secret"}}
          ],
          "hooks":["obsolete-hook-shape"]
        }
        """#.utf8)
        let config = try JSONDecoder().decode(CodexBarConfig.self, from: data)
        let encoded = try JSONEncoder().encode(config)
        let json = String(decoding: encoded, as: UTF8.self)

        #expect(config.enabledProviders() == [.claude])
        #expect(!json.contains("pluginSettings"))
        #expect(!json.contains("pluginSecrets"))
        #expect(!json.contains("retired-secret"))
        #expect(!json.contains("hooks"))
    }

    @Test
    func `normalization discards programmatic retired IDs without transferring credentials`() throws {
        let retiredID = try #require(ProviderInstanceID(rawValue: "cursor"))
        let config = CodexBarConfig(providers: [
            ProviderConfig(id: retiredID, enabled: true, apiKey: "retired-fixture-key"),
            ProviderConfig(id: .claude, enabled: false),
        ]).normalized()

        #expect(Set(config.providers.map(\.id)) == [.codex, .claude])
        #expect(config.providers.allSatisfy { $0.apiKey == nil })
        #expect(config.providerConfig(for: .claude)?.enabled == false)
    }
}
