import Foundation

/// Scores how hard an activity was (1–10) and explains why.
///
/// Two views of the same session:
/// - **External load**: what the pace, hills and ruck weight *should* cost, via the ACSM metabolic
///   equations scaled to the user's VO2 max.
/// - **Internal load**: what it *actually* cost, via heart-rate reserve.
///
/// Both are turned into a Banister TRIMP (duration × intensity, weighted exponentially) so they share
/// one scale. When heart rate is available it wins — that's where short sleep or a few beers show up.
enum DifficultyEngine {

    // MARK: - Metabolic demand

    /// Estimated oxygen cost in ml/kg/min (ACSM walking/running equations, load scaled by total mass).
    static func vo2Demand(speedMps: Double, grade: Double, running: Bool, bodyMassKg: Double, loadKg: Double = 0) -> Double {
        let v = speedMps * 60
        let g = max(0, grade)
        let net = running ? 0.2 * v + 0.9 * v * g : 0.1 * v + 1.8 * v * g
        let loadFactor = bodyMassKg > 0 ? (bodyMassKg + loadKg) / bodyMassKg : 1
        return 3.5 + net * loadFactor
    }

    static func isRunning(type: ActivityType, speedMps: Double) -> Bool {
        type == .run || speedMps > 2.2
    }

    static func trimp(minutes: Double, hrr: Double) -> Double {
        let x = min(max(hrr, 0), 1)
        return minutes * x * 0.64 * exp(1.92 * x)
    }

    /// Maps training load onto 1–10 with diminishing returns, so a monster day tops out rather than overflowing.
    static func score(fromTrimp trimp: Double) -> Double {
        let raw = 1 + 9 * (1 - exp(-trimp / 110))
        return (raw * 10).rounded() / 10
    }

    static func label(for score: Double) -> String {
        switch score {
        case ..<3: "Easy"
        case ..<5: "Moderate"
        case ..<7: "Hard"
        case ..<8.5: "Very Hard"
        default: "Brutal"
        }
    }

    // MARK: - Baseline

    /// Fits avg HR against VO2 demand across past workouts. Falls back to a population slope anchored on
    /// the user's own average when there's too little spread in the data to trust a fitted slope.
    static func fitBaseline(points: [(vo2: Double, hr: Double)], physiology: Physiology) -> Baseline? {
        let n = Double(points.count)
        guard points.count >= 3 else { return nil }
        let meanX = points.map(\.vo2).reduce(0, +) / n
        let meanY = points.map(\.hr).reduce(0, +) / n
        let varX = points.map { pow($0.vo2 - meanX, 2) }.reduce(0, +)
        let cov = points.map { ($0.vo2 - meanX) * ($0.hr - meanY) }.reduce(0, +)

        var slope = (physiology.maxHR - physiology.restingHR) / max(physiology.vo2Max - 3.5, 1)
        if points.count >= 5, varX / n >= 4 {
            let fitted = cov / varX
            if (0.5...10).contains(fitted) { slope = fitted }
        }
        return Baseline(slope: slope, intercept: meanY - slope * meanX, workoutCount: points.count)
    }

    // MARK: - Evaluate

