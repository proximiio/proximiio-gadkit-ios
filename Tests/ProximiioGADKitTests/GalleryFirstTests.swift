//
//  GalleryFirstTests.swift
//  ProximiioGADKitTests
//
import Foundation
import os
import Proximiio
import ProximiioMap
import Testing
import UIKit
@testable import ProximiioGADKit

struct GalleryFirstTests {
    private static let square = [
        ProximiioCoordinate(latitude: 0, longitude: 0), ProximiioCoordinate(latitude: 0, longitude: 1),
        ProximiioCoordinate(latitude: 1, longitude: 1), ProximiioCoordinate(latitude: 1, longitude: 0),
    ]
    private let g106 = Gallery(id: "106", name: "Gallery 106", level: 1, ring: Self.square)

    @Test func stopNumber() {
        #expect(!GalleryFirst.showsStopNumber(state: .walking(stop: "Tongari-kun"), galleryAhead: g106))
        #expect(!GalleryFirst.showsStopNumber(state: .nextStopOnOtherLevel(stop: "Tongari-kun", level: 3), galleryAhead: g106))
        #expect(GalleryFirst.showsStopNumber(state: .walking(stop: "Tongari-kun"), galleryAhead: nil))
        #expect(GalleryFirst.showsStopNumber(state: .atStop(stop: "Tongari-kun"), galleryAhead: g106))
    }
}

struct GalleryFirstRoutingTests {
    private let artwork = MapCoordinate(latitude: 0.5, longitude: 0.5)
    private let outside = ProximiioCoordinate(latitude: 3, longitude: 3)
    private let inside = ProximiioCoordinate(latitude: 0.2, longitude: 0.2)
    private let destination = GalleryDestination(
        gallery: Gallery(id: "e1d2cd21", name: "G303 Language", level: 3, ring: [
            ProximiioCoordinate(latitude: 0, longitude: 0), ProximiioCoordinate(latitude: 0, longitude: 1),
            ProximiioCoordinate(latitude: 1, longitude: 1), ProximiioCoordinate(latitude: 1, longitude: 0),
        ]),
        entry: ProximiioCoordinate(latitude: 0.9, longitude: 0.9),
        placeID: "poi-g303"
    )

    private func state(isEnabled: Bool = true, reached: Bool = false) -> GalleryFirstRouting.State {
        let key = GalleryFirstRouting.Key(artwork)
        return GalleryFirstRouting.State(isEnabled: isEnabled, galleries: [key: destination], reached: reached ? [key] : [])
    }

    @Test func aLegFromOutsideTheGalleryEndsAtTheGallery() {
        #expect(GalleryFirstRouting.gallery(origin: outside, originLevel: 3, destination: artwork, state: state()) == destination)
        // Another floor is outside the gallery too.
        #expect(GalleryFirstRouting.gallery(origin: inside, originLevel: 1, destination: artwork, state: state()) == destination)
    }

    @Test func aLegFromInsideTheGalleryEndsAtTheArtwork() {
        #expect(GalleryFirstRouting.gallery(origin: inside, originLevel: 3, destination: artwork, state: state()) == nil)
    }

    @Test func aReachedOrUnknownArtworkOrADisabledRouterEndsAtTheArtwork() {
        #expect(GalleryFirstRouting.gallery(origin: outside, originLevel: 3, destination: artwork, state: state(reached: true)) == nil)
        #expect(GalleryFirstRouting.gallery(origin: outside, originLevel: 3, destination: artwork, state: state(isEnabled: false)) == nil)
        let other = MapCoordinate(latitude: 0.6, longitude: 0.6)
        #expect(GalleryFirstRouting.gallery(origin: outside, originLevel: 3, destination: other, state: state()) == nil)
    }

    /// A gallery is visited when its artworks of the journey are all visited or skipped, at least one
    /// visited (the customer, Monday "Visited gallery visualization", 2026-10-28).
    @MainActor @Test func aGalleryIsVisitedWhenAllItsArtworksAreDoneOrSkipped() {
        let visited = VisitView.visitedGalleries([
            ("g101", .done), ("g101", .skipped),
            ("g104", .done), ("g104", .pending),
            ("g106", .skipped),
            ("g303", .done),
        ])
        #expect(visited == ["g101", "g303"])
    }

