import ActivityKit
import SwiftUI
import WidgetKit

struct RunLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(.black.opacity(0.85))
                .activitySystemActionForegroundColor(.orange)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.title, systemImage: context.attributes.symbol)
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if state.paused {
                        Text("PAUSED").font(.caption.weight(.heavy)).foregroundStyle(.orange)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        stat(ElapsedText(state: state), "time")
                        stat(Text(Format.miles(state.distanceMeters)), "miles")
                        stat(Text(Format.pace(distanceMeters: state.distanceMeters, seconds: state.elapsed())), "avg /mi")
                    }
                }
            } compactLeading: {
                Image(systemName: context.attributes.symbol).foregroundStyle(.orange)
            } compactTrailing: {
                Text("\(Format.miles(state.distanceMeters)) mi")
                    .font(.caption.weight(.semibold).monospacedDigit())
            } minimal: {
                Image(systemName: context.attributes.symbol).foregroundStyle(.orange)
            }
            .keylineTint(.orange)
        }
    }

    private func stat(_ value: some View, _ label: String) -> some View {
        VStack(spacing: 0) {
            value.font(.title3.weight(.bold).monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Moving time that keeps ticking on its own between app updates.
struct ElapsedText: View {
    let state: RunActivityAttributes.ContentState

    var body: some View {
        if let start = state.timerStart {
            Text(timerInterval: start...Date.distantFuture, countsDown: false)
                .multilineTextAlignment(.center)
        } else {
            Text(Format.duration(state.movingSeconds))
        }
    }
}

private struct LockScreenView: View {
    let attributes: RunActivityAttributes
    let state: RunActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(attributes.title.uppercased(), systemImage: attributes.symbol)
                    .font(.caption.weight(.heavy))
                    .tracking(1.2)
                    .foregroundStyle(.orange)
                Spacer()
                Text(state.paused ? "PAUSED" : "Ruck & Run")
                    .font(.caption.weight(state.paused ? .heavy : .semibold))
                    .foregroundStyle(state.paused ? .orange : .white.opacity(0.6))
            }
            HStack(alignment: .firstTextBaseline) {
                ElapsedText(state: state)
                    .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Format.miles(state.distanceMeters)) mi")
                        .font(.title2.weight(.bold).monospacedDigit())
                    Text("\(Format.pace(distanceMeters: state.distanceMeters, seconds: state.elapsed())) /mi avg")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
                .foregroundStyle(.white)
            }
        }
        .padding(16)
    }
}
