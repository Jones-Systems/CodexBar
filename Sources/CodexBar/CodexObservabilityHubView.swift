import CodexBarCore
import Foundation
import SwiftUI

private enum ObservabilityHubTab: String, CaseIterable, Identifiable {
    case overview
    case accounts
    case systems
    case work

    var id: String { self.rawValue }

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
    @Bindable var coordinator: CAAMEnvironmentCoordinator
    let configurations: [CAAMEnvironmentConfiguration]
    let providerInputs: () -> [HubProviderInput]
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
                let snapshot = ObservabilityHub.aggregate(
                    sessions: self.configurations.map { self.coordinator.session(for: $0) },
                    providers: self.providerInputs(),
                    includeWork: self.tab == .work,
                    now: context.date)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        switch self.tab {
                        case .overview: self.overview(snapshot)
                        case .accounts: self.accounts(snapshot)
                        case .systems: self.systems(snapshot)
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
    }

    private func overview(_ snapshot: ObservabilityHubSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Service and local state")).font(.subheadline.weight(.semibold))
            if snapshot.services.isEmpty {
                Text(L("No CAAM environments configured.")).font(.caption)
            }
            ForEach(snapshot.services) { service in
                HStack(alignment: .top) {
                    Text(service.row.label)
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
            Text(L("Netdata telemetry is unsupported here. No host metrics were collected."))
                .font(.caption).foregroundStyle(.secondary)
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
            Text(L("Historical provider cache; not a billing receipt or an identified CAAM account."))
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

    private func systems(_ snapshot: ObservabilityHubSnapshot) -> some View {
        Group {
            if snapshot.services.isEmpty { Text(L("No CAAM environments configured.")) }
            ForEach(snapshot.services) { service in
                VStack(alignment: .leading, spacing: 4) {
                    Text(service.row.label).font(.subheadline.weight(.semibold))
                    Text(String(format: L("Host default: %@"), service.row.currentProfile ?? L("Unknown")))
                    Text(String(
                        format: L("Runtime effective profile: %@"),
                        service.runtimeEffectiveProfile ?? L("Unknown")))
                    HubEvidenceView(evidence: service.evidence)
                    Text(L("Netdata telemetry is unsupported here. No host metrics were collected."))
                        .foregroundStyle(.secondary)
                    NetdataDashboardLinkView(configuration: self.configurations.first { $0.id == service.id })
                }
                .font(.caption)
            }
        }
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

private struct NetdataDashboardLinkView: View {
    let configuration: CAAMEnvironmentConfiguration?
    @State private var destination = ""

    var body: some View {
        DisclosureGroup(L("Open an existing Netdata dashboard")) {
            TextField(L("Dashboard URL (not stored)"), text: self.$destination)
                .textFieldStyle(.roundedBorder)
            if let url = NetdataReadOnlyFacade.dashboardURL(self.destination) {
                Link(L("Open dashboard in browser"), destination: url)
            } else if !self.destination.isEmpty {
                Text(L("Use HTTPS, or loopback HTTP, without credentials, query parameters, or fragments."))
                    .foregroundStyle(.orange)
            }
            Text(L("Opening a dashboard does not import telemetry or verify this host."))
                .foregroundStyle(.secondary)
        }
        .onChange(of: self.configuration) { _, _ in self.destination = "" }
    }
}
