import Foundation

extension SettingsStore {
    static let netdataConfigurationDidChange = Notification.Name("netdataConfigurationDidChange")
    static let netdataConfigurationKey = "netdataConfiguration.v1"

    var netdataConfiguration: NetdataConfiguration {
        self.defaultsState.netdataConfiguration
    }

    static func loadNetdataConfiguration(userDefaults: UserDefaults) -> NetdataConfiguration {
        guard let data = userDefaults.data(forKey: netdataConfigurationKey),
              let configuration = try? JSONDecoder().decode(NetdataConfiguration.self, from: data),
              (try? configuration.validate()) != nil
        else { return NetdataConfiguration() }
        return configuration
    }

    func applyNetdataConfiguration(_ configuration: NetdataConfiguration) throws {
        try configuration.validate()
        let data = try JSONEncoder().encode(configuration)
        self.userDefaults.set(data, forKey: Self.netdataConfigurationKey)
        self.defaultsState.netdataConfiguration = configuration
        self.netdataConfigurationNotifications.post(name: Self.netdataConfigurationDidChange, object: nil)
    }
}
