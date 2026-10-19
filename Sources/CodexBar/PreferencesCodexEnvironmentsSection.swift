import CodexBarCore
import Foundation
import SwiftUI

struct CodexEnvironmentsSectionState: Equatable {
    let configurations: [CAAMEnvironmentConfiguration]
    let rows: [CAAMEnvironmentRowState]
    let isRefreshing: Bool
    let notice: String?

    var canAddLocal: Bool {
        !self.configurations.contains { $0.connection.kind == .local }
    }
}

@MainActor
struct CodexEnvironmentsSectionView: View {
    let state: CodexEnvironmentsSectionState
    let coordinator: CAAMEnvironmentCoordinator
    let saveConfigurations: ([CAAMEnvironmentConfiguration]) -> String?
    let refresh: () -> Void

    @State private var showsRemoteEditor = false
    @State private var remoteLabel = ""
    @State private var remoteDestination = ""
    @State private var localNotice: String?

    var body: some View {
        Section {
            if self.state.rows.isEmpty {
                Text(L("No CAAM environments configured."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(self.state.rows) { row in
                    VStack(alignment: .leading, spacing: 8) {
                        CodexEnvironmentRowView(
                            row: row,
                            canRemove: self.coordinator.canChangeConfigurations(
                                from: self.state.configurations,
                                to: self.state.configurations.filter { $0.id != row.id }),
                            remove: { self.removeEnvironment(id: row.id) })
                        if let configuration = self.state.configurations.first(where: { $0.id == row.id }) {
                            CAAMEnvironmentControlsView(configuration: configuration, coordinator: self.coordinator)
                        }
                    }
                }
            }

            ForEach(self.coordinator.retainedConfigurations(outside: self.state.configurations)) { configuration in
                GroupBox(L("Retained unresolved operation")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(configuration.label) · \(configuration.id)").font(.caption.weight(.semibold))
                        Text(L("Status and recovery remain bound to the original environment configuration."))
                            .font(.caption)
                        CAAMEnvironmentControlsView(configuration: configuration, coordinator: self.coordinator)
                    }
                }
            }

            if self.showsRemoteEditor {
                VStack(alignment: .leading, spacing: 8) {
                    TextField(L("Environment name"), text: self.$remoteLabel)
                        .textFieldStyle(.roundedBorder)
                    TextField(L("SSH destination"), text: self.$remoteDestination)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button(L("Add")) { self.addRemoteEnvironment() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        Button(L("Cancel")) { self.cancelRemoteEditor() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }

            if let notice = self.localNotice ?? self.state.notice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if self.state.canAddLocal {
                    Button(L("Add Laptop")) { self.addLocalEnvironment() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(self.state.isRefreshing)
                }
                Button(L("Add Remote Environment")) {
                    self.localNotice = nil
                    self.showsRemoteEditor = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(self.showsRemoteEditor || self.state.isRefreshing)

                Spacer(minLength: 8)

                Button {
                    self.refresh()
                } label: {
                    if self.state.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(L("Refresh"))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(self.state.configurations.isEmpty || self.state.isRefreshing)
            }
        } header: {
            Text(L("Environments"))
        } footer: {
            SettingsSectionFooter(
                L("CAAM keeps credentials on each environment. Remote access uses your SSH configuration."))
        }
    }

    private func addLocalEnvironment() {
        let local = CAAMEnvironmentConfiguration(
            id: "laptop",
            label: L("Laptop"),
            connection: .local())
        self.save(self.state.configurations + [local])
    }

    private func addRemoteEnvironment() {
        let id = "environment-\(UUID().uuidString.lowercased())"
        let remote = CAAMEnvironmentConfiguration(
            id: id,
            label: self.remoteLabel.trimmingCharacters(in: .whitespacesAndNewlines),
            connection: .ssh(destination: self.remoteDestination.trimmingCharacters(in: .whitespacesAndNewlines)))
        guard self.save(self.state.configurations + [remote]) else { return }
        self.cancelRemoteEditor()
    }

    private func removeEnvironment(id: String) {
        self.save(self.state.configurations.filter { $0.id != id })
    }

    @discardableResult
    private func save(_ configurations: [CAAMEnvironmentConfiguration]) -> Bool {
        self.localNotice = self.saveConfigurations(configurations)
        return self.localNotice == nil
    }

    private func cancelRemoteEditor() {
        self.remoteLabel = ""
        self.remoteDestination = ""
        self.showsRemoteEditor = false
        self.localNotice = nil
    }
}

@MainActor
private struct CodexEnvironmentRowView: View {
    let row: CAAMEnvironmentRowState
    let canRemove: Bool
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(self.row.label)
                        .font(.subheadline.weight(.semibold))
                    Text(self.row.connectionKind == .local ? L("Local") : L("SSH"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }

                Text(self.primaryStatus)
                    .font(.caption)
                    .foregroundStyle(self.row.availability == .unavailable ? .orange : .secondary)

                if let message = self.row.message, self.row.currentProfile != nil {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let fallback = self.row.fallbackProfile {
                    Text(String(format: L("Fallback: %@"), fallback))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if self.row.reloadRequired {
                    Text(L("A running Codex process may need to reload."))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let runtime = self.row.runtimeState {
                    Text(String(format: L("Runtime state: %@"), runtime.rawValue))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(self.availabilityLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(self.availabilityColor)
                if let version = self.row.caamVersion {
                    Text(String(format: L("CAAM %@"), version))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let observedAt = self.row.observedAt {
                    Text(String(format: L("Updated %@"), observedAt.relativeDescription()))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Button(L("Remove"), role: .destructive) { self.remove() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(!self.canRemove)
            }
        }
    }

    private var primaryStatus: String {
        if let account = self.row.currentAccountLabel, let profile = self.row.currentProfile {
            return "\(account) · \(profile)"
        }
        if let profile = self.row.currentProfile {
            return String(format: L("Current profile: %@"), profile)
        }
        return self.row.message ?? L("Not checked yet.")
    }

    private var availabilityLabel: String {
        switch self.row.availability {
        case .ready: L("Ready")
        case .degraded: L("Degraded")
        case .incompatible: L("Update required")
        case .recoveryRequired: L("Recovery required")
        case .unavailable: L("Unavailable")
        case .stale: L("Stale")
        }
    }

    private var availabilityColor: Color {
        switch self.row.availability {
        case .ready: .green
        case .degraded: .yellow
        case .incompatible, .recoveryRequired, .unavailable, .stale: .orange
        }
    }
}
