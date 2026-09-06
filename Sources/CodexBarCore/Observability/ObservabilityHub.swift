import Foundation

public enum HubAvailability: String, Sendable, Equatable {
    case available
    case stale
    case partial
    case unavailable
    case unsupported
}

public struct HubEvidence: Sendable, Equatable {
    public let source: String
    public let observedAt: Date?
    public let availability: HubAvailability

    public init(source: String, observedAt: Date?, availability: HubAvailability) {
        self.source = String(String.UnicodeScalarView(
            source.unicodeScalars.prefix(160).filter { !CharacterSet.controlCharacters.contains($0) }))
        self.observedAt = observedAt
        self.availability = availability
    }

    public static func cached(
        source: String,
        observedAt: Date?,
        failed: Bool,
        partial: Bool = false,
        now: Date) -> Self
    {
        guard let observedAt else {
            return Self(source: source, observedAt: nil, availability: .unavailable)
        }
        let age = now.timeIntervalSince(observedAt)
        let stale = failed || !age.isFinite || age < -5 || age > 300
        return Self(source: source, observedAt: observedAt, availability: stale ? .stale : partial ? .partial : .available)
    }
}

public struct HubAccountObservation: Sendable, Equatable, Identifiable {
    public let environmentID: String
    public let environmentLabel: String
    public let profile: String
    public let provider: String?
    public let stableID: String?
    public let displayLabel: String?
    public let hostDefault: Bool
    public let health: CAAMProfileHealth
    public let evidence: HubEvidence

    public var id: String { "\(self.environmentID):\(self.profile)" }

    /// Correlation never joins profile names or display emails across environments/providers.
    public func isSameAccount(as other: Self) -> Bool {
        guard let provider, let stableID else { return false }
        return provider == other.provider && stableID == other.stableID
    }
}

public struct HubServiceObservation: Sendable, Equatable, Identifiable {
    public let row: CAAMEnvironmentRowState
    public let runtimeEffectiveProfile: String?
    public let pendingOperationID: UUID?
    public let evidence: HubEvidence

    public var id: String { self.row.id }
}

public struct HubCostObservation: Sendable, Equatable {
    public let amount: Double?
    public let meteredAmount: Double?
    public let currency: String
    public let historyDays: Int
    public let provenance: CostProvenance
    public let evidence: HubEvidence
}

public struct HubProviderObservation: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let primaryUsedPercent: Double?
    public let windowMinutes: Int?
    public let resetsAt: Date?
    public let confidence: UsageDataConfidence
    public let evidence: HubEvidence
    public let cost: HubCostObservation?
}

public struct HubWorkObservation: Sendable, Equatable, Identifiable {
    public let id: String
    public let provider: String
    public let ordinal: Int
    public let lastActivity: Date
    public let tokens: Int?
    public let estimatedCostUSD: Double?
    public let evidence: HubEvidence
}

public struct HubProviderInput: Sendable {
    public let id: String
    public let label: String
    public let source: String
    public let usage: UsageSnapshot?
    public let cost: CostUsageTokenSnapshot?
    public let usageFailed: Bool
    public let costFailed: Bool

    public init(
        id: String,
        label: String,
        source: String,
        usage: UsageSnapshot?,
        cost: CostUsageTokenSnapshot?,
        usageFailed: Bool = false,
        costFailed: Bool = false)
    {
        self.id = id
        self.label = label
        self.source = source
        self.usage = usage
        self.cost = cost
        self.usageFailed = usageFailed
        self.costFailed = costFailed
    }
}

/// Separate ledgers by construction: there is deliberately no combined utilization or spend total.
public struct ObservabilityHubSnapshot: Sendable, Equatable {
    public let services: [HubServiceObservation]
    public let accounts: [HubAccountObservation]
    public let providers: [HubProviderObservation]
    public let hosts: [HubHostObservation]
    public let work: [HubWorkObservation]
    public let workIsPartial: Bool
}

public enum ObservabilityHub {
    public static let maximumProviders = 64
    public static let maximumWorkRows = 100

