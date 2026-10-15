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
    private func geofence(_ id: String, name: String?, remoteId: String?, type: String = "gallery") -> ProximiioGeofence {
        ProximiioGeofence(id: id, name: name, metadata: .object(["geofence_type": .string(type)]), remoteId: remoteId)
    }

    /// GAD data 2026-10-15: the artworks of "Gallery 403" (level 4) name it in `metadata.gallery_id`.
    @Test func galleryGeofencesNameGalleriesByTheirRemoteID() {
        let names = Gallery.names(geofences: [
            geofence("a", name: "Gallery 403", remoteId: "e07fe5d7"),
            geofence("b", name: "Gallery 102", remoteId: ""),
            geofence("c", name: nil, remoteId: "x"),
            geofence("d", name: "Untitled", remoteId: "GAD.2010.00033", type: "artwork"),
        ])
        #expect(names == ["e07fe5d7": "Gallery 403"])
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
