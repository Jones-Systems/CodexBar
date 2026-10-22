import Foundation
import Testing
@testable import CodexBar

struct JonesUpdateLifecycleTests {
    @Test
    func `only preparation callback produces readiness`() throws {
        var lifecycle = JonesUpdateLifecycle()
        #expect(lifecycle.state == .idle)
        lifecycle.beginCheck()
        let generation = lifecycle.generation
        #expect(lifecycle.state == .checking)
        #expect(lifecycle.state.preparedUpdate == nil)
        #expect(lifecycle.found(version: "135.2", generation: generation))
        #expect(lifecycle.state == .downloading(version: "135.2"))
        #expect(lifecycle.state.preparedUpdate == nil)
        #expect(lifecycle.preparing(version: "135.2", generation: generation))
        #expect(lifecycle.state == .preparing(version: "135.2"))
        #expect(lifecycle.state.preparedUpdate == nil)
        let prepared = try #require(lifecycle.prepared(version: "135.2", generation: generation, at: 100))
        #expect(lifecycle.state == .ready(prepared))
        #expect(lifecycle.requestInstall(prepared))
        #expect(lifecycle.state == .installing(version: "135.2"))
        #expect(lifecycle.state.preparedUpdate == nil)
        #expect(!lifecycle.requestInstall(prepared))
    }

    @Test
    func `stale generations versions and duplicate prepared events cannot replace readiness`() throws {
        var lifecycle = JonesUpdateLifecycle()
        lifecycle.beginCheck()
        let oldGeneration = lifecycle.generation
        lifecycle.found(version: "135.2", generation: oldGeneration)
        let oldPrepared = try #require(lifecycle.prepared(version: "135.2", generation: oldGeneration, at: 100))
        lifecycle.beginCheck()
        let generation = lifecycle.generation
        lifecycle.found(version: "135.3", generation: generation)
        #expect(!lifecycle.requestInstall(oldPrepared))
        #expect(lifecycle.prepared(version: "135.2", generation: oldGeneration, at: 200) == nil)
        #expect(lifecycle.prepared(version: "135.2", generation: generation, at: 200) == nil)
        #expect(lifecycle.prepared(version: "135.3", generation: oldGeneration, at: 200) == nil)
        let current = try #require(lifecycle.prepared(version: "135.3", generation: generation, at: 200))
        #expect(lifecycle.prepared(version: "135.3", generation: generation, at: 201) == nil)
        #expect(lifecycle.state.preparedUpdate == current)
        #expect(!lifecycle.preparing(version: "135.3", generation: generation))
    }

    @Test
    func `terminal outcomes invalidate the version and generation before late callbacks`() throws {
        let outcomes: [JonesUpdateOutcome] = [
            .idle, .upToDate, .cancelled, .skipped, .disabled(.channelDisabled),
            .failed(.sparkle(domain: "fixture", code: 1)),
        ]
        for outcome in outcomes {
            var lifecycle = JonesUpdateLifecycle()
            lifecycle.beginCheck()
            let generation = lifecycle.generation
            lifecycle.found(version: "135.2", generation: generation)
            let prepared = try #require(lifecycle.prepared(version: "135.2", generation: generation, at: 100))
            lifecycle.finish(outcome)
            #expect(lifecycle.state == outcome.state)
            #expect(lifecycle.version == nil)
            #expect(lifecycle.generation != generation)
            #expect(!lifecycle.requestInstall(prepared))
            #expect(!lifecycle.willInstall(version: "135.2", generation: generation))
            #expect(!lifecycle.found(version: "135.2", generation: generation))
            #expect(lifecycle.prepared(version: "135.2", generation: generation, at: 200) == nil)
        }
    }

    @Test
    func `preparation requires a known candidate and finite monotonic time`() {
        var lifecycle = JonesUpdateLifecycle()
        lifecycle.beginCheck()
        let generation = lifecycle.generation
        #expect(lifecycle.prepared(version: "135.2", generation: generation, at: 100) == nil)
        #expect(!lifecycle.found(version: "", generation: generation))
        lifecycle.found(version: "135.2", generation: generation)
        for time in [-1, Double.nan, Double.infinity] {
            #expect(lifecycle.prepared(version: "135.2", generation: generation, at: time) == nil)
        }
        #expect(lifecycle.state == .downloading(version: "135.2"))
    }
}
