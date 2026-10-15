//
//  VisitPlanTests.swift
//  ProximiioGADKitTests
//
import Foundation
import Proximiio
import ProximiioMap
import Testing
@testable import ProximiioGADKit

struct VisitPlanTests {
    private let places = [
        VenuePlace(id: "a", title: "Gallery 101", coordinate: .init(latitude: 24.5, longitude: 54.4), level: 1),
        VenuePlace(id: "b", title: "Artwork 1", coordinate: .init(latitude: 24.6, longitude: 54.5), level: 1),
        VenuePlace(id: "c", title: "Gallery 304", coordinate: .init(latitude: 24.7, longitude: 54.6), level: 3),
    ]

    @Test func journeyKeepsTheGivenOrderAndDropsUnknownIDs() {
        let journey = VisitPlan.journey(poiIDs: ["c", "x", "a"], places: places)
        #expect(journey.stops.map(\.id) == ["c", "a"])
        #expect(journey.stops[0].floor == FloorKey(level: 3))
        #expect(journey.stops.allSatisfy { $0.state == .pending && $0.poiID == $0.id })
    }

    @Test func skippedStopsAreNotNumberedAndTheRestRenumber() {
        var journey = VisitPlan.journey(poiIDs: ["a", "b", "c"], places: places)
        journey = VisitPlan.setting(.skipped, forStop: "b", in: journey)
        #expect(VisitPlan.numbers(for: journey) == ["a": 1, "c": 2])
        journey = VisitPlan.setting(.pending, forStop: "b", in: journey)
        #expect(VisitPlan.numbers(for: journey) == ["a": 1, "b": 2, "c": 3])
    }

