//
//  ProximiJourney.swift
//  ProximiioGADKit
//
//  The journey `ProximiMapView` shows. The host app owns it: it creates it, stores it, moves it on
//  and passes it in a binding. The view writes the stop order and the stop states back only with
//  `ProximiMapView.Options.progress`.
//
import Foundation
import ProximiioMap

/// A journey and its progress, for `ProximiMapView`.
public struct ProximiJourney: Codable, Equatable, Sendable {
    public var kind: JourneyKind
    /// The stops in visit order. The route leads to the first pending stop. With
    /// `ProximiMapView.Options.progress` the view orders a personalised journey floor by floor and
    /// gallery by gallery from the visitor and writes the new order back.
    public var stops: [Stop]

    public init(kind: JourneyKind = .personalised, stops: [Stop]) {
        self.kind = kind
        self.stops = stops
    }

    /// A journey whose stops are all pending.
    /// - Parameter artworks: Collection ids (`remote_id`, for example "GAD.2010.00033") or
    ///   Proximi.io POI ids, in visit order.
    public init(kind: JourneyKind = .personalised, artworks: [String]) {
        self.init(kind: kind, stops: artworks.map { Stop(id: $0) })
    }

    /// The stops of a map library journey, for a host app that built a `Journey` for its own
    /// `JourneyNavigator`. Each stop keeps its id (`JourneyStop(poi)` uses the POI id). A done stop
    /// is visited, a skipped stop is skipped, and a pending, active or reached stop is pending. A
    /// detour stop is left out.
    public init(kind: JourneyKind = .personalised, journey: Journey) {
        self.init(kind: kind, stops: journey.stops.filter { $0.kind != .detour }.map { stop in
            let state: State = switch stop.state {
            case .done: .visited
            case .skipped: .skipped
            case .pending, .active, .reached: .pending
            @unknown default: .pending
            }
            return Stop(id: stop.id, state: state)
        })
    }

    public struct Stop: Codable, Equatable, Sendable, Identifiable {
        /// The id the host app gave: a collection id (`remote_id`) or a Proximi.io POI id.
        public var id: String
        public var state: State

        public init(id: String, state: State = .pending) {
            self.id = id
            self.state = state
        }
    }

    public enum State: String, Codable, Sendable {
        /// Not visited yet. The stop the route leads to is pending too.
        case pending
        /// Visited. With `ProximiMapView.Options.progress` the view sets it when the visitor reaches
        /// the artwork or stays at it out of order.
        case visited
        /// Skipped. With `ProximiMapView.Options.progress` the view sets it when the visitor skips the
        /// artwork in the list or its POI is deleted while the view is open.
        case skipped
    }
}

/// A `ProximiJourney` matched to the venue's places, for `VisitView`.
struct HostedJourney: Equatable {
    /// The navigator's journey: one stop per matched host stop.
    var journey: Journey
    /// The host app's stop id of each POI id.
    var hostIDs: [String: String]
    /// The host app's stops that match no POI, and a second stop of the same POI. The map does not
    /// show them; the journey written back keeps them after the others.
    var unmatched: [ProximiJourney.Stop]

    /// Pure; covered by tests.
    init(_ hosted: ProximiJourney, places: [VenuePlace], galleries: [Gallery] = []) {
        let byID = Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var stops: [JourneyStop] = []
        var hostIDs: [String: String] = [:]
        var unmatched: [ProximiJourney.Stop] = []
        for stop in hosted.stops {
            guard let poiID = ProximiMap.poiIDs(for: [stop.id], in: places).first,
                  hostIDs[poiID] == nil, let place = byID[poiID]
            else {
                unmatched.append(stop)
                continue
            }
            hostIDs[poiID] = stop.id
            var journeyStop = VisitPlan.stop(for: place, galleries: galleries)
            journeyStop.state = switch stop.state {
            case .pending: .pending
            case .visited: .done
            case .skipped: .skipped
            }
            stops.append(journeyStop)
        }
        journey = Journey(stops: stops)
        self.hostIDs = hostIDs
        self.unmatched = unmatched
    }

    /// Whether the open screen, which shows `shown`, can take this journey in place
    /// (`JourneyNavigator.update(to:)`): the same kind and a stop on the map in both. A screen
    /// without stops has no started navigator, and a journey without stops shows the map alone.
    /// Pure; covered by tests.
    func canReplace(_ shown: HostedJourney, kind: JourneyKind, shownKind: JourneyKind) -> Bool {
        kind == shownKind && !shown.journey.stops.isEmpty && !journey.stops.isEmpty
    }

    /// The host app's journey with the order and states of `journey`. Detours are left out. A
    /// reached stop stays pending until it is done. Pure; covered by tests.
    func hostJourney(from journey: Journey, kind: JourneyKind) -> ProximiJourney {
        let stops = journey.stops.compactMap { stop -> ProximiJourney.Stop? in
            guard stop.kind != .detour, let id = hostIDs[stop.poiID ?? stop.id] else { return nil }
            let state: ProximiJourney.State = switch stop.state {
            case .done: .visited
            case .skipped: .skipped
            default: .pending
            }
            return ProximiJourney.Stop(id: id, state: state)
        }
        return ProximiJourney(kind: kind, stops: stops + unmatched)
    }
}

/// A change of the host app's journey for the open screen. `revision` tells two equal journeys
/// apart: the screen applies each change, also one equal to the change before it.
struct IncomingJourney: Equatable {
    var journey: Journey
    var revision: Int
}
