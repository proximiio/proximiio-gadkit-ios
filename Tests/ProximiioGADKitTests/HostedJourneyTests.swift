//
//  HostedJourneyTests.swift
//  ProximiioGADKitTests
//
import Foundation
import ProximiioMap
import Testing
@testable import ProximiioGADKit

struct HostedJourneyTests {
    private let places = [
        VenuePlace(id: "a", title: "Artwork A", coordinate: .init(latitude: 24.5, longitude: 54.4), level: 1, remoteID: "GAD.1"),
        VenuePlace(id: "b", title: "Artwork B", coordinate: .init(latitude: 24.6, longitude: 54.5), level: 1, remoteID: "GAD.2"),
        VenuePlace(id: "c", title: "Artwork C", coordinate: .init(latitude: 24.7, longitude: 54.6), level: 3),
    ]

    @Test func stopsMatchByCollectionIDOrPOIIDAndKeepTheirStates() {
        let hosted = ProximiJourney(kind: .curated, stops: [
            .init(id: "GAD.2", state: .visited),
            .init(id: "c", state: .skipped),
            .init(id: "GAD.1"),
        ])
        let matched = HostedJourney(hosted, places: places)
        #expect(matched.journey.stops.map(\.id) == ["b", "c", "a"])
        #expect(matched.journey.stops.map(\.state) == [.done, .skipped, .pending])
        #expect(matched.unmatched.isEmpty)
        #expect(matched.hostJourney(from: matched.journey, kind: .curated) == hosted)
    }

    @Test func unknownAndRepeatedStopsStayAfterTheOthers() {
        let hosted = ProximiJourney(stops: [
            .init(id: "GAD.404"),
            .init(id: "a"),
            .init(id: "GAD.1", state: .visited),
            .init(id: "b"),
        ])
        let matched = HostedJourney(hosted, places: places)
        #expect(matched.journey.stops.map(\.id) == ["a", "b"])
        #expect(matched.unmatched.map(\.id) == ["GAD.404", "GAD.1"])
        #expect(matched.hostJourney(from: matched.journey, kind: .personalised).stops.map(\.id) == ["a", "b", "GAD.404", "GAD.1"])
    }

    @Test func theWrittenJourneyFollowsTheNavigatorsOrderAndStates() {
        let matched = HostedJourney(ProximiJourney(artworks: ["GAD.1", "GAD.2", "c"]), places: places)
        var journey = matched.journey
        journey.stops = [journey.stops[2], journey.stops[0], journey.stops[1]]
        journey.stops[0].state = .done
        journey.stops[1].state = .reached
        journey.stops[2].state = .skipped
        journey.stops.append(JourneyStop(id: "cafe", title: "Café", coordinate: .init(latitude: 24.5, longitude: 54.4), poiID: "cafe", kind: .detour, state: .active))
        let written = matched.hostJourney(from: journey, kind: .personalised)
        #expect(written.stops.map(\.id) == ["c", "GAD.1", "GAD.2"])
        // A reached stop is pending until it is done; the detour is not a stop of the host app.
        #expect(written.stops.map(\.state) == [.visited, .pending, .skipped])
    }

    /// A new kind, a journey without a stop on the map and a first journey on a map without one
    /// start the screen again. Fewer stops are taken in place (`JourneyNavigator.update(to:)`).
    @Test func theOpenScreenTakesAJourneyInPlaceUnlessItCannot() {
        let shown = HostedJourney(ProximiJourney(artworks: ["GAD.1", "GAD.2"]), places: places)
        let more = HostedJourney(ProximiJourney(stops: [.init(id: "GAD.2", state: .visited), .init(id: "c"), .init(id: "GAD.1")]), places: places)
        #expect(more.canReplace(shown, kind: .personalised, shownKind: .personalised))
        #expect(!more.canReplace(shown, kind: .curated, shownKind: .personalised))
        let fewer = HostedJourney(ProximiJourney(artworks: ["GAD.1"]), places: places)
        #expect(fewer.canReplace(shown, kind: .personalised, shownKind: .personalised))
        let empty = HostedJourney(ProximiJourney(artworks: []), places: places)
        #expect(!more.canReplace(empty, kind: .personalised, shownKind: .personalised))
        #expect(!empty.canReplace(shown, kind: .personalised, shownKind: .personalised))
        let offTheMap = HostedJourney(ProximiJourney(artworks: ["GAD.unknown"]), places: places)
        #expect(!offTheMap.canReplace(shown, kind: .personalised, shownKind: .personalised))
    }

    @Test func aJourneyCanBeStoredAsJSON() throws {
        let journey = ProximiJourney(kind: .curated, stops: [.init(id: "GAD.1", state: .visited), .init(id: "b")])
        let data = try JSONEncoder().encode(journey)
        #expect(try JSONDecoder().decode(ProximiJourney.self, from: data) == journey)
    }

    @Test func aMapLibraryJourneyKeepsItsStopIDsAndProgressWithoutTheDetour() {
        func stop(_ id: String, _ state: JourneyStop.State, kind: JourneyStop.Kind = .planned) -> JourneyStop {
            JourneyStop(id: id, title: id, coordinate: .init(latitude: 24.5, longitude: 54.4), poiID: id, kind: kind, state: state)
        }
        let journey = Journey(stops: [
            stop("a", .done), stop("b", .skipped), stop("cafe", .active, kind: .detour),
            stop("c", .reached), stop("d", .active), stop("e", .pending),
        ])
        #expect(ProximiJourney(kind: .curated, journey: journey) == ProximiJourney(kind: .curated, stops: [
            .init(id: "a", state: .visited), .init(id: "b", state: .skipped),
            .init(id: "c"), .init(id: "d"), .init(id: "e"),
        ]))
    }
}
