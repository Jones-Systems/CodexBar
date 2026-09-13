import Foundation

/// One durable journal per control plane, shared across its coordinators. Targets default to unqualified.
/// Confirmation must display the exact plan; calling execute is the caller's explicit confirmation boundary.
public actor RepositorySyncCoordinator {
    private let host: any RepositorySyncHost
    private let journal: RepositorySyncJournal
    private let qualifiedTargets: Set<RepositorySyncTarget>

    public init(
        host: any RepositorySyncHost,
        journal: RepositorySyncJournal,
        qualifiedTargets: Set<RepositorySyncTarget> = [])
    {
        self.host = host
        self.journal = journal
        self.qualifiedTargets = qualifiedTargets
    }

    public func execute(_ plan: RepositorySyncPlan, now: Date = Date()) async throws -> RepositorySyncRecord {
        // An expired or dequalified prior intent still needs original-target readback, not resubmission.
        if let existing = try await self.journal.record(plan.operationID) {
            guard existing.plan == plan else { throw RepositorySyncError.operationConflict }
            return existing
        }
        try plan.validate(at: now)
        guard self.qualifiedTargets.contains(plan.snapshot.target) else { throw RepositorySyncError.unqualifiedTarget }
        let reserved = try await self.journal.reserve(plan)
        guard reserved else { return try await self.requiredRecord(plan.operationID) }
        let current = try await self.requiredRecord(plan.operationID)
        if Task.isCancelled || current.cancellationRequested {
            return try await self.journal.setState(.cancelled, for: plan.operationID)
        }
        if plan.action == .unchanged {
            return try await self.journal.setState(.notApplied, for: plan.operationID)
        }
        // From this point onward, every thrown error (including cancellation) is unknown effect.
        // The host must atomically recheck the plan and retain a cancellation tombstone even before execute arrives.
        do {
            let receipt = try await self.host.execute(plan)
            try receipt.validate(for: plan)
            return try await self.journal.setState(receipt.state, for: plan.operationID)
        } catch {
            return try await self.journal.setState(.unknown, for: plan.operationID)
        }
    }

    /// Only queries the original operation/target. Unresolved and not-found never authorize retry.
    public func reconcile(_ operationID: UUID) async throws -> RepositorySyncRecord {
        let record = try await self.requiredRecord(operationID)
        guard !record.state.isTerminal, record.state != .conflicted else { return record }
        do {
            switch try await self.host.status(of: record.plan) {
            case .unresolved:
                return try await self.journal.setState(.unknown, for: operationID)
            case let .terminal(receipt):
                try receipt.validate(for: record.plan)
                return try await self.journal.setState(receipt.state, for: operationID)
            }
        } catch {
            return try await self.journal.setState(.unknown, for: operationID)
        }
    }

    /// Cancellation is a durable request, not proof that Git did not change. Applied wins a cancellation race.
    public func cancel(_ operationID: UUID) async throws -> RepositorySyncRecord {
        let existing = try await self.requiredRecord(operationID)
        guard !existing.state.isTerminal, existing.state != .conflicted else { return existing }
        guard self.qualifiedTargets.contains(existing.plan.snapshot.target)
        else { throw RepositorySyncError.unqualifiedTarget }
        let record = try await self.journal.requestCancellation(operationID)
        guard !record.state.isTerminal, record.state != .conflicted else { return record }
        do {
            try await self.host.requestCancellation(of: record.plan)
        } catch {
            // Reconciliation below is still required, regardless of signal delivery acknowledgement.
        }
        return try await self.reconcile(operationID)
    }

    public func record(_ operationID: UUID) async throws -> RepositorySyncRecord? {
        try await self.journal.record(operationID)
    }

    private func requiredRecord(_ operationID: UUID) async throws -> RepositorySyncRecord {
        guard let record = try await self.journal.record(operationID)
        else { throw RepositorySyncError.unknownOperation }
        return record
    }
}
