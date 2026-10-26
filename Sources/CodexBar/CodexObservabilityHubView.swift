import CodexBarCore
import Foundation
import SwiftUI

private enum ObservabilityHubTab: String, CaseIterable, Identifiable {
    case overview
    case accounts
    case systems
    case work

    var id: String {
        self.rawValue
    }

    var title: String {
        switch self {
        case .overview: L("Overview")
        case .accounts: L("Accounts")
        case .systems: L("Systems")
        case .work: L("Work")
        }
    }
}

@MainActor
struct CodexObservabilityHubView: View {
    let accountInputs: () -> [HubAccountObservation]
    let providerInputs: () -> [HubProviderInput]
    var netdataBridge: NetdataObservabilityBridge?
    var netdataCoordinator: NetdataObservabilityCoordinator?
    @State private var isAppeared = false
    @State private var tab: ObservabilityHubTab = .overview

    var body: some View {
        Section {
            Picker(L("Observability view"), selection: self.$tab) {
                ForEach(ObservabilityHubTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            TimelineView(.periodic(from: .now, by: 15)) { context in
                let now = self.presentationDate(fallback: context.date)
                let accounts = self.accountInputs()
                let hosts = self.netdataBridge?.hostsByEnvironmentID(now: now) ?? [:]
                let snapshot = ObservabilityHub.aggregate(
                    services: self.systemObservations(accounts: accounts, hosts: hosts),
                    accounts: accounts,
                    providers: self.providerInputs(),
                    includeWork: self.tab == .work,
                    hostsByEnvironmentID: hosts,
                    now: now)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        switch self.tab {
                        case .overview: self.overview(snapshot, now: now)
                        case .accounts: self.accounts(snapshot)
                        case .systems: self.systems(snapshot, now: now)
                        case .work: self.work(snapshot)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 160, maxHeight: 380)
            }
        } header: {
            Text(L("Observability hub"))
        } footer: {
            SettingsSectionFooter(
                L("Local service state, provider usage and cost, and host resources are separate ledgers."))
        }
        .onAppear {
            self.isAppeared = true
            self.updateNetdataVisibility()
        }
        .onDisappear {
            self.isAppeared = false
            self.updateNetdataVisibility()
        }
        .onChange(of: self.tab) { _, _ in self.updateNetdataVisibility() }
    }

    private func presentationDate(fallback: Date) -> Date {
        guard let coordinator = self.netdataCoordinator, coordinator.isRunning,
              coordinator.configuration.activeHost != nil else { return fallback }
        return coordinator.presentationNow
    }

    private func updateNetdataVisibility() {
        self.netdataCoordinator?.setSystemsVisible(self.isAppeared && self.tab == .systems)
    }

    private func systemObservations(
        accounts: [HubAccountObservation], hosts: [String: HubHostObservation]) -> [HubServiceObservation]
    {
        let local = HubServiceObservation(
            id: "local",
            label: L("This Mac"),
            currentProfile: accounts.first { $0.environmentID == "local" && $0.hostDefault }?.profile,
            evidence: HubEvidence(source: "Existing local account projection", observedAt: nil, availability: .partial))
        let remote = hosts.keys.sorted().filter { $0 != "local" }.map { id in
            HubServiceObservation(
                id: id,
                label: self.netdataCoordinator?.configuration.activeHost.flatMap {
                    $0.environmentID == id ? $0.label : nil
                } ?? id,
                evidence: HubEvidence(source: "No service observation", observedAt: nil, availability: .unavailable))
        }
        return [local] + remote
    }

    private func overview(_ snapshot: ObservabilityHubSnapshot, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Service and local state")).font(.subheadline.weight(.semibold))
            if snapshot.services.isEmpty {
                Text(L("No system observations are available.")).font(.caption)
            }
            ForEach(snapshot.services) { service in
                HStack(alignment: .top) {
                    Text(service.label)
                    Spacer()
                    HubEvidenceView(evidence: service.evidence)
                }
                .font(.caption)
            }
            Divider()
            Text(L("Provider usage and API cost")).font(.subheadline.weight(.semibold))
            if snapshot.providers.isEmpty {
                Text(L("No provider observations are available.")).font(.caption)
            }
            ForEach(snapshot.providers) { provider in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(provider.label).font(.caption.weight(.semibold))
                        Spacer()
                        if let percent = provider.primaryUsedPercent {
                            Text(String(format: L("Primary window: %.1f%% used"), percent))
                        } else {
                            Text(L("Usage unavailable"))
                        }
                    }
                    if let minutes = provider.windowMinutes {
                        Text(String(format: L("Window length: %d minutes"), minutes)).font(.caption2)
                    }
                    if let reset = provider.resetsAt {
                        Text(String(format: L("Resets: %@"), reset.formatted())).font(.caption2)
                    }
                    HubEvidenceView(evidence: provider.evidence)
                    Text(String(format: L("Data confidence: %@"), provider.confidence.rawValue)).font(.caption2)
                    if let cost = provider.cost {
                        self.costRow(cost)
                    } else {
                        Text(L("Cost unavailable; not zero.")).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }
            Divider()
            Text(L("Host resources")).font(.subheadline.weight(.semibold))
            if snapshot.services.isEmpty {
                Text(L("No system observations are available.")).font(.caption)
            }
            ForEach(snapshot.services) { service in
                self.hostResources(environmentID: service.id, label: service.label, now: now)
            }
        }
    }

    private func costRow(_ cost: HubCostObservation) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let amount = cost.amount {
                Text(String(
                    format: L("Recorded cost: %@ · %d days · %@"),
                    UsageFormatter.currencyString(amount, currencyCode: cost.currency),
                    cost.historyDays,
                    self.provenanceLabel(cost.provenance)))
            } else {
                Text(L("Cost unavailable; not zero."))
            }
            if let metered = cost.meteredAmount {
                Text(String(
                    format: L("Separate metered amount: %@ (not added)"),
                    UsageFormatter.currencyString(metered, currencyCode: cost.currency)))
            }
            Text(L("Historical provider cache; not a billing receipt or an identified account."))
            HubEvidenceView(evidence: cost.evidence)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func accounts(_ snapshot: ObservabilityHubSnapshot) -> some View {
        Group {
            Text(L("Profiles are environment-local. Only provider and stable ID establish cross-environment identity."))
                .font(.caption).foregroundStyle(.secondary)
            if snapshot.accounts.isEmpty {
                Text(L("No account profiles have been observed."))
            }
            ForEach(snapshot.accounts) { account in
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(account.environmentLabel) · \(account.profile)").font(.caption.weight(.semibold))
                    if let label = account.displayLabel { Text(label).font(.caption) }
                    Text(String(
                        format: L("Provider: %@ · Health: %@"),
                        account.provider ?? L("Unknown"),
                        account.health.rawValue))
                        .font(.caption2)
                    if account.hostDefault { Text(L("Host default")).font(.caption2) }
                    HubEvidenceView(evidence: account.evidence)
                }
            }
        }
    }

