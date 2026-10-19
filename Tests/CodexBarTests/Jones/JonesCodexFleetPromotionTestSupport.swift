import CodexBarCore
import Foundation
@testable import CodexBar

@MainActor
final class JonesFleetMembershipFixture {
    var paths: [String]?
    var reads = 0

    init(_ paths: [String]?) {
        self.paths = paths
    }

    func load() -> [String]? {
        self.reads += 1
        return self.paths
    }
}

final class JonesRecordingAuthReader: CodexAuthMaterialReading, @unchecked Sendable {
    private let lock = NSLock()
    private var reads: [URL] = []
    let unreadableHome: URL?

    init(unreadableHome: URL? = nil) {
        self.unreadableHome = unreadableHome
    }

    var readHomes: [URL] {
        self.lock.withLock { self.reads }
    }

    func readAuthData(homeURL: URL) throws -> Data? {
        self.lock.withLock { self.reads.append(homeURL) }
        if homeURL == self.unreadableHome { throw CocoaError(.fileReadNoPermission) }
        return try DefaultCodexAuthMaterialReader().readAuthData(homeURL: homeURL)
    }
}

@MainActor
final class JonesRecordingSnapshotLoader: CodexAccountReconciliationSnapshotLoading {
    var reads = 0

    func loadSnapshot() -> CodexAccountReconciliationSnapshot {
        self.reads += 1
        return CodexAccountReconciliationSnapshot(
            storedAccounts: [],
            activeStoredAccount: nil,
            liveSystemAccount: nil,
            matchingStoredAccountForLiveSystemAccount: nil,
            activeSource: .liveSystem,
            hasUnreadableAddedAccountStore: false)
    }
}

@MainActor
final class JonesRecordingActiveSourceWriter: CodexActiveSourceWriting {
    var sources: [CodexActiveSource] = []
    func writeCodexActiveSource(_ source: CodexActiveSource) {
        self.sources.append(source)
    }
}

func jonesFleetTarget(_ profile: ObservedSystemCodexAccount) throws -> JonesCodexSystemPromotionTarget {
    guard let target = JonesCodexFleetPromotionTarget(profile: profile, fleetHomePaths: [profile.codexHomePath]) else {
        throw PromotionTestError.unexpectedDisposition
    }
    return .fleetProfile(target)
}

@MainActor
func jonesWaitForWriter(_ writer: CodexSharedAuthWriter) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while ContinuousClock.now < deadline {
        if writer._test_waitingWriterCount == 1 { return true }
        await Task.yield()
    }
    return writer._test_waitingWriterCount == 1
}

/// Supplies the ordinary home seam without consulting the invoking user's real home.
final class JonesSyntheticHomeFileManager: FileManager, @unchecked Sendable {
    private let syntheticHome: URL

    init(home: URL) {
        self.syntheticHome = home
        super.init()
    }

    override var homeDirectoryForCurrentUser: URL {
        self.syntheticHome
    }
}
