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
        let preparation = lifecycle.prepared(version: "135.2", generation: generation, at: 100)
        let prepared = try #require(preparation)
        #expect(lifecycle.state == .ready(prepared))
        let acceptedInstall = lifecycle.requestInstall(prepared)
        #expect(acceptedInstall)
        #expect(lifecycle.state == .installing(version: "135.2"))
        #expect(lifecycle.state.preparedUpdate == nil)
        let duplicateInstall = lifecycle.requestInstall(prepared)
        #expect(!duplicateInstall)
    }

    @Test
    func `stale generations versions and duplicate prepared events cannot replace readiness`() throws {
        var lifecycle = JonesUpdateLifecycle()
        lifecycle.beginCheck()
        let oldGeneration = lifecycle.generation
        lifecycle.found(version: "135.2", generation: oldGeneration)
        let oldPreparation = lifecycle.prepared(version: "135.2", generation: oldGeneration, at: 100)
        let oldPrepared = try #require(oldPreparation)
        lifecycle.beginCheck()
        let generation = lifecycle.generation
        lifecycle.found(version: "135.3", generation: generation)
        let staleInstall = lifecycle.requestInstall(oldPrepared)
        #expect(!staleInstall)
        let stalePreparation = lifecycle.prepared(version: "135.2", generation: oldGeneration, at: 200)
        #expect(stalePreparation == nil)
        let wrongVersionPreparation = lifecycle.prepared(version: "135.2", generation: generation, at: 200)
        #expect(wrongVersionPreparation == nil)
        let wrongGenerationPreparation = lifecycle.prepared(version: "135.3", generation: oldGeneration, at: 200)
        #expect(wrongGenerationPreparation == nil)
        let currentPreparation = lifecycle.prepared(version: "135.3", generation: generation, at: 200)
        let current = try #require(currentPreparation)
        let duplicatePreparation = lifecycle.prepared(version: "135.3", generation: generation, at: 201)
        #expect(duplicatePreparation == nil)
        #expect(lifecycle.state.preparedUpdate == current)
        let duplicatePreparing = lifecycle.preparing(version: "135.3", generation: generation)
        #expect(!duplicatePreparing)
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
            let preparation = lifecycle.prepared(version: "135.2", generation: generation, at: 100)
            let prepared = try #require(preparation)
            lifecycle.finish(outcome)
            #expect(lifecycle.state == outcome.state)
            #expect(lifecycle.version == nil)
            #expect(lifecycle.generation != generation)
            let lateInstall = lifecycle.requestInstall(prepared)
            #expect(!lateInstall)
            let lateWillInstall = lifecycle.willInstall(version: "135.2", generation: generation)
            #expect(!lateWillInstall)
            let lateFound = lifecycle.found(version: "135.2", generation: generation)
            #expect(!lateFound)
            let latePreparation = lifecycle.prepared(version: "135.2", generation: generation, at: 200)
            #expect(latePreparation == nil)
        }
    }

    @Test
    func `preparation requires a known candidate and finite monotonic time`() {
        var lifecycle = JonesUpdateLifecycle()
        lifecycle.beginCheck()
        let generation = lifecycle.generation
        let unknownCandidatePreparation = lifecycle.prepared(version: "135.2", generation: generation, at: 100)
        #expect(unknownCandidatePreparation == nil)
        let emptyVersionFound = lifecycle.found(version: "", generation: generation)
        #expect(!emptyVersionFound)
        lifecycle.found(version: "135.2", generation: generation)
        for time in [-1, Double.nan, Double.infinity] {
            let invalidTimePreparation = lifecycle.prepared(version: "135.2", generation: generation, at: time)
            #expect(invalidTimePreparation == nil)
        }
        #expect(lifecycle.state == .downloading(version: "135.2"))
    }
}
