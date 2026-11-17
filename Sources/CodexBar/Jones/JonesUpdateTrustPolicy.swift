import CoreFoundation
import Foundation

struct JonesUpdateTrustPolicy: Equatable, Sendable {
    enum Identity: Equatable, Sendable {
        case production
        case harness
    }

    enum Channel: String, Sendable {
        case none
        case stable
    }

    enum BuildOrigin: String, Sendable {
        case local
        case pullRequest = "ci-pr"
        case main = "ci-main"
    }

    enum Rejection: Error, Equatable, Sendable {
        case identity
        case sourceRevision
        case buildOrigin
        case buildRun
        case channel
        case disabledConfiguration
        case feedURL
        case publicKey
        case upstreamTrust
        case signedFeedRequired
        case verificationBeforeExtractionRequired
        case signedFeedExpiryMustBeZero
        case bundleMismatch
    }

    static let productionBundleID = "com.jonessystems.codexbar"
    static let harnessBundleID = "com.jonessystems.codexbar.update-harness"
    static let stableFeedURL = "https://github.com/Jones-Systems/CodexBar/releases/latest/download/appcast.xml"
    static let upstreamPublicKey = "AGCY8w5vHirVfGGDGc8Szc5iuOqupZSh9pMj/Qs67XI="

    let identity: Identity
    let channel: Channel
    let sourceRevision: String
    let buildOrigin: BuildOrigin
    let buildRun: String
    let feedURL: URL?
    let publicKey: String?

    var isEnabled: Bool {
        self.channel == .stable
    }

    private init(
        identity: Identity,
        channel: Channel,
        sourceRevision: String,
        buildOrigin: BuildOrigin,
        buildRun: String,
        feedURL: URL?,
        publicKey: String?)
    {
        self.identity = identity
        self.channel = channel
        self.sourceRevision = sourceRevision
        self.buildOrigin = buildOrigin
        self.buildRun = buildRun
        self.feedURL = feedURL
        self.publicKey = publicKey
    }

    static func validate(infoDictionary info: [String: Any]) throws -> Self {
        let identity = try self.validateIdentity(info)
        guard let revision = info["JonesSourceRevision"] as? String,
              revision.utf8.count == 40,
              revision.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
        else { throw Rejection.sourceRevision }
        guard let rawOrigin = info["JonesBuildOrigin"] as? String,
              let origin = BuildOrigin(rawValue: rawOrigin)
        else { throw Rejection.buildOrigin }
        guard let run = info["JonesBuildRun"] as? String,
              origin == .local ? run.isEmpty : self.isCanonicalBuildRun(run)
        else { throw Rejection.buildRun }
        guard let rawChannel = info["JonesUpdateChannel"] as? String,
              let channel = Channel(rawValue: rawChannel)
        else { throw Rejection.channel }

        guard let feed = info["SUFeedURL"] as? String, let key = info["SUPublicEDKey"] as? String else {
            throw Rejection.disabledConfiguration
        }
        if channel == .none {
            guard feed.isEmpty, key.isEmpty else { throw Rejection.disabledConfiguration }
            return Self(
                identity: identity,
                channel: channel,
                sourceRevision: revision,
                buildOrigin: origin,
                buildRun: run,
                feedURL: nil,
                publicKey: nil)
        }

        guard key != self.upstreamPublicKey else { throw Rejection.upstreamTrust }
        guard let decoded = Data(base64Encoded: key), decoded.count == 32,
              decoded.base64EncodedString() == key
        else { throw Rejection.publicKey }
        let feedURL = try self.validateURL(feed, identity: identity)
        guard identity == .harness || feed == self.stableFeedURL else { throw Rejection.feedURL }
        guard self.plistBoolean(info["SURequireSignedFeed"]) == true else {
            throw Rejection.signedFeedRequired
        }
        guard self.plistBoolean(info["SUVerifyUpdateBeforeExtraction"]) == true else {
            throw Rejection.verificationBeforeExtractionRequired
        }
        guard let expiry = info["SUSignedFeedFailureExpirationInterval"] as? NSNumber,
              CFGetTypeID(expiry) != CFBooleanGetTypeID(), expiry.doubleValue == 0
        else { throw Rejection.signedFeedExpiryMustBeZero }
        return Self(
            identity: identity,
            channel: channel,
            sourceRevision: revision,
            buildOrigin: origin,
            buildRun: run,
            feedURL: feedURL,
            publicKey: key)
    }

