import XCTest
@testable import HybridAthlete

final class ActivityChartsTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    /// Straight line north at a steady speed, one point per second.
    private func route(meters: Double, speed: Double, pauseAt: Double? = nil, pauseSeconds: Double = 0) -> [RoutePoint] {
        let metersPerDegree = 111_195.0
        var points: [RoutePoint] = []
        var t = 0.0, d = 0.0
        while d <= meters {
            points.append(RoutePoint(latitude: 40 + d / metersPerDegree, longitude: -105, altitude: 1600,
                                     timestamp: start.addingTimeInterval(t)))
            if let p = pauseAt, d < p, d + speed >= p { t += pauseSeconds }
            d += speed
            t += 1
        }
        return points
    }

    func testSteadyPaceSplits() {
        let splits = ActivityCharts.splits(route(meters: 2.5 * Format.metersPerMile, speed: 3))
        XCTAssertEqual(splits.count, 3)
        for s in splits { XCTAssertEqual(s.paceSeconds, Format.metersPerMile / 3, accuracy: 3) }
        XCTAssertEqual(splits[2].fraction, 0.5, accuracy: 0.01)
        XCTAssertEqual(splits[2].label, "2.5")
    }

    func testPauseTimeIsNotCountedInSplit() {
        let splits = ActivityCharts.splits(route(meters: 1.05 * Format.metersPerMile, speed: 3, pauseAt: 800, pauseSeconds: 300))
        XCTAssertEqual(splits[0].paceSeconds, Format.metersPerMile / 3, accuracy: 5)
    }

    func testZonesSplitTimeByPercentOfMax() {
        let samples = (0..<60).map { HRSample(date: start.addingTimeInterval(Double($0) * 5), bpm: $0 < 30 ? 120 : 170) }
        let zones = ActivityCharts.zones(samples, maxHR: 190)
        XCTAssertEqual(zones[1].seconds, 150, accuracy: 0.1) // 120/190 = 63% → Z2
        XCTAssertEqual(zones[3].seconds, 150, accuracy: 0.1) // 170/190 = 89% → Z4
        XCTAssertEqual(zones.map(\.seconds).reduce(0, +), 300, accuracy: 0.1)
    }

    func testElevationProfilePrefersBarometer() {
        var r = route(meters: 500, speed: 5)
        for i in r.indices { r[i].relativeAltitude = Double(i) * 0.1; r[i].altitude = 1600 + Double(i % 7) * 10 }
        let profile = ActivityCharts.elevationProfile(r)
        XCTAssertEqual(profile.first!.feet, 0, accuracy: 1)
        XCTAssertGreaterThan(profile.last!.feet, profile.first!.feet)
    }
}