    /// The marker is the gallery's icon in a 30 pt circle with its full name under it, the circle in
    /// the middle of the image (PM, Monday "Gallery numbers in gallery navigation", 2026-10-28).
    @MainActor @Test func theMarkerIsTheIconWithTheNameUnderIt() {
        let named = JourneyMapLayers.galleryMarkerImage(name: "G303 Language", icon: nil, isDestination: true)
        #expect(named.size.width > 60)
        #expect(named.size.height > 50)
        let visited = JourneyMapLayers.galleryMarkerImage(name: "G1", icon: UIImage(systemName: "square"), isDestination: false)
        #expect(visited.size.width == 30)
        let marker = JourneyMapLayers.GalleryMarker(coordinate: .init(latitude: 0, longitude: 0), level: 3, name: "G303 Language",
                                                    amenityID: "a", isDestination: true)
        #expect(marker.imageName(iconGeneration: 1) != marker.imageName(iconGeneration: 2))
    }

    /// Field test 2026-10-19: test copies of artworks named galleries in another building.
    @Test func aGalleryWithoutARouteIsLeftForTheArtwork() async {
        let inner = RecordingRouting()
        let routing = GalleryFirstRouting(inner: inner)
        routing.update(isEnabled: true, galleries: [GalleryFirstRouting.Key(artwork): destination])
        let origin = MapCoordinate(latitude: outside.latitude, longitude: outside.longitude)
        _ = await routing.route(origin: origin, originFloor: FloorKey(level: 3), destination: artwork,
                                destinationFloor: FloorKey(level: 3), options: RouteOptions())
        #expect(inner.destinations == [MapCoordinate(latitude: 0.9, longitude: 0.9), artwork])
        #expect(routing.gallery(of: artwork) == nil)
        // Later legs go to the artwork at once.
        _ = await routing.route(origin: origin, originFloor: FloorKey(level: 3), destination: artwork,
                                destinationFloor: FloorKey(level: 3), options: RouteOptions())
        #expect(inner.destinations.count == 3)
    }

    @Test func anArtworkLeadsToItsGalleryOnlyWhenItIsInIt() {
        func artwork(latitude: Double, level: Double = 3) -> VenuePlace {
            VenuePlace(id: "a", title: "Tongari-kun", coordinate: ProximiioCoordinate(latitude: latitude, longitude: 0.5), level: level)
        }
        #expect(GalleryFirstRouting.isInGallery(artwork(latitude: 0.5), destination, marginMeters: 5))
        // 0.00002° of latitude is about 2.2 m north of the outline.
        #expect(GalleryFirstRouting.isInGallery(artwork(latitude: 1.00002), destination, marginMeters: 5))
        #expect(!GalleryFirstRouting.isInGallery(artwork(latitude: 1.0001), destination, marginMeters: 5))
        #expect(!GalleryFirstRouting.isInGallery(artwork(latitude: 0.5, level: 1), destination, marginMeters: 5))
    }
}

/// Answers every leg with no route and records where each leg ends.
private final class RecordingRouting: JourneyRouting {
    private let recorded = OSAllocatedUnfairLock(initialState: [MapCoordinate]())
    var destinations: [MapCoordinate] { recorded.withLock { $0 } }

    func route(origin: MapCoordinate, originFloor: FloorKey, destination: MapCoordinate, destinationFloor: FloorKey) async -> ComputedRoute? {
        nil
    }

    func route(origin: MapCoordinate, originFloor: FloorKey, destination: MapCoordinate, destinationFloor: FloorKey, options: RouteOptions) async -> RouteResult {
        recorded.withLock { $0.append(destination) }
        return .noRoute(.disconnected)
    }

    func durations(from origins: [JourneyRoutePoint], to destinations: [JourneyRoutePoint]) async -> [[TimeInterval?]] { [] }

    func durations(from origins: [JourneyRoutePoint], to destinations: [JourneyRoutePoint], options: RouteOptions) async -> [[TimeInterval?]] { [] }
}

struct GalleryDistanceTests {
    private let square = Gallery(id: "g", name: "G", level: 1, ring: [
        ProximiioCoordinate(latitude: 0, longitude: 0), ProximiioCoordinate(latitude: 0, longitude: 0.001),
        ProximiioCoordinate(latitude: 0.001, longitude: 0.001), ProximiioCoordinate(latitude: 0.001, longitude: 0),
    ])

    @Test func insideIsZeroAndOutsideIsTheDistanceToTheNearestEdge() {
        #expect(square.distance(to: ProximiioCoordinate(latitude: 0.0005, longitude: 0.0005)) == 0)
        // 0.0001° of latitude is about 11.06 m.
        let north = square.distance(to: ProximiioCoordinate(latitude: 0.0011, longitude: 0.0005))
        #expect(abs(north - 11.06) < 0.1)
        // Beyond a corner: the distance to the corner.
        let corner = square.distance(to: ProximiioCoordinate(latitude: 0.0011, longitude: 0.0011))
        #expect(abs(corner - 11.06 * 2.0.squareRoot()) < 0.2)
    }
}

