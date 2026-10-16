import Foundation

/// Packaged identity only: environment variables cannot silently opt a process into shared state.
public enum JonesStateRoot {
    public struct Identity: Sendable, Equatable {
        public let bundleID: String
        public let groupID: String
        public let teamID: String
        public let iCloudID: String

        public init(bundleID: String, groupID: String, teamID: String, iCloudID: String) {
            self.bundleID = bundleID
            self.groupID = groupID
            self.teamID = teamID
            self.iCloudID = iCloudID
        }
    }

    public static let identity: Identity? = resolveIdentity(
        info: Bundle.main.infoDictionary ?? [:],
        executableURL: Bundle.main.executableURL?.resolvingSymlinksInPath(),
        readInfo: { url in
            guard let data = try? Data(contentsOf: url),
                  let value = try? PropertyListSerialization.propertyList(from: data, format: nil)
            else { return nil }
            return value as? [String: Any]
        })

    public static func identity(info: [String: Any]) -> Identity? {
        guard let key = info["JonesStateKey"] as? String else { return nil }
        precondition(key == "jones", "Unsupported packaged Jones state key")
        func value(_ key: String) -> String {
            guard let value = info[key] as? String, !value.isEmpty else {
                preconditionFailure("Missing packaged Jones identity field: \(key)")
            }
            return value
        }
        return Identity(
            bundleID: value("JonesAppBundleID"), groupID: value("JonesAppGroupID"),
            teamID: value("CodexBarTeamID"), iCloudID: value("JonesICloudID"))
    }

    /// A bundled CLI has no Info.plist of its own. Read only its enclosing app's metadata.
    public static func resolveIdentity(
        info: [String: Any], executableURL: URL?, readInfo: (URL) -> [String: Any]?) -> Identity?
    {
        if let identity = self.identity(info: info) { return identity }
        guard var parent = executableURL?.deletingLastPathComponent() else { return nil }
        for _ in 0..<6 {
            if parent.pathExtension == "app" {
                return readInfo(parent.appendingPathComponent("Contents/Info.plist")).flatMap(self.identity(info:))
            }
            let next = parent.deletingLastPathComponent()
            guard next != parent else { break }
            parent = next
        }
        return nil
    }

    /// Applies only at inventoried CodexBar-owned path sites, never to provider homes.
    public static func path(_ legacy: String, identity: Identity? = Self.identity) -> String {
        guard identity != nil else { return legacy }
        return legacy.split(separator: "/", omittingEmptySubsequences: false).map { component in
            switch component {
            case "CodexBar", "com.steipete.codexbar": "CodexBar Jones"
            case ".codexbar": ".codexbar-jones"
            case "codexbar": "codexbar-jones"
            default: String(component)
            }
        }.joined(separator: "/")
    }

    public static func configURL(home: URL, identity: Identity? = Self.identity) -> URL? {
        guard identity != nil else { return nil }
        return home.appendingPathComponent(".codexbar-jones/config.json")
    }

    public static func namespace(_ legacy: String, identity: Identity? = Self.identity) -> String {
        guard let identity else { return legacy }
        // Preserve the original service name in full: differently cased legacy stores stay distinct.
        return identity.bundleID + ".service." + legacy
    }

    public static func defaultsDomains(_ legacy: [String], identity: Identity? = Self.identity) -> [String] {
        identity.map { [$0.bundleID] } ?? legacy
    }
}
