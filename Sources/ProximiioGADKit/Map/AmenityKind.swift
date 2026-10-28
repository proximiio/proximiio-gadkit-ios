//
//  AmenityKind.swift
//  ProximiioGADKit
//
//  The amenity shortcuts and legend of the map (Figma "MAP Functionality Approach 02",
//  node 10889:116263): Women's restroom, Men's restroom, Café, Help Desk, Prayer Room,
//  Stairs, Elevator, Museum Shop.
//
//  An amenity has a kind when its title names it ("Prayer Room", "Women's Restroom"). A place
//  matches a kind by its amenity (`VenuePlace.amenityKind`), not by its own title: the prayer room
//  shortcut led to the artwork "Endless Prayers XIII" (PM, Monday "Amenity search & Map legend
//  views", 2026-10-28).
//
import Foundation
import Proximiio

enum AmenityKind: String, CaseIterable, Identifiable, Sendable {
    case womensRestroom, mensRestroom, cafe, helpDesk, prayerRoom, stairs, elevator, museumShop

    var id: String { rawValue }

    /// Shortcuts shown as chips on the map. Stairs and Elevator are legend entries only.
    static let shortcuts: [AmenityKind] = [.womensRestroom, .mensRestroom, .cafe, .helpDesk, .prayerRoom, .museumShop]

    var title: String {
        switch self {
        case .womensRestroom: String(localized: "Women’s restroom", bundle: .module)
        case .mensRestroom: String(localized: "Men’s restroom", bundle: .module)
        case .cafe: String(localized: "Café", bundle: .module)
        case .helpDesk: String(localized: "Help Desk", bundle: .module)
        case .prayerRoom: String(localized: "Prayer Room", bundle: .module)
        case .stairs: String(localized: "Stairs", bundle: .module)
        case .elevator: String(localized: "Elevator", bundle: .module)
        case .museumShop: String(localized: "Museum Shop", bundle: .module)
        }
    }

    /// The design's icon (`icons-svg`).
    var icon: GADIcon {
        switch self {
        case .womensRestroom: .femaleToilet
        case .mensRestroom: .maleToilet
        case .cafe: .cafe
        case .helpDesk: .info
        case .prayerRoom: .prayerRoom
        case .stairs: .stairs
        case .elevator: .elevator
        case .museumShop: .shop
        }
    }

    var symbol: String {
        switch self {
        case .womensRestroom: "figure.stand.dress"
        case .mensRestroom: "figure.stand"
        case .cafe: "cup.and.saucer"
        case .helpDesk: "info.circle"
        case .prayerRoom: "moon.stars"
        case .stairs: "figure.stairs"
        case .elevator: "arrow.up.arrow.down.square"
        case .museumShop: "bag"
        }
    }

    /// Lower-case fragments matched against an amenity's id and title.
    private var keywords: [String] {
        switch self {
        case .womensRestroom: ["women", "female", "ladies"]
        case .mensRestroom: ["men's", "mens", "male", "gents"]
        case .cafe: ["cafe", "café", "coffee"]
        case .helpDesk: ["help", "welcome desk", "information", "info"]
        case .prayerRoom: ["prayer"]
        case .stairs: ["stair"]
        case .elevator: ["elevator", "lift"]
        case .museumShop: ["shop", "store"]
        }
    }

    /// Whether the place's amenity is of this kind.
    func matches(_ place: VenuePlace) -> Bool {
        place.amenityKind == self
    }

    /// The kind of each amenity that has one, by amenity id. Pure; covered by tests.
    static func kinds(of amenities: [ProximiioAmenity]) -> [String: AmenityKind] {
        Dictionary(amenities.compactMap { amenity in kind(forAmenityID: amenity.id, title: amenity.title).map { (amenity.id, $0) } },
                   uniquingKeysWith: { first, _ in first })
    }

    /// `text` is lower case: an amenity id and a title.
    private func matches(text: String) -> Bool {
        switch self {
        case .mensRestroom:
            // "women's restroom" contains "men's"; exclude it.
            return keywords.contains { text.contains($0) } && !AmenityKind.womensRestroom.matches(text: text)
        default:
            return keywords.contains { text.contains($0) }
        }
    }

    /// The kind an amenity's id and title name, or `nil`. The data's variants for a visited stop
    /// or a destination ("Womens restroom visited") are left out. Pure; covered by tests.
    static func kind(forAmenityID id: String, title: String?) -> AmenityKind? {
        let text = "\(id) \(title ?? "")".lowercased()
        guard !["visited", "destination", "distination"].contains(where: text.contains) else { return nil }
        return allCases.first { $0.matches(text: text) }
    }

    /// The nearest place of this kind in the venue of the nearest one (`place_id`). In that venue,
    /// places on the visitor's level come first; distance is straight-line. The route gives the
    /// walking distance. The venue comes first because the GAD data has a café on level 1 of the
    /// DCT office, 11 km away, and the Guggenheim café on level 0 (2026-10-15).
    func nearest(in places: [VenuePlace], from coordinate: ProximiioCoordinate?, level: Double?) -> VenuePlace? {
        let matching = places.filter(matches)
        guard let coordinate else { return matching.first }
        guard let closest = TrackingMonitor.nearest(to: coordinate, level: nil, in: matching) else { return nil }
        let venue = matching.filter { $0.placeID == closest.placeID }
        let sameLevel = level.map { level in venue.filter { VenueLevel.same($0.level, level) } } ?? []
        return TrackingMonitor.nearest(to: coordinate, level: nil, in: sameLevel.isEmpty ? venue : sameLevel)
    }
}

extension VenuePlace {
    /// "Amenity · Level 1" for an amenity, "Level 1" for other places.
    var cardSubtitle: String {
        let level = String(localized: "Level \(Int(level.rounded()))", bundle: .module)
        return AmenityKind.allCases.contains(where: { $0.matches(self) })
            ? String(localized: "Amenity", bundle: .module) + " · " + level
            : level
    }
}
