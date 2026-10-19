import Foundation
import Security
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct ClaudeNativeKeychainProfileTests {
    private static let environment = ["CLAUDE_CONFIG_DIR": "/synthetic/home/.claude-t3/jace"]
    private static let selectedService = "Claude Code-credentials-9a9e7cae"

    private final class QueryFixture: @unchecked Sendable {
        private let lock = NSLock()
        private var services: [String] = []
        let selectedPresent: Bool

        init(selectedPresent: Bool = true) {
            self.selectedPresent = selectedPresent
        }

        func read(_ query: [String: Any]) -> (OSStatus, AnyObject?) {
            if let service = query[kSecAttrService as String] as? String {
                self.lock.withLock { self.services.append(service) }
                guard service == "Claude Code-credentials" || self.selectedPresent else {
                    return (errSecItemNotFound, nil)
                }
                if query[kSecReturnData as String] as? Bool == true {
                    return (errSecSuccess, Self.payload(service: service) as NSData)
                }
                let row: [String: Any] = [
                    kSecValuePersistentRef as String: Data(service.utf8),
                    kSecAttrAccount as String: "synthetic-account",
                    kSecAttrModificationDate as String: Date(timeIntervalSince1970: 100),
                ]
                if query[kSecMatchLimit as String] as? String == kSecMatchLimitAll as String {
                    return (errSecSuccess, [row] as NSArray)
                }
                return (errSecSuccess, row as NSDictionary)
            }
            guard let reference = query[kSecValuePersistentRef as String] as? Data,
                  let service = String(data: reference, encoding: .utf8)
            else { return (errSecItemNotFound, nil) }
            self.lock.withLock { self.services.append(service) }
            return (errSecSuccess, Self.payload(service: service) as NSData)
        }

        func observedServices() -> [String] {
            self.lock.withLock { self.services }
        }

        static func payload(service: String) -> Data {
            Data("""
            {"claudeAiOauth":{"accessToken":"synthetic-\(service)","expiresAt":4102444800000,
            "scopes":["user:profile"]}}
            """.utf8)
        }
    }

    private func withNativeFixture<T>(
        _ fixture: QueryFixture,
        operation: () throws -> T) rethrows -> T
    {
        let queryOverride: @Sendable ([String: Any]) -> (OSStatus, AnyObject?) = { query in
            fixture.read(query)
        }
        return try ClaudeOAuthDirectKeychainReadConsent.withTaskOverrideForTesting(true) {
            try KeychainAccessGate.withTaskOverrideForTesting(false) {
                try ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(.always) {
                    try ClaudeOAuthKeychainReadStrategyPreference.withTaskOverrideForTesting(.securityFramework) {
                        try ProviderInteractionContext.$current.withValue(.userInitiated) {
                            try ClaudeOAuthCredentialsStore.withClaudeKeychainFingerprintStoreOverrideForTesting(
                                .init())
                            {
                                try ClaudeOAuthKeychainQueryTiming.$queryOverrideForTesting.withValue(queryOverride) {
                                    try KeychainAccessPreflight.withCheckGenericPasswordOverrideForTesting { _, _ in
                                        .allowed
                                    } operation: {
                                        try operation()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @Test
    func `native reads preflight fingerprints and history stay within selected service`() throws {
        let fixture = QueryFixture()
        try self.withNativeFixture(fixture) {
            let data = try ClaudeOAuthCredentialsStore.loadFromClaudeKeychain(environment: Self.environment)
            let credentials = try ClaudeOAuthCredentials.parse(data: data)
            #expect(credentials.accessToken == "synthetic-" + Self.selectedService)
            #expect(ClaudeOAuthCredentialsStore.hasClaudeKeychainCredentialsWithoutPrompt(
                environment: Self.environment))
            #expect(ClaudeOAuthCredentialsStore.readRawClaudeKeychainPayloadViaSecurityFrameworkWithoutPrompt(
                environment: Self.environment) == data)
            #expect(ClaudeOAuthCredentialsStore.currentClaudeKeychainFingerprintWithoutPromptForAuthGate(
                environment: Self.environment)?.persistentRefHash != nil)
            let record = ClaudeOAuthCredentialRecord(
                credentials: credentials, owner: .claudeCLI, source: .claudeKeychain)
            #expect(ClaudeOAuthCredentialsStore.matchingClaudeKeychainPersistentRefHashWithoutPrompt(
                for: record, environment: Self.environment) != nil)
            let other = try ClaudeOAuthCredentials.parse(data: QueryFixture.payload(service: "Claude Code-credentials"))
            let otherRecord = ClaudeOAuthCredentialRecord(credentials: other, owner: .claudeCLI, source: .memoryCache)
            #expect(ClaudeOAuthCredentialsStore.claudeKeychainCredentialMatchWithoutPrompt(
                for: otherRecord, environment: Self.environment) == .mismatch)
            #expect(ClaudeOAuthCredentialsStore.consumeClaudeKeychainFingerprintChangeWithoutPrompt(environment: [:]))
            #expect(!ClaudeOAuthCredentialsStore.claudeKeychainFingerprintChangedWithoutConsuming(
                environment: Self.environment))
        }
        // The explicit default-profile fingerprint read above is the only permitted default query.
        #expect(fixture.observedServices().count(where: { $0 == "Claude Code-credentials" }) == 1)
        #expect(Set(fixture.observedServices()) == [Self.selectedService, "Claude Code-credentials"])

        var preflightServices: [String] = []
        self.withNativeFixture(QueryFixture()) {
            KeychainAccessPreflight.withCheckGenericPasswordOverrideForTesting { service, _ in
                preflightServices.append(service)
                return .allowed
            } operation: {
                #expect(ClaudeOAuthCredentialsStore.preferredClaudeKeychainAccountForSecurityCLIRead(
                    interaction: .userInitiated, environment: Self.environment) == "synthetic-account")
            }
        }
        #expect(preflightServices == [Self.selectedService])
    }

    @Test
    func `missing named service never falls back to available default credentials`() {
        let fixture = QueryFixture(selectedPresent: false)
        self.withNativeFixture(fixture) {
            #expect(throws: ClaudeOAuthCredentialsError.self) {
                try ClaudeOAuthCredentialsStore.loadFromClaudeKeychain(environment: Self.environment)
            }
            #expect(ClaudeOAuthCredentialsStore.readRawClaudeKeychainPayloadViaSecurityFrameworkWithoutPrompt(
                environment: Self.environment) == nil)
            #expect(ClaudeOAuthCredentialsStore.claudeKeychainPersistentRefHashWithoutPrompt(
                environment: Self.environment) == nil)
        }
        #expect(!fixture.observedServices().isEmpty)
        #expect(Set(fixture.observedServices()) == [Self.selectedService])
    }

    @Test
    func `concurrent native readers cannot inherit another task selected service`() async {
        let environments = [[:], Self.environment]
        let observed = await withTaskGroup(of: String?.self, returning: Set<String>.self) { group in
            for environment in environments {
                group.addTask {
                    self.withNativeFixture(QueryFixture()) {
                        guard let data = ClaudeOAuthCredentialsStore
                            .readRawClaudeKeychainPayloadViaSecurityFrameworkWithoutPrompt(environment: environment)
                        else { return nil }
                        return try? ClaudeOAuthCredentials.parse(data: data).accessToken
                    }
                }
            }
            var tokens = Set<String>()
            for await token in group {
                if let token { tokens.insert(token) }
            }
            return tokens
        }
        #expect(observed == ["synthetic-Claude Code-credentials", "synthetic-" + Self.selectedService])
    }

    @Test
    func `recovery populates only the selected native profile cache`() throws {
        let fixture = QueryFixture()
        let service = "com.steipete.codexbar.cache.native-profile-tests.\(UUID().uuidString)"
        try self.withNativeFixture(fixture) {
            try KeychainCacheStore.withServiceOverrideForTesting(service) {
                KeychainCacheStore.setTestStoreForTesting(true)
                defer { KeychainCacheStore.setTestStoreForTesting(false) }
                try ClaudeOAuthCredentialsStore.withIsolatedMemoryCacheForTesting {
                    try ClaudeOAuthCredentialsStore.withIsolatedCredentialsFileTrackingForTesting {
                        #expect(ClaudeOAuthCredentialsStore.syncFromClaudeKeychainWithoutPrompt(
                            environment: Self.environment))
                        let record = try ClaudeOAuthCredentialsStore.loadRecord(
                            environment: Self.environment,
                            allowKeychainPrompt: false)
                        #expect(record.owner == .claudeCLI)
                        #expect(record.credentials.accessToken == "synthetic-" + Self.selectedService)
                        #expect(!ClaudeOAuthCredentialsStore.hasCachedCredentials(environment: [:]))
                    }
                }
            }
        }
        #expect(!fixture.observedServices().isEmpty)
        #expect(Set(fixture.observedServices()) == [Self.selectedService])
    }

    @Test
    func `named service does not bypass revoked direct read consent`() {
        let fixture = QueryFixture()
        self.withNativeFixture(fixture) {
            ClaudeOAuthDirectKeychainReadConsent.withTaskOverrideForTesting(false) {
                #expect(ClaudeOAuthCredentialsStore.readRawClaudeKeychainPayloadViaSecurityFrameworkWithoutPrompt(
                    environment: Self.environment) == nil)
                #expect(ClaudeOAuthCredentialsStore.hasClaudeKeychainCredentialsWithoutPrompt(
                    environment: Self.environment) == false)
            }
        }
        #expect(fixture.observedServices().isEmpty)
    }
}
