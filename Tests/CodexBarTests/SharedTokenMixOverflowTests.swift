import Foundation
import Testing
@testable import CodexBarCore

struct SharedTokenMixOverflowTests {
    @Test
    func `shared token mix overflow cannot revive on a third day`() throws {
        var mix = CostUsageTokenMix(inputTokens: Int.max - 1, outputTokens: 2)
        mix.merge(CostUsageTokenMix(inputTokens: 2, outputTokens: 3))
        mix.merge(CostUsageTokenMix(inputTokens: 7, outputTokens: 4))
        #expect(mix.inputTokens == nil)
        #expect(mix.outputTokens == 9)
        var receiver = CostUsageTokenMix(inputTokens: 4)
        receiver.merge(mix)
        #expect(receiver.inputTokens == nil)
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(mix)) as? [String: Any])
        #expect(object["overflowedClasses"] == nil)
        var absent = CostUsageTokenMix()
        absent.merge(CostUsageTokenMix(inputTokens: 8))
        absent.merge(CostUsageTokenMix())
        #expect(absent.inputTokens == 8)
    }
}
