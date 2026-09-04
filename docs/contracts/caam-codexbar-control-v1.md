# Interface Contract — CAAM–CodexBar Control v1

<!-- codex-section:begin id="contract.caam-codexbar-control-v1#ctx.artifact-header.001" -->
Artifact Type: `interface-contract`

Artifact ID: `contract.caam-codexbar-control-v1`

Purpose: Define the credential-free, versioned control protocol between CodexBar and one host-local CAAM gateway.

Governing artifact: `spec.caam-environment-control`

Contract owner: CAAM environment integration owner

Consumers: CodexBar client, CAAM gateway adapter, fixture tests, and compatibility checks

Authority effect: none
<!-- codex-section:end id="contract.caam-codexbar-control-v1#ctx.artifact-header.001" -->

Contract revision: 1

<!-- codex-section:begin id="contract.caam-codexbar-control-v1#ctx.invariants.001" -->
## Invariants

- The gateway executes on the environment whose state it reports or changes.
- Requests and responses contain no credential, cookie, token, private key, complete auth-file digest, auth path, vault path, command text, or shell fragment.
- Every response is bound to one `environment_id` and `protocol_version`.
- Profile names are local selectors. `identity.stable_id` is the optional cross-environment correlation key.
- New switch and fallback mutations require an operation ID, idempotency key, exact expected revision, and a prior unexpired plan digest. Recovery instead binds the pending operation ID and exact expected revision.
- A lost response after possible execution is `unknown`, never known failure. Only operation lookup or recovery may follow automatically.
- Recovering a pending switch and restoring a configured fallback are distinct operations.
<!-- codex-section:end id="contract.caam-codexbar-control-v1#ctx.invariants.001" -->

## Invocation

Local:

```text
caam-codexbar <operation> [validated scalar arguments]
```

Remote:

```text
ssh -o BatchMode=yes -o RequestTTY=no -o ClearAllForwardings=yes -o ConnectTimeout=5 <destination> caam-codexbar <operation> [validated scalar arguments]
```

The transport does not invoke a shell. A forced-command SSH configuration may ignore the received command and dispatch the same closed operation family after its own validation.

Closed v1 operations:

```text
snapshot --environment-id <id>
plan-switch --environment-id <id> --profile <name> --expected-revision <revision>
execute-switch --environment-id <id> --plan-digest <sha256> --operation-id <uuid> --idempotency-key <uuid>
operation-status --environment-id <id> --operation-id <uuid>
recover-switch --environment-id <id> --operation-id <uuid> --expected-revision <revision>
restore-fallback --environment-id <id> --expected-revision <revision> --plan-digest <sha256> --operation-id <uuid> --idempotency-key <uuid>
```

## Common envelope

Every stdout response is one UTF-8 JSON object:

```json
{
  "schema": "caam.codexbar-control/v1",
  "kind": "snapshot",
  "environment_id": "laptop",
  "protocol_version": "1.0",
  "request_id": "optional-caller-request-id",
  "result": {},
  "error": null
}
```

Exactly one of `result` and `error` is non-null. `kind` must match the requested operation. Nonzero process exit indicates a rejected or failed command, but a syntactically valid error envelope remains the only user-presentable detail. CodexBar does not display raw stdout or stderr.

The error object is:

```json
{
  "code": "closed_machine_code",
  "message": "bounded credential-free summary",
  "effect": "known_no_effect"
}
```

`effect` is exactly `known_no_effect`, `known_effect`, or `unknown`. Mutation transport failure after launch is treated as `unknown` unless authoritative operation-status evidence says otherwise.

<!-- codex-section:begin id="contract.caam-codexbar-control-v1#iface.snapshot.001" -->
## Snapshot result

