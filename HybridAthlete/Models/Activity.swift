import Foundation
import CoreLocation

enum ActivityType: String, Codable, CaseIterable, Identifiable {
    case run, walk, ruck

    var id: String { rawValue }

    var title: String {
        switch self {
        case .run: "Run"
        case .walk: "Walk"
        case .ruck: "Ruck"
        }
    }

    var symbol: String {
        switch self {
        case .run: "figure.run"
        case .walk: "figure.walk"
        case .ruck: "figure.hiking"
        }
    }
}

struct RoutePoint: Codable, Hashable {
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var timestamp: Date

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

struct HeartRateSummary: Codable, Hashable {
    var average: Double
    var max: Double
    var sampleCount: Int
}

/// How recovered the body was going into the activity, compared to the user's own normal.
struct RecoveryContext: Codable, Hashable {
    var sleepHours: Double?
    var typicalSleepHours: Double?
    var restingHR: Double?
    var typicalRestingHR: Double?
    var hrv: Double?
    var typicalHRV: Double?
    /// Drinks logged in Apple Health in the 24h before the activity. nil = nothing logged.
    var drinksLogged: Double?
}

enum DrinksAnswer: String, Codable, CaseIterable, Identifiable {
    case none, oneOrTwo, threePlus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .oneOrTwo: "1–2"
        case .threePlus: "3+"
        }
    }
}

/// Personal numbers used to scale effort. Snapshotted onto each activity so its score is reproducible.
struct Physiology: Codable, Hashable {
    var bodyMassKg: Double = 82
    var maxHR: Double = 185
    var restingHR: Double = 60
    var vo2Max: Double = 42
}

/// Linear fit of average workout HR against metabolic demand (VO2, ml/kg/min) from past workouts.
/// Lets us ask "what HR would this effort normally cost you?"
struct Baseline: Codable, Hashable {
    var slope: Double
    var intercept: Double
    var workoutCount: Int

    func expectedHR(forVO2 vo2: Double) -> Double { intercept + slope * vo2 }
}

struct Factor: Codable, Hashable {
    enum Tone: String, Codable { case harder, easier }
    var text: String
    var tone: Tone
}

struct DifficultyResult: Codable, Hashable {
    var score: Double
    var label: String
    var headline: String
    /// What made the session itself demanding (hills, load, duration, HR vs. normal).
    var effortFactors: [Factor]
    /// Why the body was (or wasn't) ready for it (sleep, resting HR, HRV, drinks).
    var recoveryFactors: [Factor]
    var basedOnHeartRate: Bool
}

struct Activity: Codable, Identifiable, Hashable {
    var id: UUID
    var type: ActivityType
    var start: Date
    var end: Date
    var movingSeconds: TimeInterval
    var distanceMeters: Double
    var elevationGainMeters: Double
    var ruckWeightLbs: Double?
    var route: [RoutePoint]

    var heartRate: HeartRateSummary?
    var recovery: RecoveryContext?
    var physiology: Physiology?
    var baseline: Baseline?
    var drinksAnswer: DrinksAnswer?
    var difficulty: DifficultyResult?
    var savedToHealth = false
    var watchWorkoutFound = false

    var averageSpeed: Double { movingSeconds > 0 ? distanceMeters / movingSeconds : 0 }
}
