import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// The menu app's System Account uses the ordinary home; explicit profile requests remain scoped separately.
public enum JonesCodexAppLaunchEnvironment {
    public static func variablesToRemove(environment: [String: String], fleetHomePaths: [String]) -> [String] {
        guard let inheritedHome = self.normalizedPath(environment["CODEX_HOME"]),
              fleetHomePaths.compactMap({ self.normalizedPath($0) }).count(where: { $0 == inheritedHome }) == 1
        else { return [] }

        var names = ["CODEX_HOME"]
        if self.normalizedPath(environment["CODEX_SQLITE_HOME"]) == inheritedHome {
            names.append("CODEX_SQLITE_HOME")
        }
        return names
    }

    /// Invoke only at the application entrypoint, before settings and provider consumers are initialized.
    public static func prepareForApplication(fleetHomePaths: [String]) {
        for name in self.variablesToRemove(
            environment: ProcessInfo.processInfo.environment,
            fleetHomePaths: fleetHomePaths)
        {
            unsetenv(name)
        }
    }

    private static func normalizedPath(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, (value as NSString).isAbsolutePath
        else { return nil }
        return URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL.path
    }
}