    @Test func artworkAreaContainsPointsInsideTheCircleOrPolygon() {
        let center = ProximiioCoordinate(latitude: 24.5, longitude: 54.4)
        let circle = ArtworkArea(center: center, radius: 3)
        // 0.00002° of latitude is about 2.2 m; 0.00004° about 4.4 m.
        #expect(circle.contains(ProximiioCoordinate(latitude: 24.50002, longitude: 54.4)))
        #expect(!circle.contains(ProximiioCoordinate(latitude: 24.50004, longitude: 54.4)))
        #expect(!ArtworkArea(center: ProximiioCoordinate(latitude: 0, longitude: 0), radius: 3)
            .contains(ProximiioCoordinate(latitude: 0, longitude: 0)))
        let square = ArtworkArea(center: nil, radius: 0, polygon: [[54.4, 24.5], [54.401, 24.5], [54.401, 24.501], [54.4, 24.501]])
        #expect(square.contains(ProximiioCoordinate(latitude: 24.5005, longitude: 54.4005)))
        #expect(!square.contains(ProximiioCoordinate(latitude: 24.502, longitude: 54.4005)))
    }

    /// GAD data 2026-10-15: "DCT Mother/Earth" shares `remote_id` with the Guggenheim artwork.
    /// Only the first geofence was kept, so the visitor inside the DCT one did not reach it.
    @Test func everyGeofenceOfAnArtworkIsKept() {
        let artwork: JSONValue = .object(["geofence_type": .string("artwork")])
        let guggenheim = ProximiioCoordinate(latitude: 24.5, longitude: 54.4)
        let dct = ProximiioCoordinate(latitude: 25.2, longitude: 55.3)
        let areas = VisitController.artworkAreas(of: [
            ProximiioGeofence(id: "g", area: guggenheim, radius: 2, metadata: artwork, remoteId: "GAD.2018.00034"),
            ProximiioGeofence(id: "d", area: dct, radius: 2, metadata: artwork, remoteId: "GAD.2018.00034"),
            ProximiioGeofence(id: "n", area: dct, radius: 2, metadata: artwork, remoteId: ""),
            ProximiioGeofence(id: "x", area: dct, radius: 2, metadata: .object(["geofence_type": .string("gallery")]), remoteId: "e07fe5d7"),
        ])
        #expect(areas.keys.sorted() == ["GAD.2018.00034"])
        #expect(areas["GAD.2018.00034"]?.contains { $0.contains(dct) } == true)
        #expect(areas["GAD.2018.00034"]?.contains { $0.contains(guggenheim) } == true)
    }

    @Test func geofenceDwellCountsUnbrokenTimeInside() {
        var dwell = GeofenceDwell()
        let start = Date(timeIntervalSince1970: 0)
        #expect(dwell.update(inside: ["b"], now: start, dwell: 3).isEmpty)
        #expect(dwell.update(inside: ["b", "c"], now: start.addingTimeInterval(2), dwell: 3).isEmpty)
        #expect(dwell.update(inside: ["b", "c"], now: start.addingTimeInterval(3), dwell: 3) == ["b"])
        // Leaving resets the time.
        #expect(dwell.update(inside: ["b"], now: start.addingTimeInterval(4), dwell: 3) == ["b"])
        #expect(dwell.update(inside: ["c"], now: start.addingTimeInterval(5), dwell: 3).isEmpty)
        #expect(dwell.update(inside: ["c"], now: start.addingTimeInterval(8), dwell: 3) == ["c"])
    }

    @Test func enterEventFindsTheActiveArtworkOnly() {
        var journey = VisitPlan.journey(poiIDs: ["a", "b", "c"], places: places)
        let remoteIDs = ["a": "GAD.1", "b": "GAD.2", "c": "GAD.3"]
        #expect(VisitController.activeStopID(forRemoteID: "GAD.1", in: journey, remoteIDs: remoteIDs) == nil)
        journey = VisitPlan.setting(.active, forStop: "a", in: journey)
        #expect(VisitController.activeStopID(forRemoteID: "GAD.1", in: journey, remoteIDs: remoteIDs) == "a")
        #expect(VisitController.activeStopID(forRemoteID: "GAD.2", in: journey, remoteIDs: remoteIDs) == nil)
        #expect(VisitController.activeStopID(forRemoteID: nil, in: journey, remoteIDs: remoteIDs) == nil)
        journey = VisitPlan.setting(.reached, forStop: "a", in: journey)
        #expect(VisitController.activeStopID(forRemoteID: "GAD.1", in: journey, remoteIDs: remoteIDs) == "a")
    }

    @Test func detoursAreNotNumberedListedOrCounted() {
        var journey = VisitPlan.journey(poiIDs: ["a", "c"], places: places)
        var detour = VisitPlan.stop(for: places[1])
        detour.kind = .detour
        detour.state = .active
        journey.stops.insert(detour, at: 1)
        #expect(VisitPlan.numbers(for: journey) == ["a": 1, "c": 2])
        #expect(VisitPlan.artworks(in: journey).map(\.id) == ["a", "c"])
        #expect(VisitPlan.remainingStopCount(in: journey) == 2)
        #expect(VisitPlan.isLastOpenStop(journey.stops[2], in: journey) == false)
    }

    @Test func cardStates() {
        let stops = VisitPlan.journey(poiIDs: ["a", "c"], places: places).stops
        #expect(VisitCardState.make(activeStop: stops[0], hasArrived: false, isFinished: false, visitorLevel: 1) == .walking(stop: "Gallery 101"))
        #expect(VisitCardState.make(activeStop: stops[1], hasArrived: false, isFinished: false, visitorLevel: 1) == .nextStopOnOtherLevel(stop: "Gallery 304", level: 3))
        #expect(VisitCardState.make(activeStop: stops[1], hasArrived: true, isFinished: false, visitorLevel: 3) == .walking(stop: "Gallery 304"))
        #expect(VisitCardState.make(activeStop: stops[1], hasArrived: true, isFinished: false, visitorLevel: 3, showsArrival: true) == .atStop(stop: "Gallery 304"))
        #expect(VisitCardState.make(activeStop: stops[1], hasArrived: false, isFinished: false, visitorLevel: nil) == .walking(stop: "Gallery 304"))
        #expect(VisitCardState.make(activeStop: nil, hasArrived: false, isFinished: true, visitorLevel: 1) == .finished)
        #expect(VisitCardState.make(activeStop: nil, hasArrived: false, isFinished: false, visitorLevel: 1) == .starting)
    }

    @Test func visitStoreRoundTripsAndClears() throws {
        let defaults = try #require(UserDefaults(suiteName: "VisitPlanTests-\(UUID().uuidString)"))
        let journey = VisitPlan.setting(.done, forStop: "a", in: VisitPlan.journey(poiIDs: ["a", "b"], places: places))
        VisitStore.save(journey, to: defaults)
        #expect(VisitStore.load(from: defaults) == journey)
        VisitStore.save(nil, to: defaults)
        #expect(VisitStore.load(from: defaults) == nil)
    }
}

