import Foundation

enum CodexStatusProbeIsolation {
    static func supportDirectory(environment: [String: String]) throws -> URL {
        let temporaryOverride = environment["TMPDIR"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL: URL
        if TestProcessSafety.isRunningUnderTests()
            || ProcessInfo.processInfo.environment["CODEXBAR_TEST_CODEX_FILE_ISOLATION"] == "1"
        {
            let parent = TestFixtureScratch.root
            if let temporaryOverride,
               URL(fileURLWithPath: temporaryOverride).pathComponents.starts(with: parent.pathComponents),
               let contained = try? TestFixtureScratch.resolve(environment: [
                   TestFixtureScratch.workspaceEnvironmentKey: parent.path,
                   TestFixtureScratch.parentEnvironmentKey: temporaryOverride,
               ])
            {
                baseURL = contained
            } else {
                baseURL = parent
            }
        } else if let temporaryOverride, !temporaryOverride.isEmpty {
            baseURL = URL(fileURLWithPath: temporaryOverride, isDirectory: true)
        } else {
            baseURL = FileManager.default.temporaryDirectory
        }

        let directory = baseURL
            .appendingPathComponent(JonesStateRoot.path("CodexBar"), isDirectory: true) // JONES(trial-identity)
            .appendingPathComponent("CodexStatusProbe", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func workingDirectory(environment: [String: String]) -> URL? {
        let home = environment["HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let home, !home.isEmpty else { return nil }
        return URL(fileURLWithPath: home, isDirectory: true)
    }

    static func codexArguments(stateHome: URL) -> [String] {
        [
            "-s",
            "read-only",
            "-a",
            "never",
            "-c",
            "history.persistence=\"none\"",
            "-c",
            "experimental_thread_store={type=\"in_memory\",id=\"codexbar-status\"}",
            "-c",
            "sqlite_home=\"\(self.tomlEscaped(stateHome.path))\"",
        ]
    }

    private static func tomlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
