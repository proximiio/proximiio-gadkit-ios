//
//  PlaceFraming.swift
//  ProximiioGADKit
//
//  The map after an amenity is picked in the menu (PM, Monday "When selecting an amenity from the
//  menu, zoom to location", 2026-10-15). On the visitor's floor the map shows the visitor and the
//  amenity. On another floor, or without a position, it shows the amenity's floor around the
//  amenity. The camera eases to the new area; it does not fly. The amenity's marker is
//  `JourneyMapLayers.Highlight`.
//
import Proximiio
import ProximiioMap
import UIKit

enum PlaceFraming {
    /// The area that holds `points`, grown about its centre to at least `minimumMeters` wide and
    /// high. Pure; covered by tests.
    static func bounds(of points: [ProximiioCoordinate], minimumMeters: Double) -> MapBoundingBox? {
        guard let south = points.map(\.latitude).min(), let north = points.map(\.latitude).max(),
              let west = points.map(\.longitude).min(), let east = points.map(\.longitude).max()
        else { return nil }
        let latitude = (south + north) / 2
        let longitude = (west + east) / 2
        let metresPerDegree = 111_320.0
        let halfHeight = max((north - south) / 2, minimumMeters / 2 / metresPerDegree)
        let halfWidth = max((east - west) / 2, minimumMeters / 2 / (metresPerDegree * cos(latitude * .pi / 180)))
        return MapBoundingBox(
            southWest: MapCoordinate(latitude: latitude - halfHeight, longitude: longitude - halfWidth),
            northEast: MapCoordinate(latitude: latitude + halfHeight, longitude: longitude + halfWidth)
        )
    }

    /// Shows `place` on `session` inside `padding`, the map area under the screen's controls and
    /// card.
    @MainActor static func show(_ place: VenuePlace, on session: ProximiioMapSession, padding: UIEdgeInsets, minimumMeters: Double) {
        var points = [place.coordinate]
        if let here = session.position, let level = here.floor?.level, VenueLevel.same(level, place.level) {
            session.followMyFloor()
            points.append(here.coordinate.proximiio)
        } else {
            session.select(floor: FloorKey(level: place.level))
        }
        guard let bounds = bounds(of: points, minimumMeters: minimumMeters) else { return }
        session.camera.fit(bounds: bounds, padding: padding, animated: true)
    }
}
