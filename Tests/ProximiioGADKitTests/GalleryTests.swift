//
//  GalleryTests.swift
//  ProximiioGADKitTests
//
import Foundation
import Proximiio
import ProximiioMap
import Testing
@testable import ProximiioGADKit

struct GalleryTests {
    /// A 0.001° square on level 1, in GeoJSON [longitude, latitude] order.
    private func geofence(_ id: String, name: String?, floor: String?, type: String = "gallery") -> ProximiioGeofence {
        ProximiioGeofence(id: id, name: name, polygon: [[54.400, 24.500], [54.401, 24.500], [54.401, 24.501], [54.400, 24.501]],
                          floorId: floor, metadata: .object(["geofence_type": .string(type)]))
    }

    @Test func polygonGeofencesWithANameAndFloorBecomeGalleries() {
        let galleries = Gallery.all(
            geofences: [geofence("g", name: "Gallery 101", floor: "f1"),
                        geofence("x", name: nil, floor: "f1"),
                        geofence("y", name: "Unknown floor", floor: "f9"),
                        geofence("a", name: "Artwork", floor: "f1", type: "artwork")],
            levels: ["f1": 1]
        )
        #expect(galleries.map(\.id) == ["g"])
        #expect(galleries[0].ring[0] == ProximiioCoordinate(latitude: 24.5, longitude: 54.4))
    }

    @Test func containsChecksTheOutlineAndTheLevel() throws {
        let gallery = try #require(Gallery.all(geofences: [geofence("g", name: "G", floor: "f1")], levels: ["f1": 1]).first)
        let inside = ProximiioCoordinate(latitude: 24.5005, longitude: 54.4005)
        #expect(gallery.contains(inside, level: 1))
        #expect(gallery.contains(inside, level: nil))
        #expect(!gallery.contains(inside, level: 2))
        #expect(!gallery.contains(ProximiioCoordinate(latitude: 24.502, longitude: 54.4005), level: 1))
    }

    @Test func levelColours() {
        #expect(Gallery.colors(forLevel: 1).destination == 0x6FA6FF)
        #expect(Gallery.colors(forLevel: 3).visited == 0xFFF291)
    }

    @Test func stopGroupIsTheGalleryThatContainsIt() {
        let ring = [(24.0, 54.0), (24.0, 54.1), (24.1, 54.1), (24.1, 54.0)].map { ProximiioCoordinate(latitude: $0.0, longitude: $0.1) }
        let gallery = Gallery(id: "g1", name: "Gallery 1", level: 1, ring: ring)
        let places = [
            VenuePlace(id: "in", title: "in", coordinate: .init(latitude: 24.05, longitude: 54.05), level: 1),
            VenuePlace(id: "otherFloor", title: "otherFloor", coordinate: .init(latitude: 24.05, longitude: 54.05), level: 2),
            VenuePlace(id: "out", title: "out", coordinate: .init(latitude: 24.5, longitude: 54.5), level: 1),
        ]
        let stops = VisitPlan.journey(poiIDs: ["in", "otherFloor", "out"], places: places, galleries: [gallery]).stops
        #expect(stops.map(\.group) == ["g1", nil, nil])
    }

    @Test func aHeaderPrecedesEachRunOfStopsInOneSection() {
        let places = ["a", "b", "c", "d", "e"].map {
            VenuePlace(id: $0, title: $0, coordinate: .init(latitude: 24.5, longitude: 54.4), level: 1)
        }
        let stops = VisitPlan.journey(poiIDs: ["a", "b", "c", "d", "e"], places: places).stops
        let section = ["a": "G1", "b": "G1", "c": "G2", "d": "G1"]
        let rows = VisitPlan.listRows(stops) { section[$0.id] }
        #expect(rows.map(\.id) == ["header-a", "a", "b", "header-c", "c", "header-d", "d", "e"])
        let titles = rows.compactMap { row -> String? in
            if case .header(_, let title) = row { return title } else { return nil }
        }
        #expect(titles == ["G1", "G2", "G1"])
    }

    @Test func listRowIDsAreUnique() {
        let places = ["a", "b", "c"].map {
            VenuePlace(id: $0, title: $0, coordinate: .init(latitude: 24.5, longitude: 54.4), level: 1)
        }
        let stops = VisitPlan.journey(poiIDs: ["a", "b", "c"], places: places).stops
        let rows = VisitPlan.listRows(stops) { _ in "G1" }
        #expect(Set(rows.map(\.id)).count == rows.count)
    }
}

