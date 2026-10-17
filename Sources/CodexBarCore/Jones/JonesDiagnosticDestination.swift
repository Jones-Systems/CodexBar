import Foundation

/// Fork-owned exports retained with application logs, not task scratch. No age-based cleanup is scheduled.
/// Callers keep their existing overwrite/reset behavior; timestamped exports remain until explicitly removed.
public struct JonesDiagnosticDestination: Sendable {
    public let url: URL
    public let isRetained: Bool

    private init(url: URL, isRetained: Bool) {
        self.url = url
        self.isRetained = isRetained
    }

    /// Without packaged identity, preserve the exact legacy URL without consulting the user's log roots.
    public static func resolve(
        legacyURL: URL,
        identity: JonesStateRoot.Identity? = JonesStateRoot.identity,
        libraryDirectory: () -> URL? = {
            FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        },
        homeDirectory: () -> URL = { FileManager.default.homeDirectoryForCurrentUser }) -> Self
    {
        guard identity != nil else { return Self(url: legacyURL, isRetained: false) }
        let library = libraryDirectory() ?? homeDirectory().appendingPathComponent("Library", isDirectory: true)
        let directory = library.appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(JonesStateRoot.path("CodexBar", identity: identity), isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
        return Self(url: directory.appendingPathComponent(legacyURL.lastPathComponent), isRetained: true)
    }

    /// A failed log-directory creation must never redirect an export to shared temporary storage.
    public func prepareDirectory(
        createDirectory: (URL) throws -> Void = {
            try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
        }) throws
    {
        guard self.isRetained else { return }
        try createDirectory(self.url.deletingLastPathComponent())
    }

    public func write(
        _ text: String,
        createDirectory: (URL) throws -> Void = {
            try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
        },
        writeText: (String, URL) throws -> Void = {
            try $0.write(to: $1, atomically: true, encoding: .utf8)
        }) throws
    {
        try self.prepareDirectory(createDirectory: createDirectory)
        try writeText(text, self.url)
    }
}
