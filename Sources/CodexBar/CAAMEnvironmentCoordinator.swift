import CodexBarCore
import Foundation
import Observation

@MainActor
@Observable
final class CAAMEnvironmentCoordinator {
    @ObservationIgnored private let client: CAAMEnvironmentClient
    @ObservationIgnored private var configurationGeneration = 0
    @ObservationIgnored private var observedConfigurationsByID: [String: CAAMEnvironmentConfiguration] = [:]
    private(set) var rowsByID: [String: CAAMEnvironmentRowState] = [:]
    private(set) var isRefreshing = false
    private(set) var notice: String?

    init(client: CAAMEnvironmentClient = CAAMEnvironmentClient()) {
        self.client = client
    }

    func state(configurations: [CAAMEnvironmentConfiguration]) -> CodexEnvironmentsSectionState {
        let displayOrder = configurations.filter { $0.connection.kind == .local } +
            configurations.filter { $0.connection.kind == .ssh }
        let rows = displayOrder.map { configuration in
            let observedRow = self.observedConfigurationsByID[configuration.id] == configuration
                ? self.rowsByID[configuration.id]
                : nil
            return observedRow ?? CAAMEnvironmentContract.unavailableRow(
                configuration: configuration,
                message: L("Not checked yet."))
        }
        return CodexEnvironmentsSectionState(
            configurations: configurations,
            rows: rows,
            isRefreshing: self.isRefreshing,
            notice: self.notice)
    }

    func configurationsDidChange(_ configurations: [CAAMEnvironmentConfiguration]) {
        self.configurationGeneration &+= 1
        let configurationsByID = Dictionary(uniqueKeysWithValues: configurations.map { ($0.id, $0) })
        self.rowsByID = self.rowsByID.filter { id, _ in
            self.observedConfigurationsByID[id] == configurationsByID[id]
        }
        self.observedConfigurationsByID = self.observedConfigurationsByID.filter { id, configuration in
            configurationsByID[id] == configuration
        }
        self.notice = nil
    }

    func refresh(configurations: [CAAMEnvironmentConfiguration]) async {
        guard !self.isRefreshing else { return }
        do {
            _ = try CAAMEnvironmentContract.validateConfigurations(configurations)
        } catch {
            self.notice = error.localizedDescription
            return
        }

        self.isRefreshing = true
        self.notice = nil
        defer { self.isRefreshing = false }
        let generation = self.configurationGeneration

        var refreshed: [String: CAAMEnvironmentRowState] = [:]
        for configuration in configurations {
            do {
                let snapshot = try await self.client.fetchSnapshot(for: configuration)
                refreshed[configuration.id] = CAAMEnvironmentContract.rowState(
                    configuration: configuration,
                    snapshot: snapshot)
            } catch {
                refreshed[configuration.id] = CAAMEnvironmentContract.unavailableRow(
                    configuration: configuration,
                    message: error.localizedDescription)
            }
        }
        guard generation == self.configurationGeneration else { return }
        self.rowsByID = refreshed
        self.observedConfigurationsByID = Dictionary(uniqueKeysWithValues: configurations.map { ($0.id, $0) })
    }
}
