//
//  VisitActivityWidget.swift
//  ProximiioGADLiveActivity
//
//  Lock Screen and Dynamic Island presentation of the visit Live Activity. Add it to the
//  `WidgetBundle` of the host app's widget extension. The extension lists the Guggenheim Sans
//  Display fonts in its own `UIAppFonts`: the widget does not register fonts.
//
import ActivityKit
import SwiftUI
import WidgetKit

public struct VisitActivityWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: VisitActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.white.opacity(0.85))
                .activitySystemActionForegroundColor(ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.isFinished ? "checkmark.circle" : "figure.walk")
                        .font(.title2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !context.state.level.isEmpty {
                        Text(context.state.level).font(.headline)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.title).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 2) {
                        if !context.state.instruction.isEmpty {
                            Text(context.state.instruction).font(.subheadline)
                        }
                        Text(context.state.progress).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isFinished ? "checkmark.circle" : "figure.walk")
            } compactTrailing: {
                Text(context.state.progress).font(.caption2).lineLimit(1)
            } minimal: {
                Image(systemName: "figure.walk")
            }
        }
    }
}

private let ink = Color(red: 0x2B / 255, green: 0x2B / 255, blue: 0x2B / 255)

private struct LockScreenView: View {
    let attributes: VisitActivityAttributes
    let state: VisitActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(state.title)
                    .font(.custom("GuggenheimSansDisplay-Bold", size: 18, relativeTo: .headline))
                    .lineLimit(1)
                Text(verbatim: "\(attributes.journeyTitle) · \(state.progress)")
                    .font(.custom("GuggenheimSansDisplay-Regular", size: 13, relativeTo: .subheadline))
                    .lineLimit(1)
                if !state.instruction.isEmpty {
                    Text(state.instruction)
                        .font(.custom("GuggenheimSansDisplay-Medium", size: 13, relativeTo: .subheadline))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if !state.level.isEmpty {
                Text(state.level)
                    .font(.custom("GuggenheimSansDisplay-Bold", size: 14, relativeTo: .subheadline))
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .foregroundStyle(ink)
        .padding(16)
    }
}
