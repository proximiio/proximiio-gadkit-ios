//
//  RouteToStopTests.swift
//  ProximiioGADKitTests
//
import Foundation
import Proximiio
import ProximiioMap
import Testing
@testable import ProximiioGADKit

struct RouteToStopTests {
    private static let start = ProximiioCoordinate(latitude: 24.5, longitude: 54.4)
    /// About 10.1 m east of `start`: where the stop projects onto the path.
    private static let end = ProximiioCoordinate(latitude: 24.5, longitude: 54.4001)
    /// About 2.2 m north of `end`.
    private static let artwork = ProximiioCoordinate(latitude: 24.50002, longitude: 54.4001)

    /// A one-segment route from `from` to `to`, as the SDK returns it.
    static func route(from: ProximiioCoordinate = start, to: ProximiioCoordinate = end, level: Double = 1) -> ComputedRoute {
        let meters = GeoMath.haversineDistance(from: from, to: to)
        return ComputedRoute(
            coordinates: [from, to],
            distanceMeters: meters,
            segments: [RouteSegment(start: from, end: to, distanceMeters: meters)],
            level: level,
            levelChanges: [],
            instructions: [
                RouteInstruction(kind: .start, coordinate: from, distanceMeters: 0, level: level),
                RouteInstruction(kind: .arrive, coordinate: to, distanceMeters: meters, level: level),
            ]
        )
    }

    /// User, 2026-11-09: the route went only as far as the path, short of the artwork.
    @Test func theRouteGoesOnFromThePathToTheStop() throws {
        let route = Self.route()
        let extended = route.extended(to: Self.artwork, maximumMeters: 15)
        let added = GeoMath.haversineDistance(from: Self.end, to: Self.artwork)
        #expect(abs(added - 2.2) < 0.1)
        #expect(extended.coordinates == [Self.start, Self.end, Self.artwork])
        #expect(extended.segments.last == RouteSegment(start: Self.end, end: Self.artwork, distanceMeters: added))
        #expect(abs(extended.distanceMeters - (route.distanceMeters + added)) < 1e-9)
        #expect(extended.durationSeconds > route.durationSeconds)
        #expect(extended.level == 1)
        let arrive = try #require(extended.instructions.last)
        #expect(arrive.kind == .arrive)
        #expect(arrive.coordinate == Self.artwork)
        #expect(abs(arrive.distanceMeters - extended.distanceMeters) < 1e-9)
        // The instructions add up to the route, so the map's remaining time stays exact.
        #expect(abs(extended.instructions.reduce(0) { $0 + $1.durationSeconds } - extended.durationSeconds) < 1e-9)
    }

    @Test func aStopOnThePathOrTooFarFromItLeavesTheRoute() {
        let route = Self.route()
        #expect(route.extended(to: Self.end, maximumMeters: 15) == route)
        #expect(route.extended(to: Self.artwork, maximumMeters: 2) == route)
        #expect(route.extended(to: Self.artwork, maximumMeters: 0) == route)
    }

    @Test func standardSettingExtendsEveryRoute() {
        // The SDK routes to a stop at most 15 m from a path.
        #expect(GADSettings.standard.routeToStopMaximumMeters == 15)
    }
}

struct GalleryFirstRouteToStopTests {
    /// A gallery of about 22 × 22 m north of the path at latitude 24.5.
    private let destination = GalleryDestination(
        gallery: Gallery(id: "e1d2cd21", name: "G303 Language", level: 3, ring: [
            ProximiioCoordinate(latitude: 24.5001, longitude: 54.4), ProximiioCoordinate(latitude: 24.5001, longitude: 54.4002),
            ProximiioCoordinate(latitude: 24.5003, longitude: 54.4002), ProximiioCoordinate(latitude: 24.5003, longitude: 54.4),
        ]),
        entry: ProximiioCoordinate(latitude: 24.5002, longitude: 54.4001),
        placeID: "poi-g303"
    )
    private let artwork = MapCoordinate(latitude: 24.50025, longitude: 54.40015)
    private let origin = MapCoordinate(latitude: 24.5, longitude: 54.4)

    private func leg(galleryFirst: Bool) async throws -> ComputedRoute {
        let routing = GalleryFirstRouting(inner: PathRouting(), routeToStopMaximumMeters: 15)
        routing.update(isEnabled: galleryFirst, galleries: [GalleryFirstRouting.Key(artwork): destination])
        let result = await routing.route(origin: origin, originFloor: FloorKey(level: 3), destination: artwork,
                                         destinationFloor: FloorKey(level: 3), options: RouteOptions())
        guard case .route(let route) = result else { throw Unrouted() }
        return route
    }

    @Test func aLegToAnArtworkEndsAtTheArtwork() async throws {
        let route = try await leg(galleryFirst: false)
        #expect(route.coordinates.last == ProximiioCoordinate(latitude: artwork.latitude, longitude: artwork.longitude))
        #expect(route.coordinates.count == 3)
    }

    @Test func aLegToAGalleryEndsOnThePath() async throws {
        let route = try await leg(galleryFirst: true)
        #expect(route.coordinates.last == PathRouting.onPath(MapCoordinate(latitude: destination.entry.latitude,
                                                                          longitude: destination.entry.longitude)))
        #expect(route.coordinates.count == 2)
    }

    @Test func theLegWithoutOptionsEndsAtTheArtworkToo() async {
        let routing = GalleryFirstRouting(inner: PathRouting(), routeToStopMaximumMeters: 15)
        let route = await routing.route(origin: origin, originFloor: FloorKey(level: 3), destination: artwork, destinationFloor: FloorKey(level: 3))
        #expect(route?.coordinates.last == ProximiioCoordinate(latitude: artwork.latitude, longitude: artwork.longitude))
    }

    private struct Unrouted: Error {}
}

/// Routes every leg to a point on a path 2.2 m south of its destination.
private final class PathRouting: JourneyRouting {
    static func onPath(_ destination: MapCoordinate) -> ProximiioCoordinate {
        ProximiioCoordinate(latitude: destination.latitude - 0.00002, longitude: destination.longitude)
    }

    private func route(_ origin: MapCoordinate, _ destination: MapCoordinate) -> ComputedRoute {
        RouteToStopTests.route(from: ProximiioCoordinate(latitude: origin.latitude, longitude: origin.longitude),
                               to: Self.onPath(destination), level: 3)
    }

    func route(origin: MapCoordinate, originFloor: FloorKey, destination: MapCoordinate, destinationFloor: FloorKey) async -> ComputedRoute? {
        route(origin, destination)
    }

    func route(origin: MapCoordinate, originFloor: FloorKey, destination: MapCoordinate, destinationFloor: FloorKey, options: RouteOptions) async -> RouteResult {
        .route(route(origin, destination))
    }

    func durations(from origins: [JourneyRoutePoint], to destinations: [JourneyRoutePoint]) async -> [[TimeInterval?]] { [] }

    func durations(from origins: [JourneyRoutePoint], to destinations: [JourneyRoutePoint], options: RouteOptions) async -> [[TimeInterval?]] { [] }
}
