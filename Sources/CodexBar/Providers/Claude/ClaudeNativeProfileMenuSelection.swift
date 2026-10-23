import CodexBarCore

@MainActor
enum ClaudeNativeProfileMenuSelection {
    enum Outcome: Equatable {
        case changed
        case unchanged
        case stale
    }

    static func items(
        selectedAlias: String?,
        discovery: ClaudeFleetProfileDiscovery.Result,
        label: (ClaudeFleetProfileDiscovery.Profile) -> String) -> [MenuDescriptor.SubmenuItem]
    {
        let profiles = discovery.profiles
        let labels = profiles.map(label)
        var items = zip(profiles, labels).map { profile, title in
            MenuDescriptor.SubmenuItem(
                title: labels.count(where: { $0 == title }) > 1 ? "\(title) (\(profile.alias))" : title,
                action: .selectClaudeNativeProfile(alias: profile.alias),
                isChecked: profile.alias == selectedAlias)
        }
        if let selectedAlias, !profiles.contains(where: { $0.alias == selectedAlias }) {
            items.append(.init(
                title: "Unavailable saved profile", action: nil, isEnabled: false, isChecked: true))
        }
        if profiles.isEmpty {
            items.append(.init(title: "No available profiles", action: nil, isEnabled: false))
        }
        items.append(.init(title: "Selects the profile shown in CodexBar.", action: nil, isEnabled: false))
        items.append(.init(title: "Profile settings…", action: .providerSettings(.claude)))
        return items
    }

    @discardableResult
    static func select(alias: String, store: UsageStore) -> Outcome {
        guard ClaudeNativeProfileSelection.isSelected(environment: store.claudeNativeProfileFetchEnvironment()),
              ClaudeFleetProfileDiscovery.discover().profiles.contains(where: { $0.alias == alias })
        else { return .stale }
        guard store.settings.claudeNativeProfileAlias != alias else { return .unchanged }
        store.settings.claudeNativeProfileAlias = alias
        return .changed
    }
}
