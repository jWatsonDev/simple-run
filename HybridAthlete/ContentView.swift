import SwiftUI

struct ContentView: View {
    @StateObject private var healthKit = HealthKitManager()

    var body: some View {
        VStack(spacing: 24) {
            Text("Hybrid Athlete")
                .font(.largeTitle.bold())

            VStack(spacing: 8) {
                Text("Resting Heart Rate")
                    .foregroundStyle(.secondary)
                Text(healthKit.restingHeartRate.map { "\(Int($0)) bpm" } ?? "—")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
            }

            VStack(spacing: 8) {
                Text("Heart Rate Variability")
                    .foregroundStyle(.secondary)
                Text(healthKit.heartRateVariability.map { "\(Int($0)) ms" } ?? "—")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
            }

            if let error = healthKit.authorizationError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }

            Button("Refresh") {
                Task { await healthKit.fetchLatestValues() }
            }

            Button("Add Fake Sample (Simulator testing)") {
                Task { await healthKit.seedFakeSample() }
            }
            .font(.footnote)
        }
        .padding()
        .task {
            await healthKit.requestAuthorization()
        }
    }
}

#Preview {
    ContentView()
}
