//
//  ProximiMapTypes.swift
//  ProximiioGADKit
//
//  The values the host app exchanges with `ProximiMap`: the journey it sets, the journey and
//  wristband states it shows, the screens it opens, the events it receives and the errors.
//
import Foundation
import ProximiioMap

/// A journey for `ProximiMap.setJourney(_:)`: from the audio guide (personalised) or a curated tour.
public struct JourneyPlan: Equatable, Sendable {
    /// Shown on Journey ready and in `JourneySummary`.
    public var title: String
    /// The line under the title, for example "6 stops". `nil` shows the number of stops.
    public var summary: String?
    public var kind: JourneyKind
    /// The artworks in visit order: collection ids (`remote_id`, for example "GAD.2010.00033") or
    /// Proximi.io POI ids. Ids that match no POI are left out.
    public var artworks: [String]

    public init(title: String, summary: String? = nil, kind: JourneyKind = .personalised, artworks: [String]) {
        self.title = title
        self.summary = summary
        self.kind = kind
        self.artworks = artworks
    }
}

/// The stored journey, for the host app's own screens (for example a journey card).
public struct JourneySummary: Equatable, Sendable {
    public var title: String
    public var summary: String?
    public var kind: JourneyKind
    /// The artworks of the journey. Detours to amenities do not count.
    public var stopCount: Int
    /// The artworks not visited or skipped yet. 0 when the journey is finished.
    public var remainingStopCount: Int
    /// `true` once a stop was visited or skipped.
    public var isStarted: Bool

    public init(title: String, summary: String?, kind: JourneyKind, stopCount: Int, remainingStopCount: Int, isStarted: Bool) {
        self.title = title
        self.summary = summary
        self.kind = kind
        self.stopCount = stopCount
        self.remainingStopCount = remainingStopCount
        self.isStarted = isStarted
    }
}

/// The phone's wristband session.
public enum WristbandStatus: Equatable, Sendable {
    /// No session. `notice` says why the last session ended, for example "Your wristband was scanned
    /// by another phone."; `nil` when none has ended since the launch.
    case notConnected(notice: String?)
    /// A `connectWristband(code:)` request is in flight.
    case connecting
    /// The phone follows the wristband's positions.
    case connected
}

/// A journey stop, an amenity or a detour, in `ProximiMapEvent`.
public struct ProximiStop: Equatable, Sendable, Identifiable {
    /// The Proximi.io POI id.
    public var id: String
    public var title: String
    /// The artwork's collection id (`remote_id`), or `nil` for an amenity.
    public var artworkID: String?
    /// The floor, or `nil` when the POI has none.
    public var level: Int?

    public init(id: String, title: String, artworkID: String? = nil, level: Int? = nil) {
        self.id = id
        self.title = title
        self.artworkID = artworkID
        self.level = level
    }
}

/// A geofence of the venue, in `ProximiMapEvent.geofenceEntered` and `geofenceExited`.
public struct ProximiGeofence: Equatable, Sendable, Identifiable {
    /// The Proximi.io geofence id.
    public var id: String
    public var name: String?
    /// `metadata.geofence_type`: `artwork`, `gallery`, or `nil`.
    public var type: String?
    /// The artwork's collection id (`remote_id`) of an artwork geofence.
    public var artworkID: String?

    public init(id: String, name: String? = nil, type: String? = nil, artworkID: String? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.artworkID = artworkID
    }
}

/// What `ProximiMap` reports to the host app. `ProximiMap` performs every action itself; the
/// events only report it. New cases can come in minor versions: a `switch` with `default` keeps
/// compiling.
public enum ProximiMapEvent: Equatable, Sendable {
    // Screens

    /// A screen opened, by `open(_:)` or inside a flow (the stop picker opens Journey ready).
    case opened(ProximiMap.Screen)
    /// A screen closed. The host app's screen below takes taps again.
    case closed(ProximiMap.Screen)
    /// "Craft a new journey" on Manage journey. The host app shows its journey crafting, for example
    /// the audio guide. Sent after Manage journey has closed.
    case craftNewJourneyRequested
    /// "Edit stops" on Manage journey for a curated tour. The host app shows its tour choice. Sent
    /// after Manage journey has closed.
    case curatedTourChangeRequested

    // Visitor and wristband

    /// The visitor is at the museum: a wristband or playback position, or a phone fix within 400 m
    /// of the venue. Once per launch.
    case arrivedAtMuseum
    case wristbandChanged(WristbandStatus)
    /// The wristband's positions stopped or came back. No alert is shown; the host app decides.
    case trackingChanged(TrackingHealth)
    /// The visitor entered a geofence, for example an artwork's. Sent with or without a journey, for
    /// the audio guide.
    case geofenceEntered(ProximiGeofence)
    /// The visitor left a geofence.
    case geofenceExited(ProximiGeofence)

