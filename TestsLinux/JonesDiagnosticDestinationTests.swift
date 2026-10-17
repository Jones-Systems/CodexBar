import Foundation
import Testing
@testable import CodexBarCore

struct JonesDiagnosticDestinationTests {
    private enum FixtureError: Error, Equatable {
        case directoryDenied
        case writeDenied
    }

    private static let identity = JonesStateRoot.Identity(
        bundleID: "com.example.fixture", groupID: "FIXTURE.com.example.fixture",
        teamID: "FIXTURE", iCloudID: "iCloud.com.example.fixture")
    private static let filenames = [
        "codexbar-claude-probe.txt",
        "codexbar-codex-probe.txt",
        "codexbar-buy-credits.log",
        "codex-openai-dashboard-1234.html",
        "codex-openai-dashboard-1234.txt",
    ]
    private static let temporaryDirectory = URL(fileURLWithPath: "/synthetic/temp", isDirectory: true)
    private static let libraryDirectory = URL(fileURLWithPath: "/synthetic/library", isDirectory: true)
    private static let retainedDirectory = libraryDirectory.appendingPathComponent(
        "Logs/CodexBar Jones/Diagnostics", isDirectory: true)

    @Test(arguments: Self.filenames)
    func `no overlay preserves exact URLs and never consults or creates log roots`(_ filename: String) throws {
        let legacy = Self.temporaryDirectory.appendingPathComponent(filename)
        var rootLookups = 0
        let destination = JonesDiagnosticDestination.resolve(
            legacyURL: legacy, identity: nil,
            libraryDirectory: { rootLookups += 1; return Self.libraryDirectory },
            homeDirectory: { rootLookups += 1; return URL(fileURLWithPath: "/synthetic/home") })
        var created: [URL] = []
        var writes: [URL: String] = [:]
        try destination.write(
            "fixture", createDirectory: { created.append($0) },
            writeText: { writes[$1] = $0 })

        #expect(destination.url == legacy)
        #expect(!destination.isRetained)
        #expect(rootLookups == 0)
        #expect(created.isEmpty)
        #expect(writes == [legacy: "fixture"])
    }

    @Test(arguments: Self.filenames)
    func `overlay changes every export parent and preserves filenames`(_ filename: String) {
        let legacy = Self.temporaryDirectory.appendingPathComponent(filename)
        var homeLookups = 0
        let destination = JonesDiagnosticDestination.resolve(
            legacyURL: legacy, identity: Self.identity,
            libraryDirectory: { Self.libraryDirectory },
            homeDirectory: { homeLookups += 1; return URL(fileURLWithPath: "/synthetic/home") })

        #expect(destination.isRetained)
        #expect(destination.url == Self.retainedDirectory.appendingPathComponent(filename))
        #expect(destination.url.lastPathComponent == legacy.lastPathComponent)
        #expect(destination.url.deletingLastPathComponent() != legacy.deletingLastPathComponent())
        #expect(homeLookups == 0)
    }

    @Test
    func `missing platform Library uses the injected home log root`() {
        let destination = JonesDiagnosticDestination.resolve(
            legacyURL: Self.temporaryDirectory.appendingPathComponent("codexbar-buy-credits.log"),
            identity: Self.identity, libraryDirectory: { nil },
            homeDirectory: { URL(fileURLWithPath: "/synthetic/home", isDirectory: true) })

        #expect(
            destination.url.path == "/synthetic/home/Library/Logs/CodexBar Jones/Diagnostics/codexbar-buy-credits.log")
        #expect(destination.isRetained)
    }

    @Test
    func `retained writes create their parent first and leave stock artifacts untouched`() throws {
        let legacy = Self.temporaryDirectory.appendingPathComponent("codexbar-claude-probe.txt")
        let destination = Self.destination(legacy)
        var files = [legacy: "stock sentinel"]
        var events: [String] = []
        try destination.write(
            "synthetic probe",
            createDirectory: { directory in
                #expect(directory == Self.retainedDirectory)
                events.append("create")
            },
            writeText: { text, url in
                #expect(events == ["create"])
                files[url] = text
                events.append("write")
            })

        #expect(events == ["create", "write"])
        #expect(files == [legacy: "stock sentinel", destination.url: "synthetic probe"])
    }

    @Test(arguments: Self.filenames)
    func `directory failure propagates without a write or shared fallback`(_ filename: String) {
        let destination = Self.destination(Self.temporaryDirectory.appendingPathComponent(filename))
        var created: [URL] = []
        var writes: [URL] = []
        #expect(throws: FixtureError.directoryDenied) {
            try destination.write(
                "fixture",
                createDirectory: { directory in
                    created.append(directory)
                    throw FixtureError.directoryDenied
                },
                writeText: { _, url in writes.append(url) })
        }

        #expect(created == [Self.retainedDirectory])
        #expect(writes.isEmpty)
    }

    @Test(arguments: Self.filenames)
    func `write failure propagates without retrying another destination`(_ filename: String) {
        let legacy = Self.temporaryDirectory.appendingPathComponent(filename)
        let destination = Self.destination(legacy)
        var created: [URL] = []
        var writes: [URL] = []
        #expect(throws: FixtureError.writeDenied) {
            try destination.write(
                "fixture", createDirectory: { created.append($0) },
                writeText: { _, url in
                    writes.append(url)
                    throw FixtureError.writeDenied
                })
        }

        #expect(created == [Self.retainedDirectory])
        #expect(writes == [destination.url])
        #expect(!writes.contains(legacy))
    }

    @Test
    func `append preparation uses the same retained parent and propagates failure`() throws {
        let destination = Self.destination(Self.temporaryDirectory.appendingPathComponent("codexbar-buy-credits.log"))
        var created: [URL] = []
        try destination.prepareDirectory(createDirectory: { created.append($0) })
        #expect(created == [Self.retainedDirectory])
        #expect(throws: FixtureError.directoryDenied) {
            try destination.prepareDirectory(createDirectory: { directory in
                #expect(directory == Self.retainedDirectory)
                throw FixtureError.directoryDenied
            })
        }
    }

    @Test
    func `stock write errors are preserved without creating a new directory`() {
        let legacy = Self.temporaryDirectory.appendingPathComponent("codexbar-codex-probe.txt")
        let destination = JonesDiagnosticDestination.resolve(legacyURL: legacy, identity: nil)
        var created: [URL] = []
        var writes: [URL] = []
        #expect(throws: FixtureError.writeDenied) {
            try destination.write(
                "fixture", createDirectory: { created.append($0) },
                writeText: { _, url in
                    writes.append(url)
                    throw FixtureError.writeDenied
                })
        }

        #expect(created.isEmpty)
        #expect(writes == [legacy])
    }

    private static func destination(_ legacy: URL) -> JonesDiagnosticDestination {
        JonesDiagnosticDestination.resolve(
            legacyURL: legacy, identity: self.identity,
            libraryDirectory: { self.libraryDirectory },
            homeDirectory: { URL(fileURLWithPath: "/synthetic/home") })
    }
}
