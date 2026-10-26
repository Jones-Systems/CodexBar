#if os(macOS)
import Foundation
import Testing
@testable import CodexBarCore

/// Identifier-only fixtures: no WebKit store, file, network, or packaged-identity lookup.
struct JonesFrameworkIsolationTests {
    @Test
    func `fork cache keys remain bounded with long synthetic inputs`() throws {
        let key = try #require(JonesFrameworkIsolation.openAIDashboardStorageKey(
            forAccountEmail: String(repeating: "x", count: 16384) + "@example.com",
            scope: .profileHome("/fixture/" + String(repeating: "y", count: 16384)),
            identity: Self.fixtureIdentity()))
        #expect(key.utf8.count == 90)
        #expect(JonesFrameworkIsolation.websiteDataStoreIdentifier(forStorageKey: key).uuidString.count == 36)
    }

    @Test
    func `stock email keeps its exact cache key and UUID`() throws {
        let key = try #require(JonesFrameworkIsolation.openAIDashboardStorageKey(
            forAccountEmail: " SHARED@EXAMPLE.COM \n",
            scope: nil,
            identity: nil))

        #expect(key == "shared@example.com")
        #expect(JonesFrameworkIsolation.websiteDataStoreIdentifier(forStorageKey: key).uuidString
            == "CC61BD27-6855-439F-9D11-F470B7977B90")
    }

    @Test
    func `stock scoped account keeps its exact cache key and UUID`() throws {
        let scope = try CookieHeaderCache.Scope.managedAccount(
            #require(UUID(uuidString: "11111111-2222-4333-8444-555555555555")))
        let key = try #require(JonesFrameworkIsolation.openAIDashboardStorageKey(
            forAccountEmail: "shared@example.com",
            scope: scope,
            identity: nil))

        #expect(key == "shared@example.com|managed.11111111-2222-4333-8444-555555555555")
        #expect(JonesFrameworkIsolation.websiteDataStoreIdentifier(forStorageKey: key).uuidString
            == "7C811445-A0BB-4A5D-9DEF-380AAC943EC1")
    }

    @Test
    func `stock missing email still selects the default store regardless of scope`() {
        let emails: [String?] = [nil, "", " \n\t"]
        let scopes: [CookieHeaderCache.Scope?] = [nil, .managedStoreUnreadable, .profileHome("/fixture/profile")]
        for email in emails {
            for scope in scopes {
                #expect(JonesFrameworkIsolation.openAIDashboardStorageKey(
                    forAccountEmail: email,
                    scope: scope,
                    identity: nil) == nil)
            }
        }
    }

    @Test
    func `fork key and UUID are stable and normalize the email`() throws {
        let key = try #require(JonesFrameworkIsolation.openAIDashboardStorageKey(
            forAccountEmail: " SHARED@EXAMPLE.COM \n",
            scope: nil,
            identity: Self.fixtureIdentity()))
        let repeated = JonesFrameworkIsolation.openAIDashboardStorageKey(
            forAccountEmail: "shared@example.com",
            scope: nil,
            identity: Self.fixtureIdentity())

        #expect(key == "jones.openai-dashboard.v1:f4932c1e37e210726ba13c393424da8079b268370aaf59e78e403722122c9e4e")
        #expect(key == repeated)
        #expect(JonesFrameworkIsolation.websiteDataStoreIdentifier(forStorageKey: key).uuidString
            == "7224CFBE-B179-45A3-B604-E65AC9D81978")
    }

    @Test
    func `fork missing email has a stable persistent identifier instead of the default store`() throws {
        var keys: Set<String> = []
        let emails: [String?] = [nil, "", " \n\t"]
        for email in emails {
            let key = try #require(JonesFrameworkIsolation.openAIDashboardStorageKey(
                forAccountEmail: email,
                scope: nil,
                identity: Self.fixtureIdentity()))
            keys.insert(key)
        }
        #expect(keys.count == 1)
        let key = try #require(keys.first)
        #expect(key == "jones.openai-dashboard.v1:961d153e767b8745a5fe3ac36874aba179033778d011ada0bdb5dd5de40a5568")
        #expect(JonesFrameworkIsolation.websiteDataStoreIdentifier(forStorageKey: key).uuidString
            == "660E737C-0E5F-49B3-99EF-9210CC88E9A5")
    }

    @Test
    func `fork retains account and scope separation including no account`() throws {
        let emails: [String?] = [nil, "one@example.com", "two@example.com", "no-account"]
        let scopes: [CookieHeaderCache.Scope?] = try [
            nil,
            .managedAccount(#require(UUID(uuidString: "11111111-2222-4333-8444-555555555555"))),
            .managedStoreUnreadable,
            .profileHome("/fixture/profile-a"),
            .profileHome("/fixture/profile-b"),
            .providerVariant("fixture-variant"),
        ]
        var keys: Set<String> = []
        var identifiers: Set<UUID> = []
        for email in emails {
            for scope in scopes {
                let key = try #require(JonesFrameworkIsolation.openAIDashboardStorageKey(
                    forAccountEmail: email,
                    scope: scope,
                    identity: Self.fixtureIdentity()))
                keys.insert(key)
                identifiers.insert(JonesFrameworkIsolation.websiteDataStoreIdentifier(forStorageKey: key))
                let stock = JonesFrameworkIsolation.openAIDashboardStorageKey(
                    forAccountEmail: email,
                    scope: scope,
                    identity: nil)
                #expect(key != stock)
                if let stock {
                    #expect(JonesFrameworkIsolation.websiteDataStoreIdentifier(forStorageKey: key)
                        != JonesFrameworkIsolation.websiteDataStoreIdentifier(forStorageKey: stock))
                }
            }
        }
        #expect(keys.count == emails.count * scopes.count)
        #expect(identifiers.count == keys.count)
    }

    @Test
    func `every packaged identity component separates fork cache keys and UUIDs`() throws {
        let identities = [
            Self.fixtureIdentity(),
            Self.fixtureIdentity(bundleID: "com.example.other"),
            Self.fixtureIdentity(groupID: "group.com.example.other"),
            Self.fixtureIdentity(teamID: "OTHERTEAM"),
            Self.fixtureIdentity(iCloudID: "iCloud.com.example.other"),
        ]
        var keys: Set<String> = []
        var identifiers: Set<UUID> = []
        for identity in identities {
            let key = try #require(JonesFrameworkIsolation.openAIDashboardStorageKey(
                forAccountEmail: "shared@example.com",
                scope: nil,
                identity: identity))
            keys.insert(key)
            identifiers.insert(JonesFrameworkIsolation.websiteDataStoreIdentifier(forStorageKey: key))
        }
        #expect(keys.count == identities.count)
        #expect(identifiers.count == identities.count)
    }

    @Test
    func `identity component framing prevents delimiter ambiguity`() throws {
        let first = try #require(JonesFrameworkIsolation.openAIDashboardStorageKey(
            forAccountEmail: "shared@example.com",
            scope: nil,
            identity: Self.fixtureIdentity(bundleID: "fixture:a", groupID: "b")))
        let second = try #require(JonesFrameworkIsolation.openAIDashboardStorageKey(
            forAccountEmail: "shared@example.com",
            scope: nil,
            identity: Self.fixtureIdentity(bundleID: "fixture", groupID: "a:b")))
        #expect(first != second)
    }

    private static func fixtureIdentity(
        bundleID: String = "com.example.jones.fixture",
        groupID: String = "group.com.example.jones.fixture",
        teamID: String = "FIXTURETEAM",
        iCloudID: String = "iCloud.com.example.jones.fixture") -> JonesStateRoot.Identity
    {
        JonesStateRoot.Identity(bundleID: bundleID, groupID: groupID, teamID: teamID, iCloudID: iCloudID)
    }
}
#endif
