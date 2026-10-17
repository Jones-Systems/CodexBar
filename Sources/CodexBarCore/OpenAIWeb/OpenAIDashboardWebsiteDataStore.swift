#if os(macOS)
import Foundation
import WebKit

/// Per-account persistent `WKWebsiteDataStore` for the OpenAI dashboard scrape.
///
/// Why: `WKWebsiteDataStore.default()` is a single shared cookie jar. If the user switches Codex accounts,
/// we want to keep multiple signed-in dashboard sessions around (one per email) without clearing cookies.
///
/// Implementation detail: macOS 14+ supports `WKWebsiteDataStore.dataStore(forIdentifier:)`, which creates
/// persistent isolated stores keyed by an identifier. We derive a stable UUID from the email and optional
/// Codex source scope so distinct profiles with the same email never share a cookie store. Packaged
/// Jones identities add a fork namespace, including a persistent store for the no-account case.
///
/// Important: We cache the `WKWebsiteDataStore` instances so the same object is returned for the same
/// account email. This ensures `OpenAIDashboardWebViewCache` can use object identity for cache lookups.
@MainActor
public enum OpenAIDashboardWebsiteDataStore {
    /// Cached data store instances keyed by fork identity, normalized email and optional Codex source scope.
    /// Using the same instance ensures stable object identity for WebView cache lookups.
    private static var cachedStores: [String: WKWebsiteDataStore] = [:]

    public static func store(
        forAccountEmail email: String?,
        scope: CookieHeaderCache.Scope? = nil) -> WKWebsiteDataStore
    {
        guard let storageKey = self.storageKey(forAccountEmail: email, scope: scope) else { return .default() }

        // Return cached instance if available to maintain stable object identity
        if let cached = cachedStores[storageKey] {
            return cached
        }

        let id = JonesFrameworkIsolation.websiteDataStoreIdentifier(forStorageKey: storageKey)
        let store = WKWebsiteDataStore(forIdentifier: id)
        self.cachedStores[storageKey] = store
        return store
    }

    /// Clears the persistent cookie store for a single account email.
    ///
    /// Note: this does *not* impact other accounts, and is safe to use when the stored session is "stuck"
    /// or signed in to a different account than expected.
    public static func clearStore(
        forAccountEmail email: String?,
        scope: CookieHeaderCache.Scope? = nil) async
    {
        // Clear only ChatGPT/OpenAI domain data for the per-account store.
        // Avoid deleting the entire persistent store (WebKit requires all WKWebViews using it to be released).
        let store = self.store(forAccountEmail: email, scope: scope)
        await withCheckedContinuation { cont in
            store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
                let filtered = records.filter { record in
                    let name = record.displayName.lowercased()
                    return name.contains("chatgpt.com") || name.contains("openai.com")
                }
                store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: filtered) {
                    cont.resume()
                }
            }
        }

        // Remove from cache so a fresh instance is created on next access
        if let storageKey = self.storageKey(forAccountEmail: email, scope: scope) {
            self.cachedStores.removeValue(forKey: storageKey)
        }
    }

    #if DEBUG
    /// Clear all cached store instances (for test isolation).
    public static func clearCacheForTesting() {
        self.cachedStores.removeAll()
    }

    #endif

    // MARK: - Private

    private static func storageKey(forAccountEmail email: String?, scope: CookieHeaderCache.Scope?) -> String? {
        JonesFrameworkIsolation.openAIDashboardStorageKey(
            forAccountEmail: email,
            scope: scope,
            identity: JonesStateRoot.identity)
    }
}
#endif
