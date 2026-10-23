import Foundation
import Observation

enum JonesUpdateDisabledReason: Equatable, Sendable {
    case channelDisabled
    case sparkleUnavailable
}

enum JonesUpdateFailure: Error, Equatable, Sendable {
    case trust(JonesUpdateTrustPolicy.Rejection)
    case admission(JonesUpdateAdmission.Rejection)
    case sparkle(domain: String, code: Int)
}

struct JonesPreparedUpdate: Equatable, Sendable {
    let version: String
    let generation: UUID
    let preparedAt: TimeInterval
}

enum JonesUpdateState: Equatable, Sendable {
    case disabled(JonesUpdateDisabledReason)
    case idle
    case checking
    case downloading(version: String)
    case preparing(version: String)
    case ready(JonesPreparedUpdate)
    case installing(version: String)
    case upToDate
    case cancelled
    case skipped
    case failed(JonesUpdateFailure)

    var preparedUpdate: JonesPreparedUpdate? {
        guard case let .ready(prepared) = self else { return nil }
        return prepared
    }
}

enum JonesUpdateOutcome {
    case disabled(JonesUpdateDisabledReason)
    case idle
    case upToDate
    case cancelled
    case skipped
    case failed(JonesUpdateFailure)

    var state: JonesUpdateState {
        switch self {
        case let .disabled(reason): .disabled(reason)
        case .idle: .idle
        case .upToDate: .upToDate
        case .cancelled: .cancelled
        case .skipped: .skipped
        case let .failed(reason): .failed(reason)
        }
    }
}

enum JonesUpdateUserChoice {
    case install
    case skip
    case dismiss
}

struct JonesUpdateLifecycle {
    private(set) var state: JonesUpdateState
    private(set) var generation = UUID()
    private(set) var version: String?

    init(disabledReason: JonesUpdateDisabledReason? = nil) {
        self.state = disabledReason.map(JonesUpdateState.disabled) ?? .idle
    }

    mutating func beginCheck() {
        self.generation = UUID()
        self.version = nil
        self.state = .checking
    }

    @discardableResult
    mutating func found(version: String, generation: UUID) -> Bool {
        guard self.generation == generation, !version.isEmpty else { return false }
        switch self.state {
        case .checking:
            self.version = version
        case .downloading where self.version == version:
            break
        default:
            return false
        }
        self.state = .downloading(version: version)
        return true
    }

    @discardableResult
    mutating func preparing(version: String, generation: UUID) -> Bool {
        guard self.matches(version: version, generation: generation) else { return false }
        switch self.state {
        case .downloading, .preparing:
            self.state = .preparing(version: version)
            return true
        default:
            return false
        }
    }

    mutating func prepared(version: String, generation: UUID, at time: TimeInterval) -> JonesPreparedUpdate? {
        guard self.matches(version: version, generation: generation), time.isFinite, time >= 0 else { return nil }
        switch self.state {
        case .downloading, .preparing:
            let prepared = JonesPreparedUpdate(version: version, generation: generation, preparedAt: time)
            self.state = .ready(prepared)
            return prepared
        default:
            return nil
        }
    }

    @discardableResult
    mutating func requestInstall(_ prepared: JonesPreparedUpdate) -> Bool {
        guard self.state.preparedUpdate == prepared else { return false }
        self.state = .installing(version: prepared.version)
        return true
    }

    @discardableResult
    mutating func willInstall(version: String, generation: UUID) -> Bool {
        guard self.matches(version: version, generation: generation) else { return false }
        switch self.state {
        case .downloading, .preparing, .ready, .installing:
            self.state = .installing(version: version)
            return true
        default:
            return false
        }
    }

    mutating func finish(_ outcome: JonesUpdateOutcome) {
        self.generation = UUID()
        self.version = nil
        self.state = outcome.state
    }

    private func matches(version: String, generation: UUID) -> Bool {
        self.generation == generation && self.version == version
    }
}

@MainActor
@Observable
final class JonesUpdateDetail {
    fileprivate(set) var state: JonesUpdateState
    var canCheckForUpdates = false
    var automaticUpdatesEnabled = false
    var idleDecision: JonesUpdateApplyPolicy.Decision = .deferred(.notPrepared)

    var preparedUpdate: JonesPreparedUpdate? {
        self.state.preparedUpdate
    }

    /// Disabling automatic updates cannot revoke Sparkle's already-prepared install at normal quit.
    var installsPreparedUpdateAtQuit: Bool {
        self.preparedUpdate != nil
    }

    init(state: JonesUpdateState) {
        self.state = state
    }

    func update(state: JonesUpdateState) {
        self.state = state
    }
}
