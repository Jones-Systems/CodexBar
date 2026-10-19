#if os(macOS)
import CryptoKit
import Foundation

/// Pure framework identifiers; callers own store creation and packaged identity resolution.
enum JonesFrameworkIsolation {
    static func openAIDashboardStorageKey(
        forAccountEmail email: String?,
        scope: CookieHeaderCache.Scope?,
        identity: JonesStateRoot.Identity?) -> String?
    {
        let trimmed = email?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.flatMap { $0.isEmpty ? nil : $0.lowercased() }
        guard let identity else {
            guard let normalized else { return nil }
            guard let scope else { return normalized }
            return "\(normalized)|\(scope.isolationIdentifier)"
        }

        // Length framing keeps identity/account/scope boundaries unambiguous, including absent values.
        let components = [
            identity.bundleID, identity.groupID, identity.teamID, identity.iCloudID,
            normalized == nil ? "no-account" : "account", normalized ?? "",
            scope == nil ? "no-scope" : "scope", scope?.isolationIdentifier ?? "",
        ]
        let framed = components.map { "\($0.utf8.count):\($0)" }.joined()
        let digest = SHA256.hash(data: Data(framed.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return "jones.openai-dashboard.v1:\(digest)"
    }

    /// Retains the stock SHA-256-to-UUID mapping for unmodified legacy storage keys.
    static func websiteDataStoreIdentifier(forStorageKey storageKey: String) -> UUID {
        let digest = SHA256.hash(data: Data(storageKey.utf8))
        var bytes = Array(digest.prefix(16))

        // Keep the existing v4 and RFC4122 variant bits even though the value is deterministic.
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        let uuidBytes: uuid_t = (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15])
        return UUID(uuid: uuidBytes)
    }
}
#endif
