import Foundation
import HealthKit

@MainActor
final class HealthKitManager: ObservableObject {
    private let store = HKHealthStore()

    @Published var restingHeartRate: Double?
    @Published var heartRateVariability: Double?
    @Published var authorizationError: String?

    private let restingHRType = HKQuantityType(.restingHeartRate)
    private let hrvType = HKQuantityType(.heartRateVariabilitySDNN)

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationError = "Health data is not available on this device."
            return
        }
        do {
            try await store.requestAuthorization(toShare: [restingHRType, hrvType], read: [restingHRType, hrvType])
            await fetchLatestValues()
        } catch {
            authorizationError = error.localizedDescription
        }
    }

    /// Simulator-only helper: writes one fake sample of each type so the read path can be
    /// verified end-to-end without a paired device. Remove once tested on a real iPhone/Watch.
    func seedFakeSample() async {
        let now = Date()
        let restingSample = HKQuantitySample(
            type: restingHRType,
            quantity: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: Double.random(in: 54...62)),
            start: now,
            end: now
        )
        let hrvSample = HKQuantitySample(
            type: hrvType,
            quantity: HKQuantity(unit: .secondUnit(with: .milli), doubleValue: Double.random(in: 38...58)),
            start: now,
            end: now
        )
        try? await store.save(restingSample)
        try? await store.save(hrvSample)
        await fetchLatestValues()
    }

    func fetchLatestValues() async {
        async let resting = latestSample(for: restingHRType, unit: .count().unitDivided(by: .minute()))
        async let hrv = latestSample(for: hrvType, unit: .secondUnit(with: .milli))
        restingHeartRate = await resting
        heartRateVariability = await hrv
    }

    private func latestSample(for type: HKQuantityType, unit: HKUnit) async -> Double? {
        await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }
}
