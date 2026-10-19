//
//  GalleryFirstRouting.swift
//  ProximiioGADKit
//
//  Gallery first (PM, Monday "Navigation to a gallery", 2026-10-15; personalised journeys only): a
//  leg to an artwork in a gallery that the visitor is not in ends at the gallery's POI
//  (`GalleryDestination`). When the visitor enters that gallery, `VisitController` marks the artwork
//  reached and routes the leg again, to the artwork. A leg that starts in the artwork's gallery ends
//  at the artwork.
//
//  The navigator's legs come from this router (`JourneyRouting`). The walking times that order the
//  journey come from the SDK's router unchanged.
//
import Foundation
import os
import Proximiio
import ProximiioMap

final class GalleryFirstRouting: JourneyRouting {
    struct State: Sendable {
        var isEnabled = false
        /// The gallery of each artwork, by the artwork's coordinate.
        var galleries: [Key: GalleryDestination] = [:]
        /// Artworks whose gallery the visitor entered on the way to them.
        var reached: Set<Key> = []
    }

    /// An artwork's coordinate to about 1 cm. A journey stop has its POI's coordinate.
    struct Key: Hashable, Sendable {
        let latitude: Int64
        let longitude: Int64

        init(_ coordinate: MapCoordinate) {
            latitude = Int64((coordinate.latitude * 10_000_000).rounded())
            longitude = Int64((coordinate.longitude * 10_000_000).rounded())
        }
    }

    private let inner: any JourneyRouting
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(inner: any JourneyRouting) {
        self.inner = inner
    }

    /// Turns gallery first on or off and sets the gallery of each artwork. Keeps the reached artworks.
    func update(isEnabled: Bool, galleries: [Key: GalleryDestination]) {
        state.withLock {
            $0.isEnabled = isEnabled
            $0.galleries = galleries
        }
    }

    /// The gallery that a leg to `artwork` leads to first while the visitor is outside it, or `nil`.
    func gallery(of artwork: MapCoordinate) -> GalleryDestination? {
        state.withLock { state in
            let key = Key(artwork)
            return state.isEnabled && !state.reached.contains(key) ? state.galleries[key] : nil
        }
    }

    /// The visitor entered the gallery of `artwork`: legs to it end at the artwork from now on.
    func markReached(_ artwork: MapCoordinate) {
        _ = state.withLock { $0.reached.insert(Key(artwork)) }
    }

    /// The gallery where a leg from `origin` to `destination` ends instead of the artwork, or `nil`.
    /// Pure; covered by tests.
    static func gallery(origin: ProximiioCoordinate, originLevel: Double, destination: MapCoordinate, state: State) -> GalleryDestination? {
        let key = Key(destination)
        guard state.isEnabled, !state.reached.contains(key), let gallery = state.galleries[key],
              !gallery.gallery.contains(origin, level: originLevel) else { return nil }
        return gallery
    }

    // MARK: JourneyRouting

    func route(origin: MapCoordinate, originFloor: FloorKey, destination: MapCoordinate, destinationFloor: FloorKey) async -> ComputedRoute? {
        await inner.route(origin: origin, originFloor: originFloor, destination: destination, destinationFloor: destinationFloor)
    }

    func route(
        origin: MapCoordinate,
        originFloor: FloorKey,
        destination: MapCoordinate,
        destinationFloor: FloorKey,
        options: RouteOptions
    ) async -> RouteResult {
        let start = ProximiioCoordinate(latitude: origin.latitude, longitude: origin.longitude)
        if let gallery = state.withLock({ Self.gallery(origin: start, originLevel: originFloor.level, destination: destination, state: $0) }) {
            return await inner.route(
                origin: origin,
                originFloor: originFloor,
                destination: MapCoordinate(latitude: gallery.entry.latitude, longitude: gallery.entry.longitude),
                destinationFloor: FloorKey(level: gallery.gallery.level),
                options: options
            )
        }
        return await inner.route(origin: origin, originFloor: originFloor, destination: destination, destinationFloor: destinationFloor, options: options)
    }

    func durations(from origins: [JourneyRoutePoint], to destinations: [JourneyRoutePoint]) async -> [[TimeInterval?]] {
        await inner.durations(from: origins, to: destinations)
    }

    func durations(from origins: [JourneyRoutePoint], to destinations: [JourneyRoutePoint], options: RouteOptions) async -> [[TimeInterval?]] {
        await inner.durations(from: origins, to: destinations, options: options)
    }
}
