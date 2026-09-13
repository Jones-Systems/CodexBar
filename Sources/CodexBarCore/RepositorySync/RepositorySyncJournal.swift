import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Musl)
import Musl
#else
import Glibc
#endif

/// Private, bounded, process-locked intent storage. Creation is explicit; a missing existing store fails closed.
/// The caller owns the directory and its ancestors. Never point this store into a repository working tree.
public actor RepositorySyncJournal {
    private let directoryFD: Int32
    private static let maximumBytes = 1048576
    private static let maximumRecords = 256

    public init(directory: URL, createNew: Bool = false) throws {
        guard directory.isFileURL else { throw RepositorySyncError.journalUnavailable }
        let descriptor = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw RepositorySyncError.journalUnavailable }
        do {
            try Self.check(descriptor, directory: true)
            let flags = O_RDWR | O_NOFOLLOW | O_CLOEXEC | (createNew ? O_CREAT | O_EXCL : 0)
            let lock = openat(descriptor, "operations.lock", flags, mode_t(0o600))
            guard lock >= 0 else { throw RepositorySyncError.journalUnavailable }
            defer { _ = close(lock) }
            try Self.check(lock)
            guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw RepositorySyncError.journalUnavailable }
            defer { _ = flock(lock, LOCK_UN) }
            if createNew {
                var info = stat()
                guard fstatat(descriptor, "operations.json", &info, AT_SYMLINK_NOFOLLOW) == -1, errno == ENOENT
                else { throw RepositorySyncError.journalUnavailable }
                try Self.persist([], directory: descriptor)
            } else {
                _ = try Self.load(directory: descriptor)
            }
            self.directoryFD = descriptor
        } catch {
            _ = close(descriptor)
            throw error
        }
    }

    deinit { _ = close(self.directoryFD) }

    public func record(_ operationID: UUID) throws -> RepositorySyncRecord? {
        try self.transaction { records in records.first { $0.plan.operationID == operationID } }
    }

    /// True grants the only dispatch. False means same intent already exists: lookup only, never execute again.
    func reserve(_ plan: RepositorySyncPlan) throws -> Bool {
        try plan.validate(at: plan.createdAt)
        return try self.transaction { records in
            if let existing = records.first(where: { $0.plan.operationID == plan.operationID }) {
                guard existing.plan == plan else { throw RepositorySyncError.operationConflict }
                return false
            }
            guard !records.contains(where: {
                !$0.state.isTerminal && $0.plan.snapshot.target.overlaps(plan.snapshot.target)
            }) else { throw RepositorySyncError.resourceBusy }
            guard records.count < Self.maximumRecords else { throw RepositorySyncError.journalCapacity }
            if plan.action == .rollback {
                guard let original = records.first(where: { $0.plan.operationID == plan.originalOperationID })
                else { throw RepositorySyncError.rollbackUnavailable }
                let expected = try RepositorySyncPlan.rollback(
                    original: original,
                    snapshot: plan.snapshot,
                    operationID: plan.operationID,
                    now: plan.createdAt)
                guard plan == expected else { throw RepositorySyncError.rollbackUnavailable }
            }
            records.append(RepositorySyncRecord(plan: plan))
            return true
        }
    }

    func setState(_ state: RepositorySyncState, for operationID: UUID) throws -> RepositorySyncRecord {
        try self.transaction { records in
            guard let index = records.firstIndex(where: { $0.plan.operationID == operationID })
            else { throw RepositorySyncError.unknownOperation }
            if records[index].state == .conflicted {
                return records[index]
            }
            if records[index].state.isTerminal {
                if state.isTerminal, records[index].state != state { records[index].state = .conflicted }
            } else {
                records[index].state = state
            }
            return records[index]
        }
    }

    func requestCancellation(_ operationID: UUID) throws -> RepositorySyncRecord {
        try self.transaction { records in
            guard let index = records.firstIndex(where: { $0.plan.operationID == operationID })
            else { throw RepositorySyncError.unknownOperation }
            if !records[index].state.isTerminal { records[index].cancellationRequested = true }
            return records[index]
        }
    }

    private func transaction<T>(_ body: (inout [RepositorySyncRecord]) throws -> T) throws -> T {
        try Self.check(self.directoryFD, directory: true)
        let lock = openat(self.directoryFD, "operations.lock", O_RDWR | O_NOFOLLOW | O_CLOEXEC)
        guard lock >= 0 else { throw RepositorySyncError.journalUnavailable }
        defer { _ = close(lock) }
        try Self.check(lock)
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw RepositorySyncError.journalUnavailable }
        defer { _ = flock(lock, LOCK_UN) }
        var records = try Self.load(directory: self.directoryFD)
        let previous = records
        let result = try body(&records)
        if records != previous { try Self.persist(records, directory: self.directoryFD) }
        return result
    }

    private struct Contents: Codable {
        let version: Int
        let records: [RepositorySyncRecord]
    }

    private static func check(_ descriptor: Int32, directory: Bool = false) throws {
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_uid == geteuid(), info.st_mode & 0o077 == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(directory ? S_IFDIR : S_IFREG),
              directory || info.st_nlink == 1
        else { throw RepositorySyncError.journalUnavailable }
    }

    private static func load(directory: Int32) throws -> [RepositorySyncRecord] {
        let descriptor = openat(directory, "operations.json", O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw RepositorySyncError.journalUnavailable }
        defer { _ = close(descriptor) }
        try Self.check(descriptor)
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_size > 0, info.st_size <= Self.maximumBytes
        else { throw RepositorySyncError.journalUnavailable }
        var data = Data(count: Int(info.st_size))
        let complete = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            var offset = 0
            while offset < buffer.count {
                let count = read(descriptor, base.advanced(by: offset), buffer.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { return false }
                offset += count
            }
            var extra: UInt8 = 0
            return read(descriptor, &extra, 1) == 0
        }
        guard complete else { throw RepositorySyncError.journalUnavailable }
        do {
            let contents = try JSONDecoder().decode(Contents.self, from: data)
            let records = contents.records
            guard contents.version == 1, records.count <= Self.maximumRecords,
                  Set(records.map(\.plan.operationID)).count == records.count
            else { throw RepositorySyncError.journalUnavailable }
            for record in records { try record.plan.validate(at: record.plan.createdAt) }
            return records
        } catch {
            throw RepositorySyncError.journalUnavailable
        }
    }

    private static func persist(_ records: [RepositorySyncRecord], directory: Int32) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Contents(version: 1, records: records))
        guard records.count <= Self.maximumRecords, data.count <= Self.maximumBytes
        else { throw RepositorySyncError.journalCapacity }
        let temporary = "intent-" + UUID().uuidString + ".tmp"
        let descriptor = openat(
            directory,
            temporary,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            mode_t(0o600))
        guard descriptor >= 0 else { throw RepositorySyncError.journalUnavailable }
        defer {
            _ = close(descriptor)
            _ = unlinkat(directory, temporary, 0)
        }
        let complete = data.withUnsafeBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            var offset = 0
            while offset < buffer.count {
                let count = write(descriptor, base.advanced(by: offset), buffer.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { return false }
                offset += count
            }
            return true
        }
        guard complete, fsync(descriptor) == 0,
              renameat(directory, temporary, directory, "operations.json") == 0,
              fsync(directory) == 0
        else { throw RepositorySyncError.journalUnavailable }
    }
}
