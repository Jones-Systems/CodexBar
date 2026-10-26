#if os(Linux)
import Foundation
import Testing
@testable import CodexBarCore

struct ResetCountdownDayRolloverLinuxTests {
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func at(hoursFromNow hours: Double) -> Date {
        Self.now.addingTimeInterval(hours * 3600)
    }

}
#endif
