import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Live Activity for an in-progress run — Lock Screen + Dynamic Island. Shared by the app and widget extension.
struct RunActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var distanceMeters: Double
        /// Moving time banked before the current segment.
        var movingSeconds: TimeInterval
        /// When the current moving segment started; nil while paused. Lets the timer tick without app updates.
        var segmentStart: Date?

        var paused: Bool { segmentStart == nil }

        /// Reference date for a counting-up timer showing total moving time.
        var timerStart: Date? { segmentStart.map { $0.addingTimeInterval(-movingSeconds) } }

        func elapsed(at date: Date = Date()) -> TimeInterval {
            movingSeconds + (segmentStart.map { date.timeIntervalSince($0) } ?? 0)
        }
    }

    var title: String
    var symbol: String
}
#endif
