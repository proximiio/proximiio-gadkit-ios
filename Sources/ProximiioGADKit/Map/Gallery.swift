//
//  Gallery.swift
//  ProximiioGADKit
//
//  A gallery has a name, a level and an outline. Galleries come from the venue's polygon
//  features of type `gallery` (also `gallery-visited` and `gallery-destination`), named after the
//  gallery POI inside them, and from polygon geofences. Journey stops and the visitor's position
//  are placed in a gallery by a point-in-polygon test on the same level.
//
import Foundation
import Proximiio

extension ProximiioGeofence {
    /// `metadata.geofence_type` is `gallery` or `artwork`. Artworks hold their collection id in
    /// `remoteId`.
    var isGallery: Bool {
        metadata?["geofence_type"]?.stringValue == "gallery"
    }

    var isArtwork: Bool {
        metadata?["geofence_type"]?.stringValue == "artwork"
    }
}

public struct Gallery: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let level: Double
    /// Outline as (latitude, longitude) pairs.
    let ring: [ProximiioCoordinate]

    /// Polygon geofences with a name and a known floor. Geofence polygons are GeoJSON
    /// `[longitude, latitude]` pairs.
    static func all(geofences: [ProximiioGeofence], levels: [String: Double]) -> [Gallery] {
        geofences.compactMap { geofence in
            guard geofence.isGallery, let name = geofence.name, !name.isEmpty,
                  let polygon = geofence.polygon, polygon.count >= 3,
                  let floorID = geofence.floorId, let level = levels[floorID] else { return nil }
            let ring = polygon.compactMap { pair in
                pair.count >= 2 ? ProximiioCoordinate(latitude: pair[1], longitude: pair[0]) : nil
            }
            return ring.count >= 3 ? Gallery(id: geofence.id, name: name, level: level, ring: ring) : nil
        }
    }

    /// The gallery outlines among `features`, or the named polygon geofences when there are none.
    public static func load(from sdk: Proximiio, features: [ProximiioFeature], places: [VenuePlace]) async -> [Gallery] {
        let outlines = all(features: features, places: places)
        guard outlines.isEmpty else { return outlines }
        let levels = Dictionary(await sdk.floors().map { ($0.id, $0.level) }, uniquingKeysWith: { first, _ in first })
        return all(geofences: await sdk.geofences(), levels: levels)
    }

    /// Polygon features whose type starts with `gallery`. The name is the title of a place
    /// inside the outline whose title names a gallery; outlines without one are left out.
    static func all(features: [ProximiioFeature], places: [VenuePlace]) -> [Gallery] {
        let galleryPlaces = places.filter { $0.title.localizedCaseInsensitiveContains("gallery") }
        return features.compactMap { feature in
            guard (feature.propertyType ?? "").hasPrefix("gallery"),
                  let geometry = feature.geometry, let level = feature.level,
                  let ring = outerRing(type: geometry.type, coordinates: geometry.coordinates) else { return nil }
            let outline = Gallery(id: feature.id, name: "", level: level, ring: ring)
            guard let place = galleryPlaces.first(where: { outline.contains($0.coordinate, level: $0.level) }) else { return nil }
            return Gallery(id: feature.id, name: place.title, level: level, ring: ring)
        }
    }

    /// The outer ring of a GeoJSON Polygon, or of the first polygon of a MultiPolygon.
    static func outerRing(type: String, coordinates: JSONValue) -> [ProximiioCoordinate]? {
        let rings: JSONValue?
        switch type {
        case "Polygon": rings = coordinates.arrayValue?.first
        case "MultiPolygon": rings = coordinates.arrayValue?.first?.arrayValue?.first
        default: rings = nil
        }
        let ring = rings?.arrayValue?.compactMap { pair -> ProximiioCoordinate? in
            guard let pair = pair.arrayValue, pair.count >= 2,
                  let longitude = pair[0].doubleValue, let latitude = pair[1].doubleValue else { return nil }
            return ProximiioCoordinate(latitude: latitude, longitude: longitude)
        }
        guard let ring, ring.count >= 3 else { return nil }
        return ring
    }

    func contains(_ coordinate: ProximiioCoordinate, level: Double?) -> Bool {
        if let level, !VenueLevel.same(level, self.level) { return false }
        // Ray casting on the longitude axis.
        var inside = false
        var j = ring.count - 1
        for i in ring.indices {
            let a = ring[i], b = ring[j]
            if (a.latitude > coordinate.latitude) != (b.latitude > coordinate.latitude) {
                let x = (b.longitude - a.longitude) * (coordinate.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude
                if coordinate.longitude < x { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    static func containing(_ coordinate: ProximiioCoordinate, level: Double?, in galleries: [Gallery]) -> Gallery? {
        galleries.first { $0.contains(coordinate, level: level) }
    }

    /// Fill colours per level (page 3, section `Colors`, node 10930:60509).
    static func colors(forLevel level: Double) -> (destination: UInt32, visited: UInt32) {
        switch Int(level.rounded()) {
        case 0: (0x00FFB2, 0x80FFD9)
        case 1: (0x6FA6FF, 0xB7D3FF)
        case 2: (0xBB87F3, 0xDDC3F9)
        case 3: (0xFFE523, 0xFFF291)
        default: (0xFA8352, 0xFDC1A8)
        }
    }
}
