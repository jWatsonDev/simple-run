import SwiftUI
import MapKit

/// 9:16 story-sized share image (1080×1920) for a finished activity.
enum ShareCard {
    static let size = CGSize(width: 360, height: 640)
    static let scale: CGFloat = 3
    private static let mapSize = CGSize(width: 360, height: 430)

    @MainActor
    static func render(_ activity: Activity) async -> UIImage? {
        let map = await mapImage(activity.route)
        let renderer = ImageRenderer(content: ShareCardView(activity: activity, map: map).environment(\.colorScheme, .dark))
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(size)
        return renderer.uiImage
    }

    /// Dark, muted map snapshot with the route drawn on top. The route sits in the upper part of the frame.
    private static func mapImage(_ route: [RoutePoint]) async -> UIImage? {
        guard route.count > 1 else { return nil }
        let points = route.map { MKMapPoint($0.coordinate) }
        let minX = points.map(\.x).min()!, maxX = points.map(\.x).max()!
        let minY = points.map(\.y).min()!, maxY = points.map(\.y).max()!
        var w = max(maxX - minX, 200) * 1.5
        var h = max(maxY - minY, 200) * 2.5
        let aspect = mapSize.width / mapSize.height
        if w / h < aspect { w = h * aspect } else { h = w / aspect }
        let midX = (minX + maxX) / 2
        // Route centered 30% down, so the score block below doesn't cover it.
        let top = (minY + maxY) / 2 - 0.3 * h

        let options = MKMapSnapshotter.Options()
        options.mapRect = MKMapRect(x: midX - w / 2, y: top, width: w, height: h)
        options.size = mapSize
        options.scale = scale
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        options.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        options.pointOfInterestFilter = .excludingAll

        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: mapSize, format: format).image { ctx in
            snapshot.image.draw(at: .zero)
            let path = UIBezierPath()
            for (i, p) in route.enumerated() {
                let pt = snapshot.point(for: p.coordinate)
                i == 0 ? path.move(to: pt) : path.addLine(to: pt)
            }
            path.lineWidth = 5
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            UIColor.systemOrange.setStroke()
            path.stroke()

            if let first = route.first {
                let pt = snapshot.point(for: first.coordinate)
                let dot = UIBezierPath(ovalIn: CGRect(x: pt.x - 6, y: pt.y - 6, width: 12, height: 12))
                UIColor.white.setFill()
                dot.fill()
                UIColor.systemOrange.setStroke()
                dot.lineWidth = 3
                dot.stroke()
            }
        }
    }
}

struct ShareCardView: View {
    let activity: Activity
    let map: UIImage?

    var body: some View {
        ZStack(alignment: .top) {
            Color.black

            if let map {
                Image(uiImage: map)
                    .resizable()
                    .frame(width: 360, height: 430)
            }
            LinearGradient(stops: [.init(color: .black.opacity(0.1), location: 0),
                                   .init(color: .black.opacity(0.3), location: 0.35),
                                   .init(color: .black, location: 0.68)],
                           startPoint: .top, endPoint: .bottom)

            VStack(spacing: 0) {
                Rectangle().fill(.orange).frame(height: 5)

                HStack {
                    Label(activity.type.title.uppercased(), systemImage: activity.type.symbol)
                        .font(.system(size: 13, weight: .heavy))
                        .tracking(1.5)
                    Spacer()
                    Text(activity.start.formatted(.dateTime.month(.abbreviated).day().year()))
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 22)
                .padding(.top, 16)

                Spacer(minLength: 0)

                if let d = activity.difficulty {
                    ScoreRing(score: d.score, size: 128, lineWidth: 11, textColor: .white, trackColor: .white.opacity(0.18))
                        .background(Circle().fill(.black.opacity(0.6)).padding(-6))
                    HStack(spacing: 6) {
                        Circle().fill(Theme.scoreColor(d.score)).frame(width: 8, height: 8)
                        Text(d.label.uppercased()).font(.system(size: 15, weight: .heavy)).tracking(2)
                    }
                    .foregroundStyle(.white)
                    .padding(.top, 12)
                    Text(d.headline)
                        .font(.system(size: 19, weight: .bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 26)
                        .padding(.top, 8)
                }

                HStack(spacing: 0) {
                    stat(Format.miles(activity.distanceMeters), "MILES")
                    stat(Format.duration(activity.movingSeconds), "TIME")
                    stat(Format.pace(distanceMeters: activity.distanceMeters, seconds: activity.movingSeconds), "PACE /MI")
                    if let lbs = activity.ruckWeightLbs {
                        stat("\(Int(lbs))", "LB RUCK")
                    } else if let hr = activity.heartRate {
                        stat("\(Int(hr.average))", "AVG HR")
                    } else {
                        stat("\(Int((activity.elevationGainMeters * Format.feetPerMeter).rounded()))", "FT CLIMB")
                    }
                }
                .padding(.top, 22)
                .padding(.horizontal, 14)

                Rectangle().fill(.white.opacity(0.18)).frame(height: 1)
                    .padding(.horizontal, 22)
                    .padding(.top, 20)

                HStack {
                    Text("Ruck & Run").font(.system(size: 15, weight: .heavy))
                    Spacer()
                    Text("A DadHabit.dad app").font(.system(size: 12, weight: .semibold)).opacity(0.6)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 16)

                Rectangle().fill(.orange).frame(height: 5)
            }
        }
        .frame(width: ShareCard.size.width, height: ShareCard.size.height)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 10, weight: .heavy))
                .tracking(1)
                .opacity(0.6)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
    }
}

/// Preview of the card with the system share sheet (Instagram, Messages, Save Image, …).
struct ShareSheet: View {
    let image: UIImage
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
                    .padding(.horizontal, 36)

                ShareLink(item: Image(uiImage: image), preview: SharePreview(title, image: Image(uiImage: image))) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 36)
            }
            .padding(.vertical)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
