import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Countdown Live Activity
//
// Lock Screen + Dynamic Island for date nights, trips and anniversaries.
// Started from the app (e.g. day-of countdown), updated via push in production.

struct CountdownLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CountdownActivityAttributes.self) { context in
            // Lock Screen
            HStack(spacing: 14) {
                heartBadge(context.attributes)
                VStack(alignment: .leading, spacing: 3) {
                    Text(context.attributes.title)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.white)
                    Text(context.state.subtitle)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Text(context.state.targetDate, style: .timer)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(Lovio.Palette.gold)
                    .frame(width: 90, alignment: .trailing)
            }
            .padding(16)
            .activityBackgroundTint(Lovio.Palette.plum)
            .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    heartBadge(context.attributes)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.attributes.title)
                            .font(.system(.headline, design: .rounded))
                        Text(context.state.subtitle)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.targetDate, style: .timer)
                        .font(.system(.title3, design: .rounded, weight: .heavy))
                        .foregroundStyle(Lovio.Palette.rose)
                        .frame(width: 70)
                }
            } compactLeading: {
                Image(systemName: "heart.fill")
                    .foregroundStyle(Lovio.Palette.rose)
            } compactTrailing: {
                Text(context.state.targetDate, style: .timer)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(Lovio.Palette.rose)
                    .frame(width: 44)
            } minimal: {
                Image(systemName: "heart.fill")
                    .foregroundStyle(Lovio.Palette.rose)
            }
        }
    }

    private func heartBadge(_ attributes: CountdownActivityAttributes) -> some View {
        ZStack {
            Circle().fill(Lovio.Palette.rose.opacity(0.25))
            HStack(spacing: -6) {
                initial(attributes.myInitials)
                initial(attributes.partnerInitials)
            }
        }
        .frame(width: 44, height: 44)
    }

    private func initial(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(Circle().fill(Lovio.Palette.rose))
    }
}
