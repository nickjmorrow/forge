import ActivityKit
import SwiftUI
import WidgetKit

@main
struct ForgeWidgets: WidgetBundle {
    var body: some Widget { RestLiveActivityWidget() }
}

/// The app icon's plate: vermilion flame on the oxblood fire tile, cream figures (the widget doesn't link ForgeUI's Theme).
private let accent = Color(red: 0xCF / 255, green: 0x6F / 255, blue: 0x45 / 255)
private let ink = Color(red: 0x2A / 255, green: 0x15 / 255, blue: 0x18 / 255)
private let bone = Color(red: 0xE8 / 255, green: 0xDC / 255, blue: 0xC0 / 255)
private let brass = Color(red: 0xC9 / 255, green: 0xA8 / 255, blue: 0x5C / 255)

struct RestLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: "flame.fill").font(.title).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rest").font(.subheadline).foregroundStyle(brass)
                    Text(timerInterval: Date.now...max(Date.now, context.state.endsAt), countsDown: true)
                        .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(bone)
                }
                Spacer()
                ProgressView(timerInterval: Date.now...max(Date.now, context.state.endsAt), countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.circular).tint(accent).frame(width: 44, height: 44)
            }
            .padding(16)
            .activityBackgroundTint(ink.opacity(0.96))
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