    private func systems(_ snapshot: ObservabilityHubSnapshot, now: Date) -> some View {
        Group {
            if snapshot.services.isEmpty { Text(L("No system observations are available.")) }
            ForEach(snapshot.services) { service in
                VStack(alignment: .leading, spacing: 4) {
                    Text(service.label).font(.subheadline.weight(.semibold))
                    Text(String(format: L("Host default: %@"), service.currentProfile ?? L("Unknown")))
                    Text(String(
                        format: L("Runtime effective profile: %@"),
                        service.runtimeEffectiveProfile ?? L("Unknown")))
                    HubEvidenceView(evidence: service.evidence)
                    self.hostResources(environmentID: service.id, label: service.label, now: now)
                    if self.netdataCoordinator?.configuration.activeHost?.environmentID == service.id,
                       let destination = self.netdataCoordinator?.configuration.dashboardDestination
                    {
                        Link(L("Open dashboard in browser"), destination: destination)
                        Text(L("Opening a dashboard does not import telemetry or verify this host."))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }
        }
    }

    private func hostResources(environmentID: String, label: String, now: Date) -> some View {
        let state = self.netdataBridge?.systemsState(environmentID: environmentID, now: now) ?? NetdataSystemsState(
            environmentID: environmentID,
            observation: NetdataReadOnlyFacade.unavailable(environmentID: environmentID),
            now: now)
        return VStack(alignment: .leading, spacing: 3) {
            Text(state.compactLabel(hostLabel: label))
            if state.availability == .unsupported {
                Text(L("Netdata telemetry is unsupported here. No host metrics were collected."))
            } else {
                HubEvidenceView(evidence: HubEvidence(
                    source: state.source, observedAt: state.observedAt, availability: state.availability))
                if state.isRefreshing { Text(L("Refreshing")) }
            }
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    private func work(_ snapshot: ObservabilityHubSnapshot) -> some View {
        Group {
            Text(L("Recorded local sessions only; not a live job queue or evidence of running processes."))
                .font(.caption).foregroundStyle(.secondary)
            if snapshot.work.isEmpty {
                Text(L("No session details are loaded. Use the existing provider refresh to collect supported data."))
                    .font(.caption)
            }
            ForEach(snapshot.work) { work in
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(format: L("%@ · Recorded session %d"), work.provider, work.ordinal))
                        .font(.caption.weight(.semibold))
                    Text(work.lastActivity, style: .date).font(.caption2)
                    if let tokens = work.tokens { Text(String(format: L("Tokens: %d"), tokens)).font(.caption2) }
                    if let amount = work.estimatedCostUSD {
                        Text(String(
                            format: L("Estimated API cost: %@"),
                            UsageFormatter.currencyString(amount, currencyCode: "USD")))
                            .font(.caption2)
                    }
                    HubEvidenceView(evidence: work.evidence)
                }
            }
            if snapshot.workIsPartial {
                Text(L("Partial view: limited to 100 recorded sessions.")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func provenanceLabel(_ provenance: CostProvenance) -> String {
        switch provenance {
        case .listPriceEstimate: L("List-price estimate")
        case .vendorMetered: L("Vendor-metered")
        case .mixed: L("Mixed provenance")
        case .unknown: L("Unknown provenance")
        }
    }
}

private struct HubEvidenceView: View {
    let evidence: HubEvidence

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(self.evidence.source) · \(self.availabilityLabel)")
            if let date = self.evidence.observedAt {
                Text(String(format: L("Observed: %@"), date.formatted()))
            } else {
                Text(L("No observation timestamp"))
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var availabilityLabel: String {
        switch self.evidence.availability {
        case .available: L("Available")
        case .stale: L("Stale")
        case .partial: L("Partial")
        case .unavailable: L("Unavailable")
        case .unsupported: L("Unsupported")
        }
    }
}
