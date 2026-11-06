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
    /// The activities that `end()` ended in this run of the app.
    private static var endedInThisRun: Set<String> = []
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
        } else if let leftover = Self.adoptLeftover() {
            activityID = leftover
            FieldLog.log("live activity: continues the activity of an earlier run")
            Task.detached { await Self.send(content, to: leftover) }
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
        Self.endedInThisRun.insert(activityID)
        let final = lastState.map { ActivityContent(state: $0, staleDate: nil) }
        Task.detached { await Self.end(activityID, with: final) }
        self.activityID = nil
        lastState = nil
    }

    /// The id of a running visit activity that an earlier run of the app left, or `nil`. The other
    /// running ones end at once. An app that is killed during a visit cannot end its activity, and
    /// ActivityKit refuses a new one when the app has its maximum of running activities
    /// (`targetMaximumExceeded`, field test 2026-11-06).
    private static func adoptLeftover() -> String? {
        let running = Activity<VisitActivityAttributes>.activities
            .filter { $0.activityState == .active || $0.activityState == .stale }
            .map(\.id)
            // An activity this run ended can still be running for a moment.
            .filter { !endedInThisRun.contains($0) }
        guard let first = running.first else { return nil }
        let others = Array(running.dropFirst())
        if !others.isEmpty {
            FieldLog.log("live activity: ends \(others.count) more of earlier runs")
            Task.detached { await endAtOnce(others) }
        }
        return first
    }

    // The `Activity` value stays inside these nonisolated functions, so it never crosses
    // an isolation boundary.
    private nonisolated static func endAtOnce(_ ids: [String]) async {
        for activity in Activity<VisitActivityAttributes>.activities where ids.contains(activity.id) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

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
            // At a reached artwork the guidance is the leg to the next stop.
            instruction: navigator.hasArrived ? nil : navigator.guidance.map { GuidanceText.instruction(for: $0, markers: session.routeRenderer?.geometry?.markers ?? []) }
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
