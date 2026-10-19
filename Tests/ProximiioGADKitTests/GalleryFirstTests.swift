//
//  GalleryFirstTests.swift
//  ProximiioGADKitTests
//
import Foundation
import Proximiio
import ProximiioMap
import Testing
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

    @Test func theLabelIsTheFirstWordOfTheName() {
        #expect(destination.label == "G303")
    }

    @MainActor @Test func theMarkerIsALabel28PointsHigh() throws {
        let image = try #require(JourneyMapLayers.galleryLabel("G303"))
        #expect(image.size.height == 28)
        #expect(image.size.width > 40)
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

    @Test func aGeofenceWithoutAnOutlineIsLeftOut() {
        let poi = VenuePlace(id: "poi", title: "G303 Language", coordinate: ProximiioCoordinate(latitude: 24, longitude: 54), level: 3, remoteID: "e1d2cd21")
        #expect(Gallery.destinations(geofences: [geofence(remoteID: "e1d2cd21", polygon: nil)], places: [poi]).isEmpty)
    }
}
