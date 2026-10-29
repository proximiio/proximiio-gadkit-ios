//
//  VenueDataTests.swift
//  ProximiioGADKitTests
//
import Foundation
import Proximiio
import ProximiioMap
import Testing
@testable import ProximiioGADKit

struct VenueDataTests {
    private let places = [
        VenuePlace(id: "a", title: "Artwork A", coordinate: .init(latitude: 24.5, longitude: 54.4), level: 1),
        VenuePlace(id: "b", title: "Artwork B", coordinate: .init(latitude: 24.6, longitude: 54.5), level: 1),
        VenuePlace(id: "c", title: "Artwork C", coordinate: .init(latitude: 24.7, longitude: 54.6), level: 3),
    ]

    private func journey(states: [String: JourneyStop.State] = [:]) -> Journey {
        var journey = VisitPlan.journey(poiIDs: ["a", "b", "c"], places: places)
        for index in journey.stops.indices {
            journey.stops[index].state = states[journey.stops[index].id] ?? .pending
        }
        return journey
    }

    @Test func aStopWhosePlaceIsDeletedIsRemovedUnlessItIsDone() {
        let stored = journey(states: ["a": .done, "b": .active])
        let remaining = [places[2]]
        let reconciled = VisitPlan.reconciled(stored, places: remaining)
        #expect(reconciled.stops.map(\.id) == ["a", "c"])
        #expect(reconciled.stops[0] == stored.stops[0])
        #expect(VisitPlan.stopsWithoutPlace(in: stored, places: remaining).map(\.id) == ["b"])
    }

    @Test func aMovedPlaceMovesItsStopAndKeepsTheState() {
        let stored = journey(states: ["a": .done, "b": .skipped, "c": .active])
        let moved = [
            VenuePlace(id: "a", title: "Artwork A (new)", coordinate: .init(latitude: 25, longitude: 55), level: 2),
            VenuePlace(id: "b", title: "Artwork B (new)", coordinate: .init(latitude: 25, longitude: 55), level: 2),
            VenuePlace(id: "c", title: "Artwork C (new)", coordinate: .init(latitude: 25.1, longitude: 55.1), level: 4),
        ]
        let reconciled = VisitPlan.reconciled(stored, places: moved)
        #expect(reconciled.stops.map(\.state) == [.done, .skipped, .active])
        // A done stop keeps the title and position the visitor saw.
        #expect(reconciled.stops[0].title == "Artwork A")
        #expect(reconciled.stops[1].title == "Artwork B (new)")
        #expect(reconciled.stops[2].coordinate == MapCoordinate(latitude: 25.1, longitude: 55.1))
        #expect(reconciled.stops[2].floor == FloorKey(level: 4))
    }

    @Test func unchangedPlacesLeaveTheJourneyAsItIs() {
        let stored = journey(states: ["a": .done, "b": .active])
        #expect(VisitPlan.reconciled(stored, places: places) == stored)
        #expect(VisitPlan.stopsWithoutPlace(in: stored, places: places).isEmpty)
    }

    @Test func aDetourStopIsKept() {
        var stored = journey()
        stored.stops.append(JourneyStop(id: "cafe", title: "Café", coordinate: .init(latitude: 24.5, longitude: 54.4), poiID: "cafe", kind: .detour, state: .active))
        #expect(VisitPlan.reconciled(stored, places: places).stops.last?.id == "cafe")
    }

    @Test func featureChangesAreCountedByID() {
        func feature(_ id: String, title: String) -> ProximiioFeature {
            ProximiioFeature(
                id: id,
                geometry: .init(type: "Point", coordinates: .array([.number(54.4), .number(24.5)])),
                properties: .object(["title": .string(title)])
            )
        }
        let old = [feature("1", title: "One"), feature("2", title: "Two"), feature("3", title: "Three")]
        let new = [feature("3", title: "Three"), feature("2", title: "Two, moved"), feature("4", title: "Four")]
        #expect(VenueDataRefresh.changes(from: old, to: new) == .init(added: 1, removed: 1, changed: 1))
        #expect(VenueDataRefresh.changes(from: old, to: old.reversed()).isEmpty)
    }

    /// The open map redraws a changed style itself. The screens read the amenity catalogue for the
    /// icons and lists, so a change of it reads it again.
    @Test func theScreensFollowFeaturesGeofencesFloorsPlacesAndAmenities() {
        #expect(VenueDataRefresh.watchedKinds == [.features, .geofences, .floors, .places, .amenities])
    }
}
