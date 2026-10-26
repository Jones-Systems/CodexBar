import AppKit
import CodexBarCore
import Observation

extension StatusItemController {
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === self.netdataMenu {
            self.updateNetdataStatusItem()
            return
        }
        guard self.shouldMergeIcons, menu === self.mergedMenu else { return }
        self.refreshMenuForOpenIfNeeded(menu, provider: self.resolvedMenuProvider())
    }

    enum NetdataMenuRow: Int, CaseIterable {
        case cpu
        case memory
        case age
        case availability
        case source
        case refresh
        case settings
        case dashboard
    }

    func setNetdataCoordinator(_ coordinator: NetdataObservabilityCoordinator?) {
        self.netdataObservabilityCoordinator?.setMenuVisible(false)
        self.netdataObservationID = UUID()
        self.netdataObservabilityCoordinator = coordinator
        self.removeNetdataStatusItem()
        guard !self.hasPreparedForAppShutdown else { return }
        self.observeNetdataChanges(observationID: self.netdataObservationID)
    }

    private func observeNetdataChanges(observationID: UUID) {
        guard observationID == self.netdataObservationID, !self.hasPreparedForAppShutdown else { return }
        withObservationTracking {
            self.updateNetdataStatusItem()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeNetdataChanges(observationID: observationID)
            }
        }
    }

    func updateNetdataStatusItem() {
        guard !self.hasPreparedForAppShutdown,
              let coordinator = self.netdataObservabilityCoordinator,
              let host = coordinator.configuration.activeHost
        else {
            self.removeNetdataStatusItem()
            return
        }
        if self.netdataStatusItem == nil {
            let item = Self.makeStatusItem(
                statusBar: self.statusBar,
                identity: .netdata,
                defaults: self.settings.userDefaults,
                legacyDefaultItemIndex: nil)
            let menu = self.makeNetdataMenu()
            item.menu = menu
            self.netdataMenu = menu
            self.netdataStatusItem = item
        }
        let state = coordinator.bridge.systemsState(environmentID: host.environmentID, now: coordinator.presentationNow)
        self.netdataStatusItem?.button?.title = state.compactLabel(hostLabel: host.label)
        self.netdataStatusItem?.button?.image = nil
        self.netdataStatusItem?.isVisible = true
        self.expectedVisibleStatusItemAutosaveNames.insert(StatusItemIdentity.netdata.autosaveName)
        self.updateNetdataMenu(state: state, coordinator: coordinator)
    }

    private func makeNetdataMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        for row in NetdataMenuRow.allCases {
            let action: Selector? = switch row {
            case .refresh: #selector(self.refreshNetdata(_:))
            case .settings: #selector(self.openNetdataSettings(_:))
            case .dashboard: #selector(self.openNetdataDashboard(_:))
            default: nil
            }
            let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
            item.tag = row.rawValue
            item.target = self
            item.isEnabled = action != nil
            menu.addItem(item)
        }
        return menu
    }

    private func updateNetdataMenu(state: NetdataSystemsState, coordinator: NetdataObservabilityCoordinator) {
        guard let menu = self.netdataMenu else { return }
        let cpu = state.cpuPercent.map { String(format: "%.0f%%", $0) } ?? L("Unavailable")
        let memory = state.availableRAMGiB.map { String(format: "%.1f GiB", $0) } ?? L("Unavailable")
        let age = state.sampleAgeSeconds.map { String(format: L("netdata_age_seconds"), $0) }
            ?? L("No observation timestamp")
        let availability: String = switch state.availability {
        case .available: L("Available")
        case .partial: L("Partial")
        case .stale: L("Stale")
        case .unavailable: L("Unavailable")
        case .unsupported: L("Unsupported")
        }
        let titles: [NetdataMenuRow: String] = [
            .cpu: String(format: L("netdata_cpu_value"), cpu),
            .memory: String(format: L("netdata_ram_value"), memory),
            .age: String(format: L("netdata_sample_age_value"), age),
            .availability: String(format: L("netdata_availability_value"), availability),
            .source: String(format: L("netdata_source_value"), state.source),
            .refresh: L("Refresh"),
            .settings: L("Settings..."),
            .dashboard: L("Open dashboard in browser"),
        ]
        // Keep item identities and actions stable throughout AppKit menu tracking.
        for row in NetdataMenuRow.allCases {
            menu.item(withTag: row.rawValue)?.title = titles[row] ?? ""
        }
        menu.item(withTag: NetdataMenuRow.dashboard.rawValue)?.isHidden =
            coordinator.configuration.dashboardDestination == nil
    }

    func netdataMenuWillOpen(_ menu: NSMenu) -> Bool {
        guard menu === self.netdataMenu else { return false }
        StatusMenuAppearance.pin(menu)
        self.netdataObservabilityCoordinator?.setMenuVisible(true)
        self.updateNetdataStatusItem()
        return true
    }

    func netdataMenuDidClose(_ menu: NSMenu) -> Bool {
        guard menu === self.netdataMenu else { return false }
        self.netdataObservabilityCoordinator?.setMenuVisible(false)
        return true
    }

    func removeNetdataStatusItem() {
        self.netdataObservabilityCoordinator?.setMenuVisible(false)
        self.netdataMenu?.cancelTrackingWithoutAnimation()
        self.netdataMenu?.delegate = nil
        self.netdataMenu = nil
        if let item = self.netdataStatusItem {
            item.menu = nil
            self.statusBar.removeStatusItem(item)
        }
        self.netdataStatusItem = nil
        self.expectedVisibleStatusItemAutosaveNames.remove(StatusItemIdentity.netdata.autosaveName)
    }

    func detachNetdata() {
        self.netdataObservationID = UUID()
        self.removeNetdataStatusItem()
        self.netdataObservabilityCoordinator = nil
    }

    @objc private func refreshNetdata(_ sender: NSMenuItem) {
        self.netdataObservabilityCoordinator?.refresh()
    }

    @objc private func openNetdataSettings(_ sender: NSMenuItem) {
        self.netdataMenu?.cancelTrackingWithoutAnimation()
        self.settingsOpenHandler?(.general)
    }

    @objc private func openNetdataDashboard(_ sender: NSMenuItem) {
        guard let destination = self.netdataObservabilityCoordinator?.configuration.dashboardDestination else { return }
        NSWorkspace.shared.open(destination)
    }
}
