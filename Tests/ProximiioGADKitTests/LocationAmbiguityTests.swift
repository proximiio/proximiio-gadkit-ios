//
//  LocationAmbiguityTests.swift
//  ProximiioGADKitTests
//
import Foundation
import Proximiio
import ProximiioMap
import Testing
@testable import ProximiioGADKit

struct LocationAmbiguityTests {
    /// 0.00001° of latitude is about 1.1 m.
    private static func place(_ id: String, _ title: String, north metres: Double, level: Double = 1) -> VenuePlace {
        VenuePlace(id: id, title: title, coordinate: .init(latitude: 24.5 + metres / 111_000, longitude: 54.4), level: level)
    }

    private let here = ProximiioCoordinate(latitude: 24.5, longitude: 54.4)
    private let artworks = [Self.place("a", "Artwork A", north: 2), Self.place("b", "Artwork B", north: 4), Self.place("c", "Artwork C", north: 30)]

    private func input(accuracy: Double = 3, stops: [String] = ["a", "b", "c"], active: String? = nil,
                       galleries: [VenuePlace] = [], currentGallery: String? = nil) -> LocationAmbiguity.Input {
        let journey = VisitPlan.journey(poiIDs: stops, places: artworks)
        return .init(coordinate: here, level: 1, horizontalAccuracy: accuracy,
                     activeStop: active.flatMap { id in journey.stops.first { $0.id == id } },
                     galleries: galleries, currentGallery: currentGallery)
    }

    @Test func nearbyStopsAreNotAmbiguous() {
        #expect(LocationAmbiguity.evaluate(input()) == nil)
        #expect(LocationAmbiguity.evaluate(input(stops: ["a", "c"])) == nil)
    }

    @Test func betweenGalleriesOnlyOutsideAGalleryGeofence() {
        let galleries = [Self.place("g1", "Gallery 101", north: 8), Self.place("g2", "Gallery 102", north: -8), Self.place("g3", "Gallery 103", north: 80)]
        let outside = input(stops: ["c"], galleries: galleries)
        #expect(LocationAmbiguity.evaluate(outside)?.kind == "galleries")
        #expect(LocationAmbiguity.evaluate(input(stops: ["c"], galleries: galleries, currentGallery: "Gallery 101")) == nil)
    }

    @Test func uncertainPositionNearTheActiveStopIsASoftPrompt() {
        #expect(LocationAmbiguity.evaluate(input(accuracy: 12, stops: ["c"], active: "c")) == nil)
        #expect(LocationAmbiguity.evaluate(input(accuracy: 40, stops: ["c"], active: "c"))?.kind == "low")
        #expect(LocationAmbiguity.evaluate(input(accuracy: 5, stops: ["c"], active: "c")) == nil)
    }

    @Test func galleriesAreFoundByTitle() {
        #expect(LocationAmbiguity.galleries(in: artworks + [Self.place("g", "Gallery 101", north: 0)]).map(\.id) == ["g"])
    }
}

struct JourneyLifecycleTests {
    private let places = ["a", "b", "c", "d"].map {
        VenuePlace(id: $0, title: $0.uppercased(), coordinate: .init(latitude: 24.5, longitude: 54.4), level: 1)
    }

    @Test func lastOpenStop() {
        var journey = VisitPlan.journey(poiIDs: ["a", "b"], places: places)
        #expect(!VisitPlan.isLastOpenStop(journey.stops[1], in: journey))
        journey = VisitPlan.setting(.done, forStop: "a", in: journey)
        #expect(VisitPlan.isLastOpenStop(journey.stops[1], in: journey))
    }

    @Test func visitMetaRoundTripsAndClears() throws {
        let defaults = try #require(UserDefaults(suiteName: "JourneyLifecycleTests-\(UUID().uuidString)"))
        let meta = VisitMeta(title: "Light & Perception", summary: "8 stops")
        VisitStore.saveMeta(meta, to: defaults)
        #expect(VisitStore.loadMeta(from: defaults) == meta)
        VisitStore.saveMeta(nil, to: defaults)
        #expect(VisitStore.loadMeta(from: defaults) == nil)
    }
}
