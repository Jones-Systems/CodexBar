import Foundation

public struct CAAMOperationReceipt: Codable, Sendable, Equatable {
    public let configuration: CAAMEnvironmentConfiguration
    public let operationID: UUID

    public init(configuration: CAAMEnvironmentConfiguration, operationID: UUID) {
        self.configuration = configuration
        self.operationID = operationID
    }
}

public protocol CAAMOperationReceiptStoring: Sendable {
    func load() async throws -> [CAAMOperationReceipt]
    func save(_ receipts: [CAAMOperationReceipt]) async throws
}

public actor CAAMMemoryReceiptStore: CAAMOperationReceiptStoring {
    private var receipts: [CAAMOperationReceipt]

    public init(receipts: [CAAMOperationReceipt] = []) {
        self.receipts = receipts
    }

    public func load() -> [CAAMOperationReceipt] { self.receipts }

    public func save(_ receipts: [CAAMOperationReceipt]) {
        self.receipts = receipts
    }
}

/// Actor-isolated bounded file IO, never on the UI actor. Stores selectors and operation IDs, not responses.
public actor CAAMFileReceiptStore: CAAMOperationReceiptStoring {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() throws -> [CAAMOperationReceipt] {
        guard FileManager.default.fileExists(atPath: self.url.path) else { return [] }
        let file = try FileHandle(forReadingFrom: self.url)
        defer { try? file.close() }
        let data = try file.read(upToCount: CAAMEnvironmentContract.maximumOutputBytes + 1) ?? Data()
        guard data.count <= CAAMEnvironmentContract.maximumOutputBytes else {
            throw CAAMControlFailure(reason: .oversized)
        }
        let receipts = try JSONDecoder().decode([CAAMOperationReceipt].self, from: data)
        _ = try CAAMEnvironmentContract.validateConfigurations(receipts.map(\.configuration))
        return receipts
    }

    public func save(_ receipts: [CAAMOperationReceipt]) throws {
        _ = try CAAMEnvironmentContract.validateConfigurations(receipts.map(\.configuration))
        let data = try JSONEncoder().encode(receipts)
        guard data.count <= CAAMEnvironmentContract.maximumOutputBytes else {
            throw CAAMControlFailure(reason: .oversized)
        }
        try FileManager.default.createDirectory(
            at: self.url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try data.write(to: self.url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: self.url.path)
    }
}
