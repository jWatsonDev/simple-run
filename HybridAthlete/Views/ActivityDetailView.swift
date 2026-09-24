import SwiftUI
import MapKit

struct ActivityDetailView: View {
    @EnvironmentObject private var store: ActivityStore
    let id: UUID

    var body: some View {
        Group {
            if let activity = store.activity(id: id) {
                content(activity)
            } else {
                ContentUnavailableView("Activity not found", systemImage: "questionmark")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(_ a: Activity) -> some View {
        List {
            Section {
                if let d = a.difficulty {
                    DifficultyHeader(result: d)
                } else {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Checking your heart rate, sleep and recovery…").foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 24)
                }
            }

            if let d = a.difficulty {
                if needsDrinksAnswer(a) {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Drinks last night?").font(.headline)
                            HStack {
                                ForEach(DrinksAnswer.allCases) { answer in
                                    Button(answer.title) { store.setDrinks(answer, for: a.id) }
                                        .buttonStyle(.bordered)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    } footer: {
                        Text("Apple Health can't tell, so we ask. It changes the story, not the score.")
                    }
                }

                if !d.effortFactors.isEmpty {
                    Section("The session") {
                        ForEach(d.effortFactors, id: \.self, content: FactorRow.init)
                    }
                }
                if !d.recoveryFactors.isEmpty {
                    Section("Going in") {
                        ForEach(d.recoveryFactors, id: \.self, content: FactorRow.init)
                    }
                }
            }

            Section("Stats") {
                LabeledContent("Distance", value: "\(Format.miles(a.distanceMeters)) mi")
                LabeledContent("Moving time", value: Format.duration(a.movingSeconds))
                LabeledContent("Avg pace", value: "\(Format.pace(distanceMeters: a.distanceMeters, seconds: a.movingSeconds)) /mi")
                LabeledContent("Climb", value: Format.feet(a.elevationGainMeters))
                if let lbs = a.ruckWeightLbs { LabeledContent("Ruck weight", value: "\(Int(lbs)) lb") }
                if let hr = a.heartRate {
                    LabeledContent("Avg / max HR", value: "\(Int(hr.average)) / \(Int(hr.max)) bpm")
                }
            }

            Section {
                if a.route.count > 1 {
                    RouteMap(route: a.route)
                        .frame(height: 240)
                        .listRowInsets(EdgeInsets())
                }
            } footer: {
                footerNote(a)
            }
        }
        .navigationTitle("\(a.type.title) · \(a.start.formatted(date: .abbreviated, time: .omitted))")
    }

    private func needsDrinksAnswer(_ a: Activity) -> Bool {
        a.drinksAnswer == nil && a.recovery?.drinksLogged == nil
    }

    @ViewBuilder
    private func footerNote(_ a: Activity) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if a.difficulty?.basedOnHeartRate == false {
                Text("No heart rate for this one, so the score is estimated from pace, hills and weight. Start a workout on your Watch next time for the real story.")
            }
            if a.watchWorkoutFound {
                Text("Your Watch logged this workout, so it's already in Apple Health.")
            } else if a.savedToHealth {
                Text("Saved to Apple Health.")
            }
        }
    }
}

struct DifficultyHeader: View {
    let result: DifficultyResult

    var body: some View {
        VStack(spacing: 14) {
            ScoreBadge(score: result.score, size: 120)
            Text(result.label.uppercased())
                .font(.headline)
                .tracking(2)
                .foregroundStyle(ScoreBadge.color(for: result.score))
            Text(result.headline)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

struct ScoreBadge: View {
    let score: Double
    let size: CGFloat

    static func color(for score: Double) -> Color {
        switch score {
        case ..<3: .green
        case ..<5: .yellow
        case ..<7: .orange
        default: .red
        }
    }

    var body: some View {
        ZStack {
            Circle().stroke(Self.color(for: score).opacity(0.2), lineWidth: size * 0.09)
            Circle()
                .trim(from: 0, to: score / 10)
                .stroke(Self.color(for: score), style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(String(format: "%.1f", score))
                .font(.system(size: size * 0.32, weight: .bold, design: .rounded).monospacedDigit())
        }
        .frame(width: size, height: size)
    }
}

struct FactorRow: View {
    let factor: Factor

    var body: some View {
        Label {
            Text(factor.text)
        } icon: {
            Image(systemName: factor.tone == .harder ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .foregroundStyle(factor.tone == .harder ? .red : .green)
        }
    }
}

struct RouteMap: View {
    let route: [RoutePoint]

    var body: some View {
        Map(initialPosition: .automatic, interactionModes: []) {
            MapPolyline(coordinates: route.map(\.coordinate))
                .stroke(.orange, lineWidth: 4)
            if let first = route.first {
                Marker("Start", systemImage: "flag.fill", coordinate: first.coordinate).tint(.green)
            }
        }
    }
}