```json
{
  "revision": "0000000000000001",
  "observed_at": "2026-09-04T12:00:00Z",
  "caam_version": "0.0.0-fixture",
  "capabilities": ["snapshot"],
  "reachability": "reachable",
  "host_default_profile": "primary",
  "fallback_profile": "primary",
  "profiles": [
    {
      "name": "primary",
      "active": true,
      "system": false,
      "eligible": true,
      "health": "healthy",
      "identity": {
        "provider": "codex",
        "stable_id": "acct_fixture_primary",
        "display_email": "p***@example.invalid",
        "workspace_id": "workspace_fixture",
        "workspace_label": "Fixture Workspace",
        "plan": "fixture"
      }
    }
  ],
  "runtime": {
    "state": "unknown",
    "effective_profile": null,
    "reload_required": false
  },
  "pending_operation": null,
  "warnings": []
}
```

Closed values:

- `reachability`: `reachable`, `degraded`;
- profile `health`: `healthy`, `warning`, `critical`, `cooldown`, `unknown`;
- runtime `state`: `not_running`, `matches_default`, `differs_from_default`, `unknown`;
- pending state: `planned`, `executing`, `recovery_required`, `manual_required`.

Transport-level unreachability is a CodexBar client result rather than a gateway snapshot because an unreachable gateway cannot authoritatively describe itself.
<!-- codex-section:end id="contract.caam-codexbar-control-v1#iface.snapshot.001" -->

<!-- codex-section:begin id="contract.caam-codexbar-control-v1#iface.plan.001" -->
## Switch plan result

```json
{
  "plan_digest": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "expected_revision": "0000000000000001",
  "current_profile": "primary",
  "target_profile": "secondary",
  "affected_profiles": ["primary", "secondary"],
  "reload_required": true,
  "expires_at": "2026-09-04T12:05:00Z"
}
```

Planning has no credential mutation effect. A revision mismatch or ineligible target is `known_no_effect`.
<!-- codex-section:end id="contract.caam-codexbar-control-v1#iface.plan.001" -->

<!-- codex-section:begin id="contract.caam-codexbar-control-v1#iface.operation.001" -->
## Operation result and status

```json
{
  "operation_id": "11111111-2222-4333-8444-555555555555",
  "state": "committed",
  "effect": "known_effect",
  "previous_profile": "primary",
  "current_profile": "secondary",
  "recovery_required": false,
  "manual_required": false,
  "snapshot": {}
}
```

Closed operation states are `planned`, `executing`, `committed`, `rejected`, `rolled_back`, `recovery_required`, and `manual_required`. Terminal known outcomes include a fresh complete snapshot. `executing` without an authoritative terminal result remains unknown and is polled by operation ID; it is not executed again.
<!-- codex-section:end id="contract.caam-codexbar-control-v1#iface.operation.001" -->

## Bounds and validation

- Entire stdout: at most 64 KiB.
- Environment ID and profile name: 1–64 ASCII characters from `[A-Za-z0-9._-]`, not beginning with `-`.
- Display label: 1–80 trimmed Unicode scalar characters with no control characters.
- SSH destination: 1–255 ASCII characters from `[A-Za-z0-9._@:-]`, not beginning with `-`; no whitespace, control character, slash, shell metacharacter, or option injection.
- CAAM version and protocol version: at most 32 ASCII characters.
- Profiles: at most 64 unique profile names.
- Warnings: at most 16 entries of at most 240 Unicode scalar characters, with no control characters.
- Revision: 1–64 ASCII characters from `[A-Za-z0-9._:-]`.
- Plan digest: exactly 64 lowercase hexadecimal characters.
- Operation and idempotency identifiers: canonical UUID strings.
- Unknown object fields are ignored for compatible additive evolution. Unknown enum values and schema major versions fail closed for behavior and never enable a capability.

## Evolution and activation

Additive optional fields may ship under v1. A changed invariant, operation meaning, required field, credential boundary, or retry/effect classification requires a new major schema. CodexBar may display a newer gateway as incompatible but must not issue mutations.

This contract defines no authority to install a gateway, access credentials, switch an account, terminate a process, update software, or retry an ambiguous operation. Activation requires independently verified CAAM conformance and explicit operational authorization.
