import Foundation
import Testing
@testable import CodexBarCore

struct NetdataSystemsStateLinuxTests {
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test
    func `supplied host values keep their units sample time and receipt time`() {
        let received = Self.now.addingTimeInterval(2)
        let state = NetdataSystemsState(
            environmentID: "fixture", observation: Self.host(), receivedAt: received, now: received)
        #expect(state.cpuPercent == 28)
        #expect(state.availableRAMGiB == 5.5)
        #expect(state.observedAt == Self.now)
        #expect(state.receivedAt == received)
        #expect(state.sampleAgeSeconds == 2)
        #expect(state.availability == .available)
        #expect(state.compactLabel(hostLabel: "VPS") == "VPS 28% · 5.5 GiB avail")
    }

    @Test
    func `missing metrics differ from real zeros and used memory is never substituted`() {
        let partial = NetdataSystemsState(
            environmentID: "fixture", observation: Self.host(cpu: nil, memory: 0), now: Self.now)
        #expect(partial.availability == .partial)
        #expect(partial.cpuPercent == nil)
        #expect(partial.availableRAMGiB == 0)
        #expect(partial.compactLabel(hostLabel: "VPS") == "VPS CPU unavailable · 0.0 GiB avail")
        let zero = NetdataSystemsState(
            environmentID: "fixture", observation: Self.host(cpu: 0, memory: 0), now: Self.now)
        #expect(zero.availability == .available)
        #expect(zero.compactLabel(hostLabel: "VPS") == "VPS 0% · 0.0 GiB avail")
        let missing = NetdataSystemsState(
            environmentID: "fixture", observation: Self.host(cpu: nil, memory: nil), now: Self.now)
        #expect(missing.availability == .unavailable)
        #expect(missing.availableRAMGiB == nil)
    }

    @Test
    func `sample age boundaries hide stale compact values but preserve dated history`() {
        for (age, availability) in [(30.0, HubAvailability.available), (31, .stale), (300, .stale),
                                    (301, .unavailable), (-5, .available), (-6, .stale)]
        {
            let state = NetdataSystemsState(
                environmentID: "fixture", observation: Self.host(), now: Self.now.addingTimeInterval(age))
            #expect(state.availability == availability)
            #expect(state.observedAt == Self.now)
            #expect(state.cpuPercent == 28)
            if availability == .stale || availability == .unavailable {
                #expect(!state.compactLabel(hostLabel: "VPS").contains("28%"))
            }
        }
    }

    @Test
    func `foreign host missing time invalid CPU and unsupported remain explicit`() {
        let foreign = NetdataSystemsState(environmentID: "other", observation: Self.host(), now: Self.now)
        #expect(foreign.cpuPercent == nil)
        #expect(foreign.observedAt == nil)
        #expect(foreign.availability == .unavailable)
        let unsupported = NetdataSystemsState(
            environmentID: "fixture", observation: NetdataReadOnlyFacade.unavailable(environmentID: "fixture"),
            now: Self.now)
        #expect(unsupported.availability == .unsupported)
        #expect(unsupported.compactLabel(hostLabel: "Mac") == "Mac Not configured")
        let missingTime = NetdataSystemsState(
            environmentID: "fixture", observation: Self.host(sampledAt: nil), now: Self.now)
        #expect(missingTime.availability == .unavailable)
        for cpu in [-1.0, 101, .infinity, .nan] {
            let state = NetdataSystemsState(
                environmentID: "fixture", observation: Self.host(cpu: cpu), now: Self.now)
            #expect(state.cpuPercent == nil)
            #expect(state.availability == .partial)
        }
    }

    @Test
    func `failure partial evidence invalid clock and selected host never imply healthy readings`() {
        let failed = NetdataSystemsState(
            environmentID: "fixture", observation: Self.host(), now: Self.now, requestFailed: true,
            isRefreshing: true)
        #expect(failed.availability == .stale)
        #expect(failed.isRefreshing)
        let suppliedPartial = NetdataSystemsState(
            environmentID: "fixture", observation: Self.host(availability: .partial), now: Self.now)
        #expect(suppliedPartial.availability == .partial)
        let invalidClock = NetdataSystemsState(
            environmentID: "fixture", observation: Self.host(), now: Date(timeIntervalSince1970: .nan))
        #expect(invalidClock.availability == .unavailable)
        let second = NetdataSystemsState(environmentID: "second", now: Self.now)
        #expect(second.compactLabel(hostLabel: "Second") == "Second Unavailable")
        #expect(failed.cpuPercent == 28)
    }

    private static func host(
        cpu: Double? = 28,
        memory: UInt64? = 5_905_580_032,
        sampledAt: Date? = Self.now,
        availability: HubAvailability = .available) -> HubHostObservation
    {
        HubHostObservation(
            environmentID: "fixture",
            evidence: HubEvidence(source: "Synthetic fixture", observedAt: sampledAt, availability: availability),
            cpuPercent: cpu, memoryUsedBytes: 99, memoryAvailableBytes: memory)
    }
}