    public static func aggregate(
        sessions: [CAAMControlSession],
        providers: [HubProviderInput],
        includeWork: Bool = false,
        now: Date) -> ObservabilityHubSnapshot
    {
        let boundedSessions = sessions.prefix(CAAMEnvironmentContract.maximumEnvironmentCount)
        let services = boundedSessions.map { session in
            let row = session.row(now: now)
            return HubServiceObservation(
                row: row,
                runtimeEffectiveProfile: session.cachedSnapshot(now: now)?.runtime.effectiveProfile,
                pendingOperationID: session.pendingOperationID,
                evidence: self.evidence(for: row))
        }
        let accounts = boundedSessions.flatMap { session -> [HubAccountObservation] in
            guard let snapshot = session.cachedSnapshot(now: now) else { return [] }
            let evidence = self.evidence(for: session.row(now: now))
            return snapshot.profiles.prefix(CAAMEnvironmentContract.maximumProfileCount).map { profile in
                HubAccountObservation(
                    environmentID: session.configuration.id,
                    environmentLabel: session.configuration.label,
                    profile: profile.name,
                    provider: profile.identity?.provider,
                    stableID: profile.identity?.stableID,
                    displayLabel: profile.identity?.displayEmail ?? profile.identity?.workspaceLabel,
                    hostDefault: profile.name == snapshot.hostDefaultProfile,
                    health: profile.health,
                    evidence: evidence)
            }
        }
        let boundedProviders = providers.prefix(self.maximumProviders)
        let providerRows = boundedProviders.map { input in
            let primary = input.usage?.primary
            let percent = primary?.isSyntheticPlaceholder == false ? self.nonnegative(primary?.usedPercent) : nil
            let cost = input.cost.map { snapshot in
                HubCostObservation(
                    amount: self.nonnegative(snapshot.last30DaysCostUSD),
                    meteredAmount: self.nonnegative(snapshot.meteredCostUSD),
                    currency: snapshot.currencyCode,
                    historyDays: snapshot.historyDays,
                    provenance: snapshot.costProvenance,
                    evidence: .cached(
                        source: "Existing provider cost cache", observedAt: snapshot.updatedAt,
                        failed: input.costFailed,
                        partial: !snapshot.historyCoverageIsEstablished || snapshot.costProvenance == .unknown,
                        now: now))
            }
            return HubProviderObservation(
                id: input.id,
                label: input.label,
                primaryUsedPercent: percent,
                windowMinutes: primary?.windowMinutes,
                resetsAt: primary?.resetsAt,
                confidence: input.usage?.dataConfidence ?? .unknown,
                evidence: .cached(
                    source: input.source.isEmpty ? "Existing provider snapshot" : input.source,
                    observedAt: input.usage?.updatedAt, failed: input.usageFailed, partial: percent == nil, now: now),
                cost: cost)
        }
        var work: [HubWorkObservation] = []
        var workIsPartial = false
        // Work details use only already-loaded records, and are not materialized for other tabs.
        if includeWork {
            for input in boundedProviders {
                guard let cost = input.cost else { continue }
                let available = self.maximumWorkRows - work.count
                if cost.sessions.count > available { workIsPartial = true }
                for (index, session) in cost.sessions.prefix(available).enumerated() {
                    work.append(HubWorkObservation(
                        id: "\(input.id):\(index)", provider: input.label, ordinal: index + 1,
                        lastActivity: session.lastActivity,
                        tokens: session.totalTokens.flatMap { $0 >= 0 ? $0 : nil },
                        estimatedCostUSD: self.nonnegative(session.costUSD),
                        evidence: .cached(
                            source: "Recorded local session cache", observedAt: cost.updatedAt,
                            failed: input.costFailed, partial: true, now: now)))
                }
            }
        }
        return ObservabilityHubSnapshot(
            services: services, accounts: accounts, providers: providerRows,
            hosts: services.map { NetdataReadOnlyFacade.unavailable(environmentID: $0.id) },
            work: work, workIsPartial: workIsPartial)
    }

    private static func nonnegative(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    private static func evidence(for row: CAAMEnvironmentRowState) -> HubEvidence {
        let availability: HubAvailability = switch row.availability {
        case .ready: .available
        case .stale: .stale
        case .degraded, .recoveryRequired: .partial
        case .incompatible: .unsupported
        case .unavailable: .unavailable
        }
        return HubEvidence(source: "CAAM gateway snapshot", observedAt: row.observedAt, availability: availability)
    }
}
