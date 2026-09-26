#if DEBUG
import Foundation

/// Debug-only sample run for Simulator previews and screenshots. Launch with `-demoActivity`.
enum DemoData {
    static func run(endingAt end: Date = Date()) -> Activity {
        let seconds = 37.0 * 60 + 12
        let start = end.addingTimeInterval(-seconds)
        let center = (lat: 39.6990, lon: -104.9660)
        let radius = (lat: 0.0062, lon: 0.0041) // ~2.06 mi loop, run twice

        var route: [RoutePoint] = []
        var hr: [HRSample] = []
        for s in stride(from: 0.0, through: seconds, by: 3) {
            let progress = s / seconds
            // Uneven pace: faster in the middle miles, fade at the end.
            let angle = 2 * .pi * 2 * (progress + 0.006 * sin(progress * .pi * 3))
            let hill = 22 * sin(angle) + 6 * sin(angle * 3)
            route.append(RoutePoint(
                latitude: center.lat + radius.lat * sin(angle),
                longitude: center.lon + radius.lon * cos(angle),
                altitude: 1620 + hill,
                timestamp: start.addingTimeInterval(s),
                relativeAltitude: hill
            ))
        }
        for s in stride(from: 0.0, through: seconds, by: 5) {
            let progress = s / seconds
            let warmup = min(1, s / 240)
            let angle = 2 * .pi * 2 * progress
            let bpm = 118 + 42 * warmup + 9 * sin(angle + 0.6) + 8 * progress + Double.random(in: -2...2)
            hr.append(HRSample(date: start.addingTimeInterval(s), bpm: bpm))
        }

        let physiology = Physiology(bodyMassKg: 84, maxHR: 186, restingHR: 58, vo2Max: 45)
        var a = Activity(
            id: UUID(), type: .run, start: start, end: end, movingSeconds: seconds,
            distanceMeters: 4.12 * Format.metersPerMile, elevationGainMeters: 96,
            ruckWeightLbs: nil, route: route
        )
        a.heartRateSamples = hr
        a.heartRate = HeartRateSummary(average: hr.map(\.bpm).reduce(0, +) / Double(hr.count),
                                       max: hr.map(\.bpm).max() ?? 0, sampleCount: hr.count)
        a.physiology = physiology
        let vo2 = DifficultyEngine.vo2Demand(speedMps: a.averageSpeed, grade: a.elevationGainMeters / a.distanceMeters,
                                             running: true, bodyMassKg: physiology.bodyMassKg)
        a.baseline = Baseline(slope: 2.6, intercept: 148 - 2.6 * vo2, workoutCount: 34)
        a.recovery = RecoveryContext(sleepHours: 5.2, typicalSleepHours: 7.1, restingHR: 63, typicalRestingHR: 58,
                                     hrv: 33, typicalHRV: 46, drinksLogged: nil)
        a.difficulty = DifficultyEngine.evaluate(a)
        a.savedToHealth = true
        a.notesPromptDismissed = true
        return a
    }

    /// A believable week: today's run plus a ruck, a walk and an easy run.
    static func history(now: Date = Date()) -> [Activity] {
        let day = 86400.0
        var ruck = run(endingAt: now.addingTimeInterval(-2 * day - 3 * 3600))
        ruck.id = UUID()
        ruck.type = .ruck
        ruck.ruckWeightLbs = 35
        ruck.movingSeconds = 62 * 60
        ruck.distanceMeters = 3.6 * Format.metersPerMile
        ruck.recovery = RecoveryContext(sleepHours: 7.6, typicalSleepHours: 7.1, restingHR: 57, typicalRestingHR: 58,
                                        hrv: 49, typicalHRV: 46, drinksLogged: nil)
        ruck.heartRateSamples = ruck.heartRateSamples?.map { HRSample(date: $0.date, bpm: $0.bpm - 22) }
        ruck.heartRate = HeartRateSummary(average: 139, max: 152, sampleCount: ruck.heartRateSamples?.count ?? 0)
        ruck.difficulty = DifficultyEngine.evaluate(ruck)

        var walk = run(endingAt: now.addingTimeInterval(-4 * day - 5 * 3600))
        walk.id = UUID()
        walk.type = .walk
        walk.movingSeconds = 41 * 60
        walk.distanceMeters = 2.3 * Format.metersPerMile
        walk.heartRateSamples = nil
        walk.heartRate = nil
        walk.recovery = nil
        walk.difficulty = DifficultyEngine.evaluate(walk)

        var easy = run(endingAt: now.addingTimeInterval(-6 * day - 2 * 3600))
        easy.id = UUID()
        easy.movingSeconds = 29 * 60 + 40
        easy.distanceMeters = 3.1 * Format.metersPerMile
        easy.heartRateSamples = easy.heartRateSamples?.map { HRSample(date: $0.date, bpm: $0.bpm - 17) }
        easy.heartRate = HeartRateSummary(average: 144, max: 158, sampleCount: easy.heartRateSamples?.count ?? 0)
        easy.recovery = RecoveryContext(sleepHours: 7.8, typicalSleepHours: 7.1, restingHR: 56, typicalRestingHR: 58,
                                        hrv: 52, typicalHRV: 46, drinksLogged: nil)
        easy.difficulty = DifficultyEngine.evaluate(easy)

        return [run(endingAt: now), ruck, walk, easy]
    }

    static let today = RecoveryContext(sleepHours: 7.4, typicalSleepHours: 7.1, restingHR: 56, typicalRestingHR: 58,
                                       hrv: 51, typicalHRV: 46, drinksLogged: nil)
}
#endif
