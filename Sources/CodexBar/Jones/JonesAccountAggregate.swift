import CodexBarCore
import Foundation

struct JonesAccountAggregate: Equatable {
    let selectedCount: Int
    let reportingCount: Int
    let summedRemainingPercent: Int
    var paceTargetPercent: Int?
    var exhaustion: Exhaustion = .unknown(.missingTiming)
    var firstReset: Date?

    enum Tone: Equatable { case reserve, deficit, neutral }
    enum UnknownReason: Equatable { case partialRoster, missingTiming, tooEarly, beyondHorizon }
    enum Exhaustion: Equatable {
        case runsOut(at: Date, beforeFirstReset: Bool)
        case exhaustedNow
        case noUsage
        case unknown(UnknownReason)

        var shape: String {
            switch self {
            case let .runsOut(_, beforeFirstReset): beforeFirstReset ? "beforeReset" : "afterReset"
            case .exhaustedNow: "exhausted"
            case .noUsage: "noUsage"
            case let .unknown(reason): "unknown-\(reason)"
            }
        }
    }

    struct Line: Equatable {
        let text: String
        var tone: Tone = .neutral
    }

    var balancePoints: Int? {
        guard !self.isPartial, let paceTargetPercent else { return nil }
        return self.summedRemainingPercent - paceTargetPercent
    }

    var balanceTone: Tone {
        guard let balancePoints else { return .neutral }
        return balancePoints > 0 ? .reserve : balancePoints < 0 ? .deficit : .neutral
    }

    static func easternDateLabel(_ date: Date, compact: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = compact ? "EEE h:mm a" : "EEE MMM d h:mm a"
        return formatter.string(from: date)
    }

    var compactBalanceLabel: String {
        guard let balancePoints else {
            return self.isPartial ? L("Needs all accounts") : L("Pace unavailable")
        }
        if balancePoints == 0 { return L("On pace") }
        return balancePoints > 0
            ? "\(balancePoints)% in reserve"
            : "\(abs(balancePoints))% in deficit"
    }

    var compactCapacityLabel: String {
        "of \(self.maximumPercent)%"
    }

    var compactExhaustionLabel: String {
        switch self.exhaustion {
        case let .runsOut(date, _): Self.easternDateLabel(date, compact: true)
        case .exhaustedNow: L("Now")
        case .noUsage: L("No usage")
        case .unknown(.partialRoster): L("Needs all accounts")
        case .unknown(.missingTiming): L("Timing unavailable")
        case .unknown(.tooEarly): L("Too early")
        case .unknown(.beyondHorizon): L("Beyond 28 days")
        }
    }

    var expandedHelpText: String {
        self.expandedLines.map(\.text).joined(separator: "\n")
    }

    var expandedLines: [Line] {
        var lines: [Line] = []
        if let balance = self.balancePoints, let target = self.paceTargetPercent {
            let text = balance == 0 ? L("On pace")
                : "\(balance > 0 ? L("Reserve") : L("Deficit")) \(balance > 0 ? "+" : "−")" +
                "\(abs(balance))% (of \(self.maximumPercent)%)"
            lines.append(Line(text: text, tone: self.balanceTone))
            lines.append(Line(text: "Target \(target) · Remaining \(self.summedRemainingPercent)"))
        } else {
            lines.append(Line(text: self.isPartial
                    ? "Pace needs all \(self.selectedCount) · \(self.reportingCount) reporting"
                    : L("Pace timing unavailable")))
        }
        switch self.exhaustion {
        case let .runsOut(date, beforeFirstReset):
            lines.append(Line(
                text: beforeFirstReset ? L("Estimated empty at pooled pace") : L("Estimate ignores refills"),
                tone: beforeFirstReset ? .deficit : .neutral))
            lines.append(Line(text: "≈ \(Self.easternDateLabel(date))", tone: beforeFirstReset ? .deficit : .neutral))
            lines.append(Line(text: L("Assumes demand moves across accounts")))
            if !beforeFirstReset { lines.append(Line(text: L("Resets begin before this estimate"))) }
        case .exhaustedNow:
            lines.append(Line(text: L("All accounts at 0 now"), tone: .deficit))
        case .noUsage:
            lines.append(Line(text: L("No usage · lasts until reset")))
        case let .unknown(reason):
            let text = switch reason {
            case .partialRoster: L("Estimate needs all accounts")
            case .missingTiming: L("Estimate timing unavailable")
            case .tooEarly: L("Too early to estimate")
            case .beyondHorizon: L("Estimate beyond 28 days")
            }
            lines.append(Line(text: text))
        }
        if let firstReset {
            lines.append(Line(text: L("First reset")))
            lines.append(Line(text: Self.easternDateLabel(firstReset)))
        }
        return lines
    }

