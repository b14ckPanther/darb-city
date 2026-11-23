import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

/// The drive on the Lock Screen and in the Dynamic Island. Flat Darb colours: forest field, ivory type,
/// mustard for the one number that matters, the minutes left.
struct DriveLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DriveAttributes.self) { context in
            DriveLockView(context: context)
                .environment(\.layoutDirection, context.attributes.rtl ? .rightToLeft : .leftToRight)
                .activityBackgroundTint(Color(hex: 0x0B2219))
                .activitySystemActionForegroundColor(Color(hex: 0xFBF7EC))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    DriveArt(context: context, size: 52).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    DriveLeft(context: context, size: 30).padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.name).font(.darb(size: 17, .heavy)).lineLimit(1)
                        .foregroundStyle(Color(hex: 0xFBF7EC))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    DriveFacts(context: context).padding(.top, 2)
                }
            } compactLeading: {
                DriveArt(context: context, size: 24)
            } compactTrailing: {
                DriveLeft(context: context, size: 15).frame(maxWidth: 52)
            } minimal: {
                DriveArt(context: context, size: 24)
            }
            .keylineTint(Color(hex: 0xFFC330))
        }
    }
}

private let mustard = Color(hex: 0xFFC330)
private let ivory = Color(hex: 0xFBF7EC)

private struct DriveArt: View {
    let context: ActivityViewContext<DriveAttributes>
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(Color(hex: context.attributes.hex))
            if let image = UIImage(named: "live-" + context.attributes.art) {
                Image(uiImage: image).resizable().scaledToFit().padding(size * 0.1)
            }
        }
        .frame(width: size, height: size)
    }
}

/// The minutes left, counting down by itself; once you should be there it asks instead.
private struct DriveLeft: View {
    let context: ActivityViewContext<DriveAttributes>
    let size: CGFloat
    var body: some View {
        if context.isStale || context.state.arrive <= .now {
            Text(L("הגעתם?")).font(.darb(size: size * 0.6, .heavy)).foregroundStyle(mustard)
        } else {
            Text(timerInterval: Date.now...context.state.arrive, countsDown: true, showsHours: false)
                .font(.figure(size: size, .heavy)).monospacedDigit()
                .multilineTextAlignment(.trailing)
                .foregroundStyle(mustard)
                .environment(\.layoutDirection, .leftToRight)
        }
    }
}

private struct DriveFacts: View {
    let context: ActivityViewContext<DriveAttributes>
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(context.state.open ? Color(hex: 0x2FCF86) : Color(hex: 0x6F8A7D)).frame(width: 7, height: 7)
            Text(context.state.until).font(.darb(size: 14, .bold))
            Spacer(minLength: 4)
            Text(L("הגעה")).font(.darb(size: 14, .medium)).opacity(0.7)
            Text(context.state.arrive, style: .time).font(.figure(size: 14, .bold))
        }
        .foregroundStyle(ivory)
    }
}

private struct DriveLockView: View {
    let context: ActivityViewContext<DriveAttributes>
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                DriveArt(context: context, size: 54)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("בדרך")).font(.darb(size: 13, .bold)).foregroundStyle(mustard)
                    Text(context.attributes.name).font(.darb(size: 19, .heavy)).lineLimit(1).foregroundStyle(ivory)
                }
                Spacer(minLength: 6)
                DriveLeft(context: context, size: 34)
            }
            DriveFacts(context: context)
        }
        .padding(16)
    }
}
