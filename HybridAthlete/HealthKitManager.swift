import Foundation
import HealthKit
import CoreLocation

@MainActor
final class HealthKitManager: ObservableObject {
    let store = HKHealthStore()

    @Published var authorizationError: String?

    private let heartRateType = HKQuantityType(.heartRate)
    private let restingHRType = HKQuantityType(.restingHeartRate)
    private let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
    private let vo2MaxType = HKQuantityType(.vo2Max)
    private let bodyMassType = HKQuantityType(.bodyMass)
    private let distanceType = HKQuantityType(.distanceWalkingRunning)
    private let alcoholType = HKQuantityType(.numberOfAlcoholicBeverages)
    private let sleepType = HKCategoryType(.sleepAnalysis)

    private let bpm = HKUnit.count().unitDivided(by: .minute())

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationError = "Health data is not available on this device."
            return
        }
        let read: Set<HKObjectType> = [
            heartRateType, restingHRType, hrvType, vo2MaxType, bodyMassType, distanceType, alcoholType, sleepType,
            HKObjectType.workoutType(), HKSeriesType.workoutRoute(), HKCharacteristicType(.dateOfBirth),
        ]
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute(), distanceType]
        do {
            try await store.requestAuthorization(toShare: share, read: read)
        } catch {
            authorizationError = error.localizedDescription
        }
    }

    // MARK: - Heart rate during an activity

    func heartRateSamples(from start: Date, to end: Date) async -> [HRSample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: heartRateType, predicate: predicate)],
                                                 sortDescriptors: [SortDescriptor(\.startDate)])
        let samples = (try? await descriptor.result(for: store)) ?? []
        return samples.map { HRSample(date: $0.startDate, bpm: $0.quantity.doubleValue(for: bpm)) }
    }

    // MARK: - Recovery going into an activity

    func recoveryContext(before start: Date) async -> RecoveryContext {
        async let sleep = sleepHoursByNight(endingBefore: start, nights: 15)
        async let restingRecent = quantities(restingHRType, unit: bpm, from: start.addingTimeInterval(-36 * 3600), to: start)
        async let restingMonth = quantities(restingHRType, unit: bpm, from: start.addingTimeInterval(-30 * 86400), to: start.addingTimeInterval(-36 * 3600))
        async let hrvRecent = quantities(hrvType, unit: .secondUnit(with: .milli), from: start.addingTimeInterval(-24 * 3600), to: start)
        async let hrvMonth = quantities(hrvType, unit: .secondUnit(with: .milli), from: start.addingTimeInterval(-30 * 86400), to: start.addingTimeInterval(-24 * 3600))
        async let drinks = quantities(alcoholType, unit: .count(), from: start.addingTimeInterval(-24 * 3600), to: start)

        let nights = await sleep
        let lastNight = nights[Calendar.current.startOfDay(for: start)]
        let others = nights.filter { $0.key != Calendar.current.startOfDay(for: start) && $0.value >= 3 }.map(\.value)
        let drinkValues = await drinks

        return RecoveryContext(
            sleepHours: lastNight,
            typicalSleepHours: others.count >= 3 ? mean(others) : nil,
            restingHR: (await restingRecent).last,
            typicalRestingHR: mean(await restingMonth),
            hrv: mean(await hrvRecent),
            typicalHRV: mean(await hrvMonth),
            drinksLogged: drinkValues.isEmpty ? nil : drinkValues.reduce(0, +)
        )
    }

    /// Hours asleep keyed by the day the sleep ended (so Tuesday's key = Monday night's sleep).
    /// Overlapping samples from iPhone + Watch are merged so time isn't double counted.
    private func sleepHoursByNight(endingBefore end: Date, nights: Int) async -> [Date: Double] {
        let start = Calendar.current.startOfDay(for: end).addingTimeInterval(-Double(nights) * 86400)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(predicates: [.categorySample(type: sleepType, predicate: predicate)],
                                                 sortDescriptors: [SortDescriptor(\.startDate)])
        let samples = (try? await descriptor.result(for: store)) ?? []
        let asleep = Set(HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue))
        let intervals = samples
            .filter { asleep.contains($0.value) }
            .map { (start: $0.startDate, end: min($0.endDate, end)) }
            .filter { $0.end > $0.start }

        var merged: [(start: Date, end: Date)] = []
        for interval in intervals {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1].end = max(last.end, interval.end)
            } else {
                merged.append(interval)
            }
        }

        var byNight: [Date: Double] = [:]
        for interval in merged {
            byNight[Calendar.current.startOfDay(for: interval.end), default: 0] += interval.end.timeIntervalSince(interval.start) / 3600
        }
        return byNight
    }

    // MARK: - Personal physiology + baseline

    func physiology(before date: Date) async -> Physiology {
        var p = Physiology()
        if let mass = await quantities(bodyMassType, unit: .gramUnit(with: .kilo), from: date.addingTimeInterval(-365 * 86400), to: date).last {
            p.bodyMassKg = mass
        }
        if let vo2 = await quantities(vo2MaxType, unit: HKUnit(from: "ml/kg*min"), from: date.addingTimeInterval(-180 * 86400), to: date).last {
            p.vo2Max = vo2
        }
        if let resting = mean(await quantities(restingHRType, unit: bpm, from: date.addingTimeInterval(-30 * 86400), to: date)) {
            p.restingHR = resting
        }
        // Highest HR seen in the past year is a better max than 220-age, as long as it looks like a real effort.
        let yearMax = await maxQuantity(heartRateType, unit: bpm, from: date.addingTimeInterval(-365 * 86400), to: date)
        if let observed = yearMax, observed >= 160 {
            p.maxHR = observed
        } else if let dob = try? store.dateOfBirthComponents().date {
            let age = Calendar.current.dateComponents([.year], from: dob, to: date).year ?? 40
            p.maxHR = Double(220 - age)
        }
        return p
    }

    /// Builds the HR-vs-effort baseline from walking/running/hiking workouts in the last 180 days.
    func baseline(before date: Date, physiology: Physiology) async -> Baseline? {
        let workouts = await workouts(from: date.addingTimeInterval(-180 * 86400), to: date)
        let points: [(vo2: Double, hr: Double)] = workouts.compactMap { w in
            guard let distance = w.statistics(for: distanceType)?.sumQuantity()?.doubleValue(for: .meter()),
                  let hr = w.statistics(for: heartRateType)?.averageQuantity()?.doubleValue(for: bpm),
                  distance > 400, w.duration > 5 * 60 else { return nil }
            let speed = distance / w.duration
            let ascent = (w.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?.doubleValue(for: .meter()) ?? 0
            let running = w.workoutActivityType == .running
            let vo2 = DifficultyEngine.vo2Demand(speedMps: speed, grade: ascent / distance, running: running, bodyMassKg: physiology.bodyMassKg)
            return (vo2, hr)
        }
        return DifficultyEngine.fitBaseline(points: points, physiology: physiology)
    }

    /// True when another app (normally the Watch's Workout app) logged a workout overlapping this window.
    func hasOverlappingWorkout(from start: Date, to end: Date) async -> Bool {
        await workouts(from: start.addingTimeInterval(-10 * 60), to: end.addingTimeInterval(10 * 60))
            .contains { $0.sourceRevision.source != HKSource.default() && $0.endDate > start && $0.startDate < end }
    }

    // MARK: - Save

    func save(_ activity: Activity) async throws {
        let config = HKWorkoutConfiguration()
        config.locationType = .outdoor
        config.activityType = switch activity.type {
        case .run: .running
        case .walk: .walking
        case .ruck: .hiking
        }

        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        try await builder.beginCollection(at: activity.start)
        let distance = HKQuantitySample(type: distanceType, quantity: HKQuantity(unit: .meter(), doubleValue: activity.distanceMeters),
                                        start: activity.start, end: activity.end)
        try await builder.addSamples([distance])

        var metadata: [String: Any] = [
            HKMetadataKeyElevationAscended: HKQuantity(unit: .meter(), doubleValue: activity.elevationGainMeters),
            HKMetadataKeyIndoorWorkout: false,
        ]
        if let lbs = activity.ruckWeightLbs { metadata["RuckWeightLbs"] = lbs }
        try await builder.addMetadata(metadata)
        try await builder.endCollection(at: activity.end)
        guard let workout = try await builder.finishWorkout() else { return }

        if !activity.route.isEmpty {
            let routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: .local())
            let locations = activity.route.map {
                CLLocation(coordinate: $0.coordinate, altitude: $0.altitude, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: $0.timestamp)
            }
            try await routeBuilder.insertRouteData(locations)
            try await routeBuilder.finishRoute(with: workout, metadata: nil)
        }
    }

    // MARK: - Query helpers

    private func quantities(_ type: HKQuantityType, unit: HKUnit, from start: Date, to end: Date) async -> [Double] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: type, predicate: predicate)],
                                                 sortDescriptors: [SortDescriptor(\.startDate)])
        let samples = (try? await descriptor.result(for: store)) ?? []
        return samples.map { $0.quantity.doubleValue(for: unit) }
    }

    private func maxQuantity(_ type: HKQuantityType, unit: HKUnit, from start: Date, to end: Date) async -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKStatisticsQueryDescriptor(predicate: .quantitySample(type: type, predicate: predicate), options: .discreteMax)
        return try? await descriptor.result(for: store)?.maximumQuantity()?.doubleValue(for: unit)
    }

    private func workouts(from start: Date, to end: Date) async -> [HKWorkout] {
        let types: [HKWorkoutActivityType] = [.running, .walking, .hiking]
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: start, end: end),
            NSCompoundPredicate(orPredicateWithSubpredicates: types.map { HKQuery.predicateForWorkouts(with: $0) }),
        ])
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(predicate)], sortDescriptors: [SortDescriptor(\.startDate)])
        return (try? await descriptor.result(for: store)) ?? []
    }

    private func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}
