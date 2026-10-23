import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct JonesCodexAppLaunchEnvironmentTests {
    private let profile = "/fixture/.codex-t3/jace"

    @Test
    func `only a uniquely enrolled inherited home is removed`() {
        #expect(self.removals(["CODEX_HOME": self.profile]) == ["CODEX_HOME"])
        #expect(self.removals([:]).isEmpty)
        #expect(self.removals(["CODEX_HOME": "/fixture/.codex"]).isEmpty)
        #expect(self.removals(["CODEX_HOME": "/fixture/custom"]).isEmpty)
        #expect(self.removals(["CODEX_HOME": "relative"]).isEmpty)
        #expect(JonesCodexAppLaunchEnvironment.variablesToRemove(
            environment: ["CODEX_HOME": self.profile], fleetHomePaths: []).isEmpty)
        #expect(JonesCodexAppLaunchEnvironment.variablesToRemove(
            environment: ["CODEX_HOME": self.profile],
            fleetHomePaths: [self.profile, self.profile + "/."]).isEmpty)
    }

    @Test
    func `paired SQLite home is removed while independent SQLite settings remain`() {
        #expect(self.removals([
            "CODEX_HOME": self.profile,
            "CODEX_SQLITE_HOME": self.profile + "/.",
        ]) == ["CODEX_HOME", "CODEX_SQLITE_HOME"])
        #expect(self.removals([
            "CODEX_HOME": self.profile,
            "CODEX_SQLITE_HOME": "/fixture/custom-sqlite",
        ]) == ["CODEX_HOME"])
        #expect(self.removals(["CODEX_SQLITE_HOME": self.profile]).isEmpty)
    }

    @Test
    func `explicit provider profile routing survives app launch normalization`() {
        var environment = ["CODEX_HOME": self.profile, "UNRELATED": "preserved"]
        for name in self.removals(environment) {
            environment.removeValue(forKey: name)
        }
        #expect(environment == ["UNRELATED": "preserved"])
        let scoped = CodexHomeScope.scopedEnvironment(base: environment, codexHome: self.profile)
        #expect(scoped["CODEX_HOME"] == self.profile)
        #expect(scoped["UNRELATED"] == "preserved")
    }

    @Test
    @MainActor
    func `custom launch and protected path failures explain different recovery actions`() {
        let custom = CodexAccountPromotionCoordinator.mapUserFacingError(
            CodexAccountPromotionError.fleetLaunchHomeOverride)
        let overlap = CodexAccountPromotionCoordinator.mapUserFacingError(
            CodexAccountPromotionError.fleetDestinationAmbiguous)
        #expect(custom.title == overlap.title)
        #expect(custom.message.contains("CODEX_HOME"))
        #expect(overlap.message.contains("overlaps"))
        #expect(!overlap.message.contains("CODEX_HOME"))
    }

    private func removals(_ environment: [String: String]) -> [String] {
        JonesCodexAppLaunchEnvironment.variablesToRemove(environment: environment, fleetHomePaths: [self.profile])
    }
}
