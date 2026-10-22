import Foundation
import Testing
@testable import CodexBar

enum JonesUpdateTestFixtures {
    // Public fixture bytes only; no signing identity, key store, defaults suite, or filesystem fixture.
    static func package(channel: String = "stable") -> [String: Any] {
        [
            "CFBundleIdentifier": JonesUpdateTrustPolicy.productionBundleID,
            "CFBundleDisplayName": "CodexBar Jones",
            "JonesAppBundleID": JonesUpdateTrustPolicy.productionBundleID,
            "JonesStateKey": "jones",
            "CodexBarTeamID": "JONESLOCAL",
            "JonesAppGroupID": "JONESLOCAL.com.jonessystems.codexbar",
            "JonesICloudID": "iCloud.com.jonessystems.codexbar",
            "JonesSourceRevision": String(repeating: "a", count: 40),
            "JonesBuildOrigin": "local",
            "JonesBuildRun": "",
            "JonesUpdateChannel": channel,
            "SUFeedURL": channel == "none" ? "" : JonesUpdateTrustPolicy.stableFeedURL,
            "SUPublicEDKey": channel == "none" ? "" : Data(repeating: 7, count: 32).base64EncodedString(),
            "SURequireSignedFeed": true,
            "SUVerifyUpdateBeforeExtraction": true,
            "SUSignedFeedFailureExpirationInterval": 0,
        ]
    }

    static func policy(channel: String = "stable") throws -> JonesUpdateTrustPolicy {
        try JonesUpdateTrustPolicy.validate(infoDictionary: self.package(channel: channel))
    }

    static var idleSafety: JonesUpdateIdleSafetyInputs {
        .init(
            hidIdleTime: 900, hasBlockedAccountInteraction: false, hasActiveTTYProcesses: false,
            hasVisibleWindows: false, hasVisibleMenus: false)
    }
}

struct JonesUpdateTrustPolicyTests {
    @Test
    func `stable Jones package binds its feed key identity and source`() throws {
        let policy = try JonesUpdateTestFixtures.policy()
        #expect(policy.identity == .production)
        #expect(policy.channel == .stable)
        #expect(policy.isEnabled)
        #expect(policy.feedURL?.absoluteString == JonesUpdateTrustPolicy.stableFeedURL)
        #expect(policy.sourceRevision == String(repeating: "a", count: 40))
    }