    func accessibilityText(isExpanded: Bool) -> String {
        guard isExpanded else { return self.accessibilityText }
        var parts = [self.accessibilityText]
        if let balancePoints {
            parts.append("\(balancePoints) percentage points of \(self.maximumPercent) percentage points capacity")
        }
        parts.append(contentsOf: self.expandedLines.map(\.text))
        return parts.joined(separator: ", ")
    }

    func heightFingerprint(isExpanded: Bool) -> String {
        guard isExpanded else { return self.heightFingerprint + "|exp=0" }
        return self.heightFingerprint + "|exp=1|compactRows=2"
    }

    var paceMarkerPercent: Double? {
        guard let paceTargetPercent, self.selectedCount > 0 else { return nil }
        return Double(paceTargetPercent) / Double(self.selectedCount)
    }

    var maximumPercent: Int {
        self.selectedCount * 100
    }

    var isPartial: Bool {
        self.reportingCount < self.selectedCount
    }

    var normalizedPercent: Double? {
        self.reportingCount > 0 ? Double(self.summedRemainingPercent) / Double(self.selectedCount) : nil
    }

    var normalizedLabel: String {
        guard let normalizedPercent else { return L("Unavailable") }
        let value = normalizedPercent.formatted(.number.precision(.fractionLength(0...1)))
        return "\(self.isPartial ? "≥" : "")\(value)%"
    }

    var countLabel: String {
        self.isPartial
            ? String(format: L("%d of %d reporting"), self.reportingCount, self.selectedCount)
            : String(format: L("%d accounts"), self.selectedCount)
    }

    var remainingLabel: String? {
        guard self.reportingCount > 0 else { return nil }
        return "\(self.isPartial ? "≥" : "")\(self.summedRemainingPercent)% / \(self.maximumPercent)%"
    }

    var detailLabel: String {
        [self.countLabel, self.remainingLabel].compactMap(\.self).joined(separator: " · ")
    }

    var accessibilityText: String {
        guard let normalizedPercent else {
            return "\(L("Total remaining")), \(L("Unavailable")), \(self.detailLabel), \(self.paceAccessibilityText)"
        }
        let value = normalizedPercent.formatted(.number.precision(.fractionLength(0...1)))
        let remaining = self.isPartial
            ? String(format: L("At least %@ percent remaining"), value)
            : String(format: L("%@ percent remaining"), value)
        return "\(L("Total remaining")), \(remaining), \(self.detailLabel), \(self.paceAccessibilityText)"
    }

    private var paceAccessibilityText: String {
        guard let paceTargetPercent else { return L("Pacing unavailable") }
        return String(format: L("On-pace target %d of %d percent"), paceTargetPercent, self.maximumPercent)
    }

    var heightFingerprint: String {
        "accountAggregate|\(self.selectedCount)|\(self.reportingCount)|\(self.summedRemainingPercent)"
    }

    static let codexAliases = ["malcolm", "jace", "umich", "steven", "wallace"]
    static let claudeAliases = ["default", "jace"]

