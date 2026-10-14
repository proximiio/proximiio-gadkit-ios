//
//  GeofenceNotifierTests.swift
//  ProximiioGADKitTests
//
import Foundation
import Proximiio
import ProximiioMap
import Testing
@testable import ProximiioGADKit

struct GeofenceNotifierTests {
    private func geofence(_ id: String, name: String?, type: String) -> ProximiioGeofence {
        ProximiioGeofence(id: id, name: name, metadata: .object(["geofence_type": .string(type)]))
    }

    @Test func theTitleIsTheGeofenceName() throws {
        let request = try #require(GeofenceNotifier.request(for: .entered(geofence("g1", name: " Gallery 101 ", type: "gallery"))))
        #expect(request.content.title == "Gallery 101")
        #expect(request.identifier == "geofence-entered-g1")
        #expect(request.trigger == nil)
    }

    @Test func anExitPostsItsOwnNotification() throws {
        let request = try #require(GeofenceNotifier.request(for: .exited(geofence("g1", name: "Gallery 101", type: "gallery"), dwellTime: 30)))
        #expect(request.content.title == "Gallery 101")
        #expect(request.identifier == "geofence-exited-g1")
    }

    @Test func everyGeofenceTypePostsOne() {
        #expect(GeofenceNotifier.request(for: .entered(geofence("a1", name: "Artwork", type: "artwork"))) != nil)
        #expect(GeofenceNotifier.request(for: .entered(geofence("o1", name: "Shop", type: "other"))) != nil)
    }

    @Test func aGeofenceWithoutANamePostsNothing() {
        #expect(GeofenceNotifier.request(for: .entered(geofence("x", name: nil, type: "gallery"))) == nil)
        #expect(GeofenceNotifier.request(for: .exited(geofence("y", name: "  ", type: "gallery"), dwellTime: 0)) == nil)
    }
}

struct StopNearbyNotifierTests {
    private let stop = ProximiioCoordinate(latitude: 24.464, longitude: 54.329)

    /// `meters` north of `stop`. One degree of latitude is about 111 km.
    private func north(_ meters: Double) -> ProximiioCoordinate {
        ProximiioCoordinate(latitude: stop.latitude + meters / 111_000, longitude: stop.longitude)
    }

    @Test func nearbyIsLessThanFiveMetresOnTheSameLevel() {
        #expect(StopNearbyNotifier.isNearby(north(4), level: 1, stop: stop, stopLevel: 1))
        #expect(!StopNearbyNotifier.isNearby(north(6), level: 1, stop: stop, stopLevel: 1))
        #expect(!StopNearbyNotifier.isNearby(north(1), level: 2, stop: stop, stopLevel: 1))
    }

    @Test func anUnknownLevelMatchesAnyLevel() {
        #expect(StopNearbyNotifier.isNearby(north(1), level: nil, stop: stop, stopLevel: 1))
        #expect(StopNearbyNotifier.isNearby(north(1), level: 1, stop: stop, stopLevel: nil))
    }

    @Test func theRouteDistanceWinsOverTheStraightLine() {
        // A stop 2 m away behind a wall, 12 m to walk.
        #expect(!StopNearbyNotifier.isNearby(north(2), level: 1, stop: stop, stopLevel: 1, routeMeters: 12))
        // A stop 3 m away in a straight line, 4 m to walk.
        #expect(StopNearbyNotifier.isNearby(north(3), level: 1, stop: stop, stopLevel: 1, routeMeters: 4))
        #expect(!StopNearbyNotifier.isNearby(north(1), level: 2, stop: stop, stopLevel: 1, routeMeters: 1))
    }

    /// `VisitView` reports `VisitEvent.stopNearby` with the stop that `update` returns.
    @Test @MainActor func aStopIsReportedOncePerVisit() {
        var posted: [String] = []
        let notifier = StopNearbyNotifier { posted.append($0.identifier) }
        let artwork = JourneyStop(id: "a", title: "Artwork", coordinate: MapCoordinate(latitude: stop.latitude, longitude: stop.longitude))
        let here = north(1)
        let position = VenuePosition(latitude: here.latitude, longitude: here.longitude, horizontalAccuracy: 2, timestamp: .now)
        #expect(notifier.update(position: position, stop: artwork, guidance: nil) == artwork)
        #expect(notifier.update(position: position, stop: artwork, guidance: nil) == nil)
        #expect(posted == ["stop-nearby-a"])
    }
}
