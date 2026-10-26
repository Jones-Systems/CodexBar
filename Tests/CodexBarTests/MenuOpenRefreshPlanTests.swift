import CodexBarCore
import Testing
@testable import CodexBar

struct MenuOpenRefreshPlanTests {
    @Test
    func `refresh all selects every enabled provider concurrently`() {
        let plan = MenuOpenRefreshPlan.resolve(.init(
            refreshAllOnOpen: true,
            enabledProviders: [.codex, .claude],
            visibleProviders: [.codex],
            refreshingProviders: [],
            staleProviders: [],
            missingProviders: []))

        #expect(plan.providers == [.codex, .claude])
        #expect(plan.scheduling == .concurrent)
        #expect(plan.refreshCodexDashboard)
        #expect(plan.refreshTokenCost)
    }

    @Test
    func `refresh all skips dashboard refresh when codex is disabled`() {
        let plan = MenuOpenRefreshPlan.resolve(.init(
            refreshAllOnOpen: true,
            enabledProviders: [.claude],
            visibleProviders: [.claude],
            refreshingProviders: [],
            staleProviders: [],
            missingProviders: []))

        #expect(plan.providers == [.claude])
        #expect(!plan.refreshCodexDashboard)
        #expect(plan.refreshTokenCost)
    }

    @Test
    func `refresh all skips token cost refresh when no providers are enabled`() {
        let plan = MenuOpenRefreshPlan.resolve(.init(
            refreshAllOnOpen: true,
            enabledProviders: [],
            visibleProviders: [],
            refreshingProviders: [],
            staleProviders: [],
            missingProviders: []))

        #expect(plan.providers.isEmpty)
        #expect(!plan.refreshTokenCost)
    }

    @Test
    func `ordinary refresh selects only visible enabled retries sequentially`() {
        let plan = MenuOpenRefreshPlan.resolve(.init(
            refreshAllOnOpen: false,
            enabledProviders: [.codex, .claude],
            visibleProviders: [.claude, .codex],
            refreshingProviders: [.claude],
            staleProviders: [.codex],
            missingProviders: [.claude]))

        #expect(plan.providers == [.claude, .codex])
        #expect(plan.scheduling == .sequential)
        #expect(!plan.refreshCodexDashboard)
        #expect(!plan.refreshTokenCost)
    }

    @Test
    func `ordinary refresh skips fresh providers`() {
        let plan = MenuOpenRefreshPlan.resolve(.init(
            refreshAllOnOpen: false,
            enabledProviders: [.codex],
            visibleProviders: [.codex],
            refreshingProviders: [],
            staleProviders: [],
            missingProviders: []))

        #expect(plan.providers.isEmpty)
    }
}
