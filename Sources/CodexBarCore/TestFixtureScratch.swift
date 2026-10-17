import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

package enum TestFixtureScratch {
    package static let parentEnvironmentKey = "CODEXBAR_TEST_SCRATCH_PARENT"
    package static let workspaceEnvironmentKey = "CODEXBAR_TEST_WORKSPACE_ROOT"

    package enum ConfigurationError: Error, CustomStringConvertible {
        case invalid(String)

        package var description: String {
            switch self {
            case let .invalid(reason):
                "Test fixture scratch configuration: \(reason). Prepare an existing canonical workspace child "
                    + "and set CODEXBAR_TEST_WORKSPACE_ROOT and CODEXBAR_TEST_SCRATCH_PARENT before swift test."
            }
        }
    }

    // Borrowed for the process lifetime. The runner/caller alone owns this parent's cleanup.
    package static let root: URL = {
        do {
            return try TestFixtureScratch.resolve()
        } catch {
            fatalError(String(describing: error))
        }
    }()

    package static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> URL {
        let workspace = try self.canonicalDirectory(
            environment[self.workspaceEnvironmentKey], key: self.workspaceEnvironmentKey)
        let parent = try self.canonicalDirectory(
            environment[self.parentEnvironmentKey], key: self.parentEnvironmentKey)
        guard parent.pathComponents.count > workspace.pathComponents.count,
              parent.pathComponents.starts(with: workspace.pathComponents)
        else {
            throw ConfigurationError.invalid("scratch parent must be strictly inside the workspace")
        }
        return parent
    }

    private static func canonicalDirectory(_ raw: String?, key: String) throws -> URL {
        guard let raw, raw.hasPrefix("/"), !raw.contains("\n"), !raw.contains("\r"), !raw.contains("\0"),
              !raw.split(separator: "/").contains(".."), !raw.split(separator: "/").contains(".")
        else {
            throw ConfigurationError.invalid("missing or invalid \(key)")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: raw, isDirectory: &isDirectory), isDirectory.boolValue,
              let physical = realpath(raw, nil)
        else {
            throw ConfigurationError.invalid("\(key) must name an existing directory")
        }
        defer { free(physical) }
        guard String(cString: physical) == raw else {
            throw ConfigurationError.invalid("\(key) must be canonical and contain no symlink aliases")
        }
        return URL(fileURLWithPath: raw, isDirectory: true)
    }
}
