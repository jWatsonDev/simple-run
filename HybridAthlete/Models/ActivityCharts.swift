import Foundation
import CoreLocation

/// Derived series for the post-activity charts. Pure functions over the saved route + HR samples.
enum ActivityCharts {

    struct Split: Identifiable, Hashable {
        let index: Int
        /// Seconds per mile (partial last split is scaled up to a full-mile pace).
        let paceSeconds: Double
        /// 1.0 for a full mile; less for the final partial mile.
        let fraction: Double
        var id: Int { index }
        var label: String { fraction < 0.99 ? String(format: "%.1f", Double(index - 1) + fraction) : "\(index)" }
    }

    struct ElevationPoint: Identifiable, Hashable {
        let miles: Double
        let feet: Double
        var id: Double { miles }
    }

    struct ZoneTime: Identifiable, Hashable {
        let zone: Int
        let name: String
        let lowerBPM: Int
        let upperBPM: Int
        let seconds: Double
        var id: Int { zone }
    }

    /// Route points further apart than this are treated as a pause, not movement.
    private static let pauseGap: TimeInterval = 30

    static func splits(_ route: [RoutePoint]) -> [Split] {
        var splits: [Split] = []
        var mileDistance = 0.0
        var mileSeconds = 0.0
        for (a, b) in zip(route, route.dropFirst()) {
            let dt = b.timestamp.timeIntervalSince(a.timestamp)
            guard dt > 0, dt <= pauseGap else { continue }
            var d = CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            var t = dt
            while mileDistance + d >= Format.metersPerMile {
                let portion = (Format.metersPerMile - mileDistance) / d
                splits.append(Split(index: splits.count + 1, paceSeconds: mileSeconds + t * portion, fraction: 1))
                d -= d * portion
                t -= t * portion
                mileDistance = 0
                mileSeconds = 0
            }
            mileDistance += d
            mileSeconds += t
        }
        let fraction = mileDistance / Format.metersPerMile
        if fraction >= 0.1 {
            splits.append(Split(index: splits.count + 1, paceSeconds: mileSeconds / fraction, fraction: fraction))
        }
        return splits
    }

    /// Elevation relative to the start, lightly smoothed, at most ~200 points.
    static func elevationProfile(_ route: [RoutePoint]) -> [ElevationPoint] {
        guard route.count > 1 else { return [] }
        let usesBarometer = route.contains { $0.relativeAltitude != nil }
        var miles = 0.0
        var raw: [(miles: Double, meters: Double)] = []
        for (i, p) in route.enumerated() {
            if i > 0 {
                let prev = route[i - 1]
                if p.timestamp.timeIntervalSince(prev.timestamp) <= pauseGap {
                    miles += CLLocation(latitude: prev.latitude, longitude: prev.longitude)
                        .distance(from: CLLocation(latitude: p.latitude, longitude: p.longitude)) / Format.metersPerMile
                }
            }
            let altitude = usesBarometer ? p.relativeAltitude : p.altitude
            if let altitude { raw.append((miles, altitude)) }
        }
        guard let first = raw.first else { return [] }

        let window = usesBarometer ? 2 : 6
        let smoothed = raw.indices.map { i -> ElevationPoint in
            let slice = raw[max(0, i - window)...min(raw.count - 1, i + window)]
            let meters = slice.map(\.meters).reduce(0, +) / Double(slice.count)
            return ElevationPoint(miles: raw[i].miles, feet: (meters - first.meters) * Format.feetPerMeter)
        }
        return downsample(smoothed, to: 200)
    }

    /// Time spent in each zone as % of max HR (50/60/70/80/90). Each sample counts until the next one, capped at 60s.
    static func zones(_ samples: [HRSample], maxHR: Double) -> [ZoneTime] {
        let names = ["Recovery", "Easy", "Aerobic", "Threshold", "Max"]
        var seconds = Array(repeating: 0.0, count: 5)
        for (i, s) in samples.enumerated() {
            let next = i + 1 < samples.count ? samples[i + 1].date.timeIntervalSince(s.date) : 5
            let pct = s.bpm / maxHR
            guard pct >= 0.5 else { continue }
            seconds[min(4, Int((pct - 0.5) * 10))] += min(max(next, 0), 60)
        }
        return (0..<5).map { z in
            ZoneTime(zone: z + 1, name: names[z],
                     lowerBPM: Int((Double(5 + z) / 10 * maxHR).rounded()),
                     upperBPM: Int((Double(6 + z) / 10 * maxHR).rounded()),
                     seconds: seconds[z])
        }
    }

    static func downsample<T>(_ items: [T], to limit: Int) -> [T] {
        guard items.count > limit, limit > 1 else { return items }
        let step = Double(items.count - 1) / Double(limit - 1)
        return (0..<limit).map { items[Int((Double($0) * step).rounded())] }
    }
}
