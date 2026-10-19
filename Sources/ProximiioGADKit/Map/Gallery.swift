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

/// A gallery that a personalised journey leads to before the artworks in it (PM, Monday "Navigation to
/// a gallery", 2026-10-15). Two records share the id that an artwork names in `metadata.gallery_id`:
/// the gallery geofence (`metadata.geofence_type` gallery) has it in `remote_id`, and so does the
/// gallery's POI. The geofence gives the outline; the POI gives the name and the end of the route.
struct GalleryDestination: Identifiable, Equatable, Sendable {
    /// `id` is the `gallery_id`, `name` the POI's title, such as "G303 Language", `level` the POI's,
    /// `ring` the geofence's outline.
    let gallery: Gallery
    /// The gallery's POI: where the route to the gallery ends.
    let entry: ProximiioCoordinate
    /// The id of the gallery's POI.
    let placeID: String

    var id: String { gallery.id }

    /// The text of the map marker: the first word of the name, such as "G303".
    var label: String {
        gallery.name.split(separator: " ").first.map(String.init) ?? gallery.name
    }
}

struct Gallery: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let level: Double
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

    /// Gallery names by the gallery's id: the title of the POI whose `remote_id` is the id that an
    /// artwork names in `metadata.gallery_id` (`VenuePlace.galleryID`), such as "G403 Weaving"
    /// (PM 2026-10-15). Artworks are left out: their `remote_id` is a collection id. Pure; covered
    /// by tests.
    static func names(places: [VenuePlace]) -> [String: String] {
        Dictionary(
            places.compactMap { place -> (String, String)? in
                let name = place.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !place.isArtwork, let id = place.remoteID, !id.isEmpty, !name.isEmpty else { return nil }
                return (id, name)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// The galleries a personalised journey leads to first, by `gallery_id` (`GalleryDestination`). A
    /// gallery without a polygon geofence or a POI is left out. Pure; covered by tests.
    static func destinations(geofences: [ProximiioGeofence], places: [VenuePlace]) -> [String: GalleryDestination] {
        let pois = Dictionary(
            places.compactMap { place -> (String, VenuePlace)? in
                guard !place.isArtwork, let id = place.remoteID, !id.isEmpty else { return nil }
                return (id, place)
            },
            uniquingKeysWith: { first, _ in first }
        )
        var destinations: [String: GalleryDestination] = [:]
        for geofence in geofences where geofence.isGallery {
            guard let id = geofence.remoteId, !id.isEmpty, destinations[id] == nil, let poi = pois[id],
                  let polygon = geofence.polygon else { continue }
            let ring = polygon.compactMap { pair in
                pair.count >= 2 ? ProximiioCoordinate(latitude: pair[1], longitude: pair[0]) : nil
            }
            guard ring.count >= 3 else { continue }
            destinations[id] = GalleryDestination(
                gallery: Gallery(id: id, name: poi.title, level: poi.level, ring: ring),
                entry: poi.coordinate,
                placeID: poi.id
            )
        }
        return destinations
    }

    /// The gallery outlines among `features`, or the named polygon geofences when there are none.
    static func load(from sdk: Proximiio, features: [ProximiioFeature], places: [VenuePlace]) async -> [Gallery] {
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

    /// Metres from `coordinate` to the outline, 0 inside it. Measured on a flat projection around
    /// `coordinate`, which is exact enough within a building.
    func distance(to coordinate: ProximiioCoordinate) -> Double {
        if contains(coordinate, level: nil) { return 0 }
        let metersPerLongitude = GeoMath.metersPerDegreeLongitude(atLatitude: coordinate.latitude)
        func meters(_ point: ProximiioCoordinate) -> (x: Double, y: Double) {
            ((point.longitude - coordinate.longitude) * metersPerLongitude,
             (point.latitude - coordinate.latitude) * GeoMath.metersPerDegreeLatitude)
        }
        var nearest = Double.infinity
        var j = ring.count - 1
        for i in ring.indices {
            let a = meters(ring[j]), b = meters(ring[i])
            let dx = b.x - a.x, dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            // The point of the edge nearest the origin, `coordinate`.
            let t = lengthSquared > 0 ? min(max(-(a.x * dx + a.y * dy) / lengthSquared, 0), 1) : 0
            nearest = min(nearest, hypot(a.x + t * dx, a.y + t * dy))
            j = i
        }
        return nearest
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
