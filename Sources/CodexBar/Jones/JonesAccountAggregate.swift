import CodexBarCore
import Foundation

struct JonesAccountAggregate: Equatable {
    let selectedCount: Int
    let reportingCount: Int
    let summedRemainingPercent: Int
    var paceTargetPercent: Int?

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
        workDays: Int? = nil) -> Self?
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
            return Self.contribution(row, identity: [workspace, email], now: now, workDays: workDays)
        }
        return Self.make(selectedCount: Self.codexAliases.count, contributions: contributions)
    }

    static func claude(
        enrolledAliases: [String],
        accounts: [ProviderAccountUsageSnapshot],
        refreshingAliases: Set<String> = [],
        now: Date = Date(),
        workDays: Int? = nil) -> Self?
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
            return Self.contribution(row, identity: key, now: now, workDays: workDays)
        }
        return Self.make(selectedCount: Self.claudeAliases.count, contributions: contributions)
    }

    private static func claudeFallback(_ identity: ProviderIdentitySnapshot) -> [String]? {
        guard let email = normalized(identity.accountEmail) else { return nil }
        return ["email", email, Self.normalized(identity.accountOrganization) ?? ""]
    }

    private struct Contribution {
        let identity: [String]
        let remainingPercent: Int
        let targetRemainingPercent: Int?
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
        workDays: Int?) -> Contribution?
    {
        guard row.error == nil, let remaining = AccountMenuLayoutPlanner.headroomPercent(for: row),
              remaining.isFinite else { return nil }
        let timedWindows = AccountMenuLayoutPlanner.limitingWindows(for: row).compactMap { window
            -> (reset: Date, target: Int)? in
            guard let minutes = window.windowMinutes, minutes > 0,
                  let reset = window.resetsAt,
                  let pace = UsagePace.weekly(
                      window: window, now: now, defaultWindowMinutes: minutes, workDays: workDays),
                  pace.expectedUsedPercent.isFinite else { return nil }
            return (reset, Int(min(100, max(0, 100 - pace.expectedUsedPercent)).rounded()))
        }
        // The latest valid reset controls a tied limit longest; equal resets retain planner order.
        let target = timedWindows.reduce(nil as (reset: Date, target: Int)?) { selected, candidate in
            guard let selected else { return candidate }
            return candidate.reset > selected.reset ? candidate : selected
        }?.target
        return Contribution(
            identity: identity,
            remainingPercent: Int(min(100, max(0, remaining)).rounded()),
            targetRemainingPercent: target)
    }

    private static func make(selectedCount: Int, contributions: [Contribution]) -> Self {
        var seen: Set<[String]> = []
        let unique = contributions.filter { seen.insert($0.identity).inserted }
        let targets = unique.compactMap(\.targetRemainingPercent)
        return Self(
            selectedCount: selectedCount,
            reportingCount: unique.count,
            summedRemainingPercent: unique.reduce(0) { $0 + $1.remainingPercent },
            paceTargetPercent: unique.count == selectedCount && targets.count == selectedCount
                ? targets.reduce(0, +) : nil)
    }
}
