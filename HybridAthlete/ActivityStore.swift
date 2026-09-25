import Foundation

/// Activities saved on-device as JSON, newest first. Also runs the post-activity analysis.
@MainActor
final class ActivityStore: ObservableObject {
    @Published private(set) var activities: [Activity] = []
    @Published private(set) var analyzing: Set<UUID> = []

    private let health: HealthKitManager
    private let fileURL = URL.documentsDirectory.appending(path: "activities.json")

    init(health: HealthKitManager) {
        self.health = health
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([Activity].self, from: data) {
            activities = saved
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demoActivity") {
            activities = [DemoData.run()]
        }
        #endif
    }

    func activity(id: UUID) -> Activity? {
        activities.first { $0.id == id }
    }

    /// Saves a just-finished activity, then pulls heart rate + recovery data and scores it.
    func add(_ activity: Activity) {
        activities.insert(activity, at: 0)
        persist()
        Task { await analyze(activity.id, saveToHealth: true) }
    }

    func analyze(_ id: UUID, saveToHealth: Bool = false) async {
        guard var a = activity(id: id) else { return }
        analyzing.insert(id)
        defer { analyzing.remove(id) }

        let (start, end) = (a.start, a.end)
        let physiology = await health.physiology(before: start)
        async let heartRateSamples = health.heartRateSamples(from: start, to: end)
        async let recovery = health.recoveryContext(before: start)
        async let baseline = health.baseline(before: start, physiology: physiology)
        async let watchWorkout = health.hasOverlappingWorkout(from: start, to: end)

        a.physiology = physiology
        let samples = await heartRateSamples
        a.heartRateSamples = samples.isEmpty ? nil : samples
        a.heartRate = samples.isEmpty ? nil : HeartRateSummary(
            average: samples.map(\.bpm).reduce(0, +) / Double(samples.count),
            max: samples.map(\.bpm).max() ?? 0,
            sampleCount: samples.count
        )
        a.recovery = await recovery
        a.baseline = await baseline
        a.watchWorkoutFound = await watchWorkout
        a.difficulty = DifficultyEngine.evaluate(a)

        // If the Watch already logged this workout, saving ours too would double it up in Apple Health.
        if saveToHealth, !a.watchWorkoutFound, !a.savedToHealth, a.distanceMeters > 0 {
            do {
                try await health.save(a)
                a.savedToHealth = true
            } catch {
                print("HealthKit save failed: \(error)")
            }
        }
        replace(a)
    }

    func setDrinks(_ answer: DrinksAnswer, for id: UUID) {
        guard var a = activity(id: id) else { return }
        a.drinksAnswer = answer
        a.difficulty = DifficultyEngine.evaluate(a)
        replace(a)
    }

    func delete(id: UUID) {
        activities.removeAll { $0.id == id }
        persist()
    }

    private func replace(_ activity: Activity) {
        guard let index = activities.firstIndex(where: { $0.id == activity.id }) else { return }
        activities[index] = activity
        persist()
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(activities)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            print("Failed to save activities: \(error)")
        }
    }
}
