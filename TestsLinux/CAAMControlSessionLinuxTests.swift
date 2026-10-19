import Foundation
import Testing
@testable import CodexBarCore

struct CAAMControlSessionLinuxTests {
    @Test
    func `freshness and complete capabilities gate every mutation`() {
        let fixture = CAAMControlFixtures.self
        let snapshot = fixture.snapshot()
        let ready = CAAMEnvironmentContract.rowState(
            configuration: fixture.configuration, snapshot: snapshot, now: fixture.now)
        #expect(ready.canSwitch)
        #expect(ready.canRestoreFallback)
        for age in [61.0, -6.0] {
            let row = CAAMEnvironmentContract.rowState(
                configuration: fixture.configuration, snapshot: snapshot, now: fixture.now.addingTimeInterval(age))
            #expect(row.availability == .stale)
            #expect(!row.canSwitch && !row.canRecover && !row.canRestoreFallback)
        }
        for capability in ["snapshot", "plan_switch", "execute_switch", "operation_status", "recover_switch"] {
            let snapshot = fixture.snapshot(capabilities: CAAMControlCapability.allCases.map(\.rawValue)
                .filter { $0 != capability } + ["future_switch"])
            let row = CAAMEnvironmentContract.rowState(
                configuration: fixture.configuration, snapshot: snapshot, now: fixture.now)
            #expect(!row.canSwitch && !row.canRestoreFallback)
        }
        let degraded = CAAMEnvironmentContract.rowState(
            configuration: fixture.configuration, snapshot: fixture.snapshot(reachability: .degraded), now: fixture.now)
        #expect(!degraded.canSwitch && !degraded.canRestoreFallback)
    }

