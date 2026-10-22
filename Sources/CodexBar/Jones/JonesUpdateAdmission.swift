import Foundation

enum JonesUpdateAdmission {
    struct Candidate: Equatable, Sendable {
        let archiveURL: URL?
        let archiveLength: UInt64?
        let isDelta: Bool
        let installationType: String
    }

    struct Capacity: Equatable, Sendable {
        var appVolume: Int64?
        var cacheVolume: Int64?

        static let unknown = Self(appVolume: nil, cacheVolume: nil)

        /// These observations reserve no space and do not bound Sparkle's actual downloaded bytes.
        static func read(appURL: URL, cacheURL: URL) -> Self {
            Self(appVolume: Self.available(at: appURL), cacheVolume: Self.available(at: cacheURL))
        }

        private static func available(at url: URL) -> Int64? {
            guard url.isFileURL else { return nil }
            return try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                .volumeAvailableCapacityForImportantUsage
        }
    }

    enum Rejection: Error, Equatable, Sendable {
        case unknownLength
        case archiveTooLarge
        case unknownAppCapacity
        case unknownCacheCapacity
        case insufficientAppCapacity(required: Int64)
        case insufficientCacheCapacity(required: Int64)
        case unsupportedDelta
        case unsupportedInstallationType
    }

    static let maximumArchiveLength: UInt64 = 256 * 1024 * 1024
    static let reserveBytes: Int64 = 1024 * 1024 * 1024

    static func validate(archiveLength: UInt64?, capacity: Capacity) throws -> Int64 {
        guard let archiveLength, archiveLength > 0 else { throw Rejection.unknownLength }
        guard archiveLength <= Self.maximumArchiveLength else { throw Rejection.archiveTooLarge }
        // The length bound precedes arithmetic, including the conversion from Sparkle's UInt64.
        let required = 4 * Int64(archiveLength) + Self.reserveBytes
        guard let app = capacity.appVolume, app >= 0 else { throw Rejection.unknownAppCapacity }
        guard let cache = capacity.cacheVolume, cache >= 0 else { throw Rejection.unknownCacheCapacity }
        guard app >= required else { throw Rejection.insufficientAppCapacity(required: required) }
        guard cache >= required else { throw Rejection.insufficientCacheCapacity(required: required) }
        return required
    }
}
