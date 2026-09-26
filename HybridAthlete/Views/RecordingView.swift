import SwiftUI
import MapKit

struct RecordingView: View {
    @EnvironmentObject private var recorder: ActivityRecorder
    /// Called with the finished activity, or nil if it was discarded.
    let onFinish: (Activity?) -> Void

    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var confirmingFinish = false
    @State private var confirmingDiscard = false

    var body: some View {
        VStack(spacing: 0) {
            Map(position: $camera) {
                UserAnnotation()
                if recorder.route.count > 1 {
                    MapPolyline(coordinates: recorder.route.map(\.coordinate))
                        .stroke(.orange, lineWidth: 5)
                }
            }
            .mapControls { MapUserLocationButton() }
            .frame(maxHeight: .infinity)

            VStack(spacing: 20) {
                HStack {
                    Label(recorder.type.title, systemImage: recorder.type.symbol)
                    if let lbs = recorder.ruckWeightLbs { Text("· \(Int(lbs)) lb") }
                    Spacer()
                    if recorder.state == .paused {
                        Text("PAUSED").font(.caption.bold()).foregroundStyle(.orange)
                    }
                }
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

                Text(Format.duration(recorder.movingSeconds))
                    .font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())

                HStack {
                    stat(Format.miles(recorder.distanceMeters), "miles")
                    stat(Format.pace(distanceMeters: recorder.distanceMeters, seconds: recorder.movingSeconds), "avg pace /mi")
                    stat(Format.feet(recorder.elevationGainMeters), "climb")
                }

                if recorder.locationDenied {
                    Text("Location is off — turn it on in Settings to track distance.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                HStack(spacing: 16) {
                    if recorder.state == .recording {
                        Button { recorder.pause() } label: {
                            Label("Pause", systemImage: "pause.fill").frame(maxWidth: .infinity).padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button { recorder.resume() } label: {
                            Label("Resume", systemImage: "play.fill").frame(maxWidth: .infinity).padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button { confirmingFinish = true } label: {
                        Label("Finish", systemImage: "stop.fill").frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .font(.headline)
            }
            .padding(20)
            .background(.bar)
        }
        .alert("End \(recorder.type.title.lowercased())?", isPresented: $confirmingFinish) {
            Button("End & Save") { onFinish(recorder.finish()) }
            Button("Keep Going", role: .cancel) {}
            Button("Discard…", role: .destructive) { confirmingDiscard = true }
        } message: {
            Text("\(Format.miles(recorder.distanceMeters)) mi in \(Format.duration(recorder.movingSeconds)).")
        }
        .alert("Discard this \(recorder.type.title.lowercased())?", isPresented: $confirmingDiscard) {
            Button("Discard", role: .destructive) {
                recorder.discard()
                onFinish(nil)
            }
            Button("Keep It", role: .cancel) { confirmingFinish = true }
        } message: {
            Text("It won't be saved anywhere. This can't be undone.")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.bold().monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
