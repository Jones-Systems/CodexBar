import SwiftUI

@MainActor
struct PreferencesNetdataSection: View {
    let settings: SettingsStore
    @State private var draft: NetdataConfigurationDraft
    @State private var result: String?

    init(settings: SettingsStore) {
        self.settings = settings
        self._draft = State(initialValue: NetdataConfigurationDraft(configuration: settings.netdataConfiguration))
    }

    var body: some View {
        Section {
            Toggle(L("netdata_enabled"), isOn: self.$draft.enabled)
            TextField(L("netdata_environment_id"), text: self.$draft.environmentID)
            TextField(L("netdata_host_label"), text: self.$draft.label)
            TextField(L("netdata_loopback_origin"), text: self.$draft.origin)
            TextField(L("netdata_machine_guid"), text: self.$draft.expectedMachineGUID)
            TextField(L("netdata_dashboard_url"), text: self.$draft.dashboardURL)
            HStack {
                Button(L("netdata_apply")) {
                    do {
                        try self.settings.applyNetdataConfiguration(self.draft.configuration)
                        self.result = L("netdata_saved")
                    } catch {
                        self.result = L("netdata_invalid_configuration")
                    }
                }
                if let result { Text(result).font(.caption).foregroundStyle(.secondary) }
            }
        } header: {
            Text(L("netdata_title"))
        } footer: {
            SettingsSectionFooter(L("netdata_configuration_help"))
        }
    }
}