    static func codex(
        projection: CodexVisibleAccountProjection?,
        accounts: [ProviderAccountUsageSnapshot],
        now: Date = Date(),
        workDays: Int? = nil,
        calendar: Calendar = .current) -> Self?
    {
        guard let projection else { return nil }
        let enrolled = Dictionary(grouping: projection.fleetProfileHomePaths, by: {
            URL(fileURLWithPath: $0).lastPathComponent
        })
        guard Self.codexAliases.contains(where: { enrolled[$0] != nil }) else { return nil }
        let contributions = Self.codexAliases.compactMap { alias -> Contribution? in
            guard let paths = enrolled[alias], paths.count == 1,
                  let path = CodexHomeScope.normalizedHomePath(paths[0]) else { return nil }
            let visible = projection.visibleAccounts.filter {
                guard case let .profileHome(home) = $0.selectionSource else { return false }
                return CodexHomeScope.normalizedHomePath(home) == path
            }
            guard visible.count == 1, let account = visible.first,
                  let workspace = Self.normalized(account.workspaceAccountID),
                  let email = Self.normalized(account.email) else { return nil }
            // Provider-specific by design: enrolled Codex slots bind profile homes to verified workspace/email seats.
            let rows = accounts.filter {
                $0.provider == .codex && $0.id == ProviderAccountIdentity(source: "codex-account", opaqueID: account.id)
            }
            guard rows.count == 1, let row = rows.first else { return nil }
            return Self.contribution(
                row,
                identity: [workspace, email],
                now: now,
                workDays: workDays,
                calendar: calendar)
        }
        return Self.make(
            selectedCount: Self.codexAliases.count,
            contributions: contributions,
            now: now,
            workDays: workDays,
            calendar: calendar)
    }

    static func claude(
        enrolledAliases: [String],
        accounts: [ProviderAccountUsageSnapshot],
        refreshingAliases: Set<String> = [],
        now: Date = Date(),
        workDays: Int? = nil,
        calendar: Calendar = .current) -> Self?
    {
        guard self.claudeAliases.contains(where: enrolledAliases.contains), !accounts.isEmpty else { return nil }
        // Provider-specific by design: reconcile Claude's fallback identity with any selected verified account ID.
        var accountIDsByFallback: [[String]: Set<String>] = [:]
        for row in accounts where row.provider == .claude && row.id.source == "claude-native-profile" &&
            Self.claudeAliases.contains(row.id.opaqueID) && enrolledAliases.contains(row.id.opaqueID)
        {
            guard let identity = row.snapshot?.identity(for: .claude),
                  let accountID = Self.normalized(identity.accountID),
                  let fallback = Self.claudeFallback(identity) else { continue }
            accountIDsByFallback[fallback, default: []].insert(accountID)
        }
        let contributions = Self.claudeAliases.compactMap { alias -> Contribution? in
            guard enrolledAliases.count(where: { $0 == alias }) == 1,
                  !refreshingAliases.contains(alias) else { return nil }
            // Provider-specific by design: Claude native profiles use provider identity, never profile labels.
            let rows = accounts.filter {
                $0.provider == .claude && $0.id == ProviderAccountIdentity(
                    source: "claude-native-profile",
                    opaqueID: alias)
            }
            guard rows.count == 1, let row = rows.first,
                  let identity = row.snapshot?.identity(for: .claude) else { return nil }
            let key: [String]
            if let accountID = Self.normalized(identity.accountID) {
                key = ["account", accountID]
            } else if let fallback = Self.claudeFallback(identity) {
                let knownIDs = accountIDsByFallback[fallback] ?? []
                guard knownIDs.count <= 1 else { return nil }
                key = knownIDs.first.map { ["account", $0] } ?? fallback
            } else {
                return nil
            }
            return Self.contribution(row, identity: key, now: now, workDays: workDays, calendar: calendar)
        }
        return Self.make(
            selectedCount: Self.claudeAliases.count,
            contributions: contributions,
            now: now,
            workDays: workDays,
            calendar: calendar)
    }

    private static func claudeFallback(_ identity: ProviderIdentitySnapshot) -> [String]? {
        guard let email = normalized(identity.accountEmail) else { return nil }
        return ["email", email, Self.normalized(identity.accountOrganization) ?? ""]
    }

    private struct Contribution {
        let identity: [String]
        let remainingPercent: Int
        let targetRemainingPercent: Int?
        let controllingReset: Date?
        let ratePerSecond: Double?
        let wallClockRate: Double?
        let usesWorkdayClock: Bool
        let tooEarly: Bool
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !value.isEmpty else { return nil }
        return value
    }

