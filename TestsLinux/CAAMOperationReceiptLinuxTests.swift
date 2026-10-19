import Foundation
import Testing
@testable import CodexBarCore

struct CAAMOperationReceiptLinuxTests {
    @Test
    func `receipt survives restart and binds complete configuration without raw results`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("receipts.json")
        let receipt = CAAMOperationReceipt(
            configuration: CAAMControlFixtures.configuration, operationID: CAAMControlFixtures.operationID)
        let store = CAAMFileReceiptStore(url: url)
        try await store.save([receipt])
        let restarted = CAAMFileReceiptStore(url: url)
        #expect(try await restarted.load() == [receipt])
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        #expect(Set(object[0].keys) == ["configuration", "operationID"])
        try await restarted.save([])
        #expect(try await store.load().isEmpty)
    }

    @Test
    func `oversized corrupt and duplicate receipt files fail closed`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("receipts.json")
        let store = CAAMFileReceiptStore(url: url)
        let receipt = CAAMOperationReceipt(
            configuration: CAAMControlFixtures.configuration, operationID: CAAMControlFixtures.operationID)
        let duplicate = try JSONEncoder().encode([receipt, receipt])
        for data in [Data(repeating: 32, count: 65537), Data("invalid fixture".utf8), duplicate] {
            try data.write(to: url)
            do {
                _ = try await store.load()
                Issue.record("Expected receipt storage rejection")
            } catch {
                #expect(!(error.localizedDescription.isEmpty))
            }
        }
    }
}
