import Foundation
import Testing
@testable import CodexBarCore

struct CAAMEnvironmentContractLinuxTests {
    @Test
    func `provider config round trips CAAM environments`() throws {
        var provider = ProviderConfig(id: UsageProvider.codex.instanceID)
        provider.codexCAAMEnvironments = [
            CAAMEnvironmentConfiguration(id: "laptop", label: "Laptop", connection: .local()),
            CAAMEnvironmentConfiguration(id: "vps", label: "VPS", connection: .ssh(destination: "vps")),
        ]

        let data = try JSONEncoder().encode(provider)
        let decoded = try JSONDecoder().decode(ProviderConfig.self, from: data)

        #expect(decoded.codexCAAMEnvironments == provider.codexCAAMEnvironments)
    }

    @Test
    func `configuration rejects duplicate IDs duplicate local and unsafe SSH`() throws {
        let duplicateIDs = [
            CAAMEnvironmentConfiguration(id: "host", label: "Laptop", connection: .local()),
            CAAMEnvironmentConfiguration(id: "host", label: "VPS", connection: .ssh(destination: "vps")),
        ]
        #expect(throws: CAAMEnvironmentContractError.self) {
            try CAAMEnvironmentContract.validateConfigurations(duplicateIDs)
        }

        let duplicateLocal = [
            CAAMEnvironmentConfiguration(id: "one", label: "One", connection: .local()),
            CAAMEnvironmentConfiguration(id: "two", label: "Two", connection: .local()),
        ]
        #expect(throws: CAAMEnvironmentContractError.self) {
            try CAAMEnvironmentContract.validateConfigurations(duplicateLocal)
        }

        let unsafeSSH = [
            CAAMEnvironmentConfiguration(id: "vps", label: "VPS", connection: .ssh(destination: "-oProxyCommand=x")),
        ]
        #expect(throws: CAAMEnvironmentContractError.self) {
            try CAAMEnvironmentContract.validateConfigurations(unsafeSSH)
        }
    }

    @Test
    func `canonical snapshot decodes and projects read only state`() throws {
        let snapshot = try CAAMEnvironmentContract.decodeSnapshot(
            Data(Self.snapshotJSON.utf8),
            expectedEnvironmentID: "laptop")
        let configuration = CAAMEnvironmentConfiguration(id: "laptop", label: "Laptop", connection: .local())
        let row = CAAMEnvironmentContract.rowState(configuration: configuration, snapshot: snapshot)

        #expect(snapshot.hostDefaultProfile == "primary")
        #expect(snapshot.unknownCapabilities == ["future_capability"])
        #expect(row.availability == .ready)
        #expect(row.currentAccountLabel == "p***@example.invalid — Fixture Workspace")
        #expect(row.canSwitch == false)
        #expect(row.canRecover == false)
        #expect(row.canRestoreFallback == false)
    }

    @Test
    func `snapshot rejects mismatched environment unknown profile and oversized output`() throws {
        #expect(throws: CAAMEnvironmentContractError.self) {
            try CAAMEnvironmentContract.decodeSnapshot(
                Data(Self.snapshotJSON.utf8),
                expectedEnvironmentID: "vps")
        }

        let unknownProfile = Self.snapshotJSON.replacingOccurrences(
            of: #""host_default_profile":"primary""#,
            with: #""host_default_profile":"missing""#)
        #expect(throws: CAAMEnvironmentContractError.self) {
            try CAAMEnvironmentContract.decodeSnapshot(
                Data(unknownProfile.utf8),
                expectedEnvironmentID: "laptop")
        }

        #expect(throws: CAAMEnvironmentContractError.self) {
            try CAAMEnvironmentContract.decodeSnapshot(
                Data(repeating: 0x20, count: CAAMEnvironmentContract.maximumOutputBytes + 1),
                expectedEnvironmentID: "laptop")
        }

        let credentialBearing = Self.snapshotJSON.replacingOccurrences(
            of: #""warnings":[]"#,
            with: #""refresh_token":"not-a-real-secret","warnings":[]"#)
        #expect(throws: CAAMEnvironmentContractError.self) {
            try CAAMEnvironmentContract.decodeSnapshot(
                Data(credentialBearing.utf8),
                expectedEnvironmentID: "laptop")
        }
    }

    @Test
    func `recovery and fallback controls require distinct capabilities and state`() throws {
        let configuration = CAAMEnvironmentConfiguration(id: "laptop", label: "Laptop", connection: .local())
        let operationID = try #require(UUID(uuidString: "11111111-2222-4333-8444-555555555555"))
        let snapshot = CAAMEnvironmentSnapshot(
            revision: "2",
            observedAt: Date(timeIntervalSince1970: 0),
            caamVersion: "1.0.0",
            capabilities: CAAMControlCapability.allCases.map(\.rawValue),
            reachability: .reachable,
            hostDefaultProfile: "primary",
            fallbackProfile: "primary",
            profiles: [
                CAAMEnvironmentProfile(
                    name: "primary",
                    active: true,
                    system: false,
                    eligible: true,
                    health: .healthy),
            ],
            runtime: CAAMRuntimeSnapshot(state: .matchesDefault, reloadRequired: false),
            pendingOperation: CAAMPendingOperation(
                operationID: operationID,
                state: .recoveryRequired,
                targetProfile: "primary"))

        let row = CAAMEnvironmentContract.rowState(configuration: configuration, snapshot: snapshot)

        #expect(row.availability == .recoveryRequired)
        #expect(row.canSwitch == false)
        #expect(row.canRecover)
        #expect(row.canRestoreFallback == false)
    }

    static let snapshotJSON = #"""
    {
      "schema":"caam.codexbar-control/v1",
      "kind":"snapshot",
      "environment_id":"laptop",
      "protocol_version":"1.0",
      "result":{
        "revision":"0000000000000001",
        "observed_at":"2026-09-04T12:00:00Z",
        "caam_version":"0.0.0-fixture",
        "capabilities":["snapshot","future_capability"],
        "reachability":"reachable",
        "host_default_profile":"primary",
        "fallback_profile":"primary",
        "profiles":[{
          "name":"primary",
          "active":true,
          "system":false,
          "eligible":true,
          "health":"healthy",
          "identity":{
            "provider":"codex",
            "stable_id":"acct_fixture_primary",
            "display_email":"p***@example.invalid",
            "workspace_id":"workspace_fixture",
            "workspace_label":"Fixture Workspace",
            "plan":"fixture"
          }
        }],
        "runtime":{"state":"unknown","effective_profile":null,"reload_required":false},
        "pending_operation":null,
        "warnings":[]
      },
      "error":null
    }
    """#
}
