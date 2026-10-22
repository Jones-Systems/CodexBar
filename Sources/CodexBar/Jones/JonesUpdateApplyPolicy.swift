import Foundation

struct JonesUpdateIdleSafetyInputs: Equatable, Sendable {
    var hidIdleTime: TimeInterval?
    var hasBlockedAccountInteraction: Bool?
    var hasActiveTTYProcesses: Bool?
    var hasVisibleWindows: Bool?
    var hasVisibleMenus: Bool?

    static let unknown = Self()
}

enum JonesUpdateApplyPolicy {
    struct Snapshot: Equatable, Sendable {
        var preparedAge: TimeInterval?
        var launchAge: TimeInterval?
        var automaticUpdatesEnabled: Bool?
        var safety: JonesUpdateIdleSafetyInputs
    }

    enum Input: Equatable, Sendable {
        case preparedAge
        case launchAge
        case hidIdleTime
        case automaticUpdates
        case accountInteraction
        case ttyProcesses
        case windows
        case menus
    }

    enum Deferral: Equatable, Sendable {
        case notPrepared
        case unknown(Input)
        case recentlyPrepared
        case recentlyLaunched
        case userActive
        case automaticUpdatesDisabled
        case accountInteraction
        case activeTTYProcesses
        case visibleWindows
        case visibleMenus
    }

    enum Decision: Equatable, Sendable {
        case eligible
        case deferred(Deferral)
    }

    static let minimumPreparedAge: TimeInterval = 10 * 60
    static let minimumLaunchAge: TimeInterval = 15 * 60
    static let minimumHIDIdleTime: TimeInterval = 15 * 60

    static func evaluate(_ snapshot: Snapshot) -> Decision {
        guard let prepared = Self.knownDuration(snapshot.preparedAge) else {
            return .deferred(.unknown(.preparedAge))
        }
        guard let launch = Self.knownDuration(snapshot.launchAge) else {
            return .deferred(.unknown(.launchAge))
        }
        guard let idle = Self.knownDuration(snapshot.safety.hidIdleTime) else {
            return .deferred(.unknown(.hidIdleTime))
        }
        guard let automatic = snapshot.automaticUpdatesEnabled else {
            return .deferred(.unknown(.automaticUpdates))
        }
        guard let interaction = snapshot.safety.hasBlockedAccountInteraction else {
            return .deferred(.unknown(.accountInteraction))
        }
        guard let processes = snapshot.safety.hasActiveTTYProcesses else {
            return .deferred(.unknown(.ttyProcesses))
        }
        guard let windows = snapshot.safety.hasVisibleWindows else {
            return .deferred(.unknown(.windows))
        }
        guard let menus = snapshot.safety.hasVisibleMenus else { return .deferred(.unknown(.menus)) }
        guard automatic else { return .deferred(.automaticUpdatesDisabled) }
        guard prepared >= Self.minimumPreparedAge else { return .deferred(.recentlyPrepared) }
        guard launch >= Self.minimumLaunchAge else { return .deferred(.recentlyLaunched) }
        guard idle >= Self.minimumHIDIdleTime else { return .deferred(.userActive) }
        guard !interaction else { return .deferred(.accountInteraction) }
        guard !processes else { return .deferred(.activeTTYProcesses) }
        guard !windows else { return .deferred(.visibleWindows) }
        guard !menus else { return .deferred(.visibleMenus) }
        return .eligible
    }

    private static func knownDuration(_ value: TimeInterval?) -> TimeInterval? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }
}
