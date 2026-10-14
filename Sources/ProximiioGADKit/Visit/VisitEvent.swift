//
//  VisitEvent.swift
//  ProximiioGADKit
//
//  What happens in `VisitView`, for the host app: the visitor's actions on the map and the list,
//  and the progress of the journey. The host app receives the events with `onVisitEvent(_:)`.
//  `VisitView` performs every action itself; the events only report them.
//
import ProximiioMap
import SwiftUI

/// The two presentations of the journey in `VisitView`.
public enum VisitMode: String, Sendable, Equatable {
    case map
    case list
}

/// A visitor action in `VisitView`, or a change of the journey.
public enum VisitEvent: Sendable, Equatable {
    /// The presentation changed: the Map / List toggle, or "Where are you?", which shows the map.
    case modeChanged(VisitMode)
    /// The visitor swiped a stop in the list, or used its "Skip" accessibility action.
    /// `VisitView` asks "Skip artwork?".
    case skipRequested(JourneyStop)
    /// The visitor confirmed "Skip artwork". The stop is skipped.
    case stopSkipped(JourneyStop)
    /// The visitor answered "Keep it". The stop stays in the journey.
    case skipCancelled(JourneyStop)
    /// The visitor tapped "Undo skip". The stop is back in the journey.
    case skipUndone(JourneyStop)
    /// The visitor picked the stop they are at in "Where are you?". It becomes the active stop.
    case stopChosen(JourneyStop)
    /// The visitor picked the gallery they are in, by name, in "Which one are you in?".
    case galleryChosen(String)
    /// The visitor picked an amenity on the map. A card shows it with "Go here".
    case amenitySelected(VenuePlace)
    /// The amenity is now a detour of the journey: the visitor confirmed "Change your route?", or
    /// chose the route to the Welcome Desk in a tracking alert.
    case detourStarted(VenuePlace)
    /// The visitor tapped "Resume your Journey" or "Show the route from here".
    case journeyResumed
    /// The visitor tapped "Centre on me".
    case recentred
    /// The visitor tapped Back during a visit in progress. `VisitView` asks before it closes.
    case exitRequested
    /// The visitor confirmed leaving the visit. `onClose` follows.
    case exitConfirmed
    /// The visitor answered "Carry on". The visit continues.
    case exitCancelled
    /// The active stop is less than 5 m away on the visitor's level. Once per stop for the
    /// whole visit. Measured like the notification of `StopNearbyNotifier`.
    case stopNearby(JourneyStop)
    /// The visitor reached the artwork of the active stop: they entered its geofence or stand in
    /// its area. The stop is done 2 s later, when this event arrives, and the route leads to the
    /// next stop. The navigator reports no `stopReached` for artworks.
    case artworkReached(JourneyStop)
    /// The visitor stayed at an artwork further down the journey. The stop is done and the stops
    /// still ahead are ordered again from the visitor.
    case artworkVisitedOutOfOrder(JourneyStop)
    /// An event of the journey navigator: a new leg, a skipped stop, a re-route, a detour, the
    /// journey finished. For artworks use `artworkReached`: the navigator does not report them
    /// reached.
    case journey(JourneyEvent)
}

private struct VisitEventHandlerKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable (VisitEvent) -> Void = { _ in }
}

extension EnvironmentValues {
    var visitEventHandler: @MainActor @Sendable (VisitEvent) -> Void {
        get { self[VisitEventHandlerKey.self] }
        set { self[VisitEventHandlerKey.self] = newValue }
    }
}

extension View {
    /// Calls `action` with every `VisitEvent` of the `VisitView`s in this view. Handlers of
    /// enclosing views are called first.
    public func onVisitEvent(_ action: @escaping @MainActor @Sendable (VisitEvent) -> Void) -> some View {
        transformEnvironment(\.visitEventHandler) { handler in
            let enclosing = handler
            handler = { event in
                enclosing(event)
                action(event)
            }
        }
    }
}
