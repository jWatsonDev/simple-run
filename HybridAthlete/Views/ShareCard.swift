import SwiftUI
import MapKit

/// 9:16 story-sized share image (1080×1920) for a finished activity.
enum ShareCard {
    static let size = CGSize(width: 360, height: 640)
    static let scale: CGFloat = 3
    private static let mapSize = CGSize(width: 360, height: 430)

    struct Images {
        /// Score, headline and recovery story. nil until the activity has been scored.
        let detailed: UIImage?
        /// Just the run: map and stats, nothing personal.
        let basic: UIImage
    }

    @MainActor
    static func render(_ activity: Activity) async -> Images? {
        let map = await mapImage(activity.route)
        let detailed = activity.difficulty == nil ? nil : image(ShareCardView(activity: activity, map: map))
        guard let basic = image(BasicShareCardView(activity: activity, map: map)) else { return nil }
        return Images(detailed: detailed, basic: basic)
    }

    @MainActor
    private static func image(_ view: some View) -> UIImage? {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
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
                    ShareStat(value: Format.miles(activity.distanceMeters), label: "MILES")
                    ShareStat(value: Format.duration(activity.movingSeconds), label: "TIME")
                    ShareStat(value: Format.pace(distanceMeters: activity.distanceMeters, seconds: activity.movingSeconds), label: "PACE /MI")
                    if let lbs = activity.ruckWeightLbs {
                        ShareStat(value: "\(Int(lbs))", label: "LB RUCK")
                    } else if let hr = activity.heartRate {
                        ShareStat(value: "\(Int(hr.average))", label: "AVG HR")
                    } else {
                        ShareStat(value: "\(Int((activity.elevationGainMeters * Format.feetPerMeter).rounded()))", label: "FT CLIMB")
                    }
                }
                .padding(.top, 22)
                .padding(.horizontal, 14)

                ShareFooter()
            }
        }
        .frame(width: ShareCard.size.width, height: ShareCard.size.height)
    }
}

/// "Just the run" card — no score, no recovery details.
struct BasicShareCardView: View {
    let activity: Activity
    let map: UIImage?

    var body: some View {
        ZStack(alignment: .top) {
            Color.black
            if let map {
                Image(uiImage: map).resizable().frame(width: 360, height: 430)
            }
            LinearGradient(stops: [.init(color: .black.opacity(0.05), location: 0),
                                   .init(color: .black.opacity(0.2), location: 0.4),
                                   .init(color: .black, location: 0.7)],
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

                VStack(spacing: 0) {
                    Text(Format.miles(activity.distanceMeters))
                        .font(.system(size: 96, weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("MILES")
                        .font(.system(size: 14, weight: .heavy))
                        .tracking(4)
                        .opacity(0.7)
                }
                .foregroundStyle(.white)

                HStack(spacing: 0) {
                    ShareStat(value: Format.duration(activity.movingSeconds), label: "TIME")
                    ShareStat(value: Format.pace(distanceMeters: activity.distanceMeters, seconds: activity.movingSeconds), label: "PACE /MI")
                    if let lbs = activity.ruckWeightLbs {
                        ShareStat(value: "\(Int(lbs))", label: "LB RUCK")
                    } else {
                        ShareStat(value: "\(Int((activity.elevationGainMeters * Format.feetPerMeter).rounded()))", label: "FT CLIMB")
                    }
                }
                .padding(.top, 26)
                .padding(.horizontal, 14)

                ShareFooter()
            }
        }
        .frame(width: ShareCard.size.width, height: ShareCard.size.height)
    }
}

struct ShareStat: View {
    let value: String
    let label: String

    var body: some View {
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

struct ShareFooter: View {
    var body: some View {
        VStack(spacing: 0) {
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
}

/// Preview of the card with the system share sheet (Instagram, Messages, Save Image, …).
struct ShareSheet: View {
    enum Style: String, CaseIterable, Identifiable {
        case detailed = "Full story"
        case basic = "Just the run"
        var id: String { rawValue }
    }

    let images: ShareCard.Images
    let title: String
    @Environment(\.dismiss) private var dismiss
    @AppStorage("shareStyle") private var style: Style = .detailed

    private var image: UIImage {
        style == .detailed ? (images.detailed ?? images.basic) : images.basic
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if images.detailed != nil {
                    Picker("Style", selection: $style) {
                        ForEach(Style.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 36)
                }

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
                    .padding(.horizontal, 44)
                    .animation(.snappy, value: style)

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
