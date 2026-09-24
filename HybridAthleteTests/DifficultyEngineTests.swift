import XCTest
@testable import HybridAthlete

final class DifficultyEngineTests: XCTestCase {
    private let phys = Physiology(bodyMassKg: 82, maxHR: 185, restingHR: 58, vo2Max: 44)

    private func activity(_ type: ActivityType, miles: Double, minutes: Double, climbFt: Double = 0, ruckLbs: Double? = nil) -> Activity {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        return Activity(id: UUID(), type: type, start: start, end: start.addingTimeInterval(minutes * 60),
                        movingSeconds: minutes * 60, distanceMeters: miles * Format.metersPerMile,
                        elevationGainMeters: climbFt / Format.feetPerMeter, ruckWeightLbs: ruckLbs, route: [],
                        physiology: phys)
    }

    func testEasyWalkScoresEasy() {
        let r = DifficultyEngine.evaluate(activity(.walk, miles: 2, minutes: 36))
        XCTAssertLessThan(r.score, 3)
        XCTAssertEqual(r.label, "Easy")
        XCTAssertFalse(r.basedOnHeartRate)
    }

    func testLongHillyRunIsHarderThanFlatShortRun() {
        let short = DifficultyEngine.evaluate(activity(.run, miles: 3, minutes: 30))
        let long = DifficultyEngine.evaluate(activity(.run, miles: 8, minutes: 80, climbFt: 900))
        XCTAssertGreaterThan(long.score, short.score + 2)
        XCTAssertTrue(long.effortFactors.contains { $0.text.contains("ft of climbing") })
        XCTAssertTrue(long.effortFactors.contains { $0.text.hasPrefix("Long one") })
    }

    func testRuckWeightRaisesScore() {
        let walk = DifficultyEngine.evaluate(activity(.walk, miles: 4, minutes: 64))
        let ruck = DifficultyEngine.evaluate(activity(.ruck, miles: 4, minutes: 64, ruckLbs: 45))
        XCTAssertGreaterThan(ruck.score, walk.score)
        XCTAssertTrue(ruck.effortFactors.contains { $0.text.hasPrefix("Carrying 45 lb") })
    }

    func testHeartRateOverridesExternalEstimate() {
        var a = activity(.run, miles: 3, minutes: 30)
        let estimated = DifficultyEngine.evaluate(a).score
        a.heartRate = HeartRateSummary(average: 172, max: 184, sampleCount: 300)
        let actual = DifficultyEngine.evaluate(a)
        XCTAssertTrue(actual.basedOnHeartRate)
        XCTAssertGreaterThan(actual.score, estimated)
    }

    /// The beer-on-vacation run: normal pace, HR way up, short sleep, drinks.
    func testElevatedHRWithPoorRecoveryExplainsWhy() {
        var a = activity(.run, miles: 3, minutes: 30)
        let vo2 = DifficultyEngine.vo2Demand(speedMps: a.averageSpeed, grade: 0, running: true, bodyMassKg: phys.bodyMassKg)
        a.baseline = Baseline(slope: 2.5, intercept: 150 - 2.5 * vo2, workoutCount: 20) // normally 150 bpm at this pace
        a.heartRate = HeartRateSummary(average: 162, max: 175, sampleCount: 300)
        a.recovery = RecoveryContext(sleepHours: 5.2, typicalSleepHours: 7.1, restingHR: 64, typicalRestingHR: 58,
                                     hrv: 31, typicalHRV: 45, drinksLogged: nil)
        a.drinksAnswer = .threePlus

        let r = DifficultyEngine.evaluate(a)
        XCTAssertTrue(r.effortFactors.contains { $0.text == "HR ran 12 bpm above your normal for this effort" })
        XCTAssertTrue(r.recoveryFactors.contains { $0.text.hasPrefix("Only slept 5h 12m") })
        XCTAssertTrue(r.recoveryFactors.contains { $0.text == "Resting HR 6 bpm above your normal" })
        XCTAssertTrue(r.recoveryFactors.contains { $0.text == "HRV 31% below your normal" })
        XCTAssertTrue(r.recoveryFactors.contains { $0.text == "3+ drinks last night" })
        XCTAssertEqual(r.headline, "Harder than it looked — short sleep, an elevated resting HR, low HRV and the drinks last night will do that.")
    }

    func testDrinksAnswerChangesStoryNotScore() {
        var a = activity(.run, miles: 3, minutes: 30)
        a.heartRate = HeartRateSummary(average: 150, max: 165, sampleCount: 300)
        let before = DifficultyEngine.evaluate(a)
        a.drinksAnswer = .oneOrTwo
        let after = DifficultyEngine.evaluate(a)
        XCTAssertEqual(before.score, after.score)
        XCTAssertNotEqual(before.headline, after.headline)
    }

    func testLoggedDrinksUsedWhenNoAnswer() {
        var a = activity(.run, miles: 3, minutes: 30)
        a.recovery = RecoveryContext(drinksLogged: 2)
        XCTAssertEqual(DifficultyEngine.drinks(a), .oneOrTwo)
        a.drinksAnswer = DrinksAnswer.none
        XCTAssertEqual(DifficultyEngine.drinks(a), DrinksAnswer.none)
    }

    func testBaselineFitsRealSlope() {
        // HR = 60 + 3 × VO2, with spread
        let points = stride(from: 15.0, through: 40, by: 5).map { (vo2: $0, hr: 60 + 3 * $0) }
        let b = DifficultyEngine.fitBaseline(points: points, physiology: phys)!
        XCTAssertEqual(b.slope, 3, accuracy: 0.001)
        XCTAssertEqual(b.expectedHR(forVO2: 30), 150, accuracy: 0.001)
    }

    func testBaselineNeedsThreeWorkouts() {
        XCTAssertNil(DifficultyEngine.fitBaseline(points: [(20, 130), (25, 140)], physiology: phys))
    }

    func testScoreStaysInRange() {
        let huge = DifficultyEngine.evaluate(activity(.ruck, miles: 20, minutes: 400, climbFt: 5000, ruckLbs: 80))
        XCTAssertLessThanOrEqual(huge.score, 10)
        XCTAssertEqual(huge.label, "Brutal")
    }
}