    static func evaluate(_ activity: Activity) -> DifficultyResult {
        let phys = activity.physiology ?? Physiology()
        let minutes = activity.movingSeconds / 60
        let speed = activity.averageSpeed
        let grade = activity.distanceMeters > 0 ? activity.elevationGainMeters / activity.distanceMeters : 0
        let loadKg = (activity.ruckWeightLbs ?? 0) * Format.kgPerLb
        let vo2 = vo2Demand(speedMps: speed, grade: grade, running: isRunning(type: activity.type, speedMps: speed),
                            bodyMassKg: phys.bodyMassKg, loadKg: loadKg)

        let externalHRR = (vo2 - 3.5) / max(phys.vo2Max - 3.5, 1)
        var load = trimp(minutes: minutes, hrr: externalHRR)

        var basedOnHR = false
        var hrr: Double?
        if let hr = activity.heartRate, hr.sampleCount >= 3, hr.average > phys.restingHR, phys.maxHR > phys.restingHR {
            let r = (hr.average - phys.restingHR) / (phys.maxHR - phys.restingHR)
            hrr = r
            load = trimp(minutes: minutes, hrr: r)
            basedOnHR = true
        }

        let score = min(10, max(1, score(fromTrimp: load)))
        var effort: [Factor] = []

        // Hills
        let gainFt = activity.elevationGainMeters * Format.feetPerMeter
        let miles = activity.distanceMeters / Format.metersPerMile
        if miles > 0.2, gainFt / miles >= 80 {
            effort.append(.init(text: "\(Int(gainFt.rounded())) ft of climbing (\(Int((gainFt / miles).rounded())) ft/mi)", tone: .harder))
        }

        // Ruck load
        if let lbs = activity.ruckWeightLbs, lbs > 0 {
            let pct = Int((loadKg / phys.bodyMassKg * 100).rounded())
            effort.append(.init(text: "Carrying \(Int(lbs)) lb — \(pct)% of your body weight", tone: .harder))
        }

        // Duration
        if activity.movingSeconds >= 60 * 60 {
            effort.append(.init(text: "Long one: \(Format.hoursMinutes(activity.movingSeconds)) moving", tone: .harder))
        }

        // Heart rate vs. what this effort normally costs you
        var hrDelta: Double?
        if let hr = activity.heartRate, basedOnHR, let baseline = activity.baseline {
            let delta = hr.average - baseline.expectedHR(forVO2: vo2)
            hrDelta = delta
            let d = Int(abs(delta).rounded())
            if delta >= 5 {
                effort.append(.init(text: "HR ran \(d) bpm above your normal for this effort", tone: .harder))
            } else if delta <= -5 {
                effort.append(.init(text: "HR ran \(d) bpm below your normal for this effort", tone: .easier))
            }
        }
        if let r = hrr, r >= 0.85, let hr = activity.heartRate {
            effort.append(.init(text: "Avg HR \(Int(hr.average)) bpm — near the top of your range", tone: .harder))
        }

        // Recovery going in
        var recovery: [Factor] = []
        var causes: [String] = []
        if let rec = activity.recovery {
            if let sleep = rec.sleepHours {
                let typical = rec.typicalSleepHours
                if sleep < 6.5 || (typical.map { sleep <= $0 - 1 } ?? false) {
                    var text = "Only slept \(Format.hoursMinutes(sleep * 3600))"
                    if let t = typical { text += " — you usually get \(Format.hoursMinutes(t * 3600))" }
                    recovery.append(.init(text: text, tone: .harder))
                    causes.append("short sleep")
                } else if sleep >= 7.5 {
                    recovery.append(.init(text: "Slept \(Format.hoursMinutes(sleep * 3600))", tone: .easier))
                }
            }
            if let rhr = rec.restingHR, let typical = rec.typicalRestingHR {
                let d = rhr - typical
                if d >= 3 {
                    recovery.append(.init(text: "Resting HR \(Int(d.rounded())) bpm above your normal", tone: .harder))
                    causes.append("an elevated resting HR")
                }
            }
            if let hrv = rec.hrv, let typical = rec.typicalHRV, typical > 0 {
                let ratio = hrv / typical
                if ratio <= 0.85 {
                    recovery.append(.init(text: "HRV \(Int(((1 - ratio) * 100).rounded()))% below your normal", tone: .harder))
                    causes.append("low HRV")
                } else if ratio >= 1.1 {
                    recovery.append(.init(text: "HRV \(Int(((ratio - 1) * 100).rounded()))% above your normal", tone: .easier))
                }
            }
        }
        switch drinks(activity) {
        case .oneOrTwo:
            recovery.append(.init(text: "A drink or two last night", tone: .harder))
            causes.append("drinks last night")
        case .threePlus:
            recovery.append(.init(text: "3+ drinks last night", tone: .harder))
            causes.append("the drinks last night")
        default:
            break
        }

        return DifficultyResult(
            score: score,
            label: label(for: score),
            headline: headline(score: score, hrDelta: hrDelta, causes: causes),
            effortFactors: effort,
            recoveryFactors: recovery,
            basedOnHeartRate: basedOnHR
        )
    }

    /// The user's answer wins; otherwise fall back to what's logged in Apple Health.
    static func drinks(_ activity: Activity) -> DrinksAnswer? {
        if let answer = activity.drinksAnswer { return answer }
        guard let logged = activity.recovery?.drinksLogged else { return nil }
        switch logged {
        case ..<1: return DrinksAnswer.none
        case ..<3: return .oneOrTwo
        default: return .threePlus
        }
    }

    static func headline(score: Double, hrDelta: Double?, causes: [String]) -> String {
        let why = joined(causes)
        if let d = hrDelta, d >= 5 {
            return causes.isEmpty
                ? "Harder than it looked. Your heart worked more than usual for this effort."
                : "Harder than it looked — \(why) will do that."
        }
        if let d = hrDelta, d <= -5 {
            return "Easier than it looked. Your heart barely noticed — the fitness is showing."
        }
        if score >= 7 {
            return causes.isEmpty ? "Big effort. Eat, hydrate, sleep." : "Rough one, and \(why) didn't help."
        }
        if !causes.isEmpty { return "Got it done despite \(why)." }
        switch score {
        case ..<3: return "Easy day. That's what recovery looks like."
        case ..<5: return "Solid, controlled effort."
        default: return "Honest work today."
        }
    }

    static func joined(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        default: items.dropLast().joined(separator: ", ") + " and " + items.last!
        }
    }
}
