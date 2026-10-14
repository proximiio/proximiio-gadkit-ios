//
//  AmenityKind.swift
//  ProximiioGADKit
//
//  The amenity shortcuts and legend of the map (Figma "MAP Functionality Approach 02",
//  node 10889:116263): Women's restroom, Men's restroom, Café, Help Desk, Prayer Room,
//  Stairs, Elevator, Museum Shop.
//
//  A place matches a kind by its amenity id or its title. The venue data is still being
//  built, so both are checked.
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

    /// Lower-case fragments matched against the amenity id and the title.
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

    func matches(_ place: VenuePlace) -> Bool {
        let text = "\(place.amenityID ?? "") \(place.title)".lowercased()
        switch self {
        case .mensRestroom:
            // "women's restroom" contains "men's"; exclude it.
            return keywords.contains { text.contains($0) } && !AmenityKind.womensRestroom.matches(place)
        default:
            return keywords.contains { text.contains($0) }
        }
    }

    /// The nearest place of this kind. Places on the visitor's level come first; distance is
    /// straight-line. The route gives the walking distance.
    func nearest(in places: [VenuePlace], from coordinate: ProximiioCoordinate?, level: Double?) -> VenuePlace? {
        let matching = places.filter(matches)
        guard let coordinate else { return matching.first }
        let sameLevel = level.map { level in matching.filter { VenueLevel.same($0.level, level) } } ?? []
        return TrackingMonitor.nearest(to: coordinate, level: nil, in: sameLevel.isEmpty ? matching : sameLevel)
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
