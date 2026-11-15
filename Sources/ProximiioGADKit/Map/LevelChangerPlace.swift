//
//  LevelChangerPlace.swift
//  ProximiioGADKit
//
//  A staircase, lift, escalator, ramp or hill POI: a point feature of type `staircase`, `elevator`,
//  `escalator`, `ramp` or `hill`, the types the SDK router rides (`LevelChangerExtractor`). The map library draws a POI on its own floor only; GADKit hides these POIs and
//  draws them on every floor they serve (`JourneyMapLayers`), as the web map does (Monday "All
//  level changers visible", 2026-10-15).
//
//  The floors served follow the SDK router (`LevelChangerExtractor.levelChangers(from:)`,
//  6.0.0-beta.60): exactly the floors in `properties.levels`, without the POI's own floor. In the
//  GAD data lift 9f411e5a is a POI on level 0 with `levels` [1, 2, 3, 4]; the router does not use
//  it on level 0, so GADKit does not draw it there. Without usable `levels` the POI serves its own
//  floor.
//
//  The marker of a level changer that is not on the route is the design's lift or stairs icon when
//  its amenity names a lift or stairs, and the amenity's icon of the venue data otherwise: a ramp or
//  an escalator with its own amenity shows that icon (GAD PM, Monday "Ramp icon is not visible",
//  2026-11-12).
//
import Proximiio
import UIKit

struct LevelChangerPlace: Equatable {
    let id: String
    let featureType: String
    let coordinate: ProximiioCoordinate
    /// The floors in `properties.levels`, or the POI's own floor when `levels` is missing, empty or
    /// unreadable.
    let levels: [Double]
    /// `properties.amenity`, or `nil`.
    let amenityID: String?

    static let featureTypes: Set<String> = ["elevator", "staircase", "escalator", "ramp", "hill"]

    init(id: String, featureType: String, coordinate: ProximiioCoordinate, levels: [Double], amenityID: String? = nil) {
        self.id = id
        self.featureType = featureType
        self.coordinate = coordinate
        self.levels = levels
        self.amenityID = amenityID
    }

    /// `nil` for every feature that is not a point of a level changer type.
    init?(feature: ProximiioFeature) {
        guard let type = feature.propertyType, Self.featureTypes.contains(type),
              let geometry = feature.geometry, geometry.type == "Point",
              let pair = geometry.coordinates.arrayValue, pair.count >= 2,
              // GeoJSON order is [longitude, latitude].
              let longitude = pair[0].doubleValue, let latitude = pair[1].doubleValue
        else { return nil }
        let listed = feature.properties?["levels"].flatMap(Self.levels(from:))
        let levels = listed ?? feature.level.map { [$0] } ?? []
        let amenityID = feature.properties?["amenity"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
        self.init(id: feature.id, featureType: type, coordinate: ProximiioCoordinate(latitude: latitude, longitude: longitude),
                  levels: levels, amenityID: amenityID)
    }

    /// The finite levels in a `properties.levels` value, or `nil` when it holds none. Entries may
    /// be numbers or numeric strings; a single number or string counts as a one-entry list. Same
    /// rule as the SDK's `LevelChangerExtractor.levels(from:)`.
    static func levels(from value: JSONValue) -> [Double]? {
        let entries = value.arrayValue ?? [value]
        let levels = entries.compactMap { entry -> Double? in
            let level: Double?
            switch entry {
            case .number(let number): level = number
            case .string(let string): level = Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
            default: level = nil
            }
            return level.flatMap { $0.isFinite ? $0 : nil }
        }
        return levels.isEmpty ? nil : levels
    }

    /// `true` when a level changer with this amenity shows the amenity's icon of the venue data:
    /// every amenity whose id and title name neither stairs nor a lift. Pure; covered by tests.
    static func showsAmenityIcon(amenityID: String, title: String?) -> Bool {
        let kind = AmenityKind.kind(forAmenityID: amenityID, title: title)
        return kind != .stairs && kind != .elevator
    }

    /// The icons of `icons` (by amenity id) that level changers show instead of the design's lift
    /// and stairs icons.
    static func amenityIcons(of amenities: [ProximiioAmenity], icons: [String: UIImage]) -> [String: UIImage] {
        let shown = Set(amenities.filter { showsAmenityIcon(amenityID: $0.id, title: $0.title) }.map(\.id))
        return icons.filter { shown.contains($0.key) }
    }

    static func all(in features: [ProximiioFeature]) -> [LevelChangerPlace] {
        features.compactMap(LevelChangerPlace.init(feature:))
    }

    func serves(_ level: Double) -> Bool {
        levels.contains { VenueLevel.same($0, level) }
    }
}
