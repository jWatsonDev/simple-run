import SwiftUI

@main
struct HybridAthleteApp: App {
    @StateObject private var health: HealthKitManager
    @StateObject private var store: ActivityStore
    @StateObject private var recorder = ActivityRecorder()

    init() {
        let health = HealthKitManager()
        _health = StateObject(wrappedValue: health)
        _store = StateObject(wrappedValue: ActivityStore(health: health))
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(health)
                .environmentObject(store)
                .environmentObject(recorder)
                .tint(.orange)
        }
    }
}
