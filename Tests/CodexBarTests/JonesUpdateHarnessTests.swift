import Foundation
import Testing
@testable import CodexBar

@MainActor
struct JonesUpdateHarnessTests {
    private func fixture() -> [String: Any] {
        [
            "CFBundleIdentifier": JonesUpdateTrustPolicy.harnessBundleID,
            "CFBundleExecutable": "CodexBar",
            "JonesUpdateHarness": true,
            "JonesUpdateHarnessFixtureID": "a65bf229-e140-40a4-a9b6-248ac4bd5d65",
            "JonesSourceRevision": String(repeating: "a", count: 40),
            "JonesBuildOrigin": "local", "JonesBuildRun": "",
            "JonesUpdateChannel": "stable", "SUFeedURL": "http://127.0.0.1:39541/appcast.xml",
            "SUPublicEDKey": Data((0..<32).map(UInt8.init)).base64EncodedString(),
            "SURequireSignedFeed": true, "SUVerifyUpdateBeforeExtraction": true,
            "SUSignedFeedFailureExpirationInterval": 0,
        ]
    }

    @Test
    func `any harness marker diverts before normal app initialization`() {
        #expect(!JonesUpdateHarness.isMarked(["CFBundleIdentifier": JonesUpdateTrustPolicy.productionBundleID]))
        #expect(JonesUpdateHarness.isMarked(["JonesUpdateHarness": false]))
        #expect(JonesUpdateHarness.isMarked(["JonesUpdateHarnessFixtureID": "invalid"]))
        #expect(JonesUpdateHarness.isMarked(["CFBundleIdentifier": JonesUpdateTrustPolicy.harnessBundleID]))
    }

    @Test
    func `only complete fixture identity is accepted`() throws {
        let policy = try JonesUpdateHarness.validate(self.fixture())
        #expect(policy.identity == .harness)
        #expect(policy.isEnabled)
    }

    @Test
    func `production state metadata cannot enter the harness`() {
        for key in ["JonesStateKey", "JonesAppGroupID", "JonesICloudID", "JonesAppBundleID", "CodexBarTeamID"] {
            var info = self.fixture()
            info[key] = "production"
            #expect(throws: JonesUpdateTrustPolicy.Rejection.self) { try JonesUpdateHarness.validate(info) }
        }
    }

    @Test
    func `partial markers fail closed instead of falling through`() {
        for key in ["JonesUpdateHarness", "JonesUpdateHarnessFixtureID", "SUPublicEDKey", "CFBundleExecutable"] {
            var info = self.fixture()
            info.removeValue(forKey: key)
            #expect(throws: JonesUpdateTrustPolicy.Rejection.self) { try JonesUpdateHarness.validate(info) }
        }
    }
}
