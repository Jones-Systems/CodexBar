import CodexBarCore
import Observation

@MainActor
@Observable
final class FleetAccountState {
    var fleetDevices: [String: DeviceSyncPayload] = [:]
    var fleetSnapshots: [String: AccountSnapshotSyncPayload] = [:]
}
