import Foundation

@MainActor
enum JonesUpdatePresentation {
    static func status(_ detail: JonesUpdateDetail) -> String {
        switch detail.state {
        case .disabled(.channelDisabled):
            L("jones_updates_bootstrap")
        case .disabled(.sparkleUnavailable):
            L("updates_unavailable")
        case .idle, .cancelled, .skipped:
            L("jones_updates_idle")
        case .checking:
            L("jones_updates_checking")
        case let .downloading(version):
            String(format: L("jones_updates_downloading"), version)
        case let .preparing(version):
            String(format: L("jones_updates_preparing"), version)
        case let .ready(prepared):
            String(
                format: L(detail.automaticUpdatesEnabled ? "jones_updates_ready_idle" : "jones_updates_ready_quit"),
                prepared.version)
        case let .installing(version):
            String(format: L("jones_updates_installing"), version)
        case .upToDate:
            L("jones_updates_current")
        case let .failed(reason):
            Self.failure(reason)
        }
    }

    static func failure(_ reason: JonesUpdateFailure) -> String {
        switch reason {
        case .trust:
            L("jones_updates_trust_failure")
        case .sparkle:
            L("jones_updates_failure")
        case let .admission(rejection):
            switch rejection {
            case .unknownLength, .archiveTooLarge, .unsupportedDelta, .unsupportedInstallationType:
                L("jones_updates_size_failure")
            case .unknownAppCapacity, .unknownCacheCapacity:
                L("jones_updates_capacity_unknown")
            case let .insufficientAppCapacity(required), let .insufficientCacheCapacity(required):
                String(
                    format: L("jones_updates_capacity_low"),
                    ByteCountFormatter.string(fromByteCount: required, countStyle: .file))
            }
        }
    }
}