struct VenuePlaceLocalizationTests {
    @Test func artworkIsRecognisedByMetadataArtworkID() {
        #expect(VenuePlace.isArtwork(metadata: .object(["artwork_id": .string("00a3f4dc"), "acquisition_number": .string("GAD.2020.00042")])))
        #expect(!VenuePlace.isArtwork(metadata: .object(["gallery_id": .string("e98413bc")])))
        #expect(!VenuePlace.isArtwork(metadata: nil))
        #expect(VenuePlace.isArtwork(metadata: .object(["gallery_id": .string("9c8403c6")]), remoteID: "GAD.2018.00034"))
        #expect(!VenuePlace.isArtwork(metadata: nil, remoteID: "9c8403c6-2898-4259-8c6a-dc3b22d93d20"))
        #expect(VenuePlace.isArtwork(amenityID: VenuePlace.artworkAmenityID, metadata: nil))
    }

    private let i18n: JSONValue = .object(["en": .string("Café"), "ar": .string("المقهى"), "fr": .string("")])

    @Test func picksTheAppLanguageAndFallsBackToTheBaseLanguage() {
        #expect(VenuePlace.localized(i18n, language: "ar") == "المقهى")
        #expect(VenuePlace.localized(i18n, language: "en-GB") == "Café")
    }

    @Test func returnsNilForMissingOrEmptyTranslations() {
        #expect(VenuePlace.localized(i18n, language: "fr") == nil)
        #expect(VenuePlace.localized(i18n, language: "de") == nil)
        #expect(VenuePlace.localized(.string("Café"), language: "en") == nil)
        #expect(VenuePlace.localized(nil, language: "en") == nil)
    }
}

struct RemainingStopsTests {
    @Test func finishedJourneyHasNoRemainingStops() {
        let coordinate = ProximiioCoordinate(latitude: 0, longitude: 0)
        let places = [VenuePlace(id: "a", title: "A", coordinate: coordinate, level: 1),
                      VenuePlace(id: "b", title: "B", coordinate: coordinate, level: 1)]
        var journey = VisitPlan.journey(poiIDs: ["a", "b"], places: places)
        #expect(VisitPlan.remainingStopCount(in: journey) == 2)
        journey = VisitPlan.setting(.done, forStop: "a", in: journey)
        journey = VisitPlan.setting(.skipped, forStop: "b", in: journey)
        #expect(VisitPlan.remainingStopCount(in: journey) == 0)
    }
}

struct VisitLiveActivityTests {
    private let places = [
        VenuePlace(id: "a", title: "Gallery 101", coordinate: .init(latitude: 0, longitude: 0), level: 1),
        VenuePlace(id: "b", title: "Gallery 304", coordinate: .init(latitude: 0, longitude: 0), level: 3),
    ]

    @Test @MainActor func statesForEachCard() {
        let journey = VisitPlan.journey(poiIDs: ["a", "b"], places: places)
        let walking = VisitLiveActivity.contentState(card: .walking(stop: "Gallery 101"), journey: journey, activeStopID: "a", instruction: "Turn left in 50 m")
        #expect(walking == .init(title: "Gallery 101", progress: "Stop 1 of 2", instruction: "Turn left in 50 m", level: "", isFinished: false))
        let level = VisitLiveActivity.contentState(card: .nextStopOnOtherLevel(stop: "Gallery 304", level: 3), journey: journey, activeStopID: "b", instruction: nil)
        #expect(level.level == "L3")
        #expect(level.progress == "Stop 2 of 2")
        let finished = VisitLiveActivity.contentState(card: .finished, journey: journey, activeStopID: nil, instruction: nil)
        #expect(finished.isFinished)
        #expect(finished.title == "Journey complete")
    }
}

extension VisitPlan {
    /// `journey` with stop `id` set to `state`. Builds journey fixtures.
    static func setting(_ state: JourneyStop.State, forStop id: String, in journey: Journey) -> Journey {
        var journey = journey
        guard let index = journey.stops.firstIndex(where: { $0.id == id }) else { return journey }
        journey.stops[index].state = state
        return journey
    }
}
