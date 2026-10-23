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
        let found = lifecycle.found(version: "135.2", generation: generation)
        #expect(found)
        #expect(lifecycle.state == .downloading(version: "135.2"))
        #expect(lifecycle.state.preparedUpdate == nil)
        let preparing = lifecycle.preparing(version: "135.2", generation: generation)
        #expect(preparing)
        #expect(lifecycle.state == .preparing(version: "135.2"))
        #expect(lifecycle.state.preparedUpdate == nil)
        let preparedUpdate = lifecycle.prepared(version: "135.2", generation: generation, at: 100)
        let prepared = try #require(preparedUpdate)
        #expect(lifecycle.state == .ready(prepared))
        let requestedInstall = lifecycle.requestInstall(prepared)
        #expect(requestedInstall)
        #expect(lifecycle.state == .installing(version: "135.2"))
        #expect(lifecycle.state.preparedUpdate == nil)
        let repeatedInstall = lifecycle.requestInstall(prepared)
        #expect(!repeatedInstall)
    }

    @Test
    func `stale generations versions and duplicate prepared events cannot replace readiness`() throws {
        var lifecycle = JonesUpdateLifecycle()
        lifecycle.beginCheck()
        let oldGeneration = lifecycle.generation
        lifecycle.found(version: "135.2", generation: oldGeneration)
        let oldPreparedUpdate = lifecycle.prepared(version: "135.2", generation: oldGeneration, at: 100)
        let oldPrepared = try #require(oldPreparedUpdate)
        lifecycle.beginCheck()
        let generation = lifecycle.generation
        lifecycle.found(version: "135.3", generation: generation)
        let oldInstall = lifecycle.requestInstall(oldPrepared)
        #expect(!oldInstall)
        let stalePrepared = lifecycle.prepared(version: "135.2", generation: oldGeneration, at: 200)
        #expect(stalePrepared == nil)
        let wrongVersion = lifecycle.prepared(version: "135.2", generation: generation, at: 200)
        #expect(wrongVersion == nil)
        let wrongGeneration = lifecycle.prepared(version: "135.3", generation: oldGeneration, at: 200)
        #expect(wrongGeneration == nil)
        let currentPrepared = lifecycle.prepared(version: "135.3", generation: generation, at: 200)
        let current = try #require(currentPrepared)
        let duplicatePrepared = lifecycle.prepared(version: "135.3", generation: generation, at: 201)
        #expect(duplicatePrepared == nil)
        #expect(lifecycle.state.preparedUpdate == current)
        let preparingAgain = lifecycle.preparing(version: "135.3", generation: generation)
        #expect(!preparingAgain)
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
            let preparedUpdate = lifecycle.prepared(version: "135.2", generation: generation, at: 100)
            let prepared = try #require(preparedUpdate)
            lifecycle.finish(outcome)
            #expect(lifecycle.state == outcome.state)
            #expect(lifecycle.version == nil)
            #expect(lifecycle.generation != generation)
            let requestedInstall = lifecycle.requestInstall(prepared)
            #expect(!requestedInstall)
            let willInstall = lifecycle.willInstall(version: "135.2", generation: generation)
            #expect(!willInstall)
            let found = lifecycle.found(version: "135.2", generation: generation)
            #expect(!found)
            let latePrepared = lifecycle.prepared(version: "135.2", generation: generation, at: 200)
            #expect(latePrepared == nil)
        }
    }

    @Test
    func `preparation requires a known candidate and finite monotonic time`() {
        var lifecycle = JonesUpdateLifecycle()
        lifecycle.beginCheck()
        let generation = lifecycle.generation
        let unknownCandidate = lifecycle.prepared(version: "135.2", generation: generation, at: 100)
        #expect(unknownCandidate == nil)
        let emptyVersionFound = lifecycle.found(version: "", generation: generation)
        #expect(!emptyVersionFound)
        lifecycle.found(version: "135.2", generation: generation)
        for time in [-1, Double.nan, Double.infinity] {
            let prepared = lifecycle.prepared(version: "135.2", generation: generation, at: time)
            #expect(prepared == nil)
        }
        #expect(lifecycle.state == .downloading(version: "135.2"))
    }
}
