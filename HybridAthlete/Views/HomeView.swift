import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var store: ActivityStore
    @EnvironmentObject private var recorder: ActivityRecorder

    @AppStorage("activityType") private var type: ActivityType = .run
    @AppStorage("ruckWeightLbs") private var ruckWeight: Double = 30

    @State private var today: RecoveryContext?
    @State private var recording = false
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section("Going in today") {
                    RecoveryCard(context: today)
                }

                Section {
                    Picker("Activity", selection: $type) {
                        ForEach(ActivityType.allCases) { t in
                            Label(t.title, systemImage: t.symbol).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)

                    if type == .ruck {
                        Stepper(value: $ruckWeight, in: 5...150, step: 5) {
                            LabeledContent("Ruck weight", value: "\(Int(ruckWeight)) lb")
                        }
                    }

                    Button {
                        recorder.start(type: type, ruckWeightLbs: ruckWeight)
                        recording = true
                    } label: {
                        Label("Start \(type.title)", systemImage: "play.fill")
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowSeparator(.hidden)
                } footer: {
                    Text("Wearing your Watch? Start an Outdoor \(type == .run ? "Run" : "Walk") on it too — that's how your heart rate gets recorded every few seconds.")
                }

                Section("History") {
                    if store.activities.isEmpty {
                        Text("Nothing yet. Go get after it.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.activities) { activity in
                        NavigationLink(value: activity.id) {
                            ActivityRow(activity: activity, analyzing: store.analyzing.contains(activity.id))
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { store.activities[$0].id }.forEach(store.delete)
                    }
                }
            }
            .navigationTitle("Ruck & Run")
            .navigationDestination(for: UUID.self) { id in
                ActivityDetailView(id: id)
            }
            .refreshable { await loadToday() }
            .task {
                recorder.requestPermission()
                await health.requestAuthorization()
                await loadToday()
            }
            .fullScreenCover(isPresented: $recording) {
                RecordingView { finished in
                    recording = false
                    if let finished {
                        store.add(finished)
                        path = [finished.id]
                    }
                }
            }
        }
    }

    private func loadToday() async {
        today = await health.recoveryContext(before: Date())
    }
}

struct ActivityRow: View {
    let activity: Activity
    let analyzing: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: activity.type.symbol)
                .font(.title2)
                .frame(width: 36)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Format.miles(activity.distanceMeters)) mi \(activity.type.title)")
                    .font(.headline)
                Text(activity.start.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let difficulty = activity.difficulty {
                ScoreRing(score: difficulty.score, size: 44, lineWidth: 5)
            } else if analyzing {
                ProgressView()
            }
        }
        .padding(.vertical, 2)
    }
}

struct RecoveryCard: View {
    let context: RecoveryContext?

    var body: some View {
        HStack {
            stat("Sleep", value: context?.sleepHours.map { Format.hoursMinutes($0 * 3600) },
                 note: compare(context?.sleepHours, context?.typicalSleepHours, higherIsBetter: true, unit: "h", scale: 1))
            Divider()
            stat("Resting HR", value: context?.restingHR.map { "\(Int($0.rounded()))" },
                 note: compare(context?.restingHR, context?.typicalRestingHR, higherIsBetter: false, unit: "", scale: 1))
            Divider()
            stat("HRV", value: context?.hrv.map { "\(Int($0.rounded())) ms" },
                 note: compare(context?.hrv, context?.typicalHRV, higherIsBetter: true, unit: "", scale: 1))
        }
        .padding(.vertical, 4)
    }

    private func stat(_ title: String, value: String?, note: (String, Color)?) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value ?? "—").font(.title3.bold().monospacedDigit())
            Text(note?.0 ?? " ").font(.caption2.bold()).foregroundStyle(note?.1 ?? .secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// "▲ 4 vs normal" style note, green when it's the good direction.
    private func compare(_ value: Double?, _ typical: Double?, higherIsBetter: Bool, unit: String, scale: Double) -> (String, Color)? {
        guard let value, let typical else { return nil }
        let delta = value - typical
        let threshold = unit == "h" ? 0.5 : max(typical * 0.05, 2)
        guard abs(delta) >= threshold else { return ("normal", .secondary) }
        let good = (delta > 0) == higherIsBetter
        let amount = unit == "h" ? String(format: "%.1f", abs(delta)) : "\(Int(abs(delta).rounded()))"
        return ("\(delta > 0 ? "▲" : "▼") \(amount)\(unit) vs normal", good ? .green : .red)
    }
}
