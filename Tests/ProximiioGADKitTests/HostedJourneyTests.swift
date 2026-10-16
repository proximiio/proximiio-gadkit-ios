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

    @Test func aJourneyCanBeStoredAsJSON() throws {
        let journey = ProximiJourney(kind: .curated, stops: [.init(id: "GAD.1", state: .visited), .init(id: "b")])
        let data = try JSONEncoder().encode(journey)
        #expect(try JSONDecoder().decode(ProximiJourney.self, from: data) == journey)
    }
}
