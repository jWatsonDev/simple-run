import SwiftUI
import Charts

// MARK: - Splits

struct SplitsChart: View {
    let splits: [ActivityCharts.Split]

    /// Fastest full mile — a short partial final split is too noisy to crown.
    private var fastest: Int? {
        let full = splits.filter { $0.fraction >= 0.99 }
        return full.count > 1 ? full.min { $0.paceSeconds < $1.paceSeconds }?.index : nil
    }

    private var slowest: Double { splits.map(\.paceSeconds).max() ?? 1 }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(splits) { split in
                let isFastest = split.index == fastest
                HStack(spacing: 10) {
                    Text(split.label)
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .leading)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(isFastest || fastest == nil ? Theme.pace : Theme.pace.opacity(0.45))
                            .frame(width: max(6, geo.size.width * split.paceSeconds / slowest), height: 18)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(height: 22)
                    HStack(spacing: 3) {
                        Text(Format.duration(split.paceSeconds))
                            .font(.caption.monospacedDigit().weight(isFastest ? .bold : .regular))
                            .foregroundStyle(isFastest ? .primary : .secondary)
                        if isFastest {
                            Image(systemName: "bolt.fill").font(.caption2).foregroundStyle(Theme.pace)
                        }
                    }
                    .frame(width: 58, alignment: .leading)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Mile \(split.label), \(Format.duration(split.paceSeconds)) per mile\(isFastest ? ", fastest" : "")")
            }
        }
    }
}

// MARK: - Elevation

struct ElevationChart: View {
    let points: [ActivityCharts.ElevationPoint]
    @State private var selectedMiles: Double?

    private var selected: ActivityCharts.ElevationPoint? {
        guard let selectedMiles else { return nil }
        return points.min { abs($0.miles - selectedMiles) < abs($1.miles - selectedMiles) }
    }

    private var yDomain: ClosedRange<Double> {
        let lo = points.map(\.feet).min() ?? 0, hi = points.map(\.feet).max() ?? 0
        let pad = max((hi - lo) * 0.15, 10)
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        Chart {
            ForEach(points) { p in
                AreaMark(x: .value("Miles", p.miles), yStart: .value("Base", yDomain.lowerBound), yEnd: .value("Feet", p.feet))
                    .foregroundStyle(Theme.elevation.opacity(0.12))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Miles", p.miles), y: .value("Feet", p.feet))
                    .foregroundStyle(Theme.elevation)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            if let s = selected {
                RuleMark(x: .value("Miles", s.miles))
                    .foregroundStyle(Theme.muted)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ChartTooltip(title: String(format: "%.2f mi", s.miles), value: "\(Int(s.feet.rounded())) ft")
                    }
                PointMark(x: .value("Miles", s.miles), y: .value("Feet", s.feet))
                    .symbolSize(80)
                    .foregroundStyle(Theme.elevation)
            }
        }
        .chartYScale(domain: yDomain)
        .chartXSelection(value: $selectedMiles)
        .chartXAxis { axisMarks(unit: "mi") }
        .chartYAxis { axisMarks(unit: "ft") }
        .frame(height: 170)
        .accessibilityLabel("Elevation profile")
    }
}

// MARK: - Heart rate

struct HeartRateChart: View {
    let samples: [HRSample]
    let average: Double
    let start: Date
    @State private var selectedMinute: Double?

    private var points: [(minute: Double, bpm: Double)] {
        ActivityCharts.downsample(samples, to: 300).map { ($0.date.timeIntervalSince(start) / 60, $0.bpm) }
    }

    private var selected: (minute: Double, bpm: Double)? {
        guard let selectedMinute else { return nil }
        return points.min { abs($0.minute - selectedMinute) < abs($1.minute - selectedMinute) }
    }

    private var yDomain: ClosedRange<Double> {
        let lo = samples.map(\.bpm).min() ?? 60, hi = samples.map(\.bpm).max() ?? 180
        return (lo - 10).rounded(.down)...(hi + 10).rounded(.up)
    }

    var body: some View {
        Chart {
            ForEach(points, id: \.minute) { p in
                AreaMark(x: .value("Minute", p.minute), yStart: .value("Base", yDomain.lowerBound), yEnd: .value("BPM", p.bpm))
                    .foregroundStyle(Theme.heart.opacity(0.1))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Minute", p.minute), y: .value("BPM", p.bpm))
                    .foregroundStyle(Theme.heart)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            if points.count < 20 {
                // Sparse data (Watch wasn't recording a workout) — show the actual readings.
                ForEach(points, id: \.minute) { p in
                    PointMark(x: .value("Minute", p.minute), y: .value("BPM", p.bpm))
                        .symbolSize(50)
                        .foregroundStyle(Theme.heart)
                }
            }
            RuleMark(y: .value("Average", average))
                .foregroundStyle(Theme.muted)
                .lineStyle(StrokeStyle(lineWidth: 1))
            if let s = selected {
                RuleMark(x: .value("Minute", s.minute))
                    .foregroundStyle(Theme.muted)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ChartTooltip(title: Format.duration(s.minute * 60), value: "\(Int(s.bpm)) bpm")
                    }
                PointMark(x: .value("Minute", s.minute), y: .value("BPM", s.bpm))
                    .symbolSize(80)
                    .foregroundStyle(Theme.heart)
            }
        }
        .chartYScale(domain: yDomain)
        .chartXSelection(value: $selectedMinute)
        .chartXAxis { axisMarks(unit: "min") }
        .chartYAxis { axisMarks(unit: "") }
        .frame(height: 170)
        .accessibilityLabel("Heart rate over time")
    }
}

// MARK: - HR zones

struct ZonesView: View {
    let zones: [ActivityCharts.ZoneTime]

    private var total: Double { max(zones.map(\.seconds).reduce(0, +), 1) }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(zones.reversed()) { z in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Z\(z.zone) \(z.name)").font(.caption.weight(.semibold))
                        Text("\(z.lowerBPM)–\(z.upperBPM)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .frame(width: 92, alignment: .leading)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.grid).frame(height: 10)
                            Capsule()
                                .fill(Theme.zones[z.zone - 1])
                                .frame(width: max(z.seconds > 0 ? 6 : 0, geo.size.width * z.seconds / total), height: 10)
                        }
                        .frame(maxHeight: .infinity)
                    }
                    .frame(height: 28)

                    Text(z.seconds > 0 ? Format.hoursMinutes(z.seconds) : "—")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Shared

struct ChartTooltip: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 1) {
            Text(value).font(.caption.bold().monospacedDigit())
            Text(title).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private func axisMarks(unit: String) -> some AxisContent {
    AxisMarks(values: .automatic(desiredCount: 4)) { value in
        AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Theme.grid)
        AxisValueLabel {
            if let v = value.as(Double.self) {
                Text(unit.isEmpty ? "\(Int(v))" : (v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v)) \(unit)" : String(format: "%.1f \(unit)", v)))
            }
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(Theme.muted)
    }
}
