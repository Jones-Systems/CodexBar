import Foundation
import Testing
@testable import CodexBar

struct JonesUpdateApplyPolicyTests {
    private var eligible: JonesUpdateApplyPolicy.Snapshot {
        .init(
            preparedAge: 600,
            launchAge: 900,
            automaticUpdatesEnabled: true,
            safety: JonesUpdateTestFixtures.idleSafety)
    }

    @Test
    func `all thresholds are inclusive and every known busy signal denies`() {
        #expect(JonesUpdateApplyPolicy.evaluate(self.eligible) == .eligible)
        var snapshot = self.eligible
        snapshot.preparedAge = 599.999
        #expect(JonesUpdateApplyPolicy.evaluate(snapshot) == .deferred(.recentlyPrepared))
        snapshot = self.eligible
        snapshot.launchAge = 899.999
        #expect(JonesUpdateApplyPolicy.evaluate(snapshot) == .deferred(.recentlyLaunched))
        snapshot = self.eligible
        snapshot.safety.hidIdleTime = 899.999
        #expect(JonesUpdateApplyPolicy.evaluate(snapshot) == .deferred(.userActive))
        snapshot = self.eligible
        snapshot.automaticUpdatesEnabled = false
        #expect(JonesUpdateApplyPolicy.evaluate(snapshot) == .deferred(.automaticUpdatesDisabled))
        snapshot = self.eligible
        snapshot.safety.hasBlockedAccountInteraction = true
        #expect(JonesUpdateApplyPolicy.evaluate(snapshot) == .deferred(.accountInteraction))
        snapshot = self.eligible
        snapshot.safety.hasActiveTTYProcesses = true
        #expect(JonesUpdateApplyPolicy.evaluate(snapshot) == .deferred(.activeTTYProcesses))
        snapshot = self.eligible
        snapshot.safety.hasVisibleWindows = true
        #expect(JonesUpdateApplyPolicy.evaluate(snapshot) == .deferred(.visibleWindows))
        snapshot = self.eligible
        snapshot.safety.hasVisibleMenus = true
        #expect(JonesUpdateApplyPolicy.evaluate(snapshot) == .deferred(.visibleMenus))
    }

    @Test
    func `each missing input denies instead of assuming idle`() {
        var snapshot = self.eligible
        snapshot.preparedAge = nil
        #expect(JonesUpdateApplyPolicy.evaluate(snapshot) == .deferred(.unknown(.preparedAge)))
        snapshot = self.eligible
        snapshot.launchAge = nil
        #expect(JonesUpdateApplyPolicy.evaluate(snapshot) == .deferred(.unknown(.launchAge)))
        snapshot = self.eligible
        snapshot.safety.hidIdleTime = nil
        #expect(JonesUpdateApplyPolicy.evaluate(snapshot) == .deferred(.unknown(.hidIdleTime)))
        snapshot = self.eligible
        snapshot.automaticUpdatesEnabled = nil
        #expect(JonesUpdateApplyPolicy.evaluate(snapshot) == .deferred(.unknown(.automaticUpdates)))
        snapshot = self.eligible
        snapshot.safety.hasBlockedAccountInteraction = nil
        #expect(JonesUpdateApplyPolicy.evaluate(snapshot) == .deferred(.unknown(.accountInteraction)))
        snapshot = self.eligible
        snapshot.safety.hasActiveTTYProcesses = nil
        #expect(JonesUpdateApplyPolicy.evaluate(snapshot) == .deferred(.unknown(.ttyProcesses)))
        snapshot = self.eligible
        snapshot.safety.hasVisibleWindows = nil
        #expect(JonesUpdateApplyPolicy.evaluate(snapshot) == .deferred(.unknown(.windows)))
        snapshot = self.eligible
        snapshot.safety.hasVisibleMenus = nil
        #expect(JonesUpdateApplyPolicy.evaluate(snapshot) == .deferred(.unknown(.menus)))
    }

    @Test
    func `invalid and reversed clock durations fail closed`() {
        for invalid in [-1, Double.nan, Double.infinity, -Double.infinity] {
            var snapshot = self.eligible
            snapshot.preparedAge = invalid
            #expect(JonesUpdateApplyPolicy.evaluate(snapshot) == .deferred(.unknown(.preparedAge)))
            snapshot = self.eligible
            snapshot.launchAge = invalid
            #expect(JonesUpdateApplyPolicy.evaluate(snapshot) == .deferred(.unknown(.launchAge)))
            snapshot = self.eligible
            snapshot.safety.hidIdleTime = invalid
            #expect(JonesUpdateApplyPolicy.evaluate(snapshot) == .deferred(.unknown(.hidIdleTime)))
        }
    }
}
