//
//  ExploreCatalog.swift
//  ProximiioGADKit
//
//  The lists of the Explore Museum map (Figma "Explore Museum", node 12129:102006; PM screens
//  2026-10-23), each grouped by level:
//
//  - Spaces: the galleries. The gallery geofence (`geofence_type` gallery) gives the outline; the
//    POI with the same `remote_id` gives the name, the level, the category (its amenity, such as
//    "Thematic Gallery") and the description (`Gallery.destinations`).
//  - Highlights: the artworks that list the highlight amenity in `included_amenities`.
//  - Amenities: the POIs of an `AmenityKind` other than stairs and lifts.
//
//  The GAD organisation also holds the DCT office. Only the POIs with the `place_id` of the gallery
//  POIs are listed.
//
import Foundation
import Proximiio

/// A row of the Explore Museum lists and the place its card shows.
struct ExploreItem: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case space
        case highlight
        case amenity(AmenityKind)
    }

    /// The POI's id.
    let id: String
    let kind: Kind
    let title: String
    /// The lines under the title: a space's category and description; a highlight's artist and
    /// gallery.
    let lines: [String]
    let level: Double
    let coordinate: ProximiioCoordinate
    /// A space's outline.
    var gallery: Gallery?
    /// A space's category, the title of its POI's amenity.
    var category: String?

    /// The points the map frames for this item: the outline of a space, else the POI.
    var framedPoints: [ProximiioCoordinate] {
        if let ring = gallery?.ring, !ring.isEmpty { return ring }
        return [coordinate]
    }
    /// The SF Symbol of a space's category: a palette for a single-artist gallery, a grid for a
    /// thematic one, a star for Learning & Engagement, columns for any other space. Pure; covered by
    /// tests.
    static func symbol(for category: String?) -> String {
        let category = category?.lowercased() ?? ""
        if category.contains("single") { return "paintpalette.fill" }
        if category.contains("thematic") { return "square.grid.2x2.fill" }
        if category.contains("learning") { return "star.circle.fill" }
        return "building.columns.fill"
    }
}

/// The Explore Museum lists of the museum.
struct ExploreCatalog: Equatable, Sendable {
    var spaces: [ExploreItem] = []
    var highlights: [ExploreItem] = []
    var amenities: [ExploreItem] = []

    /// `categories` maps an amenity id to its title. Pure; covered by tests.
    init(places: [VenuePlace], destinations: [String: GalleryDestination], categories: [String: String]) {
        let byID = Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let museum = Self.museumPlaceID(destinations: destinations, places: byID)
        let inMuseum = { (place: VenuePlace) in museum == nil || place.placeID == museum }

        spaces = destinations.values.compactMap { destination in
            guard let poi = byID[destination.placeID], inMuseum(poi) else { return nil }
            let category = poi.amenityID.flatMap { categories[$0] }
            let line = [category, poi.details].compactMap { $0 }.joined(separator: ". ")
            return ExploreItem(
                id: poi.id, kind: .space, title: destination.gallery.name, lines: line.isEmpty ? [] : [line],
                level: poi.level, coordinate: destination.entry, gallery: destination.gallery, category: category
            )
        }
        .sorted(by: Self.order)

        let galleryNames = Dictionary(spaces.compactMap { item in item.gallery.map { ($0.id, item.title) } },
                                      uniquingKeysWith: { first, _ in first })
        highlights = places.filter { $0.isHighlight && inMuseum($0) }.map { place in
            ExploreItem(
                id: place.id, kind: .highlight, title: place.title,
                lines: [place.artist, place.galleryID.flatMap { galleryNames[$0] }].compactMap { $0 },
                level: place.level, coordinate: place.coordinate
            )
        }
        .sorted(by: Self.order)

        amenities = places.compactMap { place in
            guard !place.isArtwork, inMuseum(place),
                  let kind = AmenityKind.allCases.first(where: { $0.matches(place) }),
                  kind != .stairs, kind != .elevator else { return nil }
            return ExploreItem(id: place.id, kind: .amenity(kind), title: place.title, lines: [],
                               level: place.level, coordinate: place.coordinate)
        }
        .sorted(by: Self.order)
    }

    init() {}

    /// The levels with a space or an amenity, lowest first.
    var levels: [Double] {
        Array(Set((spaces + amenities + highlights).map { $0.level.rounded() })).sorted()
    }

    /// Every item of the catalogue, for a tap on the map.
    var all: [ExploreItem] { spaces + highlights + amenities }

    /// The space whose outline holds `coordinate` on `level`.
    func space(at coordinate: ProximiioCoordinate, level: Double) -> ExploreItem? {
        spaces.first { $0.gallery?.contains(coordinate, level: level) == true }
    }

    /// The items of one level.
    struct LevelGroup: Identifiable, Equatable {
        let level: Double
        let items: [ExploreItem]

        var id: Double { level }
    }

    /// `items` by level, lowest first. Pure; covered by tests.
    static func byLevel(_ items: [ExploreItem]) -> [LevelGroup] {
        Dictionary(grouping: items, by: { $0.level.rounded() })
            .sorted { $0.key < $1.key }
            .map { LevelGroup(level: $0.key, items: $0.value) }
    }

    /// The `place_id` most of the gallery POIs share: the museum.
    private static func museumPlaceID(destinations: [String: GalleryDestination], places: [String: VenuePlace]) -> String? {
        let counts = destinations.values.compactMap { places[$0.placeID]?.placeID }.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        return counts.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key
    }

    /// Level, then title.
    private static func order(_ a: ExploreItem, _ b: ExploreItem) -> Bool {
        if a.level != b.level { return a.level < b.level }
        return a.title.localizedStandardCompare(b.title) == .orderedAscending
    }
}