struct GalleryNameTests {
    private func place(_ id: String, _ title: String, remoteID: String?, isArtwork: Bool = false) -> VenuePlace {
        var place = VenuePlace(id: id, title: title, coordinate: .init(latitude: 24.5, longitude: 54.4), level: 4, remoteID: remoteID)
        place.isArtwork = isArtwork
        return place
    }

    /// GAD data 2026-10-15: the artworks of "G403 Weaving" (level 4) name it in `metadata.gallery_id`,
    /// and the gallery POI holds that id in `remote_id`.
    @Test func galleryPOIsNameGalleriesByTheirRemoteID() {
        let names = Gallery.names(places: [
            place("a", "G403 Weaving", remoteID: "e07fe5d7"),
            place("b", "G304 Histories ", remoteID: "24096077"),
            place("c", "Gallery 102", remoteID: ""),
            place("d", "Café", remoteID: nil),
            place("e", "Untitled", remoteID: "GAD.2010.00033", isArtwork: true),
        ])
        #expect(names == ["e07fe5d7": "G403 Weaving", "24096077": "G304 Histories"])
    }
}

struct GalleryOutlineTests {
    @Test func polygonOuterRingIsReadInGeoJSONOrder() throws {
        let square: JSONValue = .array([.array([
            .array([.number(54.400), .number(24.500)]), .array([.number(54.401), .number(24.500)]),
            .array([.number(54.401), .number(24.501)]), .array([.number(54.400), .number(24.500)]),
        ])])
        let ring = try #require(Gallery.outerRing(type: "Polygon", coordinates: square))
        #expect(ring.count == 4)
        #expect(ring[1] == ProximiioCoordinate(latitude: 24.5, longitude: 54.401))
        #expect(Gallery.outerRing(type: "MultiPolygon", coordinates: .array([square]))?.count == 4)
        #expect(Gallery.outerRing(type: "Point", coordinates: square) == nil)
    }
}

struct LevelChangerPlaceTests {
    private func feature(_ id: String, type: String, level: Double, levels: JSONValue?, geometry: String = "Point") -> ProximiioFeature {
        var properties: [String: JSONValue] = ["type": .string(type), "level": .number(level)]
        if let levels { properties["levels"] = levels }
        return ProximiioFeature(
            id: id,
            geometry: .init(type: geometry, coordinates: .array([.number(54.399), .number(24.5397)])),
            properties: .object(properties)
        )
    }

    private func numbers(_ levels: [Double]) -> JSONValue {
        .array(levels.map { .number($0) })
    }

    /// GAD data 2026-10-15: lift 9f411e5a is a POI on level 0 with `levels` [1, 2, 3, 4]. The SDK
    /// router (6.0.0-beta.60) does not use it on level 0, so it is drawn on levels 1 to 4 only.
    @Test func aLevelChangerServesTheFloorsOfItsLevels() throws {
        let changers = LevelChangerPlace.all(in: [
            feature("lift", type: "elevator", level: 0, levels: numbers([1, 2, 3, 4])),
            feature("stairs", type: "staircase", level: 1, levels: nil),
            feature("cafe", type: "poi", level: 0, levels: numbers([1])),
            feature("outline", type: "elevator", level: 1, levels: nil, geometry: "MultiPolygon"),
        ])
        #expect(changers.map(\.id) == ["lift", "stairs"])
        let lift = try #require(changers.first)
        #expect(lift.coordinate == ProximiioCoordinate(latitude: 24.5397, longitude: 54.399))
        #expect([1, 2, 4].allSatisfy { lift.serves($0) })
        #expect(!lift.serves(0) && !lift.serves(5))
        #expect(changers[1].serves(1) && !changers[1].serves(2))
    }

    /// Same reading of `properties.levels` as the SDK's `LevelChangerExtractor.levels(from:)`.
    @Test func levelsAreNumbersOrNumericStrings() {
        let changers = LevelChangerPlace.all(in: [
            feature("strings", type: "elevator", level: 0, levels: .array([.string("1"), .string(" 2 "), .string("x"), .bool(true)])),
            feature("single", type: "staircase", level: 0, levels: .number(3)),
            feature("empty", type: "escalator", level: 2, levels: .array([])),
            feature("unreadable", type: "elevator", level: 1, levels: .array([.string("ground")])),
        ])
        #expect(changers.map(\.levels) == [[1, 2], [3], [2], [1]])
    }
}
