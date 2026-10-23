import Testing
@testable import CodexBar

struct CodexBarLaunchModeTests {
    @Test
    func `normal launch starts the application`() {
        #expect(CodexBarLaunchMode.resolve(arguments: ["/Applications/CodexBar"]) == .application)
    }

    @Test
    func `hook event launch skips application initialization`() {
        #expect(CodexBarLaunchMode.resolve(
            arguments: ["/Applications/CodexBar", "--hook-event"]) == .hookEvent)
    }

    @Test
    func `hook event is recognized among other arguments`() {
        #expect(CodexBarLaunchMode.resolve(
            arguments: ["/Applications/CodexBar", "--verbose", "--hook-event"]) == .hookEvent)
    }

    @Test
    func `similar argument still starts the application`() {
        #expect(CodexBarLaunchMode.resolve(
            arguments: ["/Applications/CodexBar", "--hook-events"]) == .application)
    }

    @Test
    @MainActor
    func `bootstrap is explicit and disables credential access before its operation`() {
        #expect(JonesBootstrapCommand.isRequested(["CodexBar", "--jones-bootstrap", "prepare"]))
        #expect(!JonesBootstrapCommand.isRequested(["CodexBar", "--jones-bootstraps"]))
        #expect(!JonesBootstrapCommand.isRequested(["CodexBar"]))
        var events: [String] = []
        let result = JonesBootstrapCommand.withKeychainDisabled(disable: {
            events.append("disabled")
        }, operation: {
            #expect(events == ["disabled"])
            events.append("bootstrap")
            return 2
        })
        #expect(result == 2)
        #expect(events == ["disabled", "bootstrap"])
    }

    @Test
    @MainActor
    func `bootstrap marker refuses manual launch before the recorded launch boundary`() {
        let target = "/synthetic/Applications/CodexBar Jones.app"
        #expect(JonesBootstrapCommand.permitsNormalLaunch(marker: nil, target: target))
        var marker: [String: Any] = [
            "schema": "jones-bootstrap-install/v1", "target": target, "phase": "launch-attempted",
        ]
        #expect(JonesBootstrapCommand.permitsNormalLaunch(marker: marker, target: target))
        for phase in ["installed", "prepared", "incomplete", "rollback-intent", "rolled-back", "unknown"] {
            marker["phase"] = phase
            #expect(!JonesBootstrapCommand.permitsNormalLaunch(marker: marker, target: target))
        }
        marker["phase"] = "launch-attempted"
        #expect(!JonesBootstrapCommand.permitsNormalLaunch(marker: marker, target: "/other/CodexBar Jones.app"))
        marker["schema"] = "unknown"
        #expect(!JonesBootstrapCommand.permitsNormalLaunch(marker: marker, target: target))
        #expect(!JonesBootstrapCommand.permitsNormalLaunch(marker: [:], target: target))
    }
}
