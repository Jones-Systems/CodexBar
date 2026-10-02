import Foundation

/// Pure refresh decisions. The caller owns transport, cancellation, timers and app lifecycle.
public struct NetdataRefreshState: Sendable, Equatable {
    public struct Request: Sendable, Equatable {
        public let environmentID: String
        public let generation: UInt64
    }

    public private(set) var environmentID: String
    public private(set) var inFlight: Request?
    public private(set) var observation: HubHostObservation?
    public private(set) var receivedAt: Date?
    public private(set) var requestFailed = false
    public private(set) var isSuspended = false
    public private(set) var nextRefreshAt: Date?
    private var generation: UInt64 = 0
    private var consecutiveFailures = 0

    public init(environmentID: String) {
        self.environmentID = environmentID
    }

    public mutating func beginRefresh(now: Date, force: Bool = false) -> Request? {
        guard !self.isSuspended, self.inFlight == nil,
              !self.environmentID.isEmpty, self.environmentID.utf8.count <= 128,
              !self.environmentID.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              now.timeIntervalSince1970.isFinite, self.generation < UInt64.max,
              force || self.nextRefreshAt.map({ now >= $0 }) != false
        else { return nil }
        self.generation += 1
        let request = Request(environmentID: self.environmentID, generation: self.generation)
        self.inFlight = request
        self.nextRefreshAt = nil
        return request
    }

    /// Completion time schedules the next decision; it does not repair the legacy client's sample-time bug.
    @discardableResult
    public mutating func complete(
        _ request: Request,
        observation: HubHostObservation?,
        now: Date,
        visible: Bool = false) -> Bool
    {
        guard self.inFlight == request, request.environmentID == self.environmentID,
              now.timeIntervalSince1970.isFinite
        else { return false }
        self.inFlight = nil
        let state = NetdataSystemsState(environmentID: self.environmentID, observation: observation, now: now)
        if observation?.environmentID == self.environmentID,
           state.observedAt != nil, state.cpuPercent != nil || state.availableRAMGiB != nil,
           state.availability != .unsupported, state.availability != .unavailable
        {
            self.observation = observation
            self.receivedAt = now
            self.requestFailed = false
            self.consecutiveFailures = 0
        } else {
            self.requestFailed = true
            self.consecutiveFailures = min(self.consecutiveFailures + 1, 6)
        }
        let interval = visible ? 5.0 : 10.0
        let multiplier = pow(2.0, Double(max(0, self.consecutiveFailures - 1)))
        self.nextRefreshAt = now.addingTimeInterval(min(60, interval * multiplier))
        return true
    }

    @discardableResult
    public mutating func cancel(_ request: Request, now: Date) -> Bool {
        guard self.inFlight == request, now.timeIntervalSince1970.isFinite else { return false }
        self.inFlight = nil
        self.nextRefreshAt = now
        return true
    }

    public mutating func configure(environmentID: String) {
        self.environmentID = environmentID
        self.inFlight = nil
        self.observation = nil
        self.receivedAt = nil
        self.requestFailed = false
        self.consecutiveFailures = 0
        self.nextRefreshAt = nil
    }

    public mutating func suspend() {
        self.isSuspended = true
        self.inFlight = nil
        self.nextRefreshAt = nil
    }

    public mutating func wake(now: Date) {
        self.isSuspended = false
        self.nextRefreshAt = now.timeIntervalSince1970.isFinite ? now : nil
    }

    public func systemsState(now: Date) -> NetdataSystemsState {
        NetdataSystemsState(
            environmentID: self.environmentID,
            observation: self.observation,
            receivedAt: self.receivedAt,
            now: now,
            requestFailed: self.requestFailed,
            isRefreshing: self.inFlight != nil)
    }
}
