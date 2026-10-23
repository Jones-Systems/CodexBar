import AppKit
import SwiftUI

@MainActor
struct AboutPane: View {
    let updater: UpdaterProviding
    @State private var iconHover = false
    @AppStorage("autoUpdateEnabled") private var autoUpdateEnabled: Bool = true
    @AppStorage(UpdateChannel.userDefaultsKey)
    private var updateChannelRaw: String = UpdateChannel.defaultChannel.rawValue
    @State private var didLoadUpdaterState = false

    private var isJonesBuild: Bool {
        Bundle.main.bundleIdentifier == "com.jonessystems.codexbar"
    }

    private var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "CodexBar"
    }

    private var projectURL: String {
        self.isJonesBuild ? "https://github.com/Jones-Systems/CodexBar" : "https://github.com/steipete/CodexBar"
    }

    private var sourceRevision: String? {
        guard self.isJonesBuild else { return nil }
        return Bundle.main.object(forInfoDictionaryKey: "JonesSourceRevision") as? String
    }

    private var jonesUpdater: JonesUpdateController? {
        self.updater as? JonesUpdateController
    }

    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    private var buildTimestamp: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "CodexBuildTimestamp") as? String else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        guard let date = parser.date(from: raw) else { return raw }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = .current
        return formatter.string(from: date)
    }

    var body: some View {
        Form {
            Section {
                self.hero
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }

            if self.updater.isAvailable {
                Section {
                    Toggle(
                        L(self.isJonesBuild ? "jones_updates_automatic" : "check_updates_auto"),
                        isOn: self.$autoUpdateEnabled)

                    if let jonesUpdater {
                        LabeledContent(L("update_channel"), value: L("jones_updates_channel_stable"))
                        Text(JonesUpdatePresentation.status(jonesUpdater.detail))
                            .foregroundStyle(.secondary)
                        if jonesUpdater.updateStatus.isUpdateReady {
                            Button(L("Update ready, restart now?")) { jonesUpdater.installUpdate() }
                        }
                    } else {
                        Picker(selection: self.updateChannelBinding) {
                            ForEach(UpdateChannel.allCases) { channel in
                                Text(channel.displayName).tag(channel)
                            }
                        } label: {
                            SettingsRowLabel(L("update_channel"), subtitle: self.updateChannel.description)
                        }
                    }

                    LabeledContent(String(format: L("version_format"), self.versionString)) {
                        Button(L("check_for_updates")) { self.updater.checkForUpdates(nil) }
                            .disabled(self.jonesUpdater?.detail.canCheckForUpdates == false)
                    }
                } header: {
                    Text(L("section_updates"))
                }
            } else {
                Section {
                    if let jonesUpdater {
                        LabeledContent(
                            L("update_channel"),
                            value: L(jonesUpdater.policy.channel == .stable ?
                                "jones_updates_channel_stable" : "jones_updates_channel_none"))
                        Text(JonesUpdatePresentation.status(jonesUpdater.detail))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(self.updater.unavailableReason ?? L("updates_unavailable"))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                AboutLinkRow(
                    icon: "chevron.left.slash.chevron.right",
                    title: L("link_github"),
                    url: self.projectURL)
                if !self.isJonesBuild {
                    AboutLinkRow(icon: "globe", title: L("link_website"), url: "https://steipete.me")
                    AboutLinkRow(icon: "bird", title: L("link_twitter"), url: "https://twitter.com/steipete")
                    AboutLinkRow(icon: "envelope", title: L("link_email"), url: "mailto:peter@steipete.me")
                }
            } header: {
                Text(L("section_links"))
            } footer: {
                Text(L("copyright"))
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .scrollContentBackground(.hidden)
        .onAppear {
            guard !self.didLoadUpdaterState else { return }
            // Align Sparkle's flag with the persisted preference on first load.
            self.updater.automaticallyChecksForUpdates = self.autoUpdateEnabled
            self.updater.automaticallyDownloadsUpdates = self.autoUpdateEnabled
            self.didLoadUpdaterState = true
        }
        .onChange(of: self.autoUpdateEnabled) { _, newValue in
            self.updater.automaticallyChecksForUpdates = newValue
            self.updater.automaticallyDownloadsUpdates = newValue
        }
    }

    private var hero: some View {
        VStack(spacing: 10) {
            if let image = NSApplication.shared.applicationIconImage {
                Button(action: self.openProjectHome) {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: 92, height: 92)
                        .cornerRadius(16)
                        .scaleEffect(self.iconHover ? 1.05 : 1.0)
                        .shadow(color: self.iconHover ? .accentColor.opacity(0.25) : .clear, radius: 6)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .onHover { hovering in
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        self.iconHover = hovering
                    }
                }
            }

            VStack(spacing: 2) {
                Text(self.displayName)
                    .font(.title3).bold()
                Text(String(format: L("version_format"), self.versionString))
                    .foregroundStyle(.secondary)
                if let buildTimestamp {
                    Text(String(format: L("built_format"), buildTimestamp))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let sourceRevision {
                    LabeledContent(L("Source")) {
                        Text(sourceRevision)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    .foregroundStyle(.secondary)
                }
                Text(L("about_tagline"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private var updateChannel: UpdateChannel {
        UpdateChannel(rawValue: self.updateChannelRaw) ?? .stable
    }

    private var updateChannelBinding: Binding<UpdateChannel> {
        Binding(
            get: { self.updateChannel },
            set: { newValue in
                self.updateChannelRaw = newValue.rawValue
                self.updater.checkForUpdates(nil)
            })
    }

    private func openProjectHome() {
        guard let url = URL(string: self.projectURL) else { return }
        NSWorkspace.shared.open(url)
    }
}

@MainActor
struct AboutLinkRow: View {
    let icon: String
    let title: String
    let url: String
    @State private var hovering = false

    var body: some View {
        Button {
            if let url = URL(string: self.url) { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: self.icon)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                Text(self.title)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(self.hovering ? Color.accentColor : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { self.hovering = $0 }
    }
}