    /// Bind an injected policy to the actual host package before constructing Sparkle.
    func validateHostBundle(_ bundle: Bundle) throws {
        guard let info = bundle.infoDictionary, bundle.bundleURL.pathExtension == "app",
              try Self.validate(infoDictionary: info) == self
        else { throw Rejection.bundleMismatch }
    }

    func validateArchiveURL(_ url: URL?) throws {
        guard let url else { throw Rejection.feedURL }
        _ = try Self.validateURL(url.absoluteString, identity: self.identity)
    }

    private static func validateIdentity(_ info: [String: Any]) throws -> Identity {
        if info["CFBundleIdentifier"] as? String == self.harnessBundleID {
            guard self.plistBoolean(info["JonesUpdateHarness"]) == true,
                  info["JonesStateKey"] == nil
            else { throw Rejection.identity }
            return .harness
        }
        let signingMode = info["JonesSigningMode"] as? String ?? "adhoc"
        let team: String
        switch signingMode {
        case "adhoc": team = "JONESLOCAL"
        case "developer-id":
            team = "2CUPSQS986"
            // The new app group requires a separately qualified bootstrap before updates can be enabled.
            guard info["JonesUpdateChannel"] as? String == "none" else { throw Rejection.channel }
        default: throw Rejection.identity
        }
        guard info["JonesSigningMode"] == nil || info["JonesSigningMode"] is String,
              info["CFBundleIdentifier"] as? String == self.productionBundleID,
              info["JonesAppBundleID"] as? String == self.productionBundleID,
              info["CFBundleDisplayName"] as? String == "CodexBar Jones",
              info["JonesStateKey"] as? String == "jones",
              info["CodexBarTeamID"] as? String == team,
              info["JonesAppGroupID"] as? String == "\(team).com.jonessystems.codexbar",
              info["JonesICloudID"] as? String == "iCloud.com.jonessystems.codexbar",
              info["JonesUpdateHarness"] == nil, info["JonesUpdateHarnessFixtureID"] == nil
        else { throw Rejection.identity }
        return .production
    }

    private static func validateURL(_ value: String, identity: Identity) throws -> URL {
        guard value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              let components = URLComponents(string: value), let url = components.url,
              let host = components.host?.lowercased(), !host.isEmpty,
              components.user == nil, components.password == nil, components.fragment == nil,
              !components.path.isEmpty
        else { throw Rejection.feedURL }
        let scheme = components.scheme?.lowercased()
        if identity == .harness {
            guard scheme == "http", host == "127.0.0.1",
                  components.port.map({ (1...65535).contains($0) }) ?? true
            else { throw Rejection.feedURL }
            return url
        }
        guard scheme == "https", components.port == nil || components.port == 443,
              host != "localhost", !host.hasSuffix(".localhost"),
              host != "::1", host != "[::1]", host != "0.0.0.0", !host.hasPrefix("127.")
        else { throw Rejection.feedURL }

        // The sealed package selects the Jones endpoint; no defaults or environment can replace it.
        let path = components.path.lowercased()
        guard host != "codexbar.app", !host.hasSuffix(".codexbar.app"),
              !["github.com", "raw.githubusercontent.com", "api.github.com"].contains(host)
              || !(path.hasPrefix("/steipete/") || path.hasPrefix("/repos/steipete/"))
        else { throw Rejection.upstreamTrust }
        return url
    }

    private static func isCanonicalBuildRun(_ value: String) -> Bool {
        guard let url = URLComponents(string: value), url.scheme == "https", url.host == "github.com",
              url.user == nil, url.password == nil, url.port == nil, url.query == nil, url.fragment == nil
        else { return false }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 6, parts[0].isEmpty, parts[1] == "Jones-Systems", parts[2] == "CodexBar",
              parts[3] == "actions", parts[4] == "runs", !parts[5].isEmpty
        else { return false }
        return parts[5].utf8.allSatisfy { (48...57).contains($0) }
    }

    private static func plistBoolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
}
