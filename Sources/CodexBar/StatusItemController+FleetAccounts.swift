import AppKit
import CodexBarCore
import Observation

extension StatusItemController {
    func observeFleetAccountChanges() {
        withObservationTracking {
            _ = self.fleetAccountState.fleetDevices
            _ = self.fleetAccountState.fleetSnapshots
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeFleetAccountChanges()
                self.invalidateMenus(refreshOpenMenus: true)
            }
        }
    }

    func fleetAccountProjection(for provider: UsageProvider) -> FleetAccountMenuProjection {
        let localSnapshots = self.store.localAccountSnapshots()
        return FleetAccountMenuPlanner.projection(
            provider: provider,
            snapshots: self.fleetAccountState.fleetSnapshots.values,
            currentDeviceID: self.settings.localDeviceID,
            localAccountKeys: self.store.localAccountKeys(for: provider),
            hasLocalUsage: localSnapshots.contains(where: { $0.provider == provider.instanceID }))
    }

    func addFleetAccountMenuCards(
        _ snapshots: [AccountSnapshotSyncPayload],
        to menu: NSMenu,
        context: MenuCardContext)
    {
        guard !snapshots.isEmpty else { return }
        if menu.items.last?.isSeparatorItem != true {
            menu.addItem(.separator())
        }
        for (index, snapshot) in snapshots.enumerated() {
            guard let model = self.fleetAccountMenuCardModel(snapshot) else { continue }
            menu.addItem(self.makeMenuCardItem(
                FleetAccountMenuCardView(model: model, width: context.menuWidth),
                id: "fleetAccount-\(snapshot.accountKey)",
                width: context.menuWidth,
                heightCacheScope: "fleet-\(context.currentProvider.rawValue)-\(snapshot.accountKey)",
                heightCacheFingerprint: model.heightFingerprint(section: "fleetAccount"),
                containsInteractiveControls: false))
            if index < snapshots.count - 1 {
                menu.addItem(.separator())
            }
        }
        if menu.items.last?.isSeparatorItem != true {
            menu.addItem(.separator())
        }
    }

    func addFleetFallback(
        _ projection: FleetAccountMenuProjection,
        to menu: NSMenu,
        context: MenuCardContext) -> Bool
    {
        guard let fallback = projection.fallback else { return false }
        self.addFleetAccountMenuCards(
            [fallback] + projection.additionalAccounts,
            to: menu,
            context: context)
        return true
    }

    func fleetAccountMenuCardModel(
        _ snapshot: AccountSnapshotSyncPayload) -> UsageMenuCardView.Model?
    {
        guard let provider = snapshot.provider.firstPartyProvider else { return nil }
        let deviceName = self.fleetAccountState.fleetDevices.values
            .first(where: { $0.deviceID == snapshot.deviceID })?
            .hostName ?? L("another Mac")
        let badge = FleetAccountMenuPlanner.badge(deviceName: deviceName, fetchedAt: snapshot.fetchedAt)
        let label = snapshot.displayLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return self.menuCardModel(
            for: provider,
            snapshotOverride: snapshot.usage,
            forceOverrideCard: true,
            accountOverride: AccountInfo(email: label.isEmpty ? nil : label, plan: nil),
            subtitleOverride: badge)
    }
}
