import Foundation
import Testing
@testable import CodexBarCore

struct ClaudeNativeProfileCredentialCacheIsolationTests {
    @Test
    func `one memory slot preserves credential ownership across A B A`() throws {
        try self.withIsolatedCache { root in
            let environment = ["HOME": root.path]
            let profiles = ["synthetic-profile-a", "synthetic-profile-b"]
            defer { self.clearEntries(profiles) }
            self.seed(profile: profiles[0], token: "synthetic-a")
            self.seed(profile: profiles[1], token: "synthetic-b")

            for (profile, token) in [
                (profiles[0], "synthetic-a"),
                (profiles[1], "synthetic-b"),
                (profiles[0], "synthetic-a"),
            ] {
                try ClaudeOAuthCredentialsStore.withCredentialsProfileIdentifierOverrideForTesting(profile) {
                    let switched = try self.load(environment)
                    #expect(switched.credentials.accessToken == token)
                    #expect(switched.source == .cacheKeychain)
                    let repeated = try self.load(environment)
                    #expect(repeated.credentials.accessToken == token)
                    #expect(repeated.source == .memoryCache)
                }
            }
        }
    }

    @Test
    func `missing side profile cannot borrow the selected profile memory record`() throws {
        try self.withIsolatedCache { root in
            let environment = ["HOME": root.path]
            let selected = "synthetic-selected"
            let missing = "synthetic-missing"
            defer { self.clearEntries([selected, missing]) }
            self.seed(profile: selected, token: "synthetic-selected-token")

            try ClaudeOAuthCredentialsStore.withCredentialsProfileIdentifierOverrideForTesting(selected) {
                _ = try self.load(environment)
                #expect(try self.load(environment).source == .memoryCache)
                ClaudeOAuthCredentialsStore.withCredentialsProfileIdentifierOverrideForTesting(missing) {
                    #expect(throws: ClaudeOAuthCredentialsError.self) {
                        try self.load(environment)
                    }
                }
                let resumed = try self.load(environment)
                #expect(resumed.credentials.accessToken == "synthetic-selected-token")
                #expect(resumed.source == .cacheKeychain)
            }
        }
    }

    @Test(arguments: ["default", "jace"])
    func `native selected main and serial side fetch use separate cache identities`(selectedAlias: String) throws {
        try self.withIsolatedCache { root in
            let discovery = ClaudeFleetProfileDiscovery.Result.available([
                .init(
                    alias: "default",
                    home: root.path,
                    configDirectory: nil,
                    nativeCLI: root.appendingPathComponent("claude").path,
                    store: "claude-keychain"),
                .init(
                    alias: "jace",
                    home: root.path,
                    configDirectory: root.appendingPathComponent(".claude-t3/jace").path,
                    nativeCLI: root.appendingPathComponent("claude").path,
                    store: "claude-keychain"),
            ])
            let selected = ClaudeNativeProfileSelection.environment(
                base: [:], alias: selectedAlias, discovery: discovery)
            let sideAlias = selectedAlias == "default" ? "jace" : "default"
            let side = ClaudeNativeProfileSelection.environment(base: selected, alias: sideAlias, discovery: discovery)
            let selectedID = ClaudeOAuthCredentialsStore.credentialsProfileIdentifier(environment: selected)
            let sideID = ClaudeOAuthCredentialsStore.credentialsProfileIdentifier(environment: side)
            #expect(selectedID != sideID)
            #expect(selected[ClaudeNativeProfileSelection.selectionKey] == selectedAlias)
            #expect(side[ClaudeNativeProfileSelection.selectionKey] == sideAlias)
            #expect((selectedAlias == "default" ? selected : side)["CLAUDE_CONFIG_DIR"] == nil)
            defer { self.clearEntries([selectedID, sideID]) }
            self.seed(profile: selectedID, token: "synthetic-main")
            self.seed(profile: sideID, token: "synthetic-side")

            for (environment, token) in [
                (selected, "synthetic-main"),
                (side, "synthetic-side"),
                (selected, "synthetic-main"),
            ] {
                let switched = try self.load(environment)
                #expect(switched.credentials.accessToken == token)
                #expect(switched.source == .cacheKeychain)
                #expect(switched.owner == .claudeCLI)
                try ClaudeNativeProfileSelection.validateCredentialOwner(switched.owner, environment: environment)
                let repeated = try self.load(environment)
                #expect(repeated.credentials.accessToken == token)
                #expect(repeated.source == .memoryCache)
            }
            #expect(selected[ClaudeNativeProfileSelection.selectionKey] == selectedAlias)
            #expect(ClaudeOAuthCredentialsStore.credentialsProfileIdentifier(environment: selected) == selectedID)
        }
    }

    private func load(_ environment: [String: String]) throws -> ClaudeOAuthCredentialRecord {
        try ClaudeOAuthCredentialsStore.loadRecord(
            environment: environment,
            allowKeychainPrompt: false,
            allowClaudeKeychainRepairWithoutPrompt: false)
    }

    private func seed(profile: String, token: String) {
        let expiry = Int(Date(timeIntervalSinceNow: 3600).timeIntervalSince1970 * 1000)
        let data = Data("""
        {"claudeAiOauth":{"accessToken":"\(token)","expiresAt":\(expiry),"scopes":["user:profile"]}}
        """.utf8)
        #expect(KeychainCacheStore.storeResult(
            key: ClaudeOAuthCredentialsStore.cacheKeyForTesting(profileIdentifier: profile),
            entry: ClaudeOAuthCredentialsStore.CacheEntry(
                data: data, storedAt: Date(), owner: .claudeCLI, profileIdentifier: profile)))
    }

    private func clearEntries(_ profiles: [String]) {
        for profile in profiles {
            let key = ClaudeOAuthCredentialsStore.cacheKeyForTesting(profileIdentifier: profile)
            _ = KeychainCacheStore.clear(key: key)
            guard case .missing = KeychainCacheStore.load(key: key, as: ClaudeOAuthCredentialsStore.CacheEntry.self)
            else {
                Issue.record("Synthetic profile cache entry survived cleanup")
                continue
            }
        }
    }

    private func withIsolatedCache(_ operation: (URL) throws -> Void) throws {
        let root = TestFixtureScratch.root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let marker = ClaudeOAuthCredentialsStore.DirectKeychainReadConsentRevocationMarkerStore()
        try KeychainCacheStore.withServiceOverrideForTesting("native-profile-isolation-" + UUID().uuidString) {
            try KeychainCacheStore.withImplicitTestStoreForTesting {
                try KeychainAccessGate.withTaskOverrideForTesting(true) {
                    try ClaudeOAuthCredentialsStore.withKeychainAccessOverrideForTesting(true) {
                        try ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(.onlyOnUserAction) {
                            try ClaudeOAuthCredentialsStore
                                .withDirectKeychainReadConsentRevocationMarkerStoreForTesting(
                                    marker)
                                {
                                    try ClaudeOAuthCredentialsStore.withEnvironmentCredentialsURLForTesting {
                                        try ClaudeOAuthCredentialsStore.withIsolatedCredentialsFileTrackingForTesting {
                                            try ClaudeOAuthCredentialsStore.withIsolatedMemoryCacheForTesting {
                                                try operation(root)
                                            }
                                        }
                                    }
                                }
                        }
                    }
                }
            }
        }
    }
}