struct ArtworkAreaTests {
    @Test func keepsTheGeofenceID() {
        let geofence = ProximiioGeofence(id: "50c36aad", name: "DCT the broken 5", polygon: [[54, 24], [54.1, 24], [54.1, 24.1]],
                                         metadata: .object(["geofence_type": .string("artwork")]), remoteId: "GAD.2020.00112")
        #expect(ArtworkArea(geofence).id == "50c36aad")
    }
}

struct GalleryDestinationTests {
    private func geofence(remoteID: String?, polygon: [[Double]]? = [[54, 24], [54.1, 24], [54.1, 24.1]]) -> ProximiioGeofence {
        ProximiioGeofence(id: "geofence-\(remoteID ?? "-")", name: "Gallery 303", polygon: polygon,
                          metadata: .object(["geofence_type": .string("gallery")]), remoteId: remoteID)
    }

    @Test func joinsTheGeofenceAndThePOIByTheGalleryID() throws {
        let poi = VenuePlace(id: "poi-g303", title: "G303 Language", coordinate: ProximiioCoordinate(latitude: 24.05, longitude: 54.05),
                             level: 3, remoteID: "e1d2cd21")
        let destinations = Gallery.destinations(geofences: [geofence(remoteID: "e1d2cd21"), geofence(remoteID: "no-poi"), geofence(remoteID: nil)],
                                                places: [poi])
        #expect(destinations.keys.sorted() == ["e1d2cd21"])
        let g303 = try #require(destinations["e1d2cd21"])
        #expect(g303.gallery.name == "G303 Language")
        #expect(g303.gallery.level == 3)
        #expect(g303.entry == poi.coordinate)
        #expect(g303.placeID == "poi-g303")
        // GeoJSON pairs are longitude, latitude.
        #expect(g303.gallery.ring.first == ProximiioCoordinate(latitude: 24, longitude: 54))
    }

    private func polygon(_ id: String, level: Double, galleryID: String? = nil) -> ProximiioFeature {
        let ring: JSONValue = .array([[54.02, 24.02], [54.08, 24.02], [54.08, 24.08], [54.02, 24.08]].map { .array($0.map { .number($0) }) })
        var properties: [String: JSONValue] = ["type": .string("gallery"), "level": .number(level)]
        properties["metadata"] = .object(galleryID.map { ["gallery_id": .string($0)] } ?? [:])
        return ProximiioFeature(id: id, geometry: .init(type: "Polygon", coordinates: .array([ring])), properties: .object(properties))
    }

    /// PM, Monday "Explore Museum view: gallery highlighting", 2026-10-26: the map fills the gallery's
    /// polygon, not its geofence.
    @Test func theGalleryPolygonIsTheOneWithTheGalleryIDElseTheOneAroundThePOI() throws {
        let poi = VenuePlace(id: "poi-g303", title: "G303 Language", coordinate: ProximiioCoordinate(latitude: 24.05, longitude: 54.05),
                             level: 3, remoteID: "e1d2cd21")
        let around = try #require(Gallery.destinations(geofences: [geofence(remoteID: "e1d2cd21")], places: [poi],
                                                       features: [polygon("other-floor", level: 2), polygon("room", level: 3)])["e1d2cd21"])
        #expect(around.polygon?.id == "room")
        #expect(around.shown.id == "room")
        #expect(around.gallery.id == "e1d2cd21")
        let byID = try #require(Gallery.destinations(geofences: [geofence(remoteID: "e1d2cd21")], places: [poi],
                                                     features: [polygon("room", level: 3), polygon("tagged", level: 2, galleryID: "e1d2cd21")])["e1d2cd21"])
        #expect(byID.polygon?.id == "tagged")
        let none = try #require(Gallery.destinations(geofences: [geofence(remoteID: "e1d2cd21")], places: [poi])["e1d2cd21"])
        #expect(none.polygon == nil)
        #expect(none.shown == none.gallery)
    }

    @Test func aGeofenceWithoutAnOutlineIsLeftOut() {
        let poi = VenuePlace(id: "poi", title: "G303 Language", coordinate: ProximiioCoordinate(latitude: 24, longitude: 54), level: 3, remoteID: "e1d2cd21")
        #expect(Gallery.destinations(geofences: [geofence(remoteID: "e1d2cd21", polygon: nil)], places: [poi]).isEmpty)
    }
}
