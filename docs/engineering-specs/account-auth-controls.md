# Engineering Spec — Codex Account Order and Login Cancellation

Artifact Type: `engineering-spec`

Artifact ID: `spec.account-auth-controls`

Purpose: Define the bounded native Codex settings and login behavior requested by the owner.

Governing artifact: owner request carried by the coordinating task

Specification owner: account-auth-controls builder

Integration owner: root coordinator

Consumers: CodexBar builder, verifier, and delivery owner

Authority effect: none

## Behavior and scope

Codex settings exposes accessible up/down controls for every visible account, including discovered profile homes. A move stores a Codex-only order in the existing provider configuration. The preference survives configuration reload. New accounts append after recognized saved accounts; missing accounts retain their saved keys so discovery changes do not erase their positions. Invalid edge moves are no-ops.

The first user move activates explicit ordering. Before that, the menu retains its existing automatic ranking. Once configured, segmented and stacked menus respect the saved order; workspace headings group only adjacent rows. Changing order does not change the Active selection or System account. The existing menu limit still includes the active account, replacing the last limited row when necessary.

Keys use managed UUIDs, normalized profile paths, or live email plus workspace identity. Display row IDs are unsuitable for persistence because adding a same-email sibling changes those IDs. The order is machine-local: the existing sync payload allowlist omits it, while applying sync preserves local provider fields. No credential values enter the order preference.

## Login ownership and cancellation

Settings shows Cancel Login while adding, reauthenticating a managed account, or reauthenticating the ambient system account. Cancellation releases settings busy state immediately and permits a new attempt. Each managed attempt owns a task, UUID generation, and unique staged home. A completion can clear busy state or publish changes only while its generation still owns the coordinator.

Cancelling the coordinator cancels its owned service task. Cancelling an outer caller propagates to that same task. Service cancellation checks after login and workspace awaits prevent a late result from reading identity, selecting a workspace, or committing account changes. Failed or cancelled attempts clean only their own staged home. Cancellation errors do not replace a newer attempt's notice.

Ambient login has a separate owned task and generation in the settings view. Cancellation invalidates that generation and releases the live-auth promotion gate; stale completion cannot refresh usage, present an old result, or clear a new attempt's gate.

The Codex runner uses the caller's structured cancellation context on a concurrent executor. Cancellation wakes its wait, terminates only its owned Process and successfully attached process group, waits for process exit, and returns an explicit cancelled outcome. Account-home cleanup occurs after the runner returns. Existing timeout and bounded pipe draining remain. No process-name-wide termination is introduced.

## Acceptance and checks

Synthetic coverage extends existing suites for settings persistence and menu precedence, stable profile identities across discovery changes, retained missing-account keys, interleaved workspace order, config disk reload and provider scoping, machine-local sync behavior, cancellation of the owned fake login process, and immediate same-account/different-account retry with a late old success.

The focused selector is `CodexVisibleAccountTests|CodexActiveSourceConfigTests|ManagedCodexAccountCoordinatorTests|ManagedCodexAccountServiceTests|CodexLoginRunnerTests|CodexAccountsSectionStateTests|StatusMenuCodexSwitcherPresentationTests|SyncModelTests`. Existing SwiftPM discovery owns these suite groups; no new test module or static group manifest is added.

Native compile/test, macOS layout evidence, and installed-app behavior remain verification obligations. This slice does not perform live login, credential inspection, installation, or release. Fleet discovery is a separate coordinated slice; this slice consumes its existing profile identities without editing its settings-loader file.
