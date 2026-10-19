import CodexBarCore
import SwiftUI

extension ClaudeProviderImplementation {
    @MainActor
    func nativeProfilePicker(context: ProviderSettingsContext) -> ProviderSettingsPickerDescriptor {
        let discovery = ClaudeFleetProfileDiscovery.discover()
        var options = [ProviderSettingsPickerOption(id: "", title: "Use existing source settings")]
        options += discovery.profiles.map {
            ProviderSettingsPickerOption(id: $0.alias, title: $0.alias + " (enrolled)")
        }
        if let selected = context.settings.claudeNativeProfileAlias,
           !options.contains(where: { $0.id == selected })
        {
            options.append(ProviderSettingsPickerOption(id: selected, title: "Unavailable saved profile"))
        }
        return ProviderSettingsPickerDescriptor(
            id: "claude-native-profile",
            title: "Native profile",
            subtitle: "Reuse an Authfleet-enrolled Claude profile. Enrollment does not confirm authentication " +
                "or usage access. Explicit credentials, Web, and Admin API keep precedence.",
            dynamicSubtitle: {
                let environment = context.store.claudeNativeProfileFetchEnvironment()
                if context.settings.claudeNativeProfileAlias != nil {
                    if !ClaudeNativeProfileSelection.isSelected(environment: environment) {
                        return "The native selection is saved; the current independent credential or source " +
                            "takes precedence."
                    }
                    if ClaudeNativeProfileSelection.isUnavailable(environment: environment) {
                        return ClaudeNativeProfileSelectionError.unavailable.localizedDescription
                    }
                    return "Selected native profile. Existing credentials and usage access are checked " +
                        "during refresh. " +
                        "Browser usage and extras are excluded from this profile."
                }
                switch discovery {
                case .missing:
                    return "No local Authfleet enrollment binding found. Existing source settings remain active."
                case .unavailable: return "Local Authfleet enrollment metadata is unavailable."
                case .available: return nil
                }
            },
            binding: Binding(
                get: { context.settings.claudeNativeProfileAlias ?? "" },
                set: { context.settings.claudeNativeProfileAlias = $0.isEmpty ? nil : $0 }),
            options: options,
            isVisible: nil,
            onChange: nil)
    }
}