    @Test
    func `confirmation is single use and qualification is independent of capability`() throws {
        var session = CAAMControlFixtures.session()
        _ = try session.beginPlan(target: "secondary", fallback: false, now: CAAMControlFixtures.now)
        try session.acceptPlan(CAAMControlFixtures.plan(), now: CAAMControlFixtures.now)
        let confirmation = try #require(session.confirmation)
        #expect(throws: CAAMControlFailure.self) {
            try session.confirm(id: confirmation.id, mutationsQualified: false, now: CAAMControlFixtures.now)
        }
        let operation = try session.confirm(
            id: confirmation.id, mutationsQualified: true, now: CAAMControlFixtures.now)
        #expect(operation.kind == "execute-switch")
        #expect(session.pendingOperationID == operation.operationID)
        #expect(session.phase == .executing)
        #expect(session.confirmation == nil)
        #expect(throws: CAAMControlFailure.self) {
            try session.confirm(id: confirmation.id, mutationsQualified: true, now: CAAMControlFixtures.now)
        }
    }

    @Test
    func `expired plans and changed revisions invalidate confirmation`() throws {
        var session = CAAMControlFixtures.session()
        _ = try session.beginPlan(target: "secondary", fallback: false, now: CAAMControlFixtures.now)
        try session.acceptPlan(CAAMControlFixtures.plan(), now: CAAMControlFixtures.now)
        let confirmation = try #require(session.confirmation)
        #expect(throws: CAAMControlFailure.self) {
            try session.confirm(
                id: confirmation.id, mutationsQualified: true, now: CAAMControlFixtures.now.addingTimeInterval(31))
        }
        session.observe(CAAMControlFixtures.snapshot(revision: "2"), now: CAAMControlFixtures.now)
        #expect(session.confirmation == nil)
        #expect(throws: CAAMControlFailure.self) {
            try session.confirm(id: confirmation.id, mutationsQualified: true, now: CAAMControlFixtures.now)
        }
    }

    @Test
    func `ambiguous execution survives snapshot refresh and failed lookup`() throws {
        var session = CAAMControlFixtures.session()
        _ = try session.beginPlan(target: "secondary", fallback: false, now: CAAMControlFixtures.now)
        try session.acceptPlan(CAAMControlFixtures.plan(), now: CAAMControlFixtures.now)
        let confirmation = try #require(session.confirmation)
        let execute = try session.confirm(
            id: confirmation.id, mutationsQualified: true, now: CAAMControlFixtures.now)
        session.failOperation(CAAMControlFailure(reason: .timeout, effect: .unknown), operation: execute)
        session.observe(CAAMControlFixtures.snapshot(), now: CAAMControlFixtures.now)
        #expect(session.phase == .unknown)
        #expect(session.pendingOperationID == execute.operationID)
        #expect(!session.canForget)
        #expect(!session.row(now: CAAMControlFixtures.now).canSwitch)
        let lookup = try session.beginLookup()
        #expect(lookup.kind == "operation-status")
        #expect(lookup.operationID == execute.operationID)
        session.failOperation(CAAMControlFailure(reason: .rejected), operation: lookup)
        #expect(session.pendingOperationID == execute.operationID)
        #expect(session.phase == .unknown)
        let result = CAAMControlFixtures.committed(operationID: try #require(execute.operationID))
        _ = try session.beginLookup()
        try session.acceptResult(result, now: CAAMControlFixtures.now)
        #expect(session.phase == .finished)
        #expect(session.pendingOperationID == nil)
        #expect(session.snapshot?.hostDefaultProfile == "secondary")
    }

    @Test
    func `fallback and recovery remain distinct confirmed operations`() throws {
        var fallback = CAAMControlFixtures.session()
        _ = try fallback.beginPlan(target: "secondary", fallback: true, now: CAAMControlFixtures.now)
        try fallback.acceptPlan(CAAMControlFixtures.plan(), now: CAAMControlFixtures.now)
        let confirmation = try #require(fallback.confirmation)
        let operation = try fallback.confirm(
            id: confirmation.id, mutationsQualified: true, now: CAAMControlFixtures.now)
        #expect(operation.kind == "restore-fallback")
        #expect(try operation.gatewayArguments().contains("--expected-revision"))

        var recovery = CAAMControlFixtures.session()
        recovery.observe(CAAMControlFixtures.snapshot(pending: CAAMPendingOperation(
            operationID: CAAMControlFixtures.operationID, state: .recoveryRequired)), now: CAAMControlFixtures.now)
        try recovery.prepareRecovery(now: CAAMControlFixtures.now)
        let recoveryConfirmation = try #require(recovery.confirmation)
        let recover = try recovery.confirm(
            id: recoveryConfirmation.id, mutationsQualified: true, now: CAAMControlFixtures.now)
        #expect(recover.kind == "recover-switch")
        #expect(recover.operationID == CAAMControlFixtures.operationID)
        recovery.failOperation(CAAMControlFailure(reason: .rejected), operation: recover)
        #expect(recovery.pendingOperationID == CAAMControlFixtures.operationID)
    }

    @Test
    func `manual intervention cannot be silently recovered or replaced by fallback`() {
        var session = CAAMControlFixtures.session()
        session.observe(CAAMControlFixtures.snapshot(pending: CAAMPendingOperation(
            operationID: CAAMControlFixtures.operationID, state: .manualRequired)), now: CAAMControlFixtures.now)
        let row = session.row(now: CAAMControlFixtures.now)
        #expect(session.phase == .manualRequired)
        #expect(!row.canSwitch && !row.canRecover && !row.canRestoreFallback)
        #expect(throws: CAAMControlFailure.self) { try session.prepareRecovery(now: CAAMControlFixtures.now) }
    }

    @Test
    func `stale while revalidate retains bounded evidence without mutation authority`() {
        var session = CAAMControlFixtures.session()
        session.failRefresh(CAAMControlFailure(reason: .timeout))
        let row = session.row(now: CAAMControlFixtures.now.addingTimeInterval(10))
        #expect(row.availability == .stale)
        #expect(row.currentProfile == "primary")
        #expect(row.observedAt == CAAMControlFixtures.now)
        #expect(!row.canSwitch)
        #expect(session.cachedSnapshot(now: CAAMControlFixtures.now.addingTimeInterval(901)) == nil)
        #expect(session.row(now: CAAMControlFixtures.now.addingTimeInterval(901)).availability == .unavailable)
    }

    @Test
    func `terminal result requires exact identity fresh postcondition and truthful rollback`() throws {
        let fixture = CAAMControlFixtures.self
        #expect(throws: CAAMControlFailure.self) {
            try CAAMEnvironmentContract.validateOperationResult(fixture.committed(), operationID: UUID())
        }
        let missingSnapshot = CAAMOperationResult(
            operationID: fixture.operationID, state: .committed, effect: .knownEffect)
        #expect(throws: CAAMControlFailure.self) {
            try CAAMEnvironmentContract.validateOperationResult(missingSnapshot, operationID: fixture.operationID)
        }
        let rollback = CAAMOperationResult(
            operationID: fixture.operationID, state: .rolledBack, effect: .knownEffect,
            previousProfile: "primary", currentProfile: "primary", snapshot: fixture.snapshot())
        try CAAMEnvironmentContract.validateOperationResult(rollback, operationID: fixture.operationID)
        var session = CAAMControlSession(configuration: fixture.configuration, pendingOperationID: fixture.operationID)
        #expect(throws: CAAMControlFailure.self) {
            try session.acceptResult(fixture.committed(), now: fixture.now.addingTimeInterval(61))
        }
        #expect(session.pendingOperationID == fixture.operationID)
    }
}
