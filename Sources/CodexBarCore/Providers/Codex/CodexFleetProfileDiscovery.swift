import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum CodexFleetProfileDiscovery {
    public enum Result: Equatable, Sendable {
        case available([String])
        case missing
        case unavailable(String)
    }

    public static let maximumBytes = 1024 * 1024

    public static func discover() -> Result {
        guard !TestProcessSafety.isRunningUnderTests(),
              ProcessInfo.processInfo.environment["CODEXBAR_TEST_CODEX_FILE_ISOLATION"] != "1"
        else { return .unavailable("Fleet discovery is disabled in tests") }
        return self.discover(actualHome: FileManager.default.homeDirectoryForCurrentUser, load: self.readBinding)
    }

    public static func discover(actualHome: URL, load: (URL, Int) throws -> Data?) -> Result {
        let url = actualHome.appendingPathComponent(".local/share/host-tooling/runtime/auth-fleet-binding.json")
        do {
            guard let data = try load(url, self.maximumBytes) else { return .missing }
            return self.parse(data: data, actualHome: actualHome)
        } catch {
            return .unavailable("Fleet binding cannot be read safely")
        }
    }

    public static func parse(data: Data, actualHome: URL) -> Result {
        guard data.count <= self.maximumBytes else { return .unavailable("Fleet binding exceeds size limit") }
        guard self.hasUniqueKeys(data),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys).isSubset(of: [
                  "schema",
                  "home",
                  "host_id",
                  "role",
                  "accounts",
                  "targets",
                  "runtime",
                  "os_username",
              ]),
              root["schema"] as? String == "host-tooling.auth-fleet-binding/v1",
              let home = root["home"] as? String,
              self.isCanonicalAbsolutePath(home), home == actualHome.standardizedFileURL.path,
              let hostID = root["host_id"] as? String, !hostID.isEmpty,
              let role = root["role"] as? String, ["controller", "node"].contains(role),
              let accounts = root["accounts"] as? [[String: Any]], !accounts.isEmpty
        else { return .unavailable("Fleet binding is invalid") }

        var homes: [String] = []
        var aliases: Set<String> = []
        for account in accounts {
            guard let provider = account["provider"] as? String else {
                return .unavailable("Fleet account provider is invalid")
            }
            if provider == "claude" { continue }
            guard provider == "codex",
                  Set(account.keys).isSubset(of: [
                      "provider",
                      "alias",
                      "store",
                      "config_dir",
                      "native_cli",
                      "path",
                      "metadata_path",
                  ]),
                  let alias = account["alias"] as? String, self.isSafeAlias(alias),
                  aliases.insert(alias).inserted,
                  account["store"] as? String == "codex-file",
                  let config = account["config_dir"] as? String,
                  config == home + "/.codex-t3/" + alias,
                  account["path"] as? String == config + "/auth.json",
                  let nativeCLI = account["native_cli"] as? String, self.isCanonicalAbsolutePath(nativeCLI)
            else { return .unavailable("Fleet Codex account is invalid") }
            homes.append(config)
        }
        return .available(homes)
    }

    private static func isCanonicalAbsolutePath(_ path: String) -> Bool {
        path.hasPrefix("/") && !path.contains("\0") && path != "/"
            && path.split(separator: "/", omittingEmptySubsequences: false).dropFirst().allSatisfy {
                !$0.isEmpty && $0 != "." && $0 != ".."
            }
    }

    private static func isSafeAlias(_ alias: String) -> Bool {
        !alias.isEmpty && alias != "." && alias != ".."
            && alias.utf8.allSatisfy {
                (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
                    || $0 == 45 || $0 == 95 || $0 == 46
            }
    }

    private static func hasUniqueKeys(_ data: Data) -> Bool {
        let bytes = Array(data)
        var objects: [Set<String>] = []
        var index = 0
        while index < bytes.count {
            switch bytes[index] {
            case 123:
                guard objects.count < 64 else { return false }
                objects.append([])
            case 125:
                guard !objects.isEmpty else { return false }
                objects.removeLast()
            case 34:
                let start = index
                index += 1
                while index < bytes.count, bytes[index] != 34 {
                    if bytes[index] == 92 { index += 1 }
                    index += 1
                }
                guard index < bytes.count else { return false }
                var next = index + 1
                while next < bytes.count, [9, 10, 13, 32].contains(bytes[next]) {
                    next += 1
                }
                if next < bytes.count, bytes[next] == 58 {
                    guard !objects.isEmpty,
                          let key = try? JSONDecoder().decode(String.self, from: Data(bytes[start...index])),
                          objects[objects.count - 1].insert(key).inserted
                    else { return false }
                }
            default: break
            }
            index += 1
        }
        return objects.isEmpty
    }

    private enum ReadError: Error { case unsafeBinding }

    static func readBinding(url: URL, maximumBytes: Int) throws -> Data? {
        guard self.isCanonicalAbsolutePath(url.path) else { throw ReadError.unsafeBinding }
        var directory = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw ReadError.unsafeBinding }
        defer { close(directory) }
        let components = url.path.split(separator: "/").map(String.init)
        for component in components.dropLast() {
            let next = openat(directory, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else {
                if errno == ENOENT { return nil }
                throw ReadError.unsafeBinding
            }
            close(directory)
            directory = next
        }
        let descriptor = openat(directory, components.last!, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else {
            if errno == ENOENT { return nil }
            throw ReadError.unsafeBinding
        }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_mode & 0o7777 == 0o600,
              info.st_uid == getuid(), info.st_nlink == 1,
              info.st_size >= 0, info.st_size <= off_t(maximumBytes)
        else { throw ReadError.unsafeBinding }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = buffer.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
            if count < 0 {
                if errno == EINTR { continue }
                throw ReadError.unsafeBinding
            }
            if count == 0 { return data }
            guard data.count + count <= maximumBytes else { throw ReadError.unsafeBinding }
            data.append(contentsOf: buffer.prefix(count))
        }
    }
}
