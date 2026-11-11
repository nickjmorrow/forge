import ActivityKit
import SwiftUI
import WidgetKit

@main
struct ForgeWidgets: WidgetBundle {
    var body: some Widget { RestLiveActivityWidget() }
}

/// Ember: the fire accent on indigo ink (Theme in ForgeUI; the widget doesn't link it).
private let accent = Color(red: 1.0, green: 0.541, blue: 0.239)
private let ink = Color(red: 0.039, green: 0.043, blue: 0.098)

struct RestLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: "flame.fill").font(.title).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rest").font(.subheadline).foregroundStyle(.secondary)
                    Text(timerInterval: Date.now...max(Date.now, context.state.endsAt), countsDown: true)
                        .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                }
                Spacer()
                ProgressView(timerInterval: Date.now...max(Date.now, context.state.endsAt), countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.circular).tint(accent).frame(width: 44, height: 44)
            }
            .padding(16)
            .activityBackgroundTint(ink.opacity(0.92))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "flame.fill").foregroundStyle(accent) }
                DynamicIslandExpandedRegion(.center) {
                    Text(timerInterval: Date.now...max(Date.now, context.state.endsAt), countsDown: true)
                        .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) { Text("Rest — back to the bar when it hits zero").font(.caption).foregroundStyle(.secondary) }
            } compactLeading: {
                Image(systemName: "flame.fill").foregroundStyle(accent)
            } compactTrailing: {
                Text(timerInterval: Date.now...max(Date.now, context.state.endsAt), countsDown: true).monospacedDigit().frame(width: 44)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(accent)
            }
        }
    }
}
