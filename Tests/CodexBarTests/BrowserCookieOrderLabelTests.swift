import SweetCookieKit
import Testing
@testable import CodexBarCore

struct BrowserCookieOrderStatusStringTests {
    #if os(macOS)
    @Test
    func `codex cookie import order keeps firefox ahead of extra chromium browsers`() {
        let order = ProviderDefaults.metadata[.codex]?.browserCookieOrder ?? Browser.defaultImportOrder
        #expect(Array(order.prefix(3)) == [.safari, .chrome, .firefox])
    }

    @Test
    func `automatic cookie import includes newly supported chromium browsers`() {
        #expect(Browser.defaultImportOrder.contains(.comet))
        #expect(Browser.defaultImportOrder.contains(.yandex))
    }

    @Test
    func `claude cookie import prefers chrome without dropping fallback browsers`() throws {
        let order = try #require(ProviderDefaults.metadata[.claude]?.browserCookieOrder)

        #expect(order.first == .chrome)
        #expect(order.count == Browser.defaultImportOrder.count)
        #expect(Set(order) == Set(Browser.defaultImportOrder))
    }

    #endif
}
