import Foundation
import Observation

public protocol NetdataObservationFetching: Sendable {
    func fetch(now: Date) async throws -> HubHostObservation
}

extension NetdataLoopbackClient: NetdataObservationFetching {}

/// Explicit in-memory bindings only. The caller owns transport, scheduling and app lifecycle.
@MainActor
@Observable
public final class NetdataObservabilityBridge {
    private struct Binding {
        let identity = UUID()
        let fetcher: any NetdataObservationFetching
        var state: NetdataRefreshState
    }

    private var bindings: [String: Binding] = [:]
    @ObservationIgnored private var activeFetchIDs: [String: UUID] = [:]
    public private(set) var isSuspended = false

    public init() {}

    @discardableResult
    public func bind(environmentID: String, fetcher: any NetdataObservationFetching) -> Bool {
        guard !environmentID.isEmpty, environmentID.utf8.count <= 128,
              !environmentID.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { return false }
        var state = NetdataRefreshState(environmentID: environmentID)
        if self.isSuspended { state.suspend() }
        self.bindings[environmentID] = Binding(fetcher: fetcher, state: state)
        return true
    }

    public func removeBinding(environmentID: String) {
        self.bindings.removeValue(forKey: environmentID)
    }

    public func suspend() {
        self.isSuspended = true
        for id in Array(self.bindings.keys) {
            self.bindings[id]?.state.suspend()
        }
    }

    public func wake(now: Date) {
        self.isSuspended = false
        for id in Array(self.bindings.keys) {
            self.bindings[id]?.state.wake(now: now)
        }
    }

    /// Returns whether this completion was accepted, not whether all metrics were available.
    /// Rebinding invalidates old replies even when a replacement request has the same local generation.
    @discardableResult
    public func refresh(
        environmentID: String,
        visible: Bool = false,
        force: Bool = false,
        clock: @Sendable () -> Date = { Date() }) async throws -> Bool
    {
        try Task.checkCancellation()
        guard self.activeFetchIDs[environmentID] == nil,
              var binding = self.bindings[environmentID] else { return false }
        let startedAt = clock()
        guard let request = binding.state.beginRefresh(now: startedAt, force: force) else { return false }
        self.bindings[environmentID] = binding
        let fetchID = UUID()
        self.activeFetchIDs[environmentID] = fetchID
        defer {
            if self.activeFetchIDs[environmentID] == fetchID {
                self.activeFetchIDs.removeValue(forKey: environmentID)
            }
        }
        do {
            let observation = try await binding.fetcher.fetch(now: startedAt)
            try Task.checkCancellation()
            guard var current = self.bindings[environmentID], current.identity == binding.identity else { return false }
            let accepted = current.state.complete(request, observation: observation, now: clock(), visible: visible)
            if !accepted { current.state.cancel(request, now: startedAt) }
            self.bindings[environmentID] = current
            return accepted
        } catch {
            if var current = self.bindings[environmentID], current.identity == binding.identity {
                let finishedAt = clock()
                let cleanupTime = finishedAt.timeIntervalSince1970.isFinite ? finishedAt : startedAt
                if error is CancellationError || Task.isCancelled {
                    current.state.cancel(request, now: cleanupTime)
                } else if !current.state.complete(request, observation: nil, now: finishedAt, visible: visible) {
                    current.state.cancel(request, now: cleanupTime)
                }
                self.bindings[environmentID] = current
            }
            throw error
        }
    }

    public func refreshState(environmentID: String) -> NetdataRefreshState? {
        self.bindings[environmentID]?.state
    }

    public func systemsState(environmentID: String, now: Date) -> NetdataSystemsState {
        self.bindings[environmentID]?.state.systemsState(now: now) ?? NetdataSystemsState(
            environmentID: environmentID,
            observation: NetdataReadOnlyFacade.unavailable(environmentID: environmentID),
            now: now)
    }

    /// Publishes the same age/failure projection as Systems; cached sample timestamps are never refreshed.
    public func hostsByEnvironmentID(now: Date) -> [String: HubHostObservation] {
        self.bindings.mapValues { binding in
            let state = binding.state.systemsState(now: now)
            return HubHostObservation(
                environmentID: state.environmentID,
                evidence: HubEvidence(
                    source: state.source, observedAt: state.observedAt, availability: state.availability),
                cpuPercent: state.cpuPercent,
                memoryUsedBytes: nil,
                memoryAvailableBytes: state.availableRAMGiB == nil
                    ? nil : binding.state.observation?.memoryAvailableBytes)
        }
    }
}