    private static func contribution(
        _ row: ProviderAccountUsageSnapshot,
        identity: [String],
        now: Date,
        workDays: Int?,
        calendar: Calendar) -> Contribution?
    {
        guard row.error == nil, let remaining = AccountMenuLayoutPlanner.headroomPercent(for: row),
              remaining.isFinite else { return nil }
        typealias TimedWindow = (reset: Date, pace: UsagePace, wallRate: Double?, tooEarly: Bool)
        let timedWindows = AccountMenuLayoutPlanner.limitingWindows(for: row).compactMap { window -> TimedWindow? in
            guard let minutes = window.windowMinutes, minutes > 0,
                  let reset = window.resetsAt,
                  let pace = UsagePace.weekly(
                      window: window,
                      now: now,
                      defaultWindowMinutes: minutes,
                      workDays: workDays,
                      calendar: calendar),
                  pace.expectedUsedPercent.isFinite, pace.actualUsedPercent.isFinite else { return nil }
            let elapsed = Double(minutes) * 60 - reset.timeIntervalSince(now)
            let wallRate = elapsed > 0 ? pace.actualUsedPercent / elapsed : pace.actualUsedPercent == 0 ? 0 : nil
            return (reset, pace, wallRate, pace.actualUsedPercent > 0 && pace.expectedUsedPercent < 3)
        }
        // The latest valid reset controls a tied limit longest; equal resets retain planner order.
        let controlling = timedWindows.reduce(nil as TimedWindow?) { selected, candidate in
            guard let selected else { return candidate }
            return candidate.reset > selected.reset ? candidate : selected
        }
        return Contribution(
            identity: identity,
            remainingPercent: Int(min(100, max(0, remaining)).rounded()),
            targetRemainingPercent: controlling.map {
                Int(min(100, max(0, 100 - $0.pace.expectedUsedPercent)).rounded())
            },
            controllingReset: controlling?.reset,
            ratePerSecond: controlling?.pace.consumptionRatePerSecond,
            wallClockRate: controlling?.wallRate,
            usesWorkdayClock: controlling?.pace.usesWorkdayClock ?? false,
            tooEarly: controlling?.tooEarly ?? false)
    }

    private static func make(
        selectedCount: Int,
        contributions: [Contribution],
        now: Date,
        workDays: Int?,
        calendar: Calendar) -> Self
    {
        var seen: Set<[String]> = []
        let unique = contributions.filter { seen.insert($0.identity).inserted }
        let targets = unique.compactMap(\.targetRemainingPercent)
        let completeTiming = unique.count == selectedCount && targets.count == selectedCount
        let remaining = unique.reduce(0) { $0 + $1.remainingPercent }
        let firstReset = completeTiming ? unique.compactMap(\.controllingReset).min() : nil
        let exhaustion: Exhaustion
        if unique.count != selectedCount {
            exhaustion = .unknown(.partialRoster)
        } else if remaining == 0 {
            exhaustion = .exhaustedNow
        } else if !completeTiming {
            exhaustion = .unknown(.missingTiming)
        } else if unique.contains(where: \.tooEarly) {
            exhaustion = .unknown(.tooEarly)
        } else {
            let workdayClock = unique.allSatisfy(\.usesWorkdayClock)
            let rates = unique.compactMap { workdayClock ? $0.ratePerSecond : $0.wallClockRate }
            let rate = rates.reduce(0, +)
            if rates.count != selectedCount || !rate.isFinite {
                exhaustion = .unknown(.missingTiming)
            } else if rate == 0 {
                exhaustion = .noUsage
            } else {
                let seconds = Double(remaining) / rate
                let interval = workdayClock ? workDays.flatMap {
                    UsagePace.wallClockInterval(
                        from: now, consumingWorkSeconds: seconds, workDays: $0, calendar: calendar)
                } : seconds <= 28 * 86400 ? seconds : nil
                if let interval, let firstReset {
                    let date = now.addingTimeInterval(interval)
                    exhaustion = .runsOut(at: date, beforeFirstReset: date < firstReset)
                } else {
                    exhaustion = .unknown(.beyondHorizon)
                }
            }
        }
        return Self(
            selectedCount: selectedCount,
            reportingCount: unique.count,
            summedRemainingPercent: remaining,
            paceTargetPercent: completeTiming ? targets.reduce(0, +) : nil,
            exhaustion: exhaustion,
            firstReset: firstReset)
    }
}
