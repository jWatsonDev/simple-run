import Foundation

enum Format {
    static let metersPerMile = 1609.344
    static let feetPerMeter = 3.28084
    static let kgPerLb = 0.453592

    static func miles(_ meters: Double) -> String {
        String(format: "%.2f", meters / metersPerMile)
    }

    /// 0.5 → "0.5", 1.0 → "1", 2.25 → "2.25".
    static func trimmed(_ value: Double) -> String {
        String(format: "%.2f", value)
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
    }

    static func feet(_ meters: Double) -> String {
        "\(Int((meters * feetPerMeter).rounded())) ft"
    }

    /// Clock-style duration: 42:07 or 1:02:07.
    static func duration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// Readable duration: "1h 12m", "5h 10m", "38m".
    static func hoursMinutes(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int((seconds / 60).rounded())
        let h = totalMinutes / 60, m = totalMinutes % 60
        return h > 0 ? "\(h)h \(String(format: "%02d", m))m" : "\(m)m"
    }

    /// Pace per mile, or "--:--" when not moving.
    static func pace(distanceMeters: Double, seconds: TimeInterval) -> String {
        guard distanceMeters > 20, seconds > 0 else { return "--:--" }
        let secondsPerMile = seconds / (distanceMeters / metersPerMile)
        guard secondsPerMile < 60 * 60 else { return "--:--" }
        return duration(secondsPerMile)
    }
}
