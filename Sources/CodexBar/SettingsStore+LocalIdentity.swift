import Foundation

extension SettingsStore {
    var localDeviceID: String {
        self.defaultsState.localDeviceID
    }
}
