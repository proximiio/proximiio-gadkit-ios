//
//  VisitLiveActivity.swift
//  ProximiioGADKit
//
//  Starts, updates and ends the visit Live Activity (Figma "Live Updates / Activities").
//  The Pause and Resume buttons of the design control Nagarro's audio and are not shown.
//
import ActivityKit
import Foundation
import ProximiioGADLiveActivity
import ProximiioMap
import SwiftUI

@MainActor
final class VisitLiveActivity {
    /// The shortest gap between two updates (`GADSettings.liveActivityMinimumInterval`).
    /// Guidance changes with every position.
    private let minimumUpdateInterval: TimeInterval

    init(minimumUpdateInterval: TimeInterval = GADSettings.standard.liveActivityMinimumInterval) {
        self.minimumUpdateInterval = minimumUpdateInterval
    }

    /// Id of the running activity. The activity itself is looked up by id inside each task,
    /// because `Activity` is not `Sendable`.
    private var activityID: String?
    private var lastState: VisitActivityAttributes.ContentState?
    private var lastUpdate = Date.distantPast

    func update(_ state: VisitActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            FieldLog.log("live activity: disabled")
            return
        }
        guard state != lastState else { return }
        let now = Date()
        // Step changes (title, level, finished) are sent at once; instruction changes are throttled.
        let isStepChange = state.title != lastState?.title || state.level != lastState?.level || state.isFinished
        guard isStepChange || now.timeIntervalSince(lastUpdate) >= minimumUpdateInterval else { return }
        lastState = state
        lastUpdate = now
        let content = ActivityContent(state: state, staleDate: nil)
        if let activityID {
            Task.detached { await Self.send(content, to: activityID) }
        } else {
            do {
                activityID = try Activity.request(
                    attributes: VisitActivityAttributes(journeyTitle: String(localized: "Your journey", bundle: .localized)),
                    content: content
                ).id
            } catch {
                FieldLog.log("live activity: request failed: \(error)")
            }
        }
        FieldLog.log("live activity: \(state.title) · \(state.progress) · \(state.instruction)")
    }

    func end() {
        guard let activityID else { return }
        let final = lastState.map { ActivityContent(state: $0, staleDate: nil) }
        Task.detached { await Self.end(activityID, with: final) }
        self.activityID = nil
        lastState = nil
    }

    // The `Activity` value stays inside these nonisolated functions, so it never crosses
    // an isolation boundary.
    private nonisolated static func send(_ content: ActivityContent<VisitActivityAttributes.ContentState>, to id: String) async {
        await Activity<VisitActivityAttributes>.activities.first { $0.id == id }?.update(content)
    }

    private nonisolated static func end(_ id: String, with content: ActivityContent<VisitActivityAttributes.ContentState>?) async {
        await Activity<VisitActivityAttributes>.activities.first { $0.id == id }?.end(content, dismissalPolicy: .default)
    }

    /// The activity state for the visit card state. Pure; covered by tests.
    static func contentState(
        card: VisitCardState,
        journey: Journey,
        activeStopID: String?,
        instruction: String?
    ) -> VisitActivityAttributes.ContentState {
        let numbers = VisitPlan.numbers(for: journey)
        let total = numbers.count
        let progress = activeStopID.flatMap { numbers[$0] }
            .map { String(localized: "Stop \($0) of \(total)", bundle: .localized) } ?? String(localized: "\(total) stops", bundle: .localized)
        switch card {
        case .starting:
            return .init(title: String(localized: "Your journey", bundle: .localized), progress: progress, instruction: "", level: "", isFinished: false)
        case .walking(let stop):
            return .init(title: stop, progress: progress, instruction: instruction ?? "", level: "", isFinished: false)
        case .nextStopOnOtherLevel(let stop, let level):
            return .init(title: stop, progress: progress, instruction: instruction ?? "", level: "L\(level)", isFinished: false)
        case .atStop(let stop):
            return .init(title: stop, progress: progress, instruction: String(localized: "You have arrived", bundle: .localized), level: "", isFinished: false)
        case .finished:
            return .init(title: String(localized: "Journey complete", bundle: .localized), progress: String(localized: "\(total) stops", bundle: .localized), instruction: "", level: "", isFinished: true)
        }
    }
}

/// Invisible view that observes the navigator and feeds the Live Activity.
struct VisitLiveActivityDriver: View {
    @ObservedObject var navigator: JourneyNavigator
    @ObservedObject var session: ProximiioMapSession
    let liveActivity: VisitLiveActivity

    private var state: VisitActivityAttributes.ContentState {
        let card = VisitCardState.make(
            activeStop: navigator.activeStop,
            hasArrived: navigator.hasArrived,
            isFinished: navigator.isFinished,
            visitorLevel: session.position?.floor?.level
        )
        return VisitLiveActivity.contentState(
            card: card,
            journey: navigator.journey,
            activeStopID: navigator.activeStop?.id,
            instruction: navigator.guidance.map { GuidanceText.instruction(for: $0, markers: session.routeRenderer?.geometry?.markers ?? []) }
        )
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear { liveActivity.update(state) }
            .onValueChange(of: state) { _, state in liveActivity.update(state) }
    }
}
