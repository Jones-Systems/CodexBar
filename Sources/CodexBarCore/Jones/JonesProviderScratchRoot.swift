import Foundation

/// Routes only app-owned provider scratch; provider homes and stock paths are unchanged.
public enum JonesProviderScratchRoot {
    public static func directory(
        temporaryDirectory: URL,
        identity: JonesStateRoot.Identity? = JonesStateRoot.identity) -> URL
    {
        guard identity != nil else { return temporaryDirectory }
        return temporaryDirectory.appendingPathComponent(
            JonesStateRoot.path("CodexBar/provider-scratch", identity: identity), isDirectory: true)
    }
}
