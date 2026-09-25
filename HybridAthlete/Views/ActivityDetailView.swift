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
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ a: Activity) -> some View {
        let splits = ActivityCharts.splits(a.route)
        let elevation = ActivityCharts.elevationProfile(a.route)
        let samples = a.heartRateSamples ?? []

        return ScrollView {
            VStack(spacing: 14) {
                HeroCard(activity: a, analyzing: store.analyzing.contains(a.id))

                if a.difficulty != nil, a.drinksAnswer == nil, a.recovery?.drinksLogged == nil {
                    DrinksCard { store.setDrinks($0, for: a.id) }
                }

                StatGrid(activity: a)

                if let d = a.difficulty, !(d.effortFactors + d.recoveryFactors).isEmpty {
                    Card(title: "Why it scored \(String(format: "%.1f", d.score))") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(d.effortFactors + d.recoveryFactors, id: \.self, content: FactorRow.init)
                        }
                    }
                }

                if let rec = a.recovery, rec.sleepHours != nil || rec.restingHR != nil || rec.hrv != nil {
                    Card(title: "Going in", subtitle: "Compared to your 30-day normal") {
                        RecoveryTiles(recovery: rec)
                    }
                }

                if !splits.isEmpty {
                    Card(title: "Splits", subtitle: "Pace per mile") {
                        SplitsChart(splits: splits)
                    }
                }

                if elevation.count > 2 {
                    Card(title: "Elevation", subtitle: "\(Format.feet(a.elevationGainMeters)) climbed") {
                        ElevationChart(points: elevation)
                    }
                }

                if let hr = a.heartRate, samples.count >= 2 {
                    Card(title: "Heart rate", subtitle: "Avg \(Int(hr.average)) · Max \(Int(hr.max)) bpm") {
                        HeartRateChart(samples: samples, average: hr.average, start: a.start)
                        if let maxHR = a.physiology?.maxHR {
                            Divider().padding(.vertical, 4)
                            Text("Time in zones").font(.subheadline.weight(.semibold))
                            ZonesView(zones: ActivityCharts.zones(samples, maxHR: maxHR))
                        }
                    }
                }

                footerNote(a)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .navigationTitle(a.type.title)
    }

    @ViewBuilder
    private func footerNote(_ a: Activity) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if a.difficulty?.basedOnHeartRate == false {
                Text("No heart rate for this one, so the score is estimated from pace, hills and weight. Start a workout on your Watch next time for the real story.")
            } else if let hr = a.heartRate, hr.sampleCount < 20 {
                Text("Only \(hr.sampleCount) heart rate readings — start an Outdoor workout on your Watch for a full trace.")
            }
            if a.watchWorkoutFound {
                Label("Your Watch logged this workout, so it's already in Apple Health.", systemImage: "applewatch")
            } else if a.savedToHealth {
                Label("Saved to Apple Health", systemImage: "heart.fill")
            }
        }
    }
}

// MARK: - Hero

private struct HeroCard: View {
    let activity: Activity
    let analyzing: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            background
            LinearGradient(stops: [.init(color: .black.opacity(0.15), location: 0),
                                   .init(color: .black.opacity(0.35), location: 0.4),
                                   .init(color: .black.opacity(0.92), location: 0.85)],
                           startPoint: .top, endPoint: .bottom)

