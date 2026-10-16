//
//  ProximiJourney.swift
//  ProximiioGADKit
//
//  The journey `ProximiMapView` shows and updates. The host app owns it: it creates it, stores
//  it and passes it in a binding. The view writes the stop order and the stop states back.
//
import Foundation
import ProximiioMap

/// A journey and its progress, for `ProximiMapView`.
public struct ProximiJourney: Codable, Equatable, Sendable {
    public var kind: JourneyKind
    /// The stops in visit order. `ProximiMapView` orders a personalised journey floor by floor and
    /// gallery by gallery from the visitor, and writes the new order back.
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
        /// The visitor reached the artwork, or stayed at it out of order.
        case visited
        /// The visitor skipped the artwork in the list, or its POI was deleted while the view was
        /// open.
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