    @Test
    func `none is a valid disabled bootstrap and rejects partial configuration`() throws {
        let policy = try JonesUpdateTestFixtures.policy(channel: "none")
        #expect(!policy.isEnabled)
        #expect(policy.feedURL == nil)
        #expect(policy.publicKey == nil)
        for key in ["SUFeedURL", "SUPublicEDKey"] {
            var info = JonesUpdateTestFixtures.package(channel: "none")
            info[key] = JonesUpdateTestFixtures.package()[key]
            #expect(throws: JonesUpdateTrustPolicy.Rejection.disabledConfiguration) {
                try JonesUpdateTrustPolicy.validate(infoDictionary: info)
            }
        }
    }

    @Test
    func `every production identity field is required and exact`() {
        for key in [
            "CFBundleIdentifier", "CFBundleDisplayName", "JonesAppBundleID", "JonesStateKey", "CodexBarTeamID",
            "JonesAppGroupID", "JonesICloudID",
        ] {
            let invalidValues: [String?] = [nil, "com.steipete.codexbar", "unexpected"]
            for value in invalidValues {
                var info = JonesUpdateTestFixtures.package()
                info[key] = value
                #expect(throws: JonesUpdateTrustPolicy.Rejection.identity) {
                    try JonesUpdateTrustPolicy.validate(infoDictionary: info)
                }
            }
        }
        for key in ["JonesUpdateHarness", "JonesUpdateHarnessFixtureID"] {
            var info = JonesUpdateTestFixtures.package()
            info[key] = false
            #expect(throws: JonesUpdateTrustPolicy.Rejection.identity) {
                try JonesUpdateTrustPolicy.validate(infoDictionary: info)
            }
        }
    }

    @Test
    func `harness requires its exact packaged identity true flag and absent state key`() throws {
        var info = JonesUpdateTestFixtures.package()
        info["CFBundleIdentifier"] = JonesUpdateTrustPolicy.harnessBundleID
        info["JonesUpdateHarness"] = true
        info["JonesStateKey"] = nil
        info["SUFeedURL"] = "http://127.0.0.1:32123/appcast.xml"
        let policy = try JonesUpdateTrustPolicy.validate(infoDictionary: info)
        #expect(policy.identity == .harness)

        let invalidFlags: [Any] = [false, "true", 1]
        for flag in invalidFlags {
            var invalid = info
            invalid["JonesUpdateHarness"] = flag
            #expect(throws: JonesUpdateTrustPolicy.Rejection.identity) {
                try JonesUpdateTrustPolicy.validate(infoDictionary: invalid)
            }
        }
        for key in ["", "jones"] {
            var invalid = info
            invalid["JonesStateKey"] = key
            #expect(throws: JonesUpdateTrustPolicy.Rejection.identity) {
                try JonesUpdateTrustPolicy.validate(infoDictionary: invalid)
            }
        }
        for feed in [
            "http://localhost:32123/appcast.xml", "http://127.0.0.2:32123/appcast.xml",
            "http://[::1]:32123/appcast.xml", "https://127.0.0.1:32123/appcast.xml",
            JonesUpdateTrustPolicy.stableFeedURL, "http://127.0.0.1.evil.example/appcast.xml",
        ] {
            var invalid = info
            invalid["SUFeedURL"] = feed
            #expect(throws: JonesUpdateTrustPolicy.Rejection.feedURL) {
                try JonesUpdateTrustPolicy.validate(infoDictionary: invalid)
            }
        }
    }

    @Test
    func `upstream public key and URLs cannot authorize Jones updates`() {
        var info = JonesUpdateTestFixtures.package()
        info["SUPublicEDKey"] = JonesUpdateTrustPolicy.upstreamPublicKey
        #expect(throws: JonesUpdateTrustPolicy.Rejection.upstreamTrust) {
            try JonesUpdateTrustPolicy.validate(infoDictionary: info)
        }
        for feed in [
            "https://raw.githubusercontent.com/steipete/CodexBar/main/appcast.xml",
            "https://github.com/steipete/CodexBar/releases/latest/download/appcast.xml",
            "https://codexbar.app/appcast.xml",
        ] {
            info = JonesUpdateTestFixtures.package()
            info["SUFeedURL"] = feed
            #expect(throws: JonesUpdateTrustPolicy.Rejection.upstreamTrust) {
                try JonesUpdateTrustPolicy.validate(infoDictionary: info)
            }
        }
    }

    @Test
    func `production accepts only the packaged canonical HTTPS feed`() {
        for feed in [
            "http://127.0.0.1/appcast.xml", "http://github.com/Jones-Systems/CodexBar/releases/latest/download/appcast.xml",
            "https://example.com/appcast.xml", JonesUpdateTrustPolicy.stableFeedURL + "?override=1",
            "https://github.com.evil.example/Jones-Systems/CodexBar/appcast.xml",
            "https://user:password@github.com/Jones-Systems/CodexBar/releases/latest/download/appcast.xml",
        ] {
            var info = JonesUpdateTestFixtures.package()
            info["SUFeedURL"] = feed
            #expect(throws: JonesUpdateTrustPolicy.Rejection.feedURL) {
                try JonesUpdateTrustPolicy.validate(infoDictionary: info)
            }
        }
    }

    @Test
    func `stable verification flags must be plist booleans and expiry must be numeric zero`() {
        for (key, rejection) in [
            ("SURequireSignedFeed", JonesUpdateTrustPolicy.Rejection.signedFeedRequired),
            ("SUVerifyUpdateBeforeExtraction", .verificationBeforeExtractionRequired),
        ] {
            let invalidValues: [Any?] = [nil, false, 1, "true"]
            for value in invalidValues {
                var info = JonesUpdateTestFixtures.package()
                info[key] = value
                #expect(throws: rejection) { try JonesUpdateTrustPolicy.validate(infoDictionary: info) }
            }
        }
        let invalidExpiries: [Any?] = [nil, false, "0", 1, -1, Double.nan, Double.infinity]
        for value in invalidExpiries {
            var info = JonesUpdateTestFixtures.package()
            info["SUSignedFeedFailureExpirationInterval"] = value
            #expect(throws: JonesUpdateTrustPolicy.Rejection.signedFeedExpiryMustBeZero) {
                try JonesUpdateTrustPolicy.validate(infoDictionary: info)
            }
        }
    }

    @Test
    func `invalid channel key source and build metadata fail closed`() {
        let mutations: [(String, Any, JonesUpdateTrustPolicy.Rejection)] = [
            ("JonesUpdateChannel", "beta", .channel),
            ("JonesSourceRevision", String(repeating: "A", count: 40), .sourceRevision),
            ("JonesSourceRevision", "abcdef0", .sourceRevision),
            ("JonesBuildOrigin", "unknown", .buildOrigin),
            ("JonesBuildRun", "https://github.com/Jones-Systems/CodexBar/actions/runs/123", .buildRun),
            ("SUPublicEDKey", "", .publicKey),
            ("SUPublicEDKey", Data(repeating: 1, count: 31).base64EncodedString(), .publicKey),
        ]
        for (key, value, rejection) in mutations {
            var info = JonesUpdateTestFixtures.package()
            info[key] = value
            #expect(throws: rejection) { try JonesUpdateTrustPolicy.validate(infoDictionary: info) }
        }
    }

    @Test
    func `CI run provenance belongs to the canonical repository`() throws {
        var info = JonesUpdateTestFixtures.package()
        info["JonesBuildOrigin"] = "ci-main"
        info["JonesBuildRun"] = "https://github.com/Jones-Systems/CodexBar/actions/runs/12345"
        #expect(try JonesUpdateTrustPolicy.validate(infoDictionary: info).buildOrigin == .main)
        info["JonesBuildOrigin"] = "ci-pr"
        #expect(try JonesUpdateTrustPolicy.validate(infoDictionary: info).buildOrigin == .pullRequest)
        for run in ["", "https://github.com/steipete/CodexBar/actions/runs/12345", "file:///build/12345"] {
            info["JonesBuildRun"] = run
            #expect(throws: JonesUpdateTrustPolicy.Rejection.buildRun) {
                try JonesUpdateTrustPolicy.validate(infoDictionary: info)
            }
        }
    }

    @Test
    func `archive URLs obey the same upstream and transport boundary`() throws {
        let policy = try JonesUpdateTestFixtures.policy()
        try policy.validateArchiveURL(URL(string: "https://github.com/Jones-Systems/CodexBar/releases/download/v1/app.zip"))
        #expect(throws: JonesUpdateTrustPolicy.Rejection.feedURL) { try policy.validateArchiveURL(nil) }
        #expect(throws: JonesUpdateTrustPolicy.Rejection.feedURL) {
            try policy.validateArchiveURL(URL(string: "http://127.0.0.1/app.zip"))
        }
        #expect(throws: JonesUpdateTrustPolicy.Rejection.upstreamTrust) {
            try policy.validateArchiveURL(URL(string: "https://github.com/steipete/CodexBar/releases/download/v1/app.zip"))
        }
    }
}
