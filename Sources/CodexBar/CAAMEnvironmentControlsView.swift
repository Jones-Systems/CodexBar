import CodexBarCore
import SwiftUI

@MainActor
struct CAAMEnvironmentControlsView: View {
    let configuration: CAAMEnvironmentConfiguration
    @Bindable var coordinator: CAAMEnvironmentCoordinator

    private var session: CAAMControlSession { self.coordinator.session(for: self.configuration) }

    var body: some View {
        let session = self.session
        let row = session.row(now: Date())
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Menu(L("Plan switch")) {
                    ForEach(session.snapshot?.profiles.filter { $0.eligible && !$0.active } ?? []) { profile in
                        Button(profile.name) {
                            Task {
                                await self.coordinator.plan(configuration: self.configuration, target: profile.name)
                            }
                        }
                    }
                }
                .disabled(!row.canSwitch || self.coordinator.isRefreshing || session.phase.isBusy)
                Button(L("Plan fallback")) {
                    guard let target = session.snapshot?.fallbackProfile else { return }
                    Task {
                        await self.coordinator.plan(configuration: self.configuration, target: target, fallback: true)
                    }
                }
                .disabled(!row.canRestoreFallback || self.coordinator.isRefreshing || session.phase.isBusy)
                if session.pendingOperationID != nil {
                    Button(L("Look up operation")) {
                        Task { await self.coordinator.lookup(configuration: self.configuration) }
                    }
                    .disabled(session.phase.isBusy || self.coordinator.isRefreshing)
                    Button(L("Review recovery")) {
                        self.coordinator.prepareRecovery(configuration: self.configuration)
                    }
                    .disabled(!row.canRecover || session.phase.isBusy || self.coordinator.isRefreshing)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(self.coordinator.isOperating)

            if session.phase.isBusy {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(L("Waiting for CAAM; the app remains available."))
                }
                .font(.caption)
            }
            if let operationID = session.pendingOperationID {
                Text(String(format: L("Unresolved operation: %@"), operationID.uuidString.lowercased()))
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
            }
            if session.phase == .unknown {
                Text(L("Operation outcome is unresolved. Look up the existing operation before another change."))
                    .font(.caption).foregroundStyle(.orange)
            }
            if session.phase == .manualRequired {
                Text(L("CAAM requires manual intervention on this environment. Automatic recovery is disabled."))
                    .font(.caption).foregroundStyle(.orange)
            }
            if let failure = session.failure {
                Text(failure.localizedDescription).font(.caption).foregroundStyle(.orange)
                if let code = failure.code {
                    Text(String(format: L("Gateway code: %@"), code)).font(.caption2.monospaced())
                }
            }
            if let result = session.lastResult {
                Text(String(format: L("Last operation: %@ · %@"), result.state.rawValue, result.effect.rawValue))
                    .font(.caption)
            }
            if let confirmation = session.confirmation {
                self.confirmationView(confirmation)
            } else if !self.coordinator.mutationsQualified(for: self.configuration) {
                Text(L("Read-only until CAAM conformance is independently qualified."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func confirmationView(_ confirmation: CAAMControlConfirmation) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Text(self.confirmationTitle(confirmation.kind)).font(.caption.weight(.semibold))
                Text(String(format: L("Expected revision: %@"), confirmation.revision)).font(.caption.monospaced())
                if let plan = confirmation.plan {
                    Text(String(
                        format: L("Change host default: %@ → %@"),
                        plan.currentProfile ?? "—",
                        plan.targetProfile))
                    Text(String(format: L("Plan digest: %@"), plan.planDigest)).font(.caption2.monospaced())
                    Text(plan.expiresAt, style: .time).font(.caption)
                    DisclosureGroup(L("Affected profiles")) {
                        ScrollView {
                            Text(plan.affectedProfiles.joined(separator: ", "))
                                .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 100)
                    }
                    if plan.reloadRequired {
                        Text(L("A running Codex process may need to reload.")).font(.caption)
                    }
                } else {
                    Text(L("CAAM may complete or roll back its pending transaction. This does not restore fallback."))
                        .font(.caption)
                }
                HStack {
                    Button(L("Confirm once")) {
                        Task {
                            await self.coordinator.confirm(
                                configuration: self.configuration,
                                confirmationID: confirmation.id)
                        }
                    }
                    .disabled(!self.coordinator.mutationsQualified(for: self.configuration) ||
                        self.coordinator.isOperating || self.coordinator.isRefreshing)
                    Button(L("Cancel")) { self.coordinator.cancelConfirmation(configuration: self.configuration) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                if !self.coordinator.mutationsQualified(for: self.configuration) {
                    Text(L("Read-only until CAAM conformance is independently qualified."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func confirmationTitle(_ kind: CAAMControlConfirmation.Kind) -> String {
        switch kind {
        case .switchProfile: L("Review switch plan")
        case .restoreFallback: L("Review fallback restoration")
        case .recoverSwitch: L("Review interrupted-operation recovery")
        }
    }
}
