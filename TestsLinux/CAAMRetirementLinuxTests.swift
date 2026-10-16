import Foundation
import Testing
@testable import CodexBarCore

struct CAAMRetirementLinuxTests {
    @Test
    func `legacy environment field remains inert unknown config while native settings survive`() throws {
        let data = Data(#"""
        {"version":1,"providers":[{"id":"codex",
          "codexCAAMEnvironments":[{"id":"retired","connection":{"unexpected":"unvalidated legacy value"}}],
          "codexProfileHomePaths":["/synthetic/profile"],
          "codexAccountOrder":["profile:/synthetic/profile"]}]}
        """#.utf8)
        let config = try JSONDecoder().decode(CodexBarConfig.self, from: data)
        let provider = try #require(config.providerConfig(for: .codex))
        #expect(provider.codexProfileHomePaths == ["/synthetic/profile"])
        #expect(provider.codexAccountOrder == ["profile:/synthetic/profile"])
        let encoded = try JSONEncoder().encode(config)
        let original = try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
        let roundTrip = try #require(JSONSerialization.jsonObject(with: encoded) as? NSDictionary)
        #expect(original == roundTrip)
    }
}