    // Journey

    /// A new, edited or deleted (`nil`) journey.
    case journeyChanged(JourneySummary?)
    /// The route leads to this stop now.
    case nextStop(ProximiStop)
    /// The active stop is less than `GADSettings.stopNearbyMeters` away on the visitor's level. Once
    /// per stop. The package posts no notification for it.
    case stopNearby(ProximiStop)
    /// The position is uncertain near the active stop: the accuracy is worse than
    /// `GADSettings.uncertainAccuracyMeters` and the stop is within it. Sent by `ProximiMapView` without `Options.prompts`,
    /// which otherwise asks "Probably at …". At most once per
    /// `GADSettings.locationQuestionQuietPeriod`.
    case positionUncertain(ProximiStop)
    /// The stop's POI was deleted on the backend while `ProximiMapView` is open. Once per stop.
    /// Without `ProximiMapView.Options.progress` the stop stays on the screen until the host app
    /// changes the journey; that change starts the screen again without it. With `.progress` the
    /// stop is skipped.
    case stopPlaceDeleted(ProximiStop)
    /// `GADSettings.artworkAdvanceDelay` after the visitor reached the artwork of the active stop:
    /// the stop is done and the route leads to the next stop.
    case artworkReached(ProximiStop)
    /// The visitor stayed at an artwork further down the journey. It counts as visited. A
    /// personalised journey orders the stops ahead again.
    case artworkVisitedOutOfOrder(ProximiStop)
    /// `ProximiMapView` with `Options.progress`: the view ordered the stops again, from the visitor's
    /// first position, after `artworkVisitedOutOfOrder` or after a detour. The journey in the host
    /// app's ids and its new order; the `journey` binding already holds it.
    case stopOrderChanged(ProximiJourney)
    /// The visitor swiped a stop in the list. With `ProximiMapView.Options.prompts` a dialog asks
    /// "Skip artwork?"; without them the host app decides.
    case skipRequested(ProximiStop)
    case stopSkipped(ProximiStop)
    case skipCancelled(ProximiStop)
    /// Not sent since 1.13.0: the list has no "Undo skip" (PM, Monday "Undo skip removed", 2026-10-23).
    @available(*, deprecated, message: "Not sent since 1.13.0: the list has no Undo skip.")
    case skipUndone(ProximiStop)
    /// The visitor picked an amenity on the map. A card shows it with "Go here".
    case amenitySelected(ProximiStop)
    /// The amenity is now a detour of the journey.
    case detourStarted(ProximiStop)
    /// The detour ended: reached (`completed`) or left.
    case detourEnded(ProximiStop, completed: Bool)
    /// "Resume your Journey" or "Show the route from here".
    case journeyResumed
    /// The visitor has been off the route for `GADSettings.offRouteSeconds`.
    case offRoute(duration: TimeInterval)
    /// The visitor is on the route again after `offRoute`.
    case backOnRoute
    /// Every stop is visited or skipped. `ProximiMap`, and `ProximiMapView` with
    /// `Options.journeyComplete`, show Journey Complete.
    case journeyFinished
    /// The map shows a floor without positioning and does not follow the visitor.
    case floorWithoutPositioningEntered(level: Int)
    /// The map follows the visitor again.
    case floorWithoutPositioningLeft(level: Int)

    // Controls on the journey screen

    /// The Map / List toggle.
    case modeChanged(VisitMode)
    /// "Centre on me".
    case recentred
    /// The accessible routes button: on (`true`) or off.
    case accessibleRoutesChanged(Bool)
    /// Back during a journey in progress. "Leave the tour here" asks before the journey screen closes.
    case exitRequested
    case exitConfirmed
    case exitCancelled
}

/// An error of `ProximiMap`. `localizedDescription` is the text for the visitor.
public enum ProximiMapError: LocalizedError, Equatable, Sendable {
    /// `start()` has not finished.
    case notStarted
    /// The SDK did not start, for example without network on the first launch. `start()` can be
    /// called again.
    case startFailed(String)
    /// The wristband was not connected. The text says why, for example "This wristband is already in
    /// use. Please ask the staff."
    case wristband(String)
    /// None of the plan's artworks is a POI of the venue.
    case noKnownArtworks

    public var errorDescription: String? {
        switch self {
        case .notStarted, .startFailed:
            String(localized: "I couldn’t get things started. Check your connection and let’s try again.", bundle: .module)
        case .wristband(let message):
            message
        case .noKnownArtworks:
            String(localized: "None of these artworks is on the museum map.", bundle: .module)
        }
    }
}
