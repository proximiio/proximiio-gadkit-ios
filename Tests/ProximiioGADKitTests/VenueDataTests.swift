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

    /// Nagarro, 2026-11-02: the language changed wrongly while the app ran. The stops kept the POI
    /// titles of the language the app launched in.
    @Test func everyStopTakesItsPlacesTitleInTheAppLanguage() {
        var stored = journey(states: ["a": .done, "b": .active])
        stored.stops.append(JourneyStop(id: "cafe", title: "Café", coordinate: .init(latitude: 24.5, longitude: 54.4), poiID: "cafe", kind: .detour, state: .active))
        func arabic(_ id: String, _ title: String, _ english: String) -> VenuePlace {
            var place = VenuePlace(id: id, title: title, coordinate: .init(latitude: 24.5, longitude: 54.4), level: 1)
            place.titles = [english, title]
            return place
        }
        let places = [arabic("a", "العمل أ", "Artwork A"), arabic("b", "العمل ب", "Artwork B"),
                      arabic("c", "العمل ج", "Artwork C"), arabic("cafe", "المقهى", "Café")]
        let retitled = VisitPlan.retitled(stored, places: places)
        #expect(retitled.stops.map(\.title) == ["العمل أ", "العمل ب", "العمل ج", "المقهى"])
        #expect(retitled.stops.map(\.state) == stored.stops.map(\.state))
        #expect(retitled.stops.map(\.coordinate) == stored.stops.map(\.coordinate))
        #expect(VisitPlan.retitled(retitled, places: places) == retitled)
    }

    /// A done stop keeps the title the visitor saw after the POI was renamed (`reconciled`).
    @Test func aStopWithATitleThePlaceNoLongerHasKeepsIt() {
        let stored = journey(states: ["a": .done])
        var renamed = VenuePlace(id: "a", title: "Artwork A (new)", coordinate: .init(latitude: 24.5, longitude: 54.4), level: 1)
        renamed.titles = ["Artwork A (new)"]
        #expect(VisitPlan.retitled(stored, places: [renamed]) == stored)
    }

    @Test func aPlaceHasTheTitlesOfEveryLanguage() throws {
        let feature = ProximiioFeature(
            id: "a",
            geometry: .init(type: "Point", coordinates: .array([.number(54.4), .number(24.5)])),
            properties: .object([
                "type": .string("poi"),
                "title": .string("Artwork A"),
                "title_i18n": .object(["en": .string("Artwork A"), "ar": .string("العمل أ"), "fr": .string("")]),
            ])
        )
        let place = try #require(VenuePlace(feature: feature))
        #expect(place.titles == ["Artwork A", "العمل أ"])
        #expect(place.title == VenuePlace.localized(feature.properties?["title_i18n"], language: AppLanguage.current))
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
