import CodexBarCore
import Foundation

@MainActor
extension UsageStore {
    func handleSessionQuotaTransition(
        provider: UsageProvider,
        snapshot: UsageSnapshot,
        codexOwnerKey: CodexSessionQuotaOwnerKey? = nil,
        now: Date = Date())
    {
        let notificationsEnabled = self.settings.sessionQuotaNotificationsEnabled
        // Provider-specific by design: Codex owner-scoped baselines reject stale observations across account switches.
        if provider == .codex, !notificationsEnabled {
            self.requireFreshCodexSessionQuotaBaseline(observedAt: snapshot.updatedAt)
            self.sessionQuotaLogger.debug("Codex session notifications disabled; cleared notification baseline")
            return
        }
        if provider == .codex, codexOwnerKey == nil {
            self.requireFreshCodexSessionQuotaBaseline(observedAt: snapshot.updatedAt)
            self.sessionQuotaLogger.debug("missing Codex session owner; cleared notification baseline")
            return
        }
        guard let sessionWindow = self.sessionQuotaWindow(provider: provider, snapshot: snapshot) else {
            if provider == .codex {
                if let previous = self.sessionQuotaTransitionStates[.codex] {
                    if previous.codexOwnerKey != codexOwnerKey {
                        self.requireFreshCodexSessionQuotaBaseline(observedAt: snapshot.updatedAt)
                    } else {
                        self.sessionQuotaTransitionStates[.codex] = previous.advancingObservationWatermark(
                            to: snapshot.updatedAt)
                    }
                } else if self.codexSessionQuotaBaselineRequirement != nil {
                    self.requireFreshCodexSessionQuotaBaseline(observedAt: snapshot.updatedAt)
                }
                self.sessionQuotaLogger.debug("missing Codex session window; retained notification baseline")
            } else {
                self.clearSessionQuotaTransitionState(provider: provider)
            }
            return
        }
        guard !sessionWindow.window.isSyntheticPlaceholder else { return }
        let currentRemaining = sessionWindow.window.remainingPercent
        let currentSource = sessionWindow.source
        let currentResetBoundary = sessionWindow.window.resetsAt
        if provider == .codex,
           let requirement = self.codexSessionQuotaBaselineRequirement,
           !requirement.admits(observedAt: snapshot.updatedAt)
        {
            self.sessionQuotaLogger.debug("ignored stale session observation while awaiting a fresh Codex baseline")
            return
        }
        let previousState = self.sessionQuotaTransitionStates[provider.instanceID]
        let forceBaseline = provider == .codex && self.codexSessionQuotaBaselineRequirement != nil
        let evaluation = SessionQuotaTransitionReducer.evaluate(
            previous: previousState,
            observation: SessionQuotaTransitionObservation(
                provider: provider,
                remaining: currentRemaining,
                source: currentSource,
                resetBoundary: currentResetBoundary,
                observedAt: snapshot.updatedAt,
                evaluationTime: now,
                codexOwnerKey: codexOwnerKey),
            notificationsEnabled: notificationsEnabled,
            forceBaseline: forceBaseline)
        self.sessionQuotaTransitionStates[provider.instanceID] = evaluation.state
        if provider == .codex {
            self.codexSessionQuotaBaselineRequirement = nil
        }

        let providerText = provider.rawValue
        let previousRemaining = previousState?.remaining
        switch evaluation.outcome {
        case .none:
            if SessionQuotaNotificationLogic.isDepleted(currentRemaining) ||
                SessionQuotaNotificationLogic.isDepleted(previousRemaining)
            {
                let reason = self.settings.sessionQuotaNotificationsEnabled
                    ? "no transition"
                    : "notifications disabled"
                self.sessionQuotaLogger.debug(
                    "\(reason): provider=\(providerText) " +
                        "prev=\(previousRemaining ?? -1) curr=\(currentRemaining)")
            }
        case .baselineChanged:
            self.sessionQuotaLogger.debug(
                "session notification baseline changed: provider=\(providerText) curr=\(currentRemaining)")
        case .staleCodexObservation:
            self.sessionQuotaLogger.debug(
                "ignored stale session observation: provider=\(providerText) curr=\(currentRemaining)")
        case .suppressedCodexRestore:
            self.sessionQuotaLogger.info(
                "suppressed transient restore: provider=\(providerText) " +
                    "prev=\(previousRemaining ?? -1) curr=\(currentRemaining)")
        case .awaitingCodexRestoreConfirmation:
            self.sessionQuotaLogger.info(
                "awaiting restore confirmation: provider=\(providerText) " +
                    "prev=\(previousRemaining ?? -1) curr=\(currentRemaining)")
        case .depleted, .restored:
            let transition = evaluation.outcome.transition
            self.sessionQuotaLogger.info(
                "transition \(String(describing: transition)): provider=\(providerText) " +
                    "prev=\(previousRemaining ?? -1) curr=\(currentRemaining)")
            self.publishSessionQuotaTransition(
                transition,
                provider: provider,
                sessionWindow: sessionWindow,
                snapshot: snapshot,
                notificationsEnabled: notificationsEnabled)
        }
    }

    /// Posts the OS notification when session quota notifications are enabled.
    private func publishSessionQuotaTransition(
        _ transition: SessionQuotaTransition,
        provider: UsageProvider,
        sessionWindow: (window: RateWindow, source: SessionQuotaWindowSource),
        snapshot: UsageSnapshot,
        notificationsEnabled: Bool)
    {
        if notificationsEnabled {
            self.sessionQuotaNotifier.post(transition: transition, provider: provider, badge: nil)
        }
    }
}
