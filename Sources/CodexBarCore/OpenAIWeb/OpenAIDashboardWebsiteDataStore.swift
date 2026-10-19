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
    private static let cache = StoreCache(
        defaultStore: { WKWebsiteDataStore.default() },
        identifiedStore: { WKWebsiteDataStore(forIdentifier: $0) })

    public static func store(
        forAccountEmail email: String?,
        scope: CookieHeaderCache.Scope? = nil) -> WKWebsiteDataStore
    {
        self.cache.store(forAccountEmail: email, scope: scope, identity: JonesStateRoot.identity)
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
        self.cache.removeStore(forAccountEmail: email, scope: scope, identity: JonesStateRoot.identity)
    }

    #if DEBUG
    /// Drops cached store references only; persisted website data is not removed.
    public static func clearCacheForTesting() {
        self.cache.removeAll()
    }

    #endif

    /// Instance-owned lookup logic shared by production and synthetic fixtures.
    /// Both constructors and the lookup identity are explicit so fixtures never need live store defaults.
    @MainActor
    final class StoreCache {
        private let defaultStore: () -> WKWebsiteDataStore
        private let identifiedStore: (UUID) -> WKWebsiteDataStore
        /// Keys include fork identity, normalized email and optional Codex source scope.
        private var cachedStores: [String: WKWebsiteDataStore] = [:]

        init(
            defaultStore: @escaping () -> WKWebsiteDataStore,
            identifiedStore: @escaping (UUID) -> WKWebsiteDataStore)
        {
            self.defaultStore = defaultStore
            self.identifiedStore = identifiedStore
        }

        func store(
            forAccountEmail email: String?,
            scope: CookieHeaderCache.Scope? = nil,
            identity: JonesStateRoot.Identity?) -> WKWebsiteDataStore
        {
            guard let storageKey = JonesFrameworkIsolation.openAIDashboardStorageKey(
                forAccountEmail: email, scope: scope, identity: identity)
            else { return self.defaultStore() }

            // Stable object identity is required by the WebView cache.
            if let cached = self.cachedStores[storageKey] {
                return cached
            }

            let id = JonesFrameworkIsolation.websiteDataStoreIdentifier(forStorageKey: storageKey)
            let store = self.identifiedStore(id)
            self.cachedStores[storageKey] = store
            return store
        }

        func removeStore(
            forAccountEmail email: String?,
            scope: CookieHeaderCache.Scope? = nil,
            identity: JonesStateRoot.Identity?)
        {
            if let storageKey = JonesFrameworkIsolation.openAIDashboardStorageKey(
                forAccountEmail: email, scope: scope, identity: identity)
            {
                self.cachedStores.removeValue(forKey: storageKey)
            }
        }

        func removeAll() {
            self.cachedStores.removeAll()
        }
    }
}
#endif