            VStack(spacing: 12) {
                HStack {
                    Label(activity.type.title.uppercased(), systemImage: activity.type.symbol)
                        .font(.caption.weight(.heavy))
                        .tracking(1.5)
                    Spacer()
                    Text(activity.start.formatted(.dateTime.weekday(.abbreviated).month().day().hour().minute()))
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white.opacity(0.85))

                Spacer(minLength: 0)

                if let d = activity.difficulty {
                    ScoreRing(score: d.score, size: 132, lineWidth: 12, textColor: .white, trackColor: .white.opacity(0.18))
                        .background(Circle().fill(.black.opacity(0.55)).padding(-6))
                    HStack(spacing: 6) {
                        Circle().fill(Theme.scoreColor(d.score)).frame(width: 8, height: 8)
                        Text(d.label.uppercased()).font(.subheadline.weight(.heavy)).tracking(2)
                    }
                    .foregroundStyle(.white)
                    Text(d.headline)
                        .font(.title3.weight(.bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ProgressView().tint(.white).controlSize(.large)
                    Text(analyzing ? "Checking your heart rate, sleep and recovery…" : "No score yet")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(20)
        }
        .frame(height: 440)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// Frames the route in the top part of the card, leaving the bottom clear for the score.
    private var routeCamera: MapCameraPosition {
        let points = activity.route.map { MKMapPoint($0.coordinate) }
        let minX = points.map(\.x).min() ?? 0, maxX = points.map(\.x).max() ?? 0
        let minY = points.map(\.y).min() ?? 0, maxY = points.map(\.y).max() ?? 0
        let w = max(maxX - minX, 1), h = max(maxY - minY, 1)
        let rect = MKMapRect(x: minX - w * 0.35, y: minY - h * 0.25, width: w * 1.9, height: h * 3.1)
        return .rect(rect)
    }

    @ViewBuilder
    private var background: some View {
        if activity.route.count > 1 {
            Map(initialPosition: routeCamera, interactionModes: []) {
                MapPolyline(coordinates: activity.route.map(\.coordinate))
                    .stroke(.orange, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .environment(\.colorScheme, .dark)
            .allowsHitTesting(false)
        } else {
            LinearGradient(colors: [Theme.scoreColor(activity.difficulty?.score ?? 1).opacity(0.7), .black],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

struct ScoreRing: View {
    let score: Double
    var size: CGFloat
    var lineWidth: CGFloat
    var textColor: Color = .primary
    var trackColor: Color = Color(.systemFill)

    var body: some View {
        ZStack {
            Circle().stroke(trackColor, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: score / 10)
                .stroke(Theme.scoreColor(score), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: -4) {
                Text(String(format: "%.1f", score))
                    .font(.system(size: size * 0.34, weight: .heavy, design: .rounded))
                Text("/ 10").font(.system(size: size * 0.1, weight: .semibold)).opacity(0.6)
            }
            .foregroundStyle(textColor)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Difficulty \(String(format: "%.1f", score)) out of 10")
    }
}

// MARK: - Cards

private struct DrinksCard: View {
    let onAnswer: (DrinksAnswer) -> Void

    var body: some View {
        Card(title: "Drinks last night?", subtitle: "Apple Health can't tell, so we ask. It changes the story, not the score.") {
            HStack(spacing: 10) {
                ForEach(DrinksAnswer.allCases) { answer in
                    Button { onAnswer(answer) } label: {
                        Text(answer.title).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}

private struct StatGrid: View {
    let activity: Activity

    var body: some View {
        let a = activity
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            StatTile(label: "Distance", value: Format.miles(a.distanceMeters), unit: "mi")
            StatTile(label: "Time", value: Format.duration(a.movingSeconds), unit: nil)
            StatTile(label: "Avg pace", value: Format.pace(distanceMeters: a.distanceMeters, seconds: a.movingSeconds), unit: "/mi")
            StatTile(label: "Climb", value: "\(Int((a.elevationGainMeters * Format.feetPerMeter).rounded()))", unit: "ft")
            if let hr = a.heartRate {
                StatTile(label: "Avg HR", value: "\(Int(hr.average))", unit: "bpm")
                StatTile(label: "Max HR", value: "\(Int(hr.max))", unit: "bpm")
            } else if let lbs = a.ruckWeightLbs {
                StatTile(label: "Ruck", value: "\(Int(lbs))", unit: "lb")
            }
            if a.heartRate != nil, let lbs = a.ruckWeightLbs {
                StatTile(label: "Ruck", value: "\(Int(lbs))", unit: "lb")
            }
        }
    }
}

private struct StatTile: View {
    let label: String
    let value: String
    let unit: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.title3.weight(.bold)).minimumScaleFactor(0.7).lineLimit(1)
                if let unit { Text(unit).font(.caption2.weight(.semibold)).foregroundStyle(.secondary) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct RecoveryTiles: View {
    let recovery: RecoveryContext

    var body: some View {
        HStack(spacing: 10) {
            tile("Sleep",
                 value: recovery.sleepHours.map { Format.hoursMinutes($0 * 3600) },
                 normal: recovery.typicalSleepHours.map { Format.hoursMinutes($0 * 3600) },
                 delta: delta(recovery.sleepHours, recovery.typicalSleepHours, threshold: 0.5, higherIsBetter: true) {
                     String(format: "%.1fh", $0)
                 })
            tile("Resting HR",
                 value: recovery.restingHR.map { "\(Int($0.rounded()))" },
                 normal: recovery.typicalRestingHR.map { "\(Int($0.rounded()))" },
                 delta: delta(recovery.restingHR, recovery.typicalRestingHR, threshold: 2, higherIsBetter: false) {
                     "\(Int($0.rounded())) bpm"
                 })
            tile("HRV",
                 value: recovery.hrv.map { "\(Int($0.rounded())) ms" },
                 normal: recovery.typicalHRV.map { "\(Int($0.rounded())) ms" },
                 delta: delta(recovery.hrv, recovery.typicalHRV, threshold: 3, higherIsBetter: true) {
                     "\(Int($0.rounded())) ms"
                 })
        }
    }

    private struct Delta { let text: String; let up: Bool; let good: Bool }

    private func delta(_ value: Double?, _ normal: Double?, threshold: Double, higherIsBetter: Bool,
                       format: (Double) -> String) -> Delta? {
        guard let value, let normal, abs(value - normal) >= threshold else { return nil }
        let up = value > normal
        return Delta(text: format(abs(value - normal)), up: up, good: up == higherIsBetter)
    }

    private func tile(_ label: String, value: String?, normal: String?, delta: Delta?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value ?? "—").font(.title3.weight(.bold)).minimumScaleFactor(0.7).lineLimit(1)
            if let delta {
                HStack(spacing: 3) {
                    Image(systemName: delta.up ? "arrow.up" : "arrow.down")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(delta.good ? Theme.good : Theme.critical)
                    Text(delta.text).font(.caption2.weight(.semibold))
                }
            } else if value != nil, normal != nil {
                Text("normal").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            if let normal { Text("usual \(normal)").font(.caption2).foregroundStyle(.tertiary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct FactorRow: View {
    let factor: Factor

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: factor.tone == .harder ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .foregroundStyle(factor.tone == .harder ? Theme.critical : Theme.good)
                .accessibilityLabel(factor.tone == .harder ? "Made it harder" : "Made it easier")
            Text(factor.text).font(.subheadline)
        }
    }
}
